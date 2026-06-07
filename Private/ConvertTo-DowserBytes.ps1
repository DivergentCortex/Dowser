function ConvertTo-DowserBytes {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [string]$SizeString
    )
    
    if ([string]::IsNullOrWhiteSpace($SizeString)) { return $null }
    
    if ($SizeString -match '^(\d+(?:\.\d+)?)\s*([KMGTP]B?)$') {
        $val = [double]$matches[1]
        $unit = $matches[2].ToUpper()
        switch -Regex ($unit) {
            'K' { return [long]($val * 1KB) }
            'M' { return [long]($val * 1MB) }
            'G' { return [long]($val * 1GB) }
            'T' { return [long]($val * 1TB) }
            'P' { return [long]($val * 1PB) }
        }
    }
    
    return [long]$SizeString
}
