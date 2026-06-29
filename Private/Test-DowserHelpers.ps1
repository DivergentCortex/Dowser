<#
.SYNOPSIS
    Smoke-tests the Dowser private size and sort helper functions.
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
    Dot-sources Format-DowserSize, ConvertTo-DowserBytes, and
    Get-DowserSortKey from the same directory and runs a fixed set of
    known-input assertions against each. Reports PASSED or FAILED per
    helper to the information stream, including the observed values when
    an assertion fails. Run it directly to verify the helpers behave as
    expected after a change.
.EXAMPLE
    ./Test-DowserHelpers.ps1

    Runs all helper assertions and prints a PASSED or FAILED line per helper.
.OUTPUTS
    None. Results are written to the information and warning streams.
#>

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/Format-DowserSize.ps1"
. "$PSScriptRoot/ConvertTo-DowserBytes.ps1"
. "$PSScriptRoot/Get-DowserSortKey.ps1"

Write-Log "Testing Format-DowserSize..."
$size1 = Format-DowserSize -DataValue 1024
$size2 = Format-DowserSize -DataValue 1500000
$size3 = Format-DowserSize -DataValue 0
$size4 = Format-DowserSize -DataValue $null
if ($size1 -eq "1.0KB" -and $size2 -eq "1.4MB" -and $size3 -eq "0B" -and $size4 -eq "Offline") {
    Write-Log "Format-DowserSize PASSED"
}
else {
    Write-Log "Format-DowserSize FAILED ($size1, $size2, $size3, $size4)" -Severity Warning
}

Write-Log "Testing ConvertTo-DowserBytes..."
$bytes1 = ConvertTo-DowserBytes -SizeString "1MB"
$bytes2 = ConvertTo-DowserBytes -SizeString "1.5GB"
$bytes3 = ConvertTo-DowserBytes -SizeString "1024"
if ($bytes1 -eq 1048576 -and $bytes2 -eq 1610612736 -and $bytes3 -eq 1024) {
    Write-Log "ConvertTo-DowserBytes PASSED"
}
else {
    Write-Log "ConvertTo-DowserBytes FAILED ($bytes1, $bytes2, $bytes3)" -Severity Warning
}

Write-Log "Testing Get-DowserSortKey..."
$key1 = Get-DowserSortKey -InputString "File-1"
$key2 = Get-DowserSortKey -InputString "File-10"
if ($key1 -contains "00001" -and $key2 -contains "00010") {
    Write-Log "Get-DowserSortKey PASSED"
}
else {
    Write-Log "Get-DowserSortKey FAILED" -Severity Warning
}

Write-Log "All tests complete."
