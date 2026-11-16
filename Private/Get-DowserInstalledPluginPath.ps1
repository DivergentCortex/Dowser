function Get-DowserInstalledPluginPath {
    <#
    .SYNOPSIS
        Reads the install path of every plugin named in an installed_plugins.json manifest.
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
        The manifest maps each plugin@marketplace key to one install record or a list of them,
        and every record names the folder that is the live copy in installPath. Those folders
        are never pruned. A manifest that cannot be read or holds no install path returns
        Success false so the caller refuses to remove anything on its account.
    .PARAMETER ManifestPath
        Path to installed_plugins.json.
    .EXAMPLE
        Get-DowserInstalledPluginPath -ManifestPath ~/.claude/plugins/installed_plugins.json

        Returns the install folders of every installed plugin.
    .OUTPUTS
        PSCustomObject with Success, Paths, Reason, ExceptionType, Message, ExitCode.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ManifestPath
    )

    $outcome = {
        param($success, $paths, $reason, $exception, $code)
        [pscustomobject]@{
            Success       = $success
            Paths         = @($paths)
            Reason        = $reason
            ExceptionType = if ($exception) { $exception.Exception.GetType().Name } else { $null }
            Message       = if ($exception) { $exception.Exception.Message } else { $reason }
            ExitCode      = $code
        }
    }

    $paths = [System.Collections.Generic.List[string]]::new()
    try {
        Write-Log "Attempting InstalledManifestRead on '$ManifestPath'" -Severity Verbose
        $manifest = Get-Content -LiteralPath $ManifestPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        foreach ($property in $manifest.plugins.PSObject.Properties) {
            foreach ($record in @($property.Value)) {
                if ($record.installPath) {
                    $paths.Add([System.IO.Path]::GetFullPath([string]$record.installPath))
                }
            }
        }
    }
    catch {
        Write-Log "InstalledManifestRead failed on '$ManifestPath': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Warning
        return (& $outcome $false @() 'ManifestUnreadable' $_ (Get-WindowsErrorCode -Exception $_))
    }

    if ($paths.Count -eq 0) {
        Write-Log "InstalledManifestRead found no installPath in '$ManifestPath'" -Severity Warning
        return (& $outcome $false @() 'ManifestHasNoInstallPath' $null (Get-WindowsErrorCode -HResult 0x8007000D))
    }

    Write-Log "InstalledManifestRead succeeded on '$ManifestPath': $($paths.Count) install path(s)" -Severity Verbose
    return (& $outcome $true $paths.ToArray() $null $null 0)
}
