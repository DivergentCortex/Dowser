#Requires -Version 5.1
<#
.SYNOPSIS
    Parallel text search across files using a RunspacePool.

.DESCRIPTION
    Invoke-DowserFastSearch searches for a single string across all files under
    a given path. Uses a RunspacePool for concurrent file scanning. Returns
    per-file match objects with file name, extension, matching line numbers,
    and full path.

    For multi-pattern or regex-based searching, use Find-DowserString instead.

.PARAMETER Path
    Root directory to search. Accepts pipeline input.

.PARAMETER SearchString
    The text string to search for. Aliased as -Pattern.

.PARAMETER Threads
    Number of concurrent worker runspaces. Default: 10.

.PARAMETER Include
    File type filter(s), e.g. '*.txt', '*.log'. Default: '*.*' (all files).

.PARAMETER Exclude
    File type exclusion filter(s).

.PARAMETER CaseSensitive
    Perform a case-sensitive search.

.EXAMPLE
    Invoke-DowserFastSearch -Path C:\Logs -SearchString 'ERROR'

.EXAMPLE
    Invoke-DowserFastSearch -Path . -Pattern 'timeout' -Include '*.log' -CaseSensitive

.EXAMPLE
    'C:\App\Logs','C:\App\Config' | Invoke-DowserFastSearch -SearchString 'ConnStr'

.NOTES
    Alias: dfast
    Source: Invoke-FastTextSearch.ps1 (standalone scripts)
    Related: Find-DowserString (multi-pattern, Aho-Corasick, multiple output modes)
#>
function Invoke-DowserFastSearch {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [Alias('Pattern')]
        [string]$SearchString,

        [Parameter(Mandatory = $false)]
        [int]$Threads = 10,

        [Parameter(Mandatory = $false)]
        [string[]]$Include = @('*.*'),

        [Parameter(Mandatory = $false)]
        [string[]]$Exclude,

        [Parameter(Mandatory = $false)]
        [switch]$CaseSensitive
    )

    begin {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        Write-Verbose "Invoke-DowserFastSearch: starting - pattern '$SearchString', threads $Threads"
    }

    process {
        $files = Get-ChildItem -Path $Path -Recurse -Include $Include -Exclude $Exclude -File

        if ($null -eq $files) {
            Write-Warning "No files found matching the specified criteria under '$Path'."
            return
        }

        Write-Verbose "Found $($files.Count) file(s) to search."

        $runspacePool = [runspacefactory]::CreateRunspacePool(1, $Threads)
        $runspacePool.Open()

        $jobs = @()
        $results = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))

        $scriptBlock = {
            param($filePath, $searchString, $caseSensitive)

            $selectStringParams = @{
                Path        = $filePath
                Pattern     = $searchString
                SimpleMatch = $true
                AllMatches  = $true
            }
            if ($caseSensitive) {
                $selectStringParams['CaseSensitive'] = $true
            }

            $matches = Select-String @selectStringParams

            if ($null -ne $matches) {
                $lineNumbers = $matches | ForEach-Object { $_.LineNumber }

                [pscustomobject]@{
                    FileName    = (Get-Item $filePath).Name
                    FileType    = (Get-Item $filePath).Extension
                    LineNumbers = $lineNumbers -join ', '
                    FullPath    = $filePath
                }
            }
        }

        foreach ($file in $files) {
            $ps = [powershell]::Create().AddScript($scriptBlock).AddArgument($file.FullName).AddArgument($SearchString).AddArgument($CaseSensitive.IsPresent)
            $ps.RunspacePool = $runspacePool

            $jobs += [pscustomobject]@{
                Instance = $ps
                Handle   = $ps.BeginInvoke()
            }
        }

        $totalFiles = $files.Count
        $completed = 0

        while ($jobs.Handle.IsCompleted -contains $false) {
            $completedJobs = $jobs | Where-Object { $_.Handle.IsCompleted }
            foreach ($job in $completedJobs) {
                $result = $job.Instance.EndInvoke($job.Handle)
                if ($null -ne $result) {
                    $results.Add($result) | Out-Null 
                }
                $job.Instance.Dispose()
                $completed++
                Write-Progress -Activity "Searching files" -Status "Completed $completed of $totalFiles" -PercentComplete (($completed / $totalFiles) * 100)
            }
            $jobs = $jobs | Where-Object { -not $_.Handle.IsCompleted }
            Start-Sleep -Milliseconds 100
        }

        # drain anything that finished in the last cycle
        foreach ($job in $jobs) {
            $result = $job.Instance.EndInvoke($job.Handle)
            if ($null -ne $result) {
                $results.Add($result) | Out-Null 
            }
            $job.Instance.Dispose()
            $completed++
            Write-Progress -Activity "Searching files" -Status "Completed $completed of $totalFiles" -PercentComplete (($completed / $totalFiles) * 100)
        }

        $runspacePool.Close()
        $runspacePool.Dispose()

        $stopwatch.Stop()
        Write-Verbose "Search complete: $($results.Count) match(es) across $totalFiles file(s) in $([math]::Round($stopwatch.Elapsed.TotalSeconds, 2))s"

        $results
    }
}
