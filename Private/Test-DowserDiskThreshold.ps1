function Test-DowserDiskThreshold {
    <#
    .SYNOPSIS
        Checks one DiskThreshold rule against the free space on its filesystem.
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
        Reads free space through Get-DowserFilesystemSpace and compares it with the rule's
        MinFreeBytes. A breach is logged at Warning. When the space cannot be read the result is
        Success false and Breached false, with the mapped exit code from the read.
    .PARAMETER Rule
        A DiskThreshold rule from Get-DowserRetentionRule.
    .EXAMPLE
        Test-DowserDiskThreshold -Rule $rule

        Returns whether the rule's filesystem is below its minimum free space.
    .OUTPUTS
        PSCustomObject with Success, Rule, Path, Mount, FreeBytes, TotalBytes, MinFreeBytes,
        Breached, Reason, ExitCode.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Rule
    )

    $space = Get-DowserFilesystemSpace -Path $Rule.Path
    $breached = $space.Success -and ($space.FreeBytes -lt $Rule.MinFreeBytes)
    if ($breached) {
        Write-Log "DiskThreshold rule '$($Rule.Name)': '$($space.Mount)' has $(Format-DowserSize -DataValue $space.FreeBytes) free, below the $(Format-DowserSize -DataValue $Rule.MinFreeBytes) minimum" -Severity Warning
    }
    elseif ($space.Success) {
        Write-Log "DiskThreshold rule '$($Rule.Name)': '$($space.Mount)' has $(Format-DowserSize -DataValue $space.FreeBytes) free, above the $(Format-DowserSize -DataValue $Rule.MinFreeBytes) minimum" -Severity Info
    }

    return [pscustomobject]@{
        Success      = $space.Success
        Rule         = $Rule.Name
        Path         = $Rule.Path
        Mount        = $space.Mount
        FreeBytes    = $space.FreeBytes
        TotalBytes   = $space.TotalBytes
        MinFreeBytes = $Rule.MinFreeBytes
        Breached     = $breached
        Reason       = $space.Reason
        ExitCode     = $space.ExitCode
    }
}
