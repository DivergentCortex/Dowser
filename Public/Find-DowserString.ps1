#Requires -Version 5.1

function Find-DowserString {
    <#
    .SYNOPSIS
        Searches for one or more text patterns across files in a directory.

    .NOTES
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
        -  Author:        Curtis Leggett                                  -
        =  Copyright:     2026 Divergent Cortex                           =
        -  Organization:  Divergent Cortex                                -
        =  Version:       See docs/CHANGELOG.md                           =
        =-=-                       =-=-=-=-=-=-=-=                     -=-=
        -  it is not water they seek, but the truth beneath the trees     -
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

        Source: standalone scripts\find-stringinfiles.ps1
        Threading via Invoke-DowserRunspacePool (Private helper)
        Aho-Corasick compiled inline (C# Add-Type), shared across runspaces via AppDomain

    .DESCRIPTION
        Multi-threaded string search using Invoke-DowserRunspacePool for parallel file gathering
        and parallel search. Aho-Corasick is used automatically for multi-pattern literal searches
        (SearchMode auto or aho). Single patterns or regex fall back to per-line scan.

        File gathering and string searching are both parallelized via directory partitioning
        and chunked file processing, the same strategy as the original Find-StringInFiles.

    .PARAMETER Path
        Directory to search. Defaults to current directory. Accepts pipeline input.

    .PARAMETER Patterns
        One or more text patterns to search for. Required.

    .PARAMETER Extensions
        File glob patterns to include. Default is all files.

    .PARAMETER MaxThreads
        Max worker runspaces. Defaults to CPU count minus 1.

    .PARAMETER MaxFileSizeMB
        Skip files over this size. Default 10 MB.

    .PARAMETER UseRegex
        Treat Patterns as regex. Default is literal string matching.

    .PARAMETER CaseSensitive
        Case-sensitive matching. Default is case-insensitive.

    .PARAMETER Recurse
        Recurse subdirectories. Default $true.

    .PARAMETER ExcludeFolders
        Folder names to skip. Default: .git, node_modules, bin, obj.

    .PARAMETER ExcludeExtensions
        File extensions to skip (e.g. '.log', '.dll').

    .PARAMETER ContextLines
        Lines of context around each match. Default 0. Requires IncludeLineContent.

    .PARAMETER SearchMode
        auto   - picks aho for multi-pattern literal, manual for single
        aho    - force Aho-Corasick
        manual - literal IndexOf loop
        select - not implemented (kept for compat)

    .PARAMETER OutputMode
        grouped - directory header, files indented underneath with match count and line numbers (default).
                  text output, optimized for console readability.
        counts  - one PSCustomObject per file with FilePath, MatchCount, LineNumbers. legacy default;
                  use this when you need to pipe results downstream.
        files   - just file paths.
        matches - one row per match; include line text with IncludeLineContent.

    .PARAMETER IncludeLineContent
        Include the matching line text in results. Implicitly sets OutputMode to matches.

    .EXAMPLE
        Find-DowserString -Path . -Patterns 'TODO','FIXME' -Extensions '*.ps1' -Verbose

        Searches every .ps1 file under the current directory for TODO or FIXME.

    .EXAMPLE
        Find-DowserString -Path D:\repos -Patterns 'Write-Host' -Extensions '*.ps1' -OutputMode files

        Lists just the file paths under D:\repos that contain Write-Host.

    .INPUTS
        System.String
        A directory path can be piped to this function.

    .OUTPUTS
        System.Object
        Shape depends on OutputMode: PSCustomObject rows (counts, matches), file path
        strings (files), or formatted console text (grouped, singlefile).
    #>
    [CmdletBinding()]
    [OutputType([psobject])]
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('FullName')]
        [string]$Path = $PWD,

        [Parameter(Position = 1, Mandatory = $true)]
        [string[]]$Patterns,

        [string[]]$Extensions = @('*.*'),

        [int]$MaxThreads = ([Math]::Max(1, [Environment]::ProcessorCount - 1)),

        [int]$MaxFileSizeMB = 10,

        [switch]$UseRegex,

        [switch]$CaseSensitive,

        [switch]$Recurse,

        [Alias('ExcludeDirs')]
        [string[]]$ExcludeFolders = @('.git', 'node_modules', 'bin', 'obj'),

        [string[]]$ExcludeExtensions,

        [int]$ContextLines = 0,

        [ValidateSet('auto', 'aho', 'manual', 'select')]
        [string]$SearchMode = 'auto',

        [ValidateSet('grouped', 'counts', 'files', 'matches', 'singlefile')]
        [string]$OutputMode = 'grouped',

        [switch]$IncludeLineContent
    )

    begin {
        $startTime = Get-Date

        if (-not $PSBoundParameters.ContainsKey('Recurse')) {
            $Recurse = $true 
        }
        if ($IncludeLineContent -and -not $PSBoundParameters.ContainsKey('OutputMode')) {
            $OutputMode = 'matches' 
        }

        $MaxFileSizeBytes = $MaxFileSizeMB * 1MB
        $ComputedMaxThreads = [Math]::Max(1, $MaxThreads)

        $UseAho = $false
        if ($SearchMode -eq 'aho') {
            $UseAho = $true
        }
        elseif ($SearchMode -eq 'auto') {
            # aho only makes sense for multiple literal patterns
            $UseAho = (-not $UseRegex) -and (@($Patterns).Count -gt 1)
        }

        # add-type loads into the shared appdomain so workers see it too
        # string still passed as a safety net for workers that race the main compile
        $ahoCode = @(
            'using System;'
            'using System.Collections.Generic;'
            ''
            'namespace FastSearch {'
            '    public class AhoCorasick {'
            '        private class Node {'
            '            public Dictionary<char, Node> next = new Dictionary<char, Node>();'
            '            public Node fail;'
            '            public List<int> output = new List<int>();'
            '        }'
            '        private Node root = new Node();'
            '        private string[] patterns;'
            '        public AhoCorasick(string[] patterns) {'
            '            this.patterns = patterns;'
            '            for (int i = 0; i < patterns.Length; i++) {'
            '                Node curr = root;'
            '                foreach (char c in patterns[i]) {'
            '                    if (!curr.next.ContainsKey(c)) { curr.next[c] = new Node(); }'
            '                    curr = curr.next[c];'
            '                }'
            '                curr.output.Add(i);'
            '            }'
            '            Queue<Node> queue = new Queue<Node>();'
            '            foreach (Node child in root.next.Values) { child.fail = root; queue.Enqueue(child); }'
            '            while (queue.Count > 0) {'
            '                Node r = queue.Dequeue();'
            '                foreach (var kv in r.next) {'
            '                    char c = kv.Key; Node u = kv.Value; queue.Enqueue(u);'
            '                    Node v = r.fail;'
            '                    while (v != null && !v.next.ContainsKey(c)) { v = v.fail; }'
            '                    u.fail = (v == null) ? root : v.next[c];'
            '                    if (u.fail != u) { foreach (int idx in u.fail.output) { u.output.Add(idx); } }'
            '                }'
            '            }'
            '        }'
            '        public List<Tuple<int,int>> Search(string text) {'
            '            var results = new List<Tuple<int,int>>();'
            '            Node curr = root;'
            '            for (int i = 0; i < text.Length; i++) {'
            '                while (curr != root && !curr.next.ContainsKey(text[i])) { curr = curr.fail; }'
            '                if (curr.next.ContainsKey(text[i])) { curr = curr.next[text[i]]; }'
            '                foreach (int idx in curr.output) {'
            '                    results.Add(Tuple.Create(i - patterns[idx].Length + 1, idx));'
            '                }'
            '            }'
            '            return results;'
            '        }'
            '    }'
            '}'
        ) -join [Environment]::NewLine

        if ($UseAho) {
            try {
                $null = [FastSearch.AhoCorasick] 
            }
            catch {
                Add-Type -TypeDefinition $ahoCode -ErrorAction Stop 
            }
        }

        Write-Log "Starting Find-DowserString"
        Write-Log "Find-DowserString: '$Path' patterns=[$($Patterns -join ', ')] mode=$SearchMode useAho=$UseAho outputMode=$OutputMode threads=$ComputedMaxThreads" -Severity Verbose

        # lives in function scope so end{} can still see it
        $allResults = [System.Collections.ArrayList]::new()
    }

    process {

        # .net statics choke on tilde and ps drive paths
        try {
            $Path = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
        }
        catch {
            Write-Log "Find-DowserString failed resolving path '$Path': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Error
            return
        }

        # ==================================================================
        # FILE-PATH SHORT-CIRCUIT
        # workers don't inherit drive mappings so mapped paths resolve to unc
        # ==================================================================
        $isFilePath = $false
        try {
            if ([System.IO.File]::Exists($Path)) {
                $isFilePath = $true 
            }
        }
        catch { 
        }

        if ($isFilePath) {
            try {
                $resolvedFile = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
            }
            catch {
                $resolvedFile = $Path
            }
            Write-Log "Single file mode: '$resolvedFile'" -Severity Verbose
            $allFiles = @($resolvedFile)

            # default single-file output to truncated line content unless overridden
            if (-not $PSBoundParameters.ContainsKey('OutputMode')) {
                $OutputMode = 'singlefile'
                $IncludeLineContent = $true
            }
        }
        else {

            # ==================================================================
            # PHASE 1/3 - DIRECTORY ENUMERATION
            # prune excluded folders at branch level so we never descend their subtrees
            # ==================================================================

            $excludeSet = New-Object 'System.Collections.Generic.HashSet[string]'([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($name in $ExcludeFolders) {
                [void]$excludeSet.Add($name) 
            }

            $scanTargets = [System.Collections.ArrayList]::new()
            [void]$scanTargets.Add($Path)

            Write-Log "Find-DowserString Phase 1/3: Enumerating directories under '$Path'" -Severity Verbose
            Write-Progress -Activity 'Find-DowserString' -Status 'Phase 1/3: Enumerating directories...' -PercentComplete 0
            $phase1Start = Get-Date

            if ($Recurse) {
                $stack = [System.Collections.Generic.Stack[string]]::new()
                $stack.Push($Path)
                $lastTick = [Environment]::TickCount

                while ($stack.Count -gt 0) {
                    $current = $stack.Pop()
                    try {
                        foreach ($child in [System.IO.Directory]::EnumerateDirectories($current, '*', [System.IO.SearchOption]::TopDirectoryOnly)) {
                            $leaf = [System.IO.Path]::GetFileName($child)
                            if ($excludeSet.Contains($leaf)) {
                                continue 
                            }
                            [void]$scanTargets.Add($child)
                            $stack.Push($child)

                            # throttle progress updates to ~5/sec so the I/O cost stays negligible
                            $now = [Environment]::TickCount
                            if (($now - $lastTick) -ge 200) {
                                Write-Progress -Activity 'Find-DowserString' `
                                    -Status ("Phase 1/3: Enumerating directories ({0:N0} found, current: {1})" -f $scanTargets.Count, $leaf) `
                                    -PercentComplete -1
                                $lastTick = $now
                            }
                        }
                    }
                    catch {
                        # access denied / reparse points / vanished dirs - skip silently
                        Write-Log "Find-DowserString skipped inaccessible directory '$current': $($_.Exception.Message)" -Severity Verbose
                    }
                }
            }

            $phase1Duration = (Get-Date) - $phase1Start
            Write-Log ("Find-DowserString Phase 1/3: Found {0:N0} directories in {1:N1}s" -f $scanTargets.Count, $phase1Duration.TotalSeconds)

            $gatherScriptBlock = {
                param($DirChunk, $Extensions, $MaxFileSizeBytes, $ExcludeExtensions, $ProgressQueue)

                $excludeExtSet = New-Object 'System.Collections.Generic.HashSet[string]'([System.StringComparer]::OrdinalIgnoreCase)
                if ($ExcludeExtensions) {
                    foreach ($e in $ExcludeExtensions) {
                        $norm = $e.ToLowerInvariant()
                        if ($norm -notmatch '^\.') {
                            $norm = ".$norm" 
                        }
                        [void]$excludeExtSet.Add($norm)
                    }
                }

                $found = [System.Collections.ArrayList]::new()
                foreach ($dir in $DirChunk) {
                    Get-ChildItem -Path $dir -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
                        $f = $_
                        $matchesExt = $false
                        foreach ($ext in $Extensions) {
                            if ($f.Name -like $ext) {
                                $matchesExt = $true; break 
                            }
                        }
                        if (-not $matchesExt) {
                            return 
                        }
                        if ($excludeExtSet.Count -gt 0 -and $f.Extension -and $excludeExtSet.Contains($f.Extension.ToLowerInvariant())) {
                            return 
                        }
                        if ($f.Length -gt $MaxFileSizeBytes) {
                            return 
                        }
                        [void]$found.Add($f.FullName)
                    }
                    if ($ProgressQueue) {
                        [void]$ProgressQueue.Enqueue(1) 
                    }
                }
                return $found.ToArray()
            }

            Write-Log ("Find-DowserString Phase 2/3: Gathering files in {0:N0} directories" -f $scanTargets.Count) -Severity Verbose
            $phase2Start = Get-Date

            $gatherResults = $scanTargets.ToArray() | Invoke-DowserRunspacePool `
                -ScriptBlock $gatherScriptBlock `
                -ArgumentList @($Extensions, $MaxFileSizeBytes, $ExcludeExtensions) `
                -ThreadCount $ComputedMaxThreads `
                -ProgressActivity 'Find-DowserString' `
                -ProgressStatus 'Phase 2/3: Gathering files' `
                -UseProgressQueue

            # Select-Object -Unique is O(n^2) and stalls for tens of minutes on a
            # quarter-million paths. Select-DowserUniquePath is a single-pass HashSet.
            $allFiles = @(Select-DowserUniquePath -Path $gatherResults)
            $phase2Duration = (Get-Date) - $phase2Start
            Write-Log ("Find-DowserString Phase 2/3: Matched {0:N0} files in {1:N1}s" -f $allFiles.Count, $phase2Duration.TotalSeconds)

        }  # end else (directory mode)

        if ($allFiles.Count -eq 0) {
            Write-Log "Find-DowserString: no files matched extension/size filters in '$Path'" -Severity Warning
            return
        }

        # ==================================================================
        # PHASE 3/3 - STRING SEARCHING
        # aho for multi-pattern literal, regex or manual otherwise
        # ==================================================================

        $searchScriptBlock = {
            param($FilePaths, $Patterns, $UseRegex, $CaseSensitive, $UseAho, $AhoCode, $IncludeLineContent, $ProgressQueue)

            # safety-net compile for workers that raced the main-thread compile
            if ($UseAho -and $AhoCode) {
                try {
                    $null = [FastSearch.AhoCorasick] 
                }
                catch {
                    Add-Type -TypeDefinition $AhoCode -ErrorAction SilentlyContinue 
                }
            }

            $results = [System.Collections.ArrayList]::new()

            foreach ($FilePath in $FilePaths) {
                try {
                    $content = Get-Content -Path $FilePath -Raw -ErrorAction Stop
                    if (-not $content) {
                        if ($ProgressQueue) {
                            [void]$ProgressQueue.Enqueue(1) 
                        }
                        continue
                    }
                    $lines = $content -split '\r?\n'

                    if ($UseAho) {
                        $searchPats = if ($CaseSensitive) {
                            [string[]]$Patterns
                        }
                        else {
                            [string[]]($Patterns | ForEach-Object { $_.ToLowerInvariant() })
                        }
                        $ac = [FastSearch.AhoCorasick]::new($searchPats)

                        for ($i = 0; $i -lt $lines.Count; $i++) {
                            $line = $lines[$i]
                            $searchLine = if ($CaseSensitive) {
                                $line 
                            }
                            else {
                                $line.ToLowerInvariant() 
                            }
                            $hits = $ac.Search($searchLine)
                            if ($hits.Count -gt 0) {
                                $firstPat = $Patterns[$hits[0].Item2]
                                $row = [pscustomobject]@{
                                    FilePath   = $FilePath
                                    LineNumber = $i + 1
                                    Pattern    = $firstPat
                                    Count      = $hits.Count
                                }
                                if ($IncludeLineContent) {
                                    $row | Add-Member -NotePropertyName Line -NotePropertyValue $line
                                }
                                [void]$results.Add($row)
                            }
                        }
                    }
                    else {
                        for ($i = 0; $i -lt $lines.Count; $i++) {
                            $line = $lines[$i]

                            foreach ($pattern in $Patterns) {
                                $matchCount = 0

                                if ($UseRegex) {
                                    $rOpts = if ($CaseSensitive) {
                                        [System.Text.RegularExpressions.RegexOptions]::None 
                                    }
                                    else {
                                        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase 
                                    }
                                    $matchCount = ([regex]::Matches($line, $pattern, $rOpts)).Count
                                }
                                else {
                                    $cmp = if ($CaseSensitive) {
                                        [System.StringComparison]::Ordinal 
                                    }
                                    else {
                                        [System.StringComparison]::OrdinalIgnoreCase 
                                    }
                                    $start = 0
                                    while ($true) {
                                        $idx = $line.IndexOf($pattern, $start, $cmp)
                                        if ($idx -ge 0) {
                                            $matchCount++; $start = $idx + $pattern.Length 
                                        }
                                        else {
                                            break 
                                        }
                                    }
                                }

                                if ($matchCount -gt 0) {
                                    $row = [pscustomobject]@{
                                        FilePath   = $FilePath
                                        LineNumber = $i + 1
                                        Pattern    = $pattern
                                        Count      = $matchCount
                                    }
                                    if ($IncludeLineContent) {
                                        $row | Add-Member -NotePropertyName Line -NotePropertyValue $line
                                    }
                                    [void]$results.Add($row)
                                    break  # first matching pattern wins, same as aho path
                                }
                            }
                        }
                    }
                }
                catch {
                    # emit a row so callers know the search skipped a file
                    $results.Add([pscustomobject]@{
                            FilePath   = $FilePath
                            LineNumber = 0
                            Pattern    = '[READ-ERROR]'
                            Count      = 0
                            Error      = $_.Exception.Message
                        })
                }

                if ($ProgressQueue) {
                    [void]$ProgressQueue.Enqueue(1) 
                }
            }

            return $results.ToArray()
        }

        Write-Log ("Find-DowserString Phase 3/3: Searching {0:N0} files for {1} pattern(s)" -f $allFiles.Count, @($Patterns).Count)
        $phase3Start = Get-Date

        $searchResults = $allFiles | Invoke-DowserRunspacePool `
            -ScriptBlock $searchScriptBlock `
            -ArgumentList @($Patterns, [bool]$UseRegex, [bool]$CaseSensitive, $UseAho, $ahoCode, [bool]$IncludeLineContent) `
            -ThreadCount $ComputedMaxThreads `
            -ProgressActivity 'Find-DowserString' `
            -ProgressStatus 'Phase 3/3: Searching files' `
            -UseProgressQueue

        if ($searchResults) {
            foreach ($r in $searchResults) {
                if ($null -ne $r) {
                    [void]$allResults.Add($r) 
                }
            }
        }

        $phase3Duration = (Get-Date) - $phase3Start
        Write-Log ("Find-DowserString Phase 3/3: Done. {0:N0} match rows from {1:N0} files in {2:N1}s" -f $allResults.Count, $allFiles.Count, $phase3Duration.TotalSeconds)
    }

    end {
        $results = @($allResults)

        if ($results.Count -gt 0) {
            switch ($OutputMode) {
                'singlefile' {
                    # window the context around each hit so long minified lines don't drown it
                    $totalMatches = [int]($results | Measure-Object -Property Count -Sum).Sum
                    $uniqueLines = @($results | Select-Object -ExpandProperty LineNumber -Unique).Count
                    $sorted = $results | Sort-Object LineNumber
                    $sampleCap = 25
                    $sample = $sorted | Select-Object -First $sampleCap
                    $remaining = [Math]::Max(0, @($sorted).Count - $sampleCap)
                    $patList = (@($results | Select-Object -ExpandProperty Pattern -Unique) -join ', ')
                    $filePath = @($results)[0].FilePath
                    $window = 40

                    Write-Output $filePath
                    Write-Output ("  Pattern(s) : {0}" -f $patList)
                    Write-Output ("  Matches    : {0:N0} across {1:N0} line(s)" -f $totalMatches, $uniqueLines)
                    Write-Output ''

                    foreach ($m in $sample) {
                        $line = if ($m.PSObject.Properties['Line']) {
                            $m.Line 
                        }
                        else {
                            '' 
                        }
                        $pat = $m.Pattern
                        if ($null -eq $line) {
                            $line = '' 
                        }

                        $idx = -1
                        if ($pat -and $line) {
                            $idx = $line.IndexOf($pat, [System.StringComparison]::OrdinalIgnoreCase)
                        }

                        if ($idx -lt 0) {
                            # no literal hit on regex or mapped-aho lines, head-truncate instead
                            $snippet = ($line -replace '\s+', ' ').Trim()
                            if ($snippet.Length -gt ($window * 2 + 20)) {
                                $snippet = $snippet.Substring(0, $window * 2 + 17) + '...'
                            }
                        }
                        else {
                            $start = [Math]::Max(0, $idx - $window)
                            $end = [Math]::Min($line.Length, $idx + $pat.Length + $window)
                            $snippet = $line.Substring($start, $end - $start)
                            $snippet = ($snippet -replace '\s+', ' ').Trim()
                            if ($start -gt 0) {
                                $snippet = '...' + $snippet 
                            }
                            if ($end -lt $line.Length) {
                                $snippet = $snippet + '...' 
                            }
                        }

                        Write-Output ('  {0,6}: {1}' -f $m.LineNumber, $snippet)
                    }

                    if ($remaining -gt 0) {
                        Write-Output ''
                        Write-Output ("  (+ {0:N0} more match row(s) - re-run with -OutputMode matches for full list)" -f $remaining)
                    }
                }
                'grouped' {
                    $perFile = $results | Group-Object FilePath | ForEach-Object {
                        $total = [int]($_.Group | Measure-Object -Property Count -Sum).Sum
                        $lineNums = @($_.Group | Select-Object -ExpandProperty LineNumber -Unique | Sort-Object)
                        [pscustomobject]@{
                            FilePath    = $_.Name
                            Directory   = [System.IO.Path]::GetDirectoryName($_.Name)
                            FileName    = [System.IO.Path]::GetFileName($_.Name)
                            MatchCount  = $total
                            LineNumbers = $lineNums
                        }
                    } | Sort-Object Directory, FileName

                    $byDir = $perFile | Group-Object Directory
                    $first = $true
                    foreach ($g in $byDir) {
                        if (-not $first) {
                            Write-Output '' 
                        }
                        $first = $false

                        $fileCount = @($g.Group).Count
                        $dirMatches = [int]($g.Group | Measure-Object -Property MatchCount -Sum).Sum
                        $fileWord = if ($fileCount -eq 1) {
                            'file'  
                        }
                        else {
                            'files'   
                        }
                        $matchWord = if ($dirMatches -eq 1) {
                            'match' 
                        }
                        else {
                            'matches' 
                        }
                        Write-Output ("{0}  ({1} {2}, {3} {4})" -f $g.Name, $fileCount, $fileWord, $dirMatches, $matchWord)

                        $maxLen = ($g.Group | ForEach-Object { $_.FileName.Length } | Measure-Object -Maximum).Maximum
                        $padTo = [Math]::Min(80, [Math]::Max(30, $maxLen))
                        $fmt = "    {0,-$padTo}  [{1,4}]  {2}"

                        foreach ($row in $g.Group) {
                            $count = @($row.LineNumbers).Count
                            if ($count -le 8) {
                                $word = if ($count -eq 1) {
                                    'line' 
                                }
                                else {
                                    'lines' 
                                }
                                $linesText = "$word " + ($row.LineNumbers -join ', ')
                            }
                            else {
                                $head = ($row.LineNumbers | Select-Object -First 8) -join ', '
                                $linesText = "lines $head, (+{0} more)" -f ($count - 8)
                            }
                            Write-Output ($fmt -f $row.FileName, $row.MatchCount, $linesText)
                        }
                    }

                    $totalFiles = @($perFile).Count
                    $totalMatches = [int]($perFile | Measure-Object -Property MatchCount -Sum).Sum
                    $totalDirs = @($byDir).Count
                    Write-Log "Find-DowserString: $totalMatches matches across $totalFiles files in $totalDirs directories" -Severity Verbose
                }
                'counts' {
                    $grouped = $results | Group-Object FilePath | ForEach-Object {
                        $total = [int]($_.Group | Measure-Object -Property Count -Sum).Sum
                        $lineNums = $_.Group | Select-Object -ExpandProperty LineNumber -Unique | Sort-Object
                        [pscustomobject]@{
                            FilePath    = $_.Name
                            MatchCount  = $total
                            LineNumbers = $lineNums -join ','
                        }
                    }
                    $grouped | Sort-Object FilePath | Write-Output
                    Write-Log "Find-DowserString: $($results.Count) matches across $(@($grouped).Count) files" -Severity Verbose
                }
                'files' {
                    $results | Select-Object -ExpandProperty FilePath -Unique | Sort-Object | Write-Output
                    Write-Log "Find-DowserString: $(@($results | Select-Object -ExpandProperty FilePath -Unique).Count) files with matches" -Severity Verbose
                }
                'matches' {
                    if ($IncludeLineContent) {
                        $sorted = $results | Sort-Object FilePath, LineNumber
                        $lastFile = $null
                        foreach ($m in $sorted) {
                            if ($m.FilePath -ne $lastFile) {
                                if ($lastFile) {
                                    Write-Output '' 
                                }
                                Write-Output $m.FilePath
                                $lastFile = $m.FilePath
                            }
                            $lineText = if ($m.PSObject.Properties['Line']) {
                                $m.Line 
                            }
                            else {
                                '' 
                            }
                            Write-Output ('  {0,5}: {1}' -f $m.LineNumber, $lineText)
                        }
                    }
                    else {
                        $results | Sort-Object FilePath, LineNumber | Write-Output
                    }
                    Write-Log "Find-DowserString: $($results.Count) matches" -Severity Verbose
                }
            }
        }
        else {
            Write-Output 'No matches found'
        }

        $duration = New-TimeSpan -Start $startTime -End (Get-Date)
        Write-Log "Find-DowserString completed in $([Math]::Round($duration.TotalSeconds, 2))s" -Severity Verbose
        Write-Log "Ending Find-DowserString"
    }
}
