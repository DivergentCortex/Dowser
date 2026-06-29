function Get-DowserSortKey {
    <#
    .SYNOPSIS
        Builds a natural-sort key array from a hyphenated string.
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
        Splits the input on hyphens and produces a key array suitable for
        natural (human-friendly) ordering, so that "File-2" sorts before
        "File-10". Pure-numeric segments are zero-padded to five digits.
        Mixed segments are broken into their leading prefix, the zero-padded
        numeric run, and the trailing suffix. Non-numeric segments pass
        through unchanged. The key is returned as a single array via the
        unary comma operator so the caller receives one key object rather
        than an unrolled stream.
    .PARAMETER InputString
        The string to derive a sort key from. Accepts pipeline input by
        value. Typically a file or folder name such as "Disk-10-Part-2".
    .EXAMPLE
        $items | Sort-Object { Get-DowserSortKey -InputString $_ }

        Orders a list of hyphenated names in natural numeric order.
    .EXAMPLE
        Get-DowserSortKey -InputString "File-10"

        Returns a key array containing the zero-padded segment "00010".
    .INPUTS
        System.String
    .OUTPUTS
        System.Object[]
        A string array used as a natural-sort key.
    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [string]$InputString
    )
    
    $parts = $InputString -split '-'
    $sortKey = @()
    
    foreach ($part in $parts) {
        if ($part -match '^\d+$') {
            $sortKey += $part.PadLeft(5, '0')
        }
        elseif ($part -match '(\d+)') {
            $number = $matches[1]
            $prefix = $part.Substring(0, $part.IndexOf($number))
            $suffix = $part.Substring($part.IndexOf($number) + $number.Length)
            $sortKey += $prefix
            $sortKey += $number.PadLeft(5, '0')
            $sortKey += $suffix
        }
        else {
            $sortKey += $part
        }
    }
    
    return , $sortKey
}
