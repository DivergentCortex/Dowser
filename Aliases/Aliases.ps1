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
        clobber another module's Find-File or the system pstree on Linux. Pass -Force to
        override a non-builtin name; builtins (cmdlets and native apps) are never touched.

    .PARAMETER Force
        Overwrite an alias or function name that already exists. Builtins are still skipped.

    .EXAMPLE
        Enable-DowserAliases

        Registers the brandless aliases, skipping any name already in use.

    .EXAMPLE
        Enable-DowserAliases -Force

        Registers them all, overwriting any colliding alias or function.

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

    # brandless alias -> branded command. one function can carry several aliases.
    $map = [ordered]@{
        'Compare-Report'     = 'Compare-DowserReport'
        'ConvertTo-Base64'   = 'ConvertTo-DowserBase64'
        'ConvertTo-Exe'      = 'ConvertTo-DowserExe'
        'ConvertTo-Ico'      = 'ConvertTo-DowserIco'
        'Expand-Exe'         = 'Expand-DowserExe'
        'Find-Dependency'    = 'Find-DowserDependency'
        'Find-Duplicate'     = 'Find-DowserDuplicate'
        'Find-File'          = 'Find-DowserFile'
        'Find-Modified'      = 'Find-DowserModified'
        'Find-Orphan'        = 'Find-DowserOrphan'
        'Find-RecentLog'     = 'Find-DowserRecentLog'
        'Find-ScriptFile'    = 'Find-DowserScript'
        'Find-String'        = 'Find-DowserString'
        'Get-Info'           = 'Get-DowserInfo'
        'Get-Map'            = 'Get-DowserMap'
        'Get-Ownership'      = 'Get-DowserOwnership'
        'Get-Property'       = 'Get-DowserProperty'
        'Get-Report'         = 'Get-DowserReport'
        'Get-Template'       = 'Get-DowserTemplate'
        'Get-Tree'           = 'Get-DowserTopology'
        'pstree'             = 'Get-DowserTopology'
        'shtree'             = 'Get-DowserTopology'
        'Invoke-FastSearch'  = 'Invoke-DowserFastSearch'
        'Invoke-NumericSort' = 'Invoke-DowserNumericSort'
        'Measure-Directory'  = 'Measure-DowserDirectory'
        'Measure-DiskUsage'  = 'Measure-DowserDiskUsage'
        'New-HiddenFolder'   = 'New-DowserHiddenFolder'
        'Test-Extractable'   = 'Test-DowserExtractable'
        'Test-Integrity'     = 'Test-DowserIntegrity'
    }

    Write-Log -Message "registering $($map.Count) dowser aliases" -Severity Verbose

    $set = 0
    foreach ($alias in $map.Keys) {
        $target = $map[$alias]

        # leave a name that already exists alone
        $existing = Get-Command -Name $alias -ErrorAction SilentlyContinue
        if ($existing) {
            if ($existing.CommandType -eq 'Alias' -and $existing.Definition -eq $target) {
                continue   # already ours, nothing to do
            }
            # never shadow a builtin, force or not
            if ($existing.CommandType -in 'Cmdlet', 'Application') {
                Write-Log -Message "skipped $alias, will not shadow builtin $($existing.Name) ($($existing.CommandType))" -Severity Verbose
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
