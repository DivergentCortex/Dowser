$ErrorActionPreference = 'Stop'
$ScriptPath = "/mnt/d/_REPOS/ToolProjects/Dowser/Private/Invoke-DowserRunspacePool.ps1"
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

Write-Host "Running Invoke-DowserRunspacePool Test..."
$results = Invoke-DowserRunspacePool -InputObject $items -ScriptBlock $scriptBlock -ArgumentList @(10) -UseProgressQueue -ThreadCount 5 -ProgressActivity "Test Activity"

if ($results.Count -eq 25) {
    Write-Host "Test Passed! Got 25 results." -ForegroundColor Green
    $sum = ($results | Measure-Object -Sum).Sum
    Write-Host "Sum is $sum (Expected 3250)"
} else {
    Write-Host "Test Failed! Got $($results.Count) results." -ForegroundColor Red
}