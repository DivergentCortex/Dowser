# Aliases\Aliases.ps1
# brandless verb-noun aliases for the dowser commands
# not applied on import so a public load never squats generic names
# opt in with Enable-DowserAliases or drop that line in your profile

function Enable-DowserAliases {
    <#
    .SYNOPSIS
        Register short brandless aliases for the Dowser commands in the current session.

    .DESCRIPTION
        Dowser exports its commands under branded verb-Dowser-noun names so importing the
        module never drops generic names like Find-File or Get-Info into your session
        uninvited. This function opts the current session into the natural verb-noun forms
        by registering them as global aliases.

        Put it in your PowerShell profile to have the aliases in every session:

            Enable-DowserAliases

        A name already taken by another command is left alone and reported, so this will not
        clobber someone else's Find-File. Pass -Force to override that.

    .PARAMETER Force
        Overwrite an alias or command name that already exists in the session.

    .EXAMPLE
        Enable-DowserAliases

        Registers the brandless aliases, skipping any name already in use.

    .EXAMPLE
        Enable-DowserAliases -Force

        Registers them all, overwriting any colliding name.

    .INPUTS
        None.

    .OUTPUTS
        None. Registered aliases are written to the verbose log.

    .NOTES
        Author: Curtis Leggett / Divergent Cortex
        it is not water they seek, it is truth, the path hidden in the trees
        the rods tremble as they near the truth buried beneath the tree
    #>
    [CmdletBinding()]
    param(
        [switch]$Force
    )

    # branded command -> brandless alias
    $map = [ordered]@{
        'Compare-DowserReport'     = 'Compare-Report'
        'ConvertTo-DowserBase64'   = 'ConvertTo-Base64'
        'ConvertTo-DowserExe'      = 'ConvertTo-Exe'
        'ConvertTo-DowserIco'      = 'ConvertTo-Ico'
        'Expand-DowserExe'         = 'Expand-Exe'
        'Find-DowserDependency'    = 'Find-Dependency'
        'Find-DowserDuplicate'     = 'Find-Duplicate'
        'Find-DowserFile'          = 'Find-File'
        'Find-DowserModified'      = 'Find-Modified'
        'Find-DowserOrphan'        = 'Find-Orphan'
        'Find-DowserRecentLog'     = 'Find-RecentLog'
        'Find-DowserScript'        = 'Find-Script'
        'Find-DowserString'        = 'Find-String'
        'Get-DowserInfo'           = 'Get-Info'
        'Get-DowserMap'            = 'Get-Map'
        'Get-DowserOwnership'      = 'Get-Ownership'
        'Get-DowserProperty'       = 'Get-Property'
        'Get-DowserReport'         = 'Get-Report'
        'Get-DowserTemplate'       = 'Get-Template'
        'Get-DowserTopology'       = 'Get-Tree'
        'Invoke-DowserFastSearch'  = 'Invoke-FastSearch'
        'Invoke-DowserNumericSort' = 'Invoke-NumericSort'
        'Measure-DowserDirectory'  = 'Measure-Directory'
        'Measure-DowserDiskUsage'  = 'Measure-DiskUsage'
        'New-DowserHiddenFolder'   = 'New-HiddenFolder'
        'Test-DowserExtractable'   = 'Test-Extractable'
        'Test-DowserIntegrity'     = 'Test-Integrity'
    }

    Write-Log -Message "registering $($map.Count) dowser aliases" -Severity Verbose

    $set = 0
    foreach ($target in $map.Keys) {
        $alias = $map[$target]

        # leave a name that already exists alone unless forced
        $existing = Get-Command -Name $alias -ErrorAction SilentlyContinue
        if ($existing) {
            if ($existing.CommandType -eq 'Alias' -and $existing.Definition -eq $target) {
                continue   # already ours, nothing to do
            }
            # never shadow a builtin, force or not
            if ($existing.CommandType -in 'Cmdlet', 'Application') {
                Write-Log -Message "skipped $alias, will not shadow builtin $($existing.Name) ($($existing.CommandType))" -Severity Warning
                continue
            }
            if (-not $Force) {
                Write-Log -Message "skipped $alias, name already used by $($existing.Name) ($($existing.CommandType)). pass -Force to override" -Severity Warning
                continue
            }
        }

        try {
            Set-Alias -Name $alias -Value $target -Scope Global -Force -ErrorAction Stop
            Write-Log -Message "$alias -> $target" -Severity Verbose
            $set++
        }
        catch {
            Write-Log -Message "could not set $alias. $($_.Exception.Message)" -Severity Error
        }
    }

    Write-Log -Message "dowser aliases ready: $set registered" -Severity Verbose
}
