#Requires -Version 5.1

function Invoke-DowserRunspacePool {
    <#
    .SYNOPSIS
        Executes a scriptblock across multiple runspaces with automatic chunking and progress tracking.
    .NOTES
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
        -  Author:        Curtis Leggett                                  -
        =  Copyright:     2026 Divergent Cortex                           =
        -  Organization:  Divergent Cortex                                -
        =  Version:       See docs/CHANGELOG.md                           =
        =-=-                       =-=-=-=-=-=-=-=                     -=-=
        -  it is not water they seek, but the truth beneath the trees     -
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

        Author: Curtis Leggett / Divergent Cortex
        Created: 2026-04-11
    .DESCRIPTION
        This helper generalizes the RunspacePool pattern used across the Dowser module for bulk operations.
        It consolidates the logic for:
        - RunspacePool creation, lifecycle, and safe disposal.
        - Chunking input arrays into equal batches to distribute across threads.
        - Passing arguments consistently.
        - Providing a wait loop with Write-Progress updates (both job-level and item-level via ConcurrentQueue).
        - Result aggregation from all child runspaces.

        This ensures 100% logic alignment with high-performance tools like Find-StringInFiles and Find-Files.
    .PARAMETER InputObject
        The array of items to process (e.g., file paths, directories).
    .PARAMETER ScriptBlock
        The scriptblock to execute in each runspace. The FIRST parameter of this scriptblock will 
        always receive the chunk (array) of InputObject items.
    .PARAMETER ArgumentList
        Additional arguments to pass to the scriptblock. These will be passed in order AFTER the input chunk.
    .PARAMETER ThreadCount
        Maximum number of concurrent runspaces. Defaults to [Environment]::ProcessorCount.
    .PARAMETER BatchSize
        The number of items to pass to each runspace job. 
        If not specified, defaults to [Math]::Ceiling(InputObject.Count / ThreadCount).
    .PARAMETER ProgressActivity
        The activity name for Write-Progress. Defaults to "Processing Background Jobs".
    .PARAMETER ProgressStatus
        The status text for Write-Progress. Defaults to "Working...".
    .PARAMETER UseProgressQueue
        If specified, creates a [System.Collections.Concurrent.ConcurrentQueue[int]] and passes it
        as the FINAL argument to the scriptblock. The scriptblock can call `$queue.Enqueue(1)` to report
        per-item completion, enabling highly accurate ETA and progress tracking.
    .EXAMPLE
        $results = $files | Invoke-DowserRunspacePool -ThreadCount 8 -ScriptBlock {
            param($chunk, $searchPattern, $queue)
            $res = @()
            foreach ($file in $chunk) {
                if ((Get-Content $file -Raw) -match $searchPattern) { $res += $file }
                if ($queue) { [void]$queue.Enqueue(1) }
            }
            return $res
        } -ArgumentList @('TODO') -UseProgressQueue

        Runs a parallel content search over a file list with per-item progress.
    .INPUTS
        System.Object[]
        You can pipe the items to process to this function.
    .OUTPUTS
        System.Object[]
        The aggregated results returned from all child runspaces.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object[]]$InputObject,

        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,

        [object[]]$ArgumentList = @(),

        [int]$ThreadCount = [Environment]::ProcessorCount,

        [int]$BatchSize = 0,

        [string]$ProgressActivity = "Processing Background Jobs",

        [string]$ProgressStatus = "Working...",

        [switch]$UseProgressQueue
    )

    begin {
        $inputItems = [System.Collections.ArrayList]::new()
    }

    process {
        if ($InputObject) {
            foreach ($item in $InputObject) {
                [void]$inputItems.Add($item)
            }
        }
    }

    end {
        if ($inputItems.Count -eq 0) {
            return
        }

        Write-Log "Starting Invoke-DowserRunspacePool"

        $totalItems = $inputItems.Count
        $ComputedMaxThreads = [Math]::Max(1, $ThreadCount)

        if ($BatchSize -gt 0) {
            $chunkSize = $BatchSize
        }
        else {
            $chunkSize = [Math]::Ceiling($totalItems / $ComputedMaxThreads)
            if ($chunkSize -lt 1) {
                $chunkSize = 1 
            }
        }

        $progressQueue = $null
        if ($UseProgressQueue) {
            $progressQueue = [System.Collections.Concurrent.ConcurrentQueue[int]]::new()
        }

        $pool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, $ComputedMaxThreads)
        $pool.Open()
        
        $jobs = [System.Collections.ArrayList]::new()

        $counter = 0
        while ($counter -lt $totalItems) {
            $currentChunkSize = [Math]::Min($chunkSize, $totalItems - $counter)
            $chunk = $inputItems.GetRange($counter, $currentChunkSize).ToArray()
            $counter += $currentChunkSize

            $ps = [powershell]::Create()
            $ps.RunspacePool = $pool
            [void]$ps.AddScript($ScriptBlock)
            
            [void]$ps.AddArgument($chunk)

            if ($ArgumentList) {
                foreach ($arg in $ArgumentList) {
                    [void]$ps.AddArgument($arg)
                }
            }

            if ($UseProgressQueue) {
                [void]$ps.AddArgument($progressQueue)
            }

            $job = $ps.BeginInvoke()
            [void]$jobs.Add([PSCustomObject]@{ Pipe = $ps; Result = $job })
        }

        $totalJobs = $jobs.Count
        $startTime = Get-Date

        while (@($jobs | Where-Object { -not $_.Result.IsCompleted }).Count -gt 0) {
            $completedChunks = @($jobs | Where-Object { $_.Result.IsCompleted }).Count
            
            if ($UseProgressQueue) {
                $itemsProcessed = $progressQueue.Count
                $pct = if ($totalItems -gt 0) {
                    [Math]::Min(100, [int](($itemsProcessed / $totalItems) * 100)) 
                }
                else {
                    0 
                }
                
                $elapsed = (Get-Date) - $startTime
                $etaDisplay = 'calculating...'
                if ($itemsProcessed -gt 10 -and $elapsed.TotalSeconds -gt 1) {
                    $rate = $itemsProcessed / $elapsed.TotalSeconds
                    $remaining = $totalItems - $itemsProcessed
                    $etaSec = [Math]::Max(0, [int]($remaining / $rate))
                    $ts = [TimeSpan]::FromSeconds($etaSec)
                    $etaDisplay = '{0:d2}:{1:d2}' -f [int]$ts.TotalMinutes, $ts.Seconds
                }

                Write-Progress -Activity $ProgressActivity `
                    -Status "$ProgressStatus ($itemsProcessed / $totalItems items) - ETA: $etaDisplay" `
                    -PercentComplete $pct
            }
            else {
                $pct = if ($totalJobs -gt 0) {
                    [Math]::Min(100, [int](($completedChunks / $totalJobs) * 100)) 
                }
                else {
                    0 
                }
                Write-Progress -Activity $ProgressActivity `
                    -Status "$ProgressStatus ($completedChunks / $totalJobs jobs completed)" `
                    -PercentComplete $pct
            }
            
            Start-Sleep -Milliseconds 200
        }

        Write-Progress -Activity $ProgressActivity -Status "Finalizing results..." -PercentComplete 100

        $results = [System.Collections.ArrayList]::new()
        foreach ($j in $jobs) {
            try {
                $res = $j.Pipe.EndInvoke($j.Result)
                if ($null -ne $res) {
                    foreach ($r in $res) {
                        [void]$results.Add($r)
                    }
                }
            }
            catch {
                Write-Log "Invoke-DowserRunspacePool failed collecting worker result: $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Warning
            }
            finally {
                $j.Pipe.Dispose()
            }
        }

        $pool.Close()
        $pool.Dispose()
        
        Write-Progress -Activity $ProgressActivity -Completed

        Write-Log "Ending Invoke-DowserRunspacePool"
        return $results.ToArray()
    }
}