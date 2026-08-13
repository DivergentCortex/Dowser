#Requires -Version 5.1

function Invoke-DowserJsonRepairScan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Task,

        [ValidateRange(1, 100)]
        [int]$ThreadCount = [Math]::Min(8, [Environment]::ProcessorCount)
    )

    $workerCount = [Math]::Min($Task.Count, [Math]::Max(1, $ThreadCount))
    $sync = [hashtable]::Synchronized(@{
        Pending     = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
        Results     = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
        LogQueue    = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
        Progress    = [System.Collections.Concurrent.ConcurrentQueue[int]]::new()
        OutputLocks = [hashtable]::Synchronized(@{})
        WriteEnabled = $Task[0].WriteEnabled
    })
    foreach ($item in $Task) {
        $sync.Pending.Enqueue($item)
    }

    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $workerLogger = @'
param(
    [string]$Message,
    [string]$Severity
)

$Sync.LogQueue.Enqueue([pscustomobject]@{
    Message  = $Message
    Severity = $Severity
})
'@
    $iss.Commands.Add([System.Management.Automation.Runspaces.SessionStateFunctionEntry]::new('Write-Log', $workerLogger))
    foreach ($functionName in 'Get-DowserJsonDiagnosis', 'Write-DowserJsonRepair', 'Invoke-DowserJsonRepairWorker') {
        $definition = (Get-Command -Name $functionName -CommandType Function).ScriptBlock.ToString()
        $iss.Commands.Add([System.Management.Automation.Runspaces.SessionStateFunctionEntry]::new($functionName, $definition))
    }

    $pool = $null
    $activeJobs = [System.Collections.Generic.List[object]]::new()
    try {
        $pool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, $workerCount, $iss, $Host)
        $pool.ApartmentState = 'MTA'
        $pool.Open()
        Write-Log "Repair-DowserJson starting $workerCount repair worker(s)" -Severity Info

        for ($workerIndex = 0; $workerIndex -lt $workerCount; $workerIndex++) {
            $powerShell = [PowerShell]::Create()
            $powerShell.RunspacePool = $pool
            $powerShell.AddScript({
                param($Sync)
                Invoke-DowserJsonRepairWorker -Sync $Sync
            }).AddArgument($sync) | Out-Null
            $activeJobs.Add([pscustomobject]@{
                PowerShell = $powerShell
                Handle     = $powerShell.BeginInvoke()
            })
        }

        while ($activeJobs.Count -gt 0) {
            foreach ($job in @($activeJobs | Where-Object { $_.Handle.IsCompleted })) {
                try {
                    $job.PowerShell.EndInvoke($job.Handle) | Out-Null
                }
                catch {
                    Write-Log "Repair-DowserJson worker failed: $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Warning
                }
                finally {
                    $job.PowerShell.Dispose()
                    $activeJobs.Remove($job) | Out-Null
                }
            }

            $logEntry = $null
            while ($sync.LogQueue.TryDequeue([ref]$logEntry)) {
                if ($logEntry.Severity -in 'Warning', 'Error') {
                    Write-Log $logEntry.Message -Severity $logEntry.Severity
                }
            }

            $completed = $sync.Progress.Count
            $percent = [Math]::Min(100, [int](($completed / $Task.Count) * 100))
            Write-Progress -Activity 'Repair-DowserJson' -Status "Repairing JSON files ($completed / $($Task.Count))" -PercentComplete $percent

            if ($activeJobs.Count -gt 0) {
                Start-Sleep -Milliseconds 50
            }
        }
    }
    catch {
        Write-Log "Repair-DowserJson could not run its worker pool: $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Error
        $pendingTask = $null
        while ($sync.Pending.TryDequeue([ref]$pendingTask)) {
            $sync.Results.Enqueue([pscustomobject]@{
                FilePath       = $pendingTask.FilePath
                Classification = 'WorkerUnavailable'
                Repairable     = $false
                RepairAction   = $null
                Documents      = 0
                ErrorLine      = $null
                ErrorPosition  = $null
                ErrorMessage   = $_.Exception.Message
                Result         = 'Failed'
                OutputPath     = $null
            })
            $sync.Progress.Enqueue(1)
        }
    }
    finally {
        foreach ($job in $activeJobs) {
            $job.PowerShell.Dispose()
        }
        if ($null -ne $pool) {
            $pool.Close()
            $pool.Dispose()
        }
        Write-Progress -Activity 'Repair-DowserJson' -Completed
    }

    Write-Log "Repair-DowserJson completed $($sync.Progress.Count) of $($Task.Count) JSON file(s)" -Severity Info
    $result = $null
    while ($sync.Results.TryDequeue([ref]$result)) {
        $result
    }
}
