#Requires -Version 5.1

function Invoke-DowserTransferPool {
    <#
    .SYNOPSIS
        Builds the shared runspace pool and runs Invoke-DowserTransferWorker across it.

    .DESCRIPTION
        Owns the full runspace lifecycle for a transfer run: builds an InitialSessionState
        with Invoke-DowserTransferWorker registered via SessionStateFunctionEntry, opens a
        single shared RunspacePool sized to the item count and -ThreadCount, and starts one
        worker PowerShell instance per pool slot. Each worker instance loops internally over
        $Sync.Pending, so there is never a runspace-per-file. The main thread drains
        $Sync.LogQueue into Write-Log and reports Write-Progress from the (non-destructive)
        snapshot of $Sync.Results until every worker completes, then calls EndInvoke and
        Dispose on every PowerShell instance and Close/Dispose on the pool.

    .PARAMETER TransferItem
        Objects with SourcePath and DestinationPath to copy and verify.

    .PARAMETER ThreadCount
        Maximum concurrent workers.

    .PARAMETER TotalBytes
        Total bytes across all items, used only for the Write-Progress byte total.

    .OUTPUTS
        PSCustomObject with PoolStarted (bool, $false only when the runspace pool itself
        failed to open, distinct from the pool opening and simply processing zero items)
        and Results (System.Object[], one structured result per item, see
        Invoke-DowserTransferWorker).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$TransferItem,

        [int]$ThreadCount = [Math]::Min(8, [Environment]::ProcessorCount),

        [long]$TotalBytes = 0
    )

    $workerCount = [Math]::Min($TransferItem.Count, [Math]::Max(1, $ThreadCount))
    $sync = [hashtable]::Synchronized(@{
        Pending  = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
        Results  = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
        LogQueue = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
    })
    foreach ($queuedItem in $TransferItem) {
        $sync.Pending.Enqueue($queuedItem)
    }

    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $workerDefinition = (Get-Command -Name 'Invoke-DowserTransferWorker' -CommandType Function).ScriptBlock.ToString()
    $workerEntry = [System.Management.Automation.Runspaces.SessionStateFunctionEntry]::new('Invoke-DowserTransferWorker', $workerDefinition)
    $iss.Commands.Add($workerEntry)

    try {
        $pool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, $workerCount, $iss, $Host)
        $pool.ApartmentState = 'MTA'
        $pool.Open()
    }
    catch {
        Write-Log "Invoke-DowserTransferPool could not open its worker pool: $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Error
        return [pscustomobject]@{
            PoolStarted = $false
            Results     = @()
        }
    }

    Write-Log "Start-DowserTransfer starting $workerCount transfer worker(s) for $($TransferItem.Count) file(s)" -Severity Info
    $activeJobs = [System.Collections.Generic.List[object]]::new()

    try {
        for ($workerIndex = 0; $workerIndex -lt $workerCount; $workerIndex++) {
            $powerShell = $null
            try {
                $powerShell = [PowerShell]::Create()
                $powerShell.RunspacePool = $pool
                $powerShell.AddScript({
                    param($Sync)
                    Invoke-DowserTransferWorker -Sync $Sync
                }).AddArgument($sync) | Out-Null
                $handle = $powerShell.BeginInvoke()
                $activeJobs.Add([pscustomobject]@{ PowerShell = $powerShell; Handle = $handle })
            }
            catch {
                Write-Log "Invoke-DowserTransferPool could not start a transfer worker: $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Warning
                if ($null -ne $powerShell) {
                    $powerShell.Dispose()
                }
            }
        }

        while ($activeJobs.Count -gt 0) {
            foreach ($job in @($activeJobs | Where-Object { $_.Handle.IsCompleted })) {
                try {
                    $job.PowerShell.EndInvoke($job.Handle) | Out-Null
                }
                catch {
                    Write-Log "Invoke-DowserTransferPool transfer worker failed: $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Warning
                }
                finally {
                    $job.PowerShell.Dispose()
                    $activeJobs.Remove($job) | Out-Null
                }
            }

            $logEntry = $null
            while ($sync.LogQueue.TryDequeue([ref]$logEntry)) {
                Write-Log $logEntry.Message -Severity $logEntry.Severity
            }

            $doneResults = $sync.Results.ToArray()
            $doneCount = $doneResults.Count
            $doneBytes = ($doneResults | Measure-Object -Property BytesCopied -Sum).Sum
            if ($null -eq $doneBytes) {
                $doneBytes = 0
            }
            $failCount = @($doneResults | Where-Object { -not $_.Success }).Count
            $percent = if ($TransferItem.Count -gt 0) {
                [Math]::Min(100, [int](($doneCount / $TransferItem.Count) * 100))
            }
            else {
                100
            }
            Write-Progress -Activity 'Start-DowserTransfer' -Status "$doneCount / $($TransferItem.Count) files, $doneBytes / $TotalBytes bytes, $failCount failure(s)" -PercentComplete $percent

            if ($activeJobs.Count -gt 0) {
                Start-Sleep -Milliseconds 100
            }
        }
    }
    finally {
        $pool.Close()
        $pool.Dispose()
        Write-Progress -Activity 'Start-DowserTransfer' -Completed
    }

    $logEntry = $null
    while ($sync.LogQueue.TryDequeue([ref]$logEntry)) {
        Write-Log $logEntry.Message -Severity $logEntry.Severity
    }

    return [pscustomobject]@{
        PoolStarted = $true
        Results     = $sync.Results.ToArray()
    }
}
