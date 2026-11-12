#Requires -Version 5.1

function Invoke-DowserMapIndexScan {
    <#
    .SYNOPSIS
        Walks a tree once in parallel and answers Get-DowserMap's folder filter questions for every folder.
    .DESCRIPTION
        Workers list directories from a shared queue. The main thread then folds the
        listings bottom-up so each folder gets two answers: whether its subtree holds a
        file that passes the file filter, and whether its subtree holds a folder that
        matches -IncludeFolders. Get-DowserMap seeds its MatchCache and IncludeFolderCache
        from the result, so rendering never re-walks a subtree.

        SyncHash keys (module $SyncHash, reset at the start of each run):
          MapIndex_Pending       ConcurrentQueue[object]  directories waiting to be listed
          MapIndex_Outstanding   CountdownEvent           listings queued but not finished
          MapIndex_Dirs          ConcurrentDictionary     key -> Depth, DirectMatch, Children
          MapIndex_Errors        ConcurrentBag[object]    TaskId, Operation, Target, ExceptionType, Message, Exception
          MapIndex_WorkerStatus  ConcurrentDictionary     worker id -> Running or Complete
          MapIndex_Options       hashtable                read-only filter switches for workers
    .PARAMETER RootPath
        The directory to index.
    .PARAMETER FunctionDefinition
        Filter helper name to definition text, preloaded into every worker runspace.
    .PARAMETER Variable
        Variable name to value, preloaded into every worker runspace for the helpers.
    .PARAMETER Options
        FileFilterActive, IncludeFoldersActive, IncludeHidden, FollowReparse, DepthLimit, IncludeExtensionSet.
    .PARAMETER ThreadCount
        Maximum concurrent workers.
    .OUTPUTS
        PSCustomObject with Success, MatchCache, IncludeFolderCache, DirectoryCount, ErrorCount, Seconds.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [Parameter(Mandatory = $true)]
        [hashtable]$FunctionDefinition,

        [Parameter(Mandatory = $true)]
        [hashtable]$Variable,

        [Parameter(Mandatory = $true)]
        [hashtable]$Options,

        [int]$ThreadCount = [Environment]::ProcessorCount
    )

    $failed = [pscustomobject]@{ Success = $false; MatchCache = @{}; IncludeFolderCache = @{}; DirectoryCount = 0; ErrorCount = 0; Seconds = 0 }

    if (-not $script:SyncHash) {
        $script:SyncHash = [hashtable]::Synchronized(@{ LogQueue = [System.Collections.Concurrent.ConcurrentQueue[object]]::new() })
    }
    $sync = $script:SyncHash
    if (-not $sync.ContainsKey('LogQueue')) {
        $sync.LogQueue = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
    }
    $sync.Cancellation = $false
    $sync.MapIndex_Pending = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
    $sync.MapIndex_Outstanding = [System.Threading.CountdownEvent]::new(1)
    $sync.MapIndex_Dirs = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
    $sync.MapIndex_Errors = [System.Collections.Concurrent.ConcurrentBag[object]]::new()
    $sync.MapIndex_WorkerStatus = [System.Collections.Concurrent.ConcurrentDictionary[int, string]]::new()
    $sync.MapIndex_Options = $Options
    $sync.MapIndex_Pending.Enqueue([pscustomobject]@{ Path = $RootPath; Depth = 0 })

    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $workerName = 'Invoke-DowserMapIndexWorker'
    $iss.Commands.Add([System.Management.Automation.Runspaces.SessionStateFunctionEntry]::new(
            $workerName, (Get-Command -Name $workerName -CommandType Function).ScriptBlock.ToString()))
    foreach ($name in $FunctionDefinition.Keys) {
        $iss.Commands.Add([System.Management.Automation.Runspaces.SessionStateFunctionEntry]::new($name, $FunctionDefinition[$name]))
    }
    foreach ($name in $Variable.Keys) {
        $iss.Variables.Add([System.Management.Automation.Runspaces.SessionStateVariableEntry]::new($name, $Variable[$name], ''))
    }

    $workerCount = [Math]::Max(1, $ThreadCount)
    try {
        Write-Log "Attempting MapIndexPoolOpen on '$RootPath' (workers=$workerCount)" -Severity Verbose
        $pool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, $workerCount, $iss, $Host)
        $pool.ApartmentState = 'MTA'
        $pool.Open()
        Write-Log "MapIndexPoolOpen succeeded on '$RootPath'" -Severity Verbose
    }
    catch {
        Write-Log "MapIndexPoolOpen failed on '$RootPath': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Warning
        return $failed
    }

    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $jobs = [System.Collections.Generic.List[object]]::new()
    for ($id = 0; $id -lt $workerCount; $id++) {
        $ps = $null
        try {
            $ps = [PowerShell]::Create()
            $ps.RunspacePool = $pool
            $null = $ps.AddCommand($workerName).AddParameter('Sync', $sync).AddParameter('WorkerId', $id)
            $jobs.Add([pscustomobject]@{ TaskId = $id; Power = $ps; Handle = $ps.BeginInvoke() })
        }
        catch {
            Write-Log "MapIndexWorkerStart failed on worker $id`: $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Warning
            if ($null -ne $ps) {
                $ps.Dispose()
            }
        }
    }

    $activity = "Get-DowserMap indexing '$RootPath'"
    $logEntry = $null
    if ($jobs.Count -eq 0) {
        $sync.Cancellation = $true
    }
    while ($jobs.Count -gt 0 -and @($jobs | Where-Object { -not $_.Handle.IsCompleted }).Count -gt 0) {
        while ($sync.LogQueue.TryDequeue([ref]$logEntry)) {
            Write-Log $logEntry.Message -Severity $logEntry.Severity
        }
        $listed = $sync.MapIndex_Dirs.Count
        $queued = $sync.MapIndex_Pending.Count
        # the total grows as folders are discovered, so this reports counts rather than a percentage
        Write-Progress -Activity $activity -Status "$listed folders indexed, $queued queued, $([int]$clock.Elapsed.TotalSeconds)s elapsed"
        Start-Sleep -Milliseconds 200
    }
    while ($sync.LogQueue.TryDequeue([ref]$logEntry)) {
        Write-Log $logEntry.Message -Severity $logEntry.Severity
    }
    Write-Progress -Activity $activity -Completed

    foreach ($job in $jobs) {
        try {
            $null = $job.Power.EndInvoke($job.Handle)
        }
        catch {
            $sync.MapIndex_Errors.Add([pscustomobject]@{
                    TaskId = $job.TaskId; Operation = 'EndInvoke'; Target = "worker $($job.TaskId)"
                    ExceptionType = $_.Exception.GetType().Name; Message = $_.Exception.Message; Exception = $_
                })
            $sync.MapIndex_WorkerStatus[$job.TaskId] = 'Failed'
        }
        foreach ($streamError in $job.Power.Streams.Error) {
            $sync.MapIndex_Errors.Add([pscustomobject]@{
                    TaskId = $job.TaskId; Operation = 'WorkerStream'; Target = "worker $($job.TaskId)"
                    ExceptionType = $streamError.Exception.GetType().Name; Message = $streamError.Exception.Message; Exception = $streamError
                })
        }
        $job.Power.Dispose()
    }
    $pool.Close()
    $pool.Dispose()

    $workersFailed = @($jobs | Where-Object { $sync.MapIndex_WorkerStatus[$_.TaskId] -ne 'Complete' }).Count
    $listingErrors = @($sync.MapIndex_Errors | Where-Object { $_.Operation -eq 'DirectoryList' }).Count
    foreach ($record in @($sync.MapIndex_Errors | Where-Object { $_.Operation -ne 'DirectoryList' })) {
        Write-Log "$($record.Operation) failed on $($record.Target): $($record.ExceptionType): $($record.Message)" -Severity Warning
    }
    if ($workersFailed -gt 0 -or $jobs.Count -eq 0 -or -not $sync.MapIndex_Outstanding.IsSet) {
        Write-Log "MapIndex incomplete on '$RootPath' (workers_failed=$workersFailed, folders=$($sync.MapIndex_Dirs.Count)); falling back to per-folder scans" -Severity Warning
        return $failed
    }

    # fold children into parents, deepest first, so each folder sees finished child answers
    $hasMatch = @{}
    $hasIncluded = @{}
    $ordered = @($sync.MapIndex_Dirs.GetEnumerator() | Sort-Object { $_.Value.Depth } -Descending)
    foreach ($pair in $ordered) {
        $match = $pair.Value.DirectMatch
        $included = $false
        foreach ($child in $pair.Value.Children) {
            $childIncluded = [bool]$hasIncluded[$child.Key]
            if (-not $child.ByPath -and ($child.Matches -or (-not $child.ByRule -and $childIncluded))) {
                $included = $true
            }
            if (-not $match) {
                $includeFolder = -not $Options.IncludeFoldersActive -or $child.Matches -or $child.Ancestor -or $childIncluded
                $excluded = if ($Options.IncludeFoldersActive -and $includeFolder) { $false } else { $child.ByRule }
                if (-not $excluded -and $hasMatch[$child.Key]) {
                    $match = $true
                }
            }
        }
        $hasMatch[$pair.Key] = [bool]$match
        $hasIncluded[$pair.Key] = $included
    }
    $clock.Stop()

    Write-Log "MapIndex built on '$RootPath' (folders=$($ordered.Count), unreadable=$listingErrors, workers=$workerCount, seconds=$([Math]::Round($clock.Elapsed.TotalSeconds, 1)))" -Severity Verbose
    return [pscustomobject]@{
        Success            = $true
        MatchCache         = $hasMatch
        IncludeFolderCache = $hasIncluded
        DirectoryCount     = $ordered.Count
        ErrorCount         = $listingErrors
        Seconds            = $clock.Elapsed.TotalSeconds
    }
}
