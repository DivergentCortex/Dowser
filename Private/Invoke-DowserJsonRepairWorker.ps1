#Requires -Version 5.1

function Invoke-DowserJsonRepairWorker {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Sync
    )

    $moveSourceToTriage = {
        param(
            [pscustomobject]$Task,
            [hashtable]$Sync
        )

        $outputDiagnosis = Get-DowserJsonDiagnosis -FilePath $Task.OutputPath
        if ($outputDiagnosis.Classification -notin 'ValidJson', 'ValidJsonl') {
            return [pscustomobject]@{
                Success      = $false
                ErrorMessage = "Repaired copy is not parseable: $($outputDiagnosis.Classification)."
            }
        }

        $triageDirectory = Split-Path -Parent $Task.TriagePath
        try {
            if (-not (Test-Path -LiteralPath $triageDirectory)) {
                New-Item -ItemType Directory -Path $triageDirectory -Force -ErrorAction Stop | Out-Null
            }
        }
        catch {
            $Sync.LogQueue.Enqueue([pscustomobject]@{
                Message  = "Repair-DowserJson could not create triage directory '$triageDirectory': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"
                Severity = 'Error'
            })
            return [pscustomobject]@{ Success = $false; ErrorMessage = $_.Exception.Message }
        }

        if (Test-Path -LiteralPath $Task.TriagePath) {
            return [pscustomobject]@{
                Success      = $false
                ErrorMessage = "Triage destination already exists: $($Task.TriagePath)"
            }
        }

        try {
            Move-Item -LiteralPath $Task.FilePath -Destination $Task.TriagePath -ErrorAction Stop
            return [pscustomobject]@{ Success = $true; ErrorMessage = $null }
        }
        catch {
            $Sync.LogQueue.Enqueue([pscustomobject]@{
                Message  = "Repair-DowserJson could not move '$($Task.FilePath)' into triage: $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"
                Severity = 'Error'
            })
            return [pscustomobject]@{ Success = $false; ErrorMessage = $_.Exception.Message }
        }
    }

    $task = $null
    while ($Sync.Pending.TryDequeue([ref]$task)) {
        $result = $null
        try {
            $diagnosis = Get-DowserJsonDiagnosis -FilePath $task.FilePath
            if (-not $diagnosis.Repairable) {
                $result = [pscustomobject]@{
                    FilePath       = $diagnosis.FilePath
                    Classification = $diagnosis.Classification
                    Repairable     = $false
                    RepairAction   = $diagnosis.RepairAction
                    Documents      = $diagnosis.Documents
                    ErrorLine      = $diagnosis.ErrorLine
                    ErrorPosition  = $diagnosis.ErrorPosition
                    ErrorMessage   = $diagnosis.ErrorMessage
                    Result         = 'Skipped'
                    OutputPath     = $null
                    TriagePath     = $null
                    SourceMoved    = $false
                }
            }
            elseif (-not $Sync.WriteEnabled) {
                $result = [pscustomobject]@{
                    FilePath       = $diagnosis.FilePath
                    Classification = $diagnosis.Classification
                    Repairable     = $true
                    RepairAction   = $diagnosis.RepairAction
                    Documents      = $diagnosis.Documents
                    ErrorLine      = $diagnosis.ErrorLine
                    ErrorPosition  = $diagnosis.ErrorPosition
                    ErrorMessage   = $null
                    Result         = 'WhatIf'
                    OutputPath     = $task.OutputPath
                    TriagePath     = $task.TriagePath
                    SourceMoved    = $false
                }
            }
            else {
                [System.Threading.Monitor]::Enter($Sync.OutputLocks.SyncRoot)
                try {
                    if (-not $Sync.OutputLocks.ContainsKey($task.OutputPath)) {
                        $Sync.OutputLocks[$task.OutputPath] = [object]::new()
                    }
                    $outputLock = $Sync.OutputLocks[$task.OutputPath]
                }
                finally {
                    [System.Threading.Monitor]::Exit($Sync.OutputLocks.SyncRoot)
                }

                [System.Threading.Monitor]::Enter($outputLock)
                try {
                    if ((Test-Path -LiteralPath $task.OutputPath) -and -not $task.Force) {
                        $triageResult = & $moveSourceToTriage $task $Sync
                        $result = [pscustomobject]@{
                            FilePath       = $diagnosis.FilePath
                            Classification = $diagnosis.Classification
                            Repairable     = $true
                            RepairAction   = $diagnosis.RepairAction
                            Documents      = $diagnosis.Documents
                            ErrorLine      = $diagnosis.ErrorLine
                            ErrorPosition  = $diagnosis.ErrorPosition
                            ErrorMessage   = $triageResult.ErrorMessage
                            Result         = if ($triageResult.Success) { 'TriagedExistingRepair' } else { 'ExistingRepairTriageFailed' }
                            OutputPath     = $task.OutputPath
                            TriagePath     = $task.TriagePath
                            SourceMoved    = $triageResult.Success
                        }
                    }
                    else {
                        $writeResult = Write-DowserJsonRepair -Diagnosis $diagnosis -OutputPath $task.OutputPath -Sync $Sync
                        if (-not $writeResult.Success) {
                            $result = [pscustomobject]@{
                                FilePath       = $diagnosis.FilePath
                                Classification = $diagnosis.Classification
                                Repairable     = $true
                                RepairAction   = $diagnosis.RepairAction
                                Documents      = 0
                                ErrorLine      = $diagnosis.ErrorLine
                                ErrorPosition  = $diagnosis.ErrorPosition
                                ErrorMessage   = $writeResult.ErrorMessage
                                Result         = 'Failed'
                                OutputPath     = $null
                                TriagePath     = $task.TriagePath
                                SourceMoved    = $false
                            }
                        }
                        else {
                            $triageResult = & $moveSourceToTriage $task $Sync
                            $result = [pscustomobject]@{
                                FilePath       = $diagnosis.FilePath
                                Classification = $diagnosis.Classification
                                Repairable     = $true
                                RepairAction   = $diagnosis.RepairAction
                                Documents      = $writeResult.DocumentsWritten
                                ErrorLine      = $diagnosis.ErrorLine
                                ErrorPosition  = $diagnosis.ErrorPosition
                                ErrorMessage   = $triageResult.ErrorMessage
                                Result         = if ($triageResult.Success) { 'Repaired' } else { 'RepairSucceededTriageFailed' }
                                OutputPath     = $task.OutputPath
                                TriagePath     = $task.TriagePath
                                SourceMoved    = $triageResult.Success
                            }
                        }
                    }
                }
                finally {
                    [System.Threading.Monitor]::Exit($outputLock)
                }
            }
        }
        catch {
            $Sync.LogQueue.Enqueue([pscustomobject]@{
                Message  = "Repair-DowserJson worker failed for '$($task.FilePath)': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"
                Severity = 'Error'
            })
            $result = [pscustomobject]@{
                FilePath       = $task.FilePath
                Classification = 'WorkerFailure'
                Repairable     = $false
                RepairAction   = $null
                Documents      = 0
                ErrorLine      = $null
                ErrorPosition  = $null
                ErrorMessage   = $_.Exception.Message
                Result         = 'Failed'
                OutputPath     = $null
                TriagePath     = $task.TriagePath
                SourceMoved    = $false
            }
        }
        finally {
            if ($null -ne $result) {
                $Sync.Results.Enqueue($result)
            }
            $Sync.Progress.Enqueue(1)
            $task = $null
        }
    }
}
