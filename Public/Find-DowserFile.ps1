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

    .PARAMETER ExcludePattern
        Wildcard pattern(s) to exclude, tested against both the item's bare name and its
        full path (e.g., "*.rustup*", "*node_modules*"). A bare string without wildcard
        characters is auto-wrapped the same way -Pattern is: "rustup" becomes "*rustup*".
        A directory matching any exclude pattern is pruned and never descended into, so
        excluding a large toolchain or dependency tree also cuts search time. A matching
        file is dropped from the results.

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

    .EXAMPLE
        Find-DowserFile -Path ~/ -Pattern "*.vbs" -ExcludePattern "*.rustup*","*node_modules*"

        Searches the home directory for files matching *.vbs. Both the rustup toolchain
        and node_modules trees are pruned from the walk entirely, not merely filtered
        out of the results afterward.

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

        [string[]]$ExcludePattern,

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

        # -Filter runs at the filesystem level but takes exactly one pattern, so it stays the
        # fast path for a single pattern. several patterns enumerate once and test names
        # in-process, which also avoids cross-pattern duplicates
        $nameTest = $Pattern.Count -gt 1

        # same auto-wrap as -Pattern, tested against Name and FullName so a bare folder name
        # ("node_modules") and a path fragment ("/cache/") both work. blank entries are
        # dropped: "" would wrap to "**", match everything, and silently exclude the whole
        # tree (easy to hit with a stray comma in a split string)
        $ExcludePattern = @(
            foreach ($pat in $ExcludePattern) {
                if ([string]::IsNullOrWhiteSpace($pat)) {
                    Write-Log "ExcludePattern: dropping a blank entry (would otherwise exclude everything)" -Severity Warning
                    continue
                }
                if ($pat -ne "*" -and $pat -notmatch '[*?]') {
                    Write-Log "ExcludePattern auto-wrapped to: *$pat*" -Severity Verbose
                    "*$pat*"
                }
                else {
                    $pat
                }
            }
        )
        $hasExclude = @($ExcludePattern).Count -gt 0
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
                # split by top-level dirs to spread work across threads. the @() matters: on a
                # flat directory Get-ChildItem returns nothing, and a $null in the target list
                # makes the pool's mandatory -InputObject throw
                # -Force so hidden top-level dirs show up, since nothing else scans their contents
                # skipped for -Recurse:$false, where $scanTargets is just @($p) anyway
                $topLevelItems = @()
                if ($Recurse) {
                    $topLevelItems = @(Get-ChildItem -Path $p -Directory -Force -ErrorAction SilentlyContinue)
                    if ($topLevelItems.Count -gt 0) {
                        # each top-level dir becomes its own scan root. Get-ChildItem -Recurse skips
                        # symlinked dirs it meets mid-walk but not one it is told to start in, so
                        # drop reparse points here or the real target's files come back twice under
                        # the link's path. a link's content is reachable through its real path only
                        $topLevelItems = @($topLevelItems | Where-Object {
                                ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0
                            })
                    }
                    if ($hasExclude -and $topLevelItems.Count -gt 0) {
                        # the in-worker exclude check only sees children found mid-walk, never a
                        # worker's own starting dir, so filter excluded top-level dirs here or a
                        # folder like .rustup still gets a dedicated worker that walks it in full
                        $topLevelItems = @($topLevelItems | Where-Object {
                                $item = $_
                                -not (@($ExcludePattern) | Where-Object { $item.Name -like $_ -or $item.FullName -like $_ })
                            })
                    }
                }
                if ($Recurse -and $topLevelItems.Count -gt 0) {
                    $scanTargets = @($p) + @($topLevelItems.FullName)
                }
                else {
                    $scanTargets = @($p)
                }

                # shared by every worker so one match can stop all the walks. a plain variable
                # wouldn't work since each runspace only sees the value it was handed at
                # dispatch. a synchronized hashtable is a live reference they can all read and
                # write (same trick as $progressQueue in Invoke-DowserRunspacePool). only built
                # for -StopOnFirstMatch so the common case pays nothing
                $stopSignal = if ($StopOnFirstMatch) { [hashtable]::Synchronized(@{ Stop = $false }) } else { $null }

                $scriptBlock = {
                    param($chunk, $patterns, $nameTest, $recurse, $min, $max, $after, $before, $excludePatterns, $rootPath, $stopOnFirst, $stopSignal)
                    $res = @()

                    function Test-DowserFileExcluded($item, $patternsToTest) {
                        foreach ($ep in $patternsToTest) {
                            if ($item.Name -like $ep -or $item.FullName -like $ep) {
                                return $true
                            }
                        }
                        return $false
                    }

                    function Test-DowserFileReparsePoint($item) {
                        try {
                            return ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
                        }
                        catch {
                            return $false
                        }
                    }

                    foreach ($targetPath in $chunk) {
                        # check before each new target too, so a queued chunk that hasn't started
                        # bails as soon as another worker has found a match
                        if ($stopOnFirst -and $stopSignal.Stop) {
                            break
                        }

                        # the search root ($p in the caller) is walked non-recursively: each of its
                        # subdirectories already has its own target, so recursing here too would
                        # scan every subtree twice
                        $targetRecurse = $recurse -and ($targetPath -ne $rootPath)

                        if (@($excludePatterns).Count -gt 0 -or $stopOnFirst) {
                            # manual per-directory stack walk instead of Get-ChildItem -Recurse. it is
                            # needed for -ExcludePattern (an excluded dir is never pushed, whereas
                            # -Exclude only hides it from output and still recurses) and for
                            # -StopOnFirstMatch (Get-ChildItem -Recurse buffers most of its listing
                            # before the loop sees the first item, so breaking early saves almost
                            # nothing). one directory per Get-ChildItem call keeps the gap between
                            # stop-signal checks small
                            #
                            # reparse-point dirs are never pushed, matching Get-ChildItem -Recurse:
                            # a symlink would return the same file under two paths, and a cycle
                            # (A/link -> A) would grow the stack until the OS path limit
                            $stack = New-Object 'System.Collections.Generic.Stack[string]'
                            $stack.Push($targetPath)
                            # labeled so one break leaves both the while and the foreach; a plain
                            # break would only exit the foreach and the while would keep walking
                            # whatever is left on the stack
                            :walkLoop while ($stack.Count -gt 0) {
                                if ($stopOnFirst -and $stopSignal.Stop) {
                                    break walkLoop
                                }
                                $currentDir = $stack.Pop()
                                $children = Get-ChildItem -LiteralPath $currentDir -Force -ErrorAction SilentlyContinue
                                foreach ($child in $children) {
                                    # per child too, so a match elsewhere is noticed inside a
                                    # directory with thousands of entries
                                    if ($stopOnFirst -and $stopSignal.Stop) {
                                        break walkLoop
                                    }
                                    if ($child.PSIsContainer) {
                                        if ($targetRecurse -and -not (Test-DowserFileReparsePoint $child) -and -not (Test-DowserFileExcluded $child $excludePatterns)) {
                                            $stack.Push($child.FullName)
                                        }
                                        continue
                                    }
                                    if (Test-DowserFileExcluded $child $excludePatterns) {
                                        continue
                                    }
                                    $ok = $false
                                    foreach ($pat in $patterns) {
                                        if ($child.Name -like $pat) {
                                            $ok = $true
                                            break
                                        }
                                    }
                                    if ($ok -and $min -and $child.Length -lt $min) {
                                        $ok = $false
                                    }
                                    if ($ok -and $max -and $child.Length -gt $max) {
                                        $ok = $false
                                    }
                                    if ($ok -and $after -and $child.LastWriteTime -lt $after) {
                                        $ok = $false
                                    }
                                    if ($ok -and $before -and $child.LastWriteTime -gt $before) {
                                        $ok = $false
                                    }
                                    if ($ok) {
                                        $res += $child.FullName
                                        if ($stopOnFirst) {
                                            $stopSignal.Stop = $true
                                            break walkLoop
                                        }
                                    }
                                }
                            }
                            continue
                        }

                        # fast path, only reached without -ExcludePattern or -StopOnFirstMatch,
                        # so it never needs early termination
                        $params = @{
                            Path        = $targetPath
                            File        = $true
                            ErrorAction = 'SilentlyContinue'
                            Force       = $true
                        }
                        if ($targetRecurse) {
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

                $results = Invoke-DowserRunspacePool -InputObject $scanTargets -ScriptBlock $scriptBlock -ArgumentList @($Pattern, $nameTest, $Recurse, $minBytes, $maxBytes, $ModifiedAfter, $ModifiedBefore, $ExcludePattern, $p, $StopOnFirstMatch, $stopSignal) -ThreadCount $ThreadCount -ProgressActivity "Scanning Files" -ProgressStatus "Scanning targets..."
                
                foreach ($r in $results) {
                    $filesFound.Add($r) 
                }
            }
            elseif ($hasExclude) {
                # manual stack walk so an excluded dir is never pushed (-Exclude only hides
                # output, it doesn't stop recursion). reparse-point dirs are skipped too,
                # otherwise a symlink returns the same file twice and a cycle (A/link -> A)
                # grows the stack until the OS path limit
                $stack = New-Object 'System.Collections.Generic.Stack[string]'
                $stack.Push($p)
                while ($stack.Count -gt 0) {
                    $currentDir = $stack.Pop()
                    $children = Get-ChildItem -LiteralPath $currentDir -Force -ErrorAction SilentlyContinue
                    foreach ($child in $children) {
                        $excluded = $false
                        foreach ($ep in $ExcludePattern) {
                            if ($child.Name -like $ep -or $child.FullName -like $ep) {
                                $excluded = $true
                                break
                            }
                        }

                        if ($child.PSIsContainer) {
                            $isReparse = $false
                            try {
                                $isReparse = ($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
                            }
                            catch {
                                $isReparse = $false
                            }
                            if ($Recurse -and -not $isReparse -and -not $excluded) {
                                $stack.Push($child.FullName)
                            }
                            continue
                        }
                        if ($excluded) {
                            continue
                        }

                        $ok = $false
                        foreach ($pat in $Pattern) {
                            if ($child.Name -like $pat) {
                                $ok = $true
                                break
                            }
                        }
                        if ($ok -and $minBytes -and $child.Length -lt $minBytes) {
                            $ok = $false
                        }
                        if ($ok -and $maxBytes -and $child.Length -gt $maxBytes) {
                            $ok = $false
                        }
                        if ($ok -and $ModifiedAfter -and $child.LastWriteTime -lt $ModifiedAfter) {
                            $ok = $false
                        }
                        if ($ok -and $ModifiedBefore -and $child.LastWriteTime -gt $ModifiedBefore) {
                            $ok = $false
                        }

                        if ($ok) {
                            $filesFound.Add($child.FullName)
                            if ($StopOnFirstMatch) {
                                $stack.Clear()
                                break
                            }
                        }
                    }
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
                
                # foreach, not Get-ChildItem | ForEach-Object: a return inside ForEach-Object only
                # skips to the next pipeline item and never stops enumeration, so
                # -StopOnFirstMatch would still walk the whole listing. a real loop lets break halt it
                foreach ($item in (Get-ChildItem @params)) {
                    $ok = $true
                    if ($nameTest) {
                        $ok = $false
                        foreach ($pat in $Pattern) {
                            if ($item.Name -like $pat) {
                                $ok = $true
                                break 
                            }
                        }
                    }
                    if ($ok -and $minBytes -and $item.Length -lt $minBytes) {
                        $ok = $false 
                    }
                    if ($ok -and $maxBytes -and $item.Length -gt $maxBytes) {
                        $ok = $false 
                    }
                    if ($ok -and $ModifiedAfter -and $item.LastWriteTime -lt $ModifiedAfter) {
                        $ok = $false 
                    }
                    if ($ok -and $ModifiedBefore -and $item.LastWriteTime -gt $ModifiedBefore) {
                        $ok = $false 
                    }

                    if ($ok) {
                        $filesFound.Add($item.FullName)
                        if ($StopOnFirstMatch) {
                            break
                        }
                    }
                }
            }

            # @() keeps no-match as an empty array; unwrapped it is $null, @($null).Count is 1,
            # and the formatter below would emit a row of nulls
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
                            # enumerated but won't resolve (dangling symlink, or deleted mid-scan);
                            # emitting it would give a row of null properties
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