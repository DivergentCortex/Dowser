function Format-DowserSize {
    <#
    .SYNOPSIS
        Formats a byte count as a human-readable size string.
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
        Scales a raw byte count up through the binary unit ladder (B, KB,
        MB, GB, TB, PB, EB, ZB, YB), dividing by 1KB at each step until the
        value falls below the next threshold, then renders it to one decimal
        place with the matching unit suffix. A $null value returns "Offline"
        so callers can distinguish an unreachable target from a zero-size
        one. A value of zero returns "0B".
    .PARAMETER DataValue
        The byte count to format. Accepts pipeline input and permits $null.
        $null renders as "Offline", zero renders as "0B".
    .EXAMPLE
        Format-DowserSize -DataValue 1500000

        Returns "1.4MB".
    .EXAMPLE
        Format-DowserSize -DataValue $null

        Returns "Offline".
    .INPUTS
        System.Object
    .OUTPUTS
        System.String
        The formatted size string, "0B", or "Offline".
    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true, Mandatory = $false)]
        [AllowNull()]
        $DataValue
    )
    
    $Units = "B", "KB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB"
    $index = 0
    
    if ($null -eq $DataValue) {
        return "Offline"
    }
    elseif ($DataValue -eq 0) {
        return "0B"
    }
    else {
        $value = [double]$DataValue
        while ($value -ge 1KB -and $index -lt ($Units.Length - 1)) {
            $value = $value / 1KB
            $index++
        }
        return "{0:N1}{1}" -f $value, $Units[$index]
    }
}
