function ConvertTo-DowserBytes {
    <#
    .SYNOPSIS
        Converts a human-readable size string into a byte count.
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
        Parses a size string of the form "1.5GB" or "512K" into a long byte
        count using PowerShell's native size multipliers (1KB through 1PB).
        Recognizes the unit suffixes K, M, G, T, and P, with an optional
        trailing B, case-insensitively. A blank or whitespace-only input
        returns $null. A bare numeric string with no unit is treated as a
        raw byte count and returned as a long.
    .PARAMETER SizeString
        The size string to convert. Accepts pipeline input by value.
        Examples of valid input: "1MB", "1.5GB", "512K", "1024".
    .EXAMPLE
        ConvertTo-DowserBytes -SizeString "1.5GB"

        Returns 1610612736.
    .EXAMPLE
        "512K" | ConvertTo-DowserBytes

        Returns 524288.
    .INPUTS
        System.String
    .OUTPUTS
        System.Int64
        System.Object
        Returns a long byte count, or $null when the input is blank.
    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [string]$SizeString
    )
    
    if ([string]::IsNullOrWhiteSpace($SizeString)) {
        return $null 
    }
    
    if ($SizeString -match '^(\d+(?:\.\d+)?)\s*([KMGTP]B?)$') {
        $val = [double]$matches[1]
        $unit = $matches[2].ToUpper()
        switch -Regex ($unit) {
            'K' {
                return [long]($val * 1KB) 
            }
            'M' {
                return [long]($val * 1MB) 
            }
            'G' {
                return [long]($val * 1GB) 
            }
            'T' {
                return [long]($val * 1TB) 
            }
            'P' {
                return [long]($val * 1PB) 
            }
        }
    }
    
    return [long]$SizeString
}
