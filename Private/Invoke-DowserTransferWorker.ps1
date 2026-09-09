#Requires -Version 5.1

function Invoke-DowserTransferWorker {
    <#
    .SYNOPSIS
        Runspace worker: dequeues transfer items and performs hash-copy-hash-verify.

    .DESCRIPTION
        Pulls transfer items from $Sync.Pending until the queue is empty. For each item:
        hashes the source file (SHA256), copies it to the destination, hashes the
        destination, and marks the item verified only when the two hashes match. Each
        step is its own try/catch; a failed step skips the remaining steps for that item
        but the loop continues to the next item. Never calls Write-Log directly (workers
        are not guaranteed thread-safe against the log file) -- log lines go onto
        $Sync.LogQueue for the main thread to drain. Never throws; every item produces a
        structured result on $Sync.Results.

    .PARAMETER Sync
        Synchronized hashtable shared across the pool. Requires Pending (ConcurrentQueue
        of objects with SourcePath/DestinationPath), Results (ConcurrentQueue for
        structured per-item outcomes), and LogQueue (ConcurrentQueue of @{Severity;Message}).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Sync
    )

    $item = $null
    while ($Sync.Pending.TryDequeue([ref]$item)) {
        $sourcePath = $item.SourcePath
        $destinationPath = $item.DestinationPath
        $sourceHash = $null
        $destHash = $null
        $bytesCopied = 0
        $stepOk = $true
        $errorMessage = $null

        try {
            $sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256 -ErrorAction Stop).Hash
        }
        catch {
            $stepOk = $false
            $errorMessage = "SourceHash failed on '$sourcePath': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"
            $Sync.LogQueue.Enqueue(@{ Severity = 'Error'; Message = $errorMessage })
        }

        if ($stepOk) {
            try {
                $destDir = Split-Path -Path $destinationPath -Parent
                if ($destDir -and -not (Test-Path -LiteralPath $destDir)) {
                    New-Item -ItemType Directory -Path $destDir -Force -ErrorAction Stop | Out-Null
                }
            }
            catch {
                $stepOk = $false
                $errorMessage = "Destination directory creation failed for '$destinationPath': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"
                $Sync.LogQueue.Enqueue(@{ Severity = 'Error'; Message = $errorMessage })
            }
        }

        if ($stepOk) {
            try {
                Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force -ErrorAction Stop
            }
            catch {
                $stepOk = $false
                $errorMessage = "Copy failed '$sourcePath' -> '$destinationPath': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"
                $Sync.LogQueue.Enqueue(@{ Severity = 'Error'; Message = $errorMessage })
            }
        }

        if ($stepOk) {
            try {
                $bytesCopied = (Get-Item -LiteralPath $destinationPath -ErrorAction Stop).Length
            }
            catch {
                $stepOk = $false
                $errorMessage = "Destination stat failed on '$destinationPath': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"
                $Sync.LogQueue.Enqueue(@{ Severity = 'Error'; Message = $errorMessage })
            }
        }

        if ($stepOk) {
            try {
                $destHash = (Get-FileHash -LiteralPath $destinationPath -Algorithm SHA256 -ErrorAction Stop).Hash
            }
            catch {
                $stepOk = $false
                $errorMessage = "DestHash failed on '$destinationPath': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"
                $Sync.LogQueue.Enqueue(@{ Severity = 'Error'; Message = $errorMessage })
            }
        }

        $verified = $false
        if ($stepOk) {
            if ($destHash -eq $sourceHash) {
                $verified = $true
                $Sync.LogQueue.Enqueue(@{ Severity = 'Verbose'; Message = "Verified '$sourcePath' -> '$destinationPath' ($bytesCopied bytes)" })
            }
            else {
                $errorMessage = "Hash mismatch '$sourcePath' -> '$destinationPath': source=$sourceHash dest=$destHash"
                $Sync.LogQueue.Enqueue(@{ Severity = 'Error'; Message = $errorMessage })
            }
        }

        $Sync.Results.Enqueue([pscustomobject]@{
            Success         = $verified
            SourcePath      = $sourcePath
            DestinationPath = $destinationPath
            SourceHash      = $sourceHash
            DestHash        = $destHash
            BytesCopied     = $bytesCopied
            Error           = $errorMessage
        })
        $item = $null
    }
}
