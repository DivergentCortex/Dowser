function Get-DowserVersionKey {
    <#
    .SYNOPSIS
        Builds a sort key from a dotted numeric version, or returns null for any other version text.
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
        A version such as 2026.11.16.8572 becomes its segments left-padded to twelve digits and
        joined with dots, so an ordinal string comparison orders versions numerically at any
        segment count. Text that is not dotted digits (a commit hash, local, unknown) cannot be
        ranked and returns null.
    .PARAMETER Version
        The version folder name.
    .EXAMPLE
        Get-DowserVersionKey -Version '2026.11.16.8572'

        Returns 000000002026.000000000011.000000000016.000000008572.
    .OUTPUTS
        System.String, or null when the version has no numeric order.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Version
    )

    if ($Version -notmatch '^\d{1,12}(\.\d{1,12})*$') {
        return $null
    }
    return (($Version -split '\.' | ForEach-Object { $_.PadLeft(12, '0') }) -join '.')
}
