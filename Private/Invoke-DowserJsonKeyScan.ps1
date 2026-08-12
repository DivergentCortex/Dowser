#Requires -Version 5.1

function Invoke-DowserJsonKeyScan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$FilePath,

        [int]$ThreadCount = [Math]::Min(8, [Environment]::ProcessorCount)
    )

    $workerCount = [Math]::Min($FilePath.Count, [Math]::Max(1, $ThreadCount))
    $sync = [hashtable]::Synchronized(@{
        Pending = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
        Results = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
        LogQueue = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
        Progress = [System.Collections.Concurrent.ConcurrentQueue[int]]::new()
    })
    foreach ($path in $FilePath) {
        $sync.Pending.Enqueue($path)
    }

    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    foreach ($functionName in 'Read-DowserJsonKeyFile', 'Invoke-DowserJsonKeyWorker') {
        $workerDefinition = (Get-Command -Name $functionName -CommandType Function).ScriptBlock.ToString()
        $workerEntry = [System.Management.Automation.Runspaces.SessionStateFunctionEntry]::new(
            $functionName,
            $workerDefinition
        )
        $iss.Commands.Add($workerEntry)
    }

    try {
        $pool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, $workerCount, $iss, $Host)
        $pool.ApartmentState = 'MTA'
        $pool.Open()
    }
    catch {
        Write-Log "Get-DowserJsonKey could not open its worker pool: $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Error
        return
    }

    Write-Log "Get-DowserJsonKey starting $workerCount JSON scan worker(s)" -Severity Info
    $activeJobs = [System.Collections.Generic.List[object]]::new()

    try {
        for ($workerIndex = 0; $workerIndex -lt $workerCount; $workerIndex++) {
            $powerShell = $null
            try {
                $powerShell = [PowerShell]::Create()
                $powerShell.RunspacePool = $pool
                $powerShell.AddScript({
                    param($Sync)
                    Invoke-DowserJsonKeyWorker -Sync $Sync
                }).AddArgument($sync) | Out-Null
                $handle = $powerShell.BeginInvoke()
                $activeJobs.Add([pscustomobject]@{
                    PowerShell = $powerShell
                    Handle = $handle
                })
            }
            catch {
                Write-Log "Get-DowserJsonKey could not start a JSON scan worker: $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Warning
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
                    Write-Log "Get-DowserJsonKey scan worker failed: $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Warning
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

            $completed = $sync.Progress.Count
            $percent = [Math]::Min(100, [int](($completed / $FilePath.Count) * 100))
            Write-Progress -Activity 'Get-DowserJsonKey' -Status "Scanning JSON files ($completed / $($FilePath.Count))" -PercentComplete $percent

            if ($activeJobs.Count -gt 0) {
                Start-Sleep -Milliseconds 50
            }
        }
    }
    finally {
        $pool.Close()
        $pool.Dispose()
        Write-Progress -Activity 'Get-DowserJsonKey' -Completed
    }

    if ($sync.Progress.Count -ne $FilePath.Count) {
        Write-Log "Get-DowserJsonKey completed $($sync.Progress.Count) of $($FilePath.Count) JSON file scan(s)" -Severity Warning
    }
    else {
        Write-Log "Get-DowserJsonKey completed $($sync.Progress.Count) JSON file scan(s)" -Severity Info
    }

    $result = $null
    while ($sync.Results.TryDequeue([ref]$result)) {
        $result
    }
}
