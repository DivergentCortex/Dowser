function Find-DowserFile {
    <#
    .SYNOPSIS
        A high-performance file searching tool.

    .NOTES
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
        -  Author:        Curtis Leggett                                  -
        =  Copyright:     2026 Divergent Cortex                           =
        -  Organization:  Divergent Cortex                                -
        =  Version:       See docs/CHANGELOG.md                           =
        =-=-                       =-=-=-=-=-=-=-=                     -=-=
        -  it is not water they seek, but the truth beneath the trees     -
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

    .DESCRIPTION
        Searches for files by name, wildcards, size, and dates.
        Uses Runspaces for high-performance parallel processing.

    .PARAMETER Path
        The directory path(s) to search.

    .PARAMETER Pattern
        Wildcard pattern(s) to match file names (e.g., "*.ps1", "log_?.txt").
        Accepts a comma-separated list; a file matching any pattern is returned:
        -Pattern *.md,*.json. Partial strings are auto-wrapped in wildcards:
        "cortex" becomes "*cortex*". Each element is wrapped independently.

    .PARAMETER Recurse
        Search subdirectories recursively. Default is $true. Pass -Recurse:$false to disable.

    .PARAMETER MinSize
        Minimum file size (e.g., 1MB).

    .PARAMETER MaxSize
        Maximum file size (e.g., 1GB).

    .PARAMETER ModifiedAfter
        Find files modified after this date.

    .PARAMETER ModifiedBefore
        Find files modified before this date.

    .PARAMETER StopOnFirstMatch
        Return immediately after finding the first match.

    .PARAMETER UseRunspaces
        Enable multi-threaded processing. Default is $true. Pass -UseRunspaces:$false to disable.

    .PARAMETER ThreadCount
        Number of threads to use. Defaults to processor count.

    .EXAMPLE
        Find-DowserFile -Path "D:\Repos" -Pattern "*.ps1"

        Recursively finds all PowerShell scripts under D:\Repos using runspaces.

    .EXAMPLE
        Find-DowserFile -Path ~/projects/ClauDesk -Pattern *.md,*.json

        Returns every markdown and json file under the ClauDesk tree in one pass.

    .EXAMPLE
        Find-DowserFile -Path "D:\Logs" -Pattern "error" -ModifiedAfter (Get-Date).AddDays(-1) -MinSize 1MB

        Finds files whose name contains "error", modified in the last day, at least 1MB.

    .EXAMPLE
        'C:\Tools','D:\Scripts' | Find-DowserFile -Pattern "*.exe" -StopOnFirstMatch

        Pipes two roots in and returns the first matching executable found.

    .OUTPUTS
        PSCustomObject
        Properties: FullName, Name, Directory, Size, LastWriteTime, CreationTime.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [string[]]$Path,

        [Parameter(Position = 1)]
        [string[]]$Pattern = @("*"),

        [switch]$Recurse = $true,

        [string]$MinSize,
        [string]$MaxSize,

        [DateTime]$ModifiedAfter,
        [DateTime]$ModifiedBefore,

        [switch]$StopOnFirstMatch,

        [switch]$UseRunspaces = $true,
        [int]$ThreadCount = [Environment]::ProcessorCount
    )

    begin {
        $script:startTime = Get-Date
        Write-Log "Starting Find-DowserFile"
        
        $minBytes = $null
        if (-not [string]::IsNullOrWhiteSpace($MinSize)) {
            $minBytes = ConvertTo-DowserBytes -SizeStr $MinSize
        }
        $maxBytes = $null
        if (-not [string]::IsNullOrWhiteSpace($MaxSize)) {
            $maxBytes = ConvertTo-DowserBytes -SizeStr $MaxSize
        }

        # bare strings get wrapped, already-wildcarded left alone
        $Pattern = @(
            foreach ($pat in $Pattern) {
                if ($pat -ne "*" -and $pat -notmatch '[*?]') {
                    Write-Log "Pattern auto-wrapped to: *$pat*" -Severity Verbose
                    "*$pat*"
                }
                else {
                    $pat
                }
            }
        )

        # -Filter is a filesystem-level filter and takes exactly one pattern, so it stays
        # the fast path for the single-pattern case. Multiple patterns enumerate once and
        # test names in-process; one pass, no cross-pattern duplicates.
        $nameTest = $Pattern.Count -gt 1
    }

    process {
        foreach ($p in $Path) {
            if (-not (Test-Path $p)) {
                Write-Log "Find-DowserFile path not found: '$p'" -Severity Warning
                continue
            }
            $p = (Resolve-Path $p).Path

            Write-Progress -Activity "Find-DowserFile" -Status "Scanning directory structure..." -PercentComplete -1
            
            $filesFound = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
            
            if ($UseRunspaces) {
                # partition by top-level dirs to spread across threads. @() around the
                # enumeration matters: on a flat directory Get-ChildItem returns nothing,
                # $null.FullName is $null, and @($p) + @($null) hands the pool a target
                # list with a null in it, which its mandatory -InputObject rejects.
                $topLevelItems = @(Get-ChildItem -Path $p -Directory -ErrorAction SilentlyContinue)
                if ($Recurse -and $topLevelItems.Count -gt 0) {
                    $scanTargets = @($p) + @($topLevelItems.FullName)
                }
                else {
                    $scanTargets = @($p)
                }

                $scriptBlock = {
                    param($chunk, $patterns, $nameTest, $recurse, $min, $max, $after, $before)
                    $res = @()
                    foreach ($targetPath in $chunk) {
                        $params = @{
                            Path        = $targetPath
                            File        = $true
                            ErrorAction = 'SilentlyContinue'
                            Force       = $true
                        }
                        if ($recurse) {
                            $params['Recurse'] = $true 
                        }
                        if (-not $nameTest -and $patterns[0] -ne "*") {
                            $params['Filter'] = $patterns[0] 
                        }

                        Get-ChildItem @params | ForEach-Object {
                            $ok = $true
                            if ($nameTest) {
                                $ok = $false
                                foreach ($pat in $patterns) {
                                    if ($_.Name -like $pat) {
                                        $ok = $true
                                        break 
                                    }
                                }
                            }
                            if ($ok -and $min -and $_.Length -lt $min) {
                                $ok = $false 
                            }
                            if ($ok -and $max -and $_.Length -gt $max) {
                                $ok = $false 
                            }
                            if ($ok -and $after -and $_.LastWriteTime -lt $after) {
                                $ok = $false 
                            }
                            if ($ok -and $before -and $_.LastWriteTime -gt $before) {
                                $ok = $false 
                            }

                            if ($ok) {
                                $res += $_.FullName
                            }
                        }
                    }
                    return $res
                }

                $results = Invoke-DowserRunspacePool -InputObject $scanTargets -ScriptBlock $scriptBlock -ArgumentList @($Pattern, $nameTest, $Recurse, $minBytes, $maxBytes, $ModifiedAfter, $ModifiedBefore) -ThreadCount $ThreadCount -ProgressActivity "Scanning Files" -ProgressStatus "Scanning targets..."
                
                foreach ($r in $results) {
                    $filesFound.Add($r) 
                }
            }
            else {
                $params = @{
                    Path        = $p
                    Recurse     = $Recurse
                    File        = $true
                    ErrorAction = 'SilentlyContinue'
                    Force       = $true
                }
                if (-not $nameTest -and $Pattern[0] -ne "*") {
                    $params['Filter'] = $Pattern[0] 
                }
                
                Get-ChildItem @params | ForEach-Object {
                    $ok = $true
                    if ($nameTest) {
                        $ok = $false
                        foreach ($pat in $Pattern) {
                            if ($_.Name -like $pat) {
                                $ok = $true
                                break 
                            }
                        }
                    }
                    if ($ok -and $minBytes -and $_.Length -lt $minBytes) {
                        $ok = $false 
                    }
                    if ($ok -and $maxBytes -and $_.Length -gt $maxBytes) {
                        $ok = $false 
                    }
                    if ($ok -and $ModifiedAfter -and $_.LastWriteTime -lt $ModifiedAfter) {
                        $ok = $false 
                    }
                    if ($ok -and $ModifiedBefore -and $_.LastWriteTime -gt $ModifiedBefore) {
                        $ok = $false 
                    }

                    if ($ok) {
                        $filesFound.Add($_.FullName)
                        if ($StopOnFirstMatch) {
                            return 
                        }
                    }
                }
            }

            # @() keeps an empty result an empty array. Unwrapped, no matches leaves $allPaths
            # $null, @($null).Count is 1, and the formatter below emits one row of nulls.
            $allPaths = @(Select-DowserUniquePath -Path $filesFound.ToArray())
            $count = @($allPaths).Count
            Write-Log "Found $count files matching basic criteria." -Severity Verbose
            
            if ($count -gt 0) {
                Write-Progress -Activity "Find-DowserFile" -Status "Retrieving file objects..." -PercentComplete -1
                if ($StopOnFirstMatch) {
                    $firstFile = Get-Item -LiteralPath $allPaths[0] -ErrorAction SilentlyContinue
                    if ($firstFile) {
                        [PSCustomObject]@{
                            FullName      = $firstFile.FullName
                            Name          = $firstFile.Name
                            Directory     = $firstFile.DirectoryName
                            Size          = $firstFile.Length
                            LastWriteTime = $firstFile.LastWriteTime
                            CreationTime  = $firstFile.CreationTime
                        }
                    }
                }
                else {
                    $allPaths | ForEach-Object {
                        $f = Get-Item -LiteralPath $_ -ErrorAction SilentlyContinue
                        if (-not $f) {
                            # path was enumerated but will not resolve: dangling symlink, or it
                            # was deleted mid-scan. Emitting it yields a row of null properties.
                            Write-Log "Skipping unresolvable path: $_" -Severity Verbose
                            return
                        }
                        [PSCustomObject]@{
                            FullName      = $f.FullName
                            Name          = $f.Name
                            Directory     = $f.DirectoryName
                            Size          = $f.Length
                            LastWriteTime = $f.LastWriteTime
                            CreationTime  = $f.CreationTime
                        }
                    }
                }
            }
        }
    }
    end {
        $duration = New-TimeSpan -Start $script:startTime -End (Get-Date)
        Write-Log "Ending Find-DowserFile (completed in $($duration.TotalSeconds) seconds)"
    }
}