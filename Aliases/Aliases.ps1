# opt-in on purpose: importing a module shouldn't quietly claim Find-File and friends
$DowserAliasMap = [ordered]@{
    'Compare-Directory'     = 'Compare-DowserDirectory'
    'Compare-Report'        = 'Compare-DowserReport'
    'ConvertTo-Base64'      = 'ConvertTo-DowserBase64'
    'ConvertTo-Exe'         = 'ConvertTo-DowserExe'
    'ConvertTo-Ico'         = 'ConvertTo-DowserIco'
    'Export-JsonCsv'        = 'Export-DowserJsonCsv'
    'Expand-Exe'            = 'Expand-DowserExe'
    'Find-Dependency'       = 'Find-DowserDependency'
    'Find-Duplicate'        = 'Find-DowserDuplicate'
    'Find-File'             = 'Find-DowserFile'
    'Find-Modified'         = 'Find-DowserModified'
    'Find-Orphan'           = 'Find-DowserOrphan'
    'Find-RecentLog'        = 'Find-DowserRecentLog'
    'Find-ScriptFile'       = 'Find-DowserScript'
    'Find-String'           = 'Find-DowserString'
    'Get-Info'              = 'Get-DowserInfo'
    'Get-JsonKey'           = 'Get-DowserJsonKey'
    'Get-Map'               = 'Get-DowserMap'
    'Get-Ownership'         = 'Get-DowserOwnership'
    'Get-Property'          = 'Get-DowserProperty'
    'Get-Report'            = 'Get-DowserReport'
    'Get-Template'          = 'Get-DowserTemplate'
    'Get-Tree'              = 'Get-DowserTopology'
    'pstree'                = 'Get-DowserTopology'
    'shtree'                = 'Get-DowserTopology'
    'dfast'                 = 'Invoke-DowserFastSearch'
    'Invoke-FastSearch'     = 'Invoke-DowserFastSearch'
    'Invoke-NumericSort'    = 'Invoke-DowserNumericSort'
    'Measure-Directory'     = 'Measure-DowserDirectory'
    'Measure-DiskUsage'     = 'Measure-DowserDiskUsage'
    'New-HiddenFolder'      = 'New-DowserHiddenFolder'
    'Remove-TransferSource' = 'Remove-DowserTransferSource'
    'Start-Transfer'        = 'Start-DowserTransfer'
    'Test-Extractable'      = 'Test-DowserExtractable'
    'Test-Integrity'        = 'Test-DowserIntegrity'
}

function Enable-DowserAliases {
    <#
    .SYNOPSIS
        Register short brandless aliases for the Dowser commands in the current session.

    .DESCRIPTION
        Registers global aliases such as Find-File and Get-Info for the Dowser commands.
        A name already taken by another command, for example the system pstree on Linux,
        is skipped and logged. Pass -Force to override a non-builtin name; cmdlets and
        native applications are never overridden. Add the call to a profile to enable
        the aliases in every session.

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

    Write-Log -Message "registering $($DowserAliasMap.Count) dowser aliases" -Severity Verbose

    $set = 0
    foreach ($alias in $DowserAliasMap.Keys) {
        $target = $DowserAliasMap[$alias]

        $existing = Get-Command -Name $alias -ErrorAction SilentlyContinue
        if ($existing) {
            if ($existing.CommandType -eq 'Alias' -and $existing.Definition -eq $target) {
                continue
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
