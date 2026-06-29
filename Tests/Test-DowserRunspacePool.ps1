$ErrorActionPreference = 'Stop'
$ScriptPath = "$PSScriptRoot/../Private/Invoke-DowserRunspacePool.ps1"
. $ScriptPath

$items = 1..25
$scriptBlock = {
    param($chunk, $multiplier, $progressQueue)
    $res = @()
    foreach ($item in $chunk) {
        Start-Sleep -Milliseconds 50
        $res += ($item * $multiplier)
        if ($progressQueue) { [void]$progressQueue.Enqueue(1) }
    }
    return $res
}

Write-Information "Running Invoke-DowserRunspacePool Test..." -InformationAction Continue
$results = Invoke-DowserRunspacePool -InputObject $items -ScriptBlock $scriptBlock -ArgumentList @(10) -UseProgressQueue -ThreadCount 5 -ProgressActivity "Test Activity"

if ($results.Count -eq 25) {
    Write-Information "Test Passed! Got 25 results." -InformationAction Continue
    $sum = ($results | Measure-Object -Sum).Sum
    Write-Information "Sum is $sum (Expected 3250)" -InformationAction Continue
} else {
    Write-Warning "Test Failed! Got $($results.Count) results."
}