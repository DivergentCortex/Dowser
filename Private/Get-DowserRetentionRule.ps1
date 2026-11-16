function Get-DowserRetentionRule {
    <#
    .SYNOPSIS
        Loads and validates the cache retention rule file.
    .NOTES
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
        -  Author:        Curtis Leggett                                  -
        =  Copyright:     2026 Divergent Cortex                           =
        -  Organization:  Divergent Cortex                                -
        =  Version:       See docs/CHANGELOG.md                           =
        =-=-                       =-=-=-=-=-=-=-=                     -=-=
        -  it is not water they seek, but the truth beneath the trees     -
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
    .DESCRIPTION
        Reads the .psd1 rule file, expands a leading ~ to the user's home folder, applies the
        defaults and returns one object per valid rule. A rule that fails validation is left
        out, logged at Warning and named in Rejected, so one bad rule cannot widen what a
        removal run touches. Marketplace and plugin names must be single folder names; a name
        holding a path separator or a dot-only name is rejected so a rule cannot step outside
        its root.
    .PARAMETER ConfigPath
        Path to the rule file.
    .EXAMPLE
        Get-DowserRetentionRule -ConfigPath ./Config/CacheRetentionRules.psd1

        Returns the validated rules from the shipped rule file.
    .OUTPUTS
        PSCustomObject with Success, Rules, Rejected, Reason, ExceptionType, Message, ExitCode.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ConfigPath
    )

    $outcome = {
        param($success, $rules, $rejected, $reason, $exception, $code)
        [pscustomobject]@{
            Success       = $success
            Rules         = @($rules)
            Rejected      = @($rejected)
            Reason        = $reason
            ExceptionType = if ($exception) { $exception.Exception.GetType().Name } else { $null }
            Message       = if ($exception) { $exception.Exception.Message } else { $reason }
            ExitCode      = $code
        }
    }
    $expand = {
        param($text)
        if ($text -eq '~' -or $text -like '~/*' -or $text -like '~\*') {
            return (Join-Path $HOME $text.Substring(1).TrimStart('/', '\'))
        }
        return $text
    }
    $isFolderName = {
        param($name)
        return ($name -is [string]) -and ($name -match '^[^/\\]+$') -and ($name -ne '.') -and ($name -ne '..')
    }

    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        Write-Log "RetentionRuleRead found no rule file at '$ConfigPath'" -Severity Error
        return (& $outcome $false @() @() 'RuleFileMissing' $null (Get-WindowsErrorCode -HResult 0x80070002))
    }

    $data = $null
    try {
        Write-Log "Attempting RetentionRuleRead on '$ConfigPath'" -Severity Verbose
        $data = Import-PowerShellDataFile -LiteralPath $ConfigPath -ErrorAction Stop
    }
    catch {
        Write-Log "RetentionRuleRead failed on '$ConfigPath': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Error
        return (& $outcome $false @() @() 'RuleFileUnreadable' $_ (Get-WindowsErrorCode -Exception $_))
    }

    if ($null -eq $data -or -not $data.ContainsKey('Rules') -or @($data.Rules).Count -eq 0) {
        Write-Log "RetentionRuleRead found no Rules entry in '$ConfigPath'" -Severity Error
        return (& $outcome $false @() @() 'NoRules' $null (Get-WindowsErrorCode -HResult 0x8007000D))
    }

    $rules = [System.Collections.Generic.List[object]]::new()
    $rejected = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($entry in @($data.Rules)) {
        $name = [string]$entry.Name
        $problem = $null
        if ([string]::IsNullOrWhiteSpace($name)) {
            $problem = 'Name is missing'
            $name = '(unnamed)'
        }
        elseif (-not $seen.Add($name)) {
            $problem = 'Name is used twice'
        }
        elseif ($entry.Type -eq 'VersionedCache') {
            $keep = if ($entry.ContainsKey('KeepNewest')) { $entry.KeepNewest } else { 2 }
            $quiet = if ($entry.ContainsKey('QuietMinutes')) { $entry.QuietMinutes } else { 60 }
            if ([string]::IsNullOrWhiteSpace([string]$entry.Root)) { $problem = 'Root is missing' }
            elseif (@($entry.Marketplaces).Count -eq 0 -or @($entry.Plugins).Count -eq 0) { $problem = 'Marketplaces and Plugins need at least one name each' }
            elseif (@(@($entry.Marketplaces) + @($entry.Plugins) | Where-Object { -not (& $isFolderName $_) }).Count -gt 0) { $problem = 'a Marketplaces or Plugins name is not a single folder name' }
            elseif ($keep -isnot [int] -or $keep -lt 1 -or $keep -gt 100) { $problem = 'KeepNewest must be a whole number from 1 to 100' }
            elseif ($quiet -isnot [int] -or $quiet -lt 0 -or $quiet -gt 10080) { $problem = 'QuietMinutes must be a whole number from 0 to 10080' }
            if (-not $problem) {
                $manifest = if ($entry.ContainsKey('InstalledManifest') -and $entry.InstalledManifest) { & $expand ([string]$entry.InstalledManifest) } else { $null }
                $rules.Add([pscustomobject]@{
                        Name              = $name
                        Type              = 'VersionedCache'
                        Root              = [System.IO.Path]::GetFullPath((& $expand ([string]$entry.Root)))
                        Marketplaces      = @($entry.Marketplaces)
                        Plugins           = @($entry.Plugins)
                        KeepNewest        = $keep
                        InstalledManifest = $manifest
                        QuietMinutes      = $quiet
                        Path              = $null
                        MinFreeBytes      = $null
                    })
            }
        }
        elseif ($entry.Type -eq 'DiskThreshold') {
            $minFree = $null
            if (-not [string]::IsNullOrWhiteSpace([string]$entry.Path) -and -not [string]::IsNullOrWhiteSpace([string]$entry.MinFree)) {
                $minFree = ConvertTo-DowserBytes -SizeString ([string]$entry.MinFree)
            }
            if ([string]::IsNullOrWhiteSpace([string]$entry.Path)) { $problem = 'Path is missing' }
            elseif ($null -eq $minFree -or $minFree -lt 1) { $problem = 'MinFree is missing or not a size' }
            else {
                $rules.Add([pscustomobject]@{
                        Name              = $name
                        Type              = 'DiskThreshold'
                        Root              = $null
                        Marketplaces      = @()
                        Plugins           = @()
                        KeepNewest        = $null
                        InstalledManifest = $null
                        QuietMinutes      = $null
                        Path              = (& $expand ([string]$entry.Path))
                        MinFreeBytes      = [long]$minFree
                    })
            }
        }
        else {
            $problem = "Type '$($entry.Type)' is not VersionedCache or DiskThreshold"
        }

        if ($problem) {
            $rejected.Add($name)
            Write-Log "RetentionRuleRead rejected rule '$name' in '$ConfigPath': $problem" -Severity Warning
        }
    }

    Write-Log "RetentionRuleRead succeeded on '$ConfigPath': $($rules.Count) rule(s) valid, $($rejected.Count) rejected" -Severity Verbose
    $code = 0
    if ($rejected.Count -gt 0) {
        $code = Get-WindowsErrorCode -HResult 0x8007000D
    }
    return (& $outcome ($rejected.Count -eq 0) $rules.ToArray() $rejected.ToArray() $(if ($rejected.Count -gt 0) { 'RuleRejected' } else { $null }) $null $code)
}
