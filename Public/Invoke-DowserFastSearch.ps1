#Requires -Version 5.1

function Invoke-DowserFastSearch {
    <#
    .SYNOPSIS
        Parallel text search across files using a RunspacePool.

    .NOTES
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
        -  Author:        Curtis Leggett                                  -
        =  Copyright:     2026 Divergent Cortex                           =
        -  Organization:  Divergent Cortex                                -
        =  Version:       See docs/CHANGELOG.md                           =
        =-=-                       =-=-=-=-=-=-=-=                     -=-=
        -  it is not water they seek, but the truth beneath the trees     -
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

        Alias: dfast
        Source: Invoke-FastTextSearch.ps1 (standalone scripts)
        Related: Find-DowserString (multi-pattern, Aho-Corasick, multiple output modes)

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

        Searches every file under C:\Logs for the literal string ERROR.

    .EXAMPLE
        Invoke-DowserFastSearch -Path . -Pattern 'timeout' -Include '*.log' -CaseSensitive

        Case-sensitive search for 'timeout' across .log files under the current directory.

    .EXAMPLE
        'C:\App\Logs','C:\App\Config' | Invoke-DowserFastSearch -SearchString 'ConnStr'

        Pipes two paths in and searches both for ConnStr.

    .INPUTS
        System.String
        A directory path can be piped to this function.

    .OUTPUTS
        PSCustomObject
        Properties: FileName, FileType, LineNumbers, FullPath.
    #>
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
        Write-Log "Starting Invoke-DowserFastSearch"
        Write-Log "Invoke-DowserFastSearch: pattern '$SearchString', threads $Threads"
    }

    process {
        $files = Get-ChildItem -Path $Path -Recurse -Include $Include -Exclude $Exclude -File

        if ($null -eq $files) {
            Write-Log "Invoke-DowserFastSearch: no files found matching the specified criteria under '$Path'" -Severity Warning
            return
        }

        Write-Log "Invoke-DowserFastSearch: found $($files.Count) file(s) to search"

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

        try {
            $runspacePool.Close()
            $runspacePool.Dispose()
        }
        catch {
            Write-Log "Invoke-DowserFastSearch failed disposing runspace pool: $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Error
        }

        $stopwatch.Stop()
        Write-Log "Invoke-DowserFastSearch: search complete - $($results.Count) match(es) across $totalFiles file(s) in $([math]::Round($stopwatch.Elapsed.TotalSeconds, 2))s"
        Write-Log "Ending Invoke-DowserFastSearch"

        $results
    }
}
