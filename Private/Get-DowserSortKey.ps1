function Get-DowserSortKey {
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
