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
        A directory matching any exclude pattern is pruned outright -- Find-DowserFile
        never descends into it, so excluding a large toolchain or dependency tree also
        cuts search time, not just result noise. A file matching an exclude pattern is
        dropped from the results the same way.

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

        # -Filter is a filesystem-level filter and takes exactly one pattern, so it stays
        # the fast path for the single-pattern case. Multiple patterns enumerate once and
        # test names in-process; one pass, no cross-pattern duplicates.
        $nameTest = $Pattern.Count -gt 1

        # Same auto-wrap rule as -Pattern. Tested against both Name and FullName so a bare
        # folder name ("node_modules") and a path fragment ("/cache/") both work. A blank
        # element is dropped rather than wrapped: "" would otherwise become "**", which
        # -like matches against everything, silently excluding the entire tree with no
        # error -- a plausible outcome of building the list from a split string with a
        # stray leading/trailing comma.
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
                # partition by top-level dirs to spread across threads. @() around the
                # enumeration matters: on a flat directory Get-ChildItem returns nothing,
                # $null.FullName is $null, and @($p) + @($null) hands the pool a target
                # list with a null in it, which its mandatory -InputObject rejects.
                # -Force matters here: without it a hidden top-level directory never shows up
                # in this listing at all, and once $p's own worker below stops recursing
                # through every subdirectory (see the double-scan fix further down), nothing
                # else would ever scan a hidden directory's contents either.
                # Skipped entirely when -Recurse:$false: $scanTargets falls straight to
                # @($p) below regardless of what this would compute, so the enumeration and
                # its filtering would only be discarded work.
                $topLevelItems = @()
                if ($Recurse) {
                    $topLevelItems = @(Get-ChildItem -Path $p -Directory -Force -ErrorAction SilentlyContinue)
                    if ($topLevelItems.Count -gt 0) {
                        # A top-level subdirectory becomes its own parallel scan target below, its
                        # FullName handed to a worker as the explicit root of that worker's walk.
                        # Get-ChildItem -Recurse never follows a symlinked directory it ENCOUNTERS
                        # mid-walk, but that rule does not apply to the root a worker is explicitly
                        # told to start at, so a reparse-point directory sitting directly at the top
                        # level must be dropped here unconditionally, not only when -ExcludePattern
                        # happens to be active. Left in, its dedicated worker walks straight through
                        # it and every file under the real target comes back a second time, reported
                        # under the symlink's own path (confirmed by direct execution, decision
                        # recorded 2026-09-15). Matches Get-DowserMap's documented -FollowReparse
                        # default-off convention: a symlink's content is reachable through its real
                        # path, never through the link.
                        $topLevelItems = @($topLevelItems | Where-Object {
                                ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0
                            })
                    }
                    if ($hasExclude -and $topLevelItems.Count -gt 0) {
                        # A top-level subdirectory becomes its own parallel scan target below (its
                        # FullName is pushed straight onto that worker's stack as the walk root), so
                        # it must be tested here too -- the in-worker exclusion check only fires for
                        # CHILDREN discovered during a walk, never for a worker's own starting point.
                        # Skipping this would let an excluded top-level folder (".rustup" sitting
                        # directly under the searched root) get its own dedicated worker that walks
                        # it in full, defeating the exclusion for exactly the case it exists to catch.
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

                # Shared across every worker so one worker finding a match can stop every
                # other worker's walk too, not just its own. A plain variable would not do
                # this: each runspace only sees the value it was handed at dispatch time.
                # A synchronized hashtable is a reference type every worker holds a live
                # handle to and can both read and mutate, the same mechanism already used
                # for $progressQueue in Invoke-DowserRunspacePool. Only created when
                # actually needed so the common case (no -StopOnFirstMatch) pays nothing.
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
                        # Checked before starting each new target, not only inside one: a
                        # queued chunk that has not begun yet sees this the moment it starts,
                        # so a match found by a different, already-running worker stops a
                        # not-yet-started one from doing any work at all.
                        if ($stopOnFirst -and $stopSignal.Stop) {
                            break
                        }

                        # $rootPath (the original search root, $p in the caller) is always
                        # walked non-recursively here: every one of its subdirectories already
                        # has its own dedicated target elsewhere in $chunk, or in another
                        # thread's chunk, each walking its own subtree in full. Recursing
                        # through $rootPath on top of that walked every subtree twice, once
                        # through $rootPath's own pass and once through each subdirectory's
                        # dedicated worker (confirmed by direct execution, decision recorded
                        # 2026-09-15). A target that is not $rootPath keeps the caller's real
                        # $recurse value.
                        $targetRecurse = $recurse -and ($targetPath -ne $rootPath)

                        if (@($excludePatterns).Count -gt 0 -or $stopOnFirst) {
                            # Manual, per-directory stack walk instead of Get-ChildItem -Recurse.
                            # Needed for -ExcludePattern (pruning, so an excluded directory is
                            # never pushed and never descended into -- Get-ChildItem -Exclude
                            # only hides a matched item from output, it does not stop recursion
                            # into it) AND now also for -StopOnFirstMatch on its own: measured by
                            # direct execution that Get-ChildItem -Recurse largely BUFFERS its
                            # entire recursive listing before a consuming foreach loop can even
                            # begin iterating (breaking after the very first of 50,000
                            # recursively-enumerated items still cost 77% of the time to
                            # enumerate all 50,000). That made an earlier version of this fix
                            # only skip PER-ITEM PROCESSING after a match, never the actual disk
                            # enumeration -- confirmed independently by adversarial review
                            # measuring only a 16% saving against a large non-matching sibling
                            # directory, far short of "halts every other worker's walk." A
                            # per-directory, non-recursive Get-ChildItem call bounds the work
                            # between stop-signal checks to one directory's worth of children
                            # at a time, which is what actually lets one worker's match
                            # interrupt another worker mid-walk of a large sibling. Decision
                            # recorded 2026-09-15.
                            #
                            # A symlinked/reparse-point directory is never pushed either, matching
                            # Get-ChildItem -Recurse's own default (and Get-DowserMap's documented
                            # -FollowReparse default-off convention) -- without this check, a plain
                            # symlink returns the same file twice under two paths, and a cycle
                            # (A/link -> A) grows the stack without bound until an OS path-length
                            # limit intervenes, since nothing here would ever detect the loop.
                            $stack = New-Object 'System.Collections.Generic.Stack[string]'
                            $stack.Push($targetPath)
                            # Labeled so a match (this worker's own, or the stop-signal check
                            # seeing another worker's) can break both this while loop and the
                            # foreach below in one step; an unlabeled break here would only
                            # exit the foreach, leaving the while loop to pop and walk
                            # whatever the stack still holds.
                            :walkLoop while ($stack.Count -gt 0) {
                                if ($stopOnFirst -and $stopSignal.Stop) {
                                    break walkLoop
                                }
                                $currentDir = $stack.Pop()
                                $children = Get-ChildItem -LiteralPath $currentDir -Force -ErrorAction SilentlyContinue
                                foreach ($child in $children) {
                                    # Checked per child, not only per directory: a directory can
                                    # hold thousands of entries on its own, and this is what lets
                                    # another worker's match be noticed within a single directory
                                    # listing, not only between them.
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

                        # Reached only when neither -ExcludePattern nor -StopOnFirstMatch is
                        # active, so this fast Get-ChildItem -Recurse path (with its -Filter
                        # optimization for the single-pattern case) never needs to support
                        # early termination -- the whole target is always meant to be scanned
                        # here, matching every caller that reaches this branch.
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
                # Manual stack walk: an excluded directory is never pushed, so the walk never
                # descends into it. Get-ChildItem -Exclude only hides a matched item from
                # output; it does not stop recursion into it. A symlinked/reparse-point
                # directory is never pushed either, matching Get-ChildItem -Recurse's own
                # default (and Get-DowserMap's documented -FollowReparse default-off
                # convention) -- without this check, a plain symlink returns the same file
                # twice under two paths, and a cycle (A/link -> A) grows the stack without
                # bound until an OS path-length limit intervenes.
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
                
                # foreach, not Get-ChildItem | ForEach-Object: a plain "return" inside a
                # ForEach-Object script block only skips to the pipeline's next input item,
                # it never stops Get-ChildItem's own enumeration -- identical to the gap
                # already fixed in the runspace scriptblock's fast path (2026-09-15), missed
                # here in this plain serial (-UseRunspaces:$false, no -ExcludePattern) branch
                # at the time, confirmed by independent adversarial review executing a
                # controlled repro against this exact branch: a match placed first vs. last
                # in enumeration order showed no timing difference, proving the full listing
                # was walked regardless of -StopOnFirstMatch. A real foreach loop is required
                # so "break" genuinely halts enumeration.
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