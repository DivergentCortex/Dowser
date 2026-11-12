#Requires -Version 5.1

function Invoke-DowserMapIndexWorker {
    <#
    .SYNOPSIS
        Lists queued directories for the Get-DowserMap index until the shared queue drains.
    .DESCRIPTION
        Pulls directories from MapIndex_Pending, records each one's child folders and
        whether it directly holds a file that passes the active file filter, and queues
        every child folder for listing. Runs inside the Invoke-DowserMapIndexScan pool,
        where the Get-DowserMap filter helpers and their variables are preloaded.
    .PARAMETER Sync
        The module SyncHash carrying the MapIndex_ keys.
    .PARAMETER WorkerId
        Identifier recorded in MapIndex_WorkerStatus.
    .OUTPUTS
        None. Results are written to Sync.MapIndex_Dirs.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Sync,

        [Parameter(Mandatory = $true)]
        [int]$WorkerId
    )

    $Sync.MapIndex_WorkerStatus[$WorkerId] = 'Running'
    $opts = $Sync.MapIndex_Options
    $skipAttributes = [IO.FileAttributes]::Hidden -bor [IO.FileAttributes]::System
    $reparse = [IO.FileAttributes]::ReparsePoint
    $entry = $null

    while ($true) {
        if (-not $Sync.MapIndex_Pending.TryDequeue([ref]$entry)) {
            if ($Sync.MapIndex_Outstanding.IsSet -or $Sync.Cancellation) {
                break
            }
            Start-Sleep -Milliseconds 5
            continue
        }

        $dirPath = $entry.Path
        try {
            $directMatch = -not $opts.FileFilterActive
            $children = [System.Collections.Generic.List[object]]::new()
            foreach ($item in [IO.DirectoryInfo]::new($dirPath).EnumerateFileSystemInfos()) {
                $isDir = $item -is [IO.DirectoryInfo]
                if (-not $opts.IncludeHidden -and ($item.Attributes -band $skipAttributes)) {
                    # a hidden folder you named still gets in, the rest of the dotfiles stay home
                    if (-not ($isDir -and $opts.IncludeFoldersActive -and (Test-FolderMatchesInclude $item))) {
                        continue
                    }
                }
                if ($isDir) {
                    if (($item.Attributes -band $reparse) -and -not $opts.FollowReparse) {
                        continue
                    }
                    $children.Add([pscustomobject]@{
                        Key      = (ConvertTo-NativeSeparator $item.FullName).ToLowerInvariant()
                        ByPath   = [bool](Test-ExcludeByPath $item)
                        ByRule   = [bool](Test-FolderExcludedByRule $item)
                        Matches  = $opts.IncludeFoldersActive -and [bool](Test-FolderMatchesInclude $item)
                        Ancestor = $opts.IncludeFoldersActive -and [bool](Test-FolderIsIncludePathAncestor $item)
                    })
                    if ($entry.Depth -lt $opts.DepthLimit) {
                        $Sync.MapIndex_Outstanding.AddCount()
                        $Sync.MapIndex_Pending.Enqueue([pscustomobject]@{ Path = $item.FullName; Depth = $entry.Depth + 1 })
                    }
                }
                elseif (-not $directMatch) {
                    # the extension set is Test-IncludeFile's first rejection, checked here without a call
                    if ($opts.IncludeExtensionSet.Count -gt 0 -and -not $opts.IncludeExtensionSet.Contains($item.Extension)) {
                        continue
                    }
                    $directMatch = [bool](Test-IncludeFile $item)
                }
            }
            $Sync.MapIndex_Dirs[(ConvertTo-NativeSeparator $dirPath).ToLowerInvariant()] = [pscustomobject]@{
                Depth       = $entry.Depth
                DirectMatch = $directMatch
                Children    = $children.ToArray()
            }
        }
        catch {
            $Sync.MapIndex_Errors.Add([pscustomobject]@{
                TaskId        = $WorkerId
                Operation     = 'DirectoryList'
                Target        = $dirPath
                ExceptionType = $_.Exception.GetType().Name
                Message       = $_.Exception.Message
                Exception     = $_
            })
            $Sync.LogQueue.Enqueue(@{ Severity = 'Verbose'; Message = "DirectoryList failed on '$dirPath': $($_.Exception.GetType().Name): $($_.Exception.Message)" })
        }
        $Sync.MapIndex_Outstanding.Signal() | Out-Null
    }

    $Sync.MapIndex_WorkerStatus[$WorkerId] = 'Complete'
}
