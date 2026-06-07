function Format-DowserSize {
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
