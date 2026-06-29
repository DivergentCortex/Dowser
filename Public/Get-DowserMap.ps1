#Requires -Version 5.1
<#
.SYNOPSIS
    Visual tree renderer for directory structures with optional size and file count annotations.
.DESCRIPTION
    Renders a directory tree using Unicode or ASCII box-drawing characters. Supports HTML and
    Markdown output, full-path trunk display, filtering by extension/pattern/folder, parallel
    pre-scan for large trees, WSL/Linux path display mode.

    Optionally annotates each folder with its total size (-IncludeSize) and/or .ps1 file count
    (-IncludePsCount), inlined directly into the tree branches.
.PARAMETER Path
    Root directory to render.
.PARAMETER IncludeSize
    Append total folder size (e.g., [1.2 GB]) to each folder in the tree.
.PARAMETER IncludePsCount
    Append .ps1 file count (e.g., [14 .ps1]) to each folder in the tree.
.PARAMETER MaxDepth
    Maximum depth to traverse. Default: 3.
.EXAMPLE
    Get-DowserMap -Path D:\Projects -MaxDepth 2 -IncludeSize
.EXAMPLE
    Get-DowserMap -Path D:\Scripts -IncludePsCount -FoldersOnly
.NOTES
    Author: Curtis Leggett / Divergent Cortex
    Ported from: Get-DirectoryMap.ps1 (standalone scripts)
    Absorbs data features from: Get-FolderTree.ps1, Get-DirectoryTreeOutputAndFileCount.ps1
#>

# visual tree builder. self-recursive. dont reorder the filter logic unless you enjoy broken connectors.
# size and .ps1 count annotations bolt onto the folder line, computed lazily per folder

function Get-DowserMap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('FullName')]
        [string]$Path,

        # Data Annotation Switches (from merged scripts)
        [switch]$IncludeSize,             # Append folder size to each branch
        [switch]$IncludePsCount,          # Append .ps1 file count to each branch

        # File/Folder Filtering
        [string[]]$IncludeFilePatterns,
        [string[]]$IncludeExtensions,
        [string[]]$ExcludeExtensions,
        [string[]]$ExcludeFolders,
        [string[]]$ExcludeFiles,
        [string[]]$IncludeFolders,
        [string[]]$ExcludePathPatterns,
        [switch]$NoDefaultExcludes,
        [switch]$FoldersOnly,

        # Display Options
        [Alias('Max')]
        [int]$MaxDepth = 3,
        [Alias('S')]
        [switch]$ShowFullPathTree,
        [Alias('L')]
        [switch]$LinuxPaths,
        [switch]$Ascii,
        [switch]$AsHtml,
        [switch]$AsMarkdown,
        [switch]$IncludeHidden,
        [switch]$FollowReparse,

        # Performance Options
        [bool]$UseRunspaces = $true,
        [int]$MaxThreads = ([Math]::Max(1, [Environment]::ProcessorCount - 1)),

        # Output Options
        [string]$OutputFile,
        [string]$MarkdownFile,
        [switch]$EmitSummary,

        # internal for recursion, dont mess with these
        [string]$Indent = "",
        [int]$CurrentDepth = 0,
        [Parameter(DontShow = $true)]
        [hashtable]$MatchCache,
        [Parameter(DontShow = $true)]
        [hashtable]$IncludeFolderCache,
        [Parameter(DontShow = $true)]
        [hashtable]$TraversalState,
        [Parameter(DontShow = $true)]
        [hashtable]$SizeCache,
        [Parameter(DontShow = $true)]
        [hashtable]$PsCountCache
    )

    if (-not $PSBoundParameters.ContainsKey('ShowFullPathTree')) { $ShowFullPathTree = $true }

    if ($MarkdownFile) { $AsMarkdown = $true }
    if ($AsHtml -and $AsMarkdown) {
        Write-Warning 'Cannot use -AsHtml and -AsMarkdown together. Pick one.'
        return
    }

    function ConvertTo-NormalizedExtension {
        param([string]$ext)
        if ([string]::IsNullOrEmpty($ext)) { return '' }
        $ext = $ext.ToLowerInvariant()
        if ($ext -notmatch '^\.') { return ".$ext" } else { return $ext }
    }

    function Get-FolderAnnotation {
        param([string]$folderPath)
        $annotation = ''

        if ($IncludeSize) {
            if (-not $SizeCache.ContainsKey($folderPath)) {
                $sizeBytes = 0
                try {
                    $measured = Get-ChildItem -LiteralPath $folderPath -Recurse -File -Force -ErrorAction SilentlyContinue |
                        Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue
                    if ($measured.Sum) { $sizeBytes = $measured.Sum }
                } catch { Write-Verbose "Size measurement failed for '$folderPath': $_" }
                $SizeCache[$folderPath] = $sizeBytes
            }
            $formatted = Format-DowserSize $SizeCache[$folderPath]
            $annotation += " [$formatted]"
        }

        if ($IncludePsCount) {
            if (-not $PsCountCache.ContainsKey($folderPath)) {
                $count = 0
                try {
                    $counted = Get-ChildItem -LiteralPath $folderPath -Recurse -Filter '*.ps1' -File -Force -ErrorAction SilentlyContinue |
                        Measure-Object
                    $count = $counted.Count
                } catch { Write-Verbose "PS1 count failed for '$folderPath': $_" }
                $PsCountCache[$folderPath] = $count
            }
            $cnt = $PsCountCache[$folderPath]
            $annotation += " [$cnt .ps1]"
        }

        return $annotation
    }

    $normInclude = @()
    if ($IncludeExtensions) { $normInclude = @($IncludeExtensions | ForEach-Object { ConvertTo-NormalizedExtension $_ }) }

    $defaultExcludeExts = @(
        '.pyc', '.pyo', '.pyd', '.so', '.dll', '.dylib', '.obj', '.o', '.a', '.lib',
        '.class', '.jar', '.war', '.ear', '.whl', '.egg', '.zip', '.tar', '.gz', '.bz2',
        '.7z', '.rar', '.iso', '.dmg', '.pkg', '.deb', '.rpm',
        '.bak', '.tmp', '.temp', '.log', '.swp', '.swo', '~', '.DS_Store', 'Thumbs.db',
        '.cache', '.eslintcache', '.parcel-cache'
    )
    $allExcludeExts = @()
    if (-not $NoDefaultExcludes) { $allExcludeExts += $defaultExcludeExts }
    if ($ExcludeExtensions) { $allExcludeExts += @($ExcludeExtensions) }
    $allExcludeExts = $allExcludeExts | Select-Object -Unique
    $normExclude = @()
    if ($allExcludeExts) { $normExclude = @($allExcludeExts | ForEach-Object { ConvertTo-NormalizedExtension $_ }) }

    # folder exclude defaults, bypass with -NoDefaultExcludes
    $defaultExcludes = @(
        '__pycache__', 'node_modules', '.git', '.svn', '.hg', '.vs', '.vscode', 'obj', '.idea',
        'dist', '.pytest_cache', '.mypy_cache', '.tox', 'venv', '.venv', 'env', '.env',
        'Lib', 'lib', 'Include', 'include', 'share', 'man',
        '.next', '.nuxt', 'target', 'vendor', 'packages',
        '.angular', '.sass-cache', 'bower_components', 'jspm_packages',
        '.gradle', '.maven', '.m2', '.cache', '__MACOSX', 'Thumbs.db',
        '.DS_Store', '.eggs', '*.egg-info', '.pytest_cache', 'htmlcov', 'coverage',
        '.nyc_output', 'logs', 'log', 'tmp', 'temp', '.tmp', '.temp',
        'site-packages', 'dist-info', '.dist-info', '.claude'
    )
    $allExcludes = @()
    if (-not $NoDefaultExcludes) { $allExcludes += $defaultExcludes }
    if ($ExcludeFolders) { $allExcludes += @($ExcludeFolders) }
    $allExcludes = $allExcludes | Select-Object -Unique

    $excludeExact = @()
    $excludeWild  = @()
    if ($allExcludes) {
        $excludeExact = @($allExcludes | Where-Object { $_ -notmatch '[\*\?\[\]]' })
        $excludeWild  = @($allExcludes | Where-Object { $_ -match     '[\*\?\[\]]' })
    }

    $defaultExcludeFiles = @( 'settings.local.json', '.env', 'sccm.code-workspace', '*.code-workspace' )
    $allExcludeFiles = @()
    if (-not $NoDefaultExcludes) { $allExcludeFiles += $defaultExcludeFiles }
    if ($ExcludeFiles) { $allExcludeFiles += @($ExcludeFiles) }
    $allExcludeFiles = $allExcludeFiles | Select-Object -Unique

    $excludeExactFiles = @()
    $excludeWildFiles  = @()
    if ($allExcludeFiles) {
        $excludeExactFiles = @($allExcludeFiles | Where-Object { $_ -notmatch '[\*\?\[\]]' })
        $excludeWildFiles  = @($allExcludeFiles | Where-Object { $_ -match     '[\*\?\[\]]' })
    }

    $effectiveIncludePatterns = @()
    if ($IncludeFilePatterns) {
        foreach ($pattern in $IncludeFilePatterns) {
            if ([string]::IsNullOrWhiteSpace($pattern)) { continue }
            $p = $pattern.Trim()
            if ($p -notmatch '[\*\?\[\]]') {
                if ($p.StartsWith('.')) { $p = "*$p" }
                else { $p = "*$p*" }
            }
            $effectiveIncludePatterns += $p
        }
    }

    # native separator so path compares stay valid on linux and windows
    $sep = [string][IO.Path]::DirectorySeparatorChar
    function ConvertTo-NativeSeparator { param([string]$s) if ($null -eq $s) { return $null } if ($sep -eq '/') { return ($s -replace '\\', '/') } else { return ($s -replace '/', '\') } }
    # regex needs backslash input so normalize locally
    function ConvertTo-WslPath {
        param([string]$inputPath)
        if ([string]::IsNullOrWhiteSpace($inputPath)) { return $inputPath }
        $normalized = ($inputPath -replace '/', '\')
        if ($normalized -match '^[\\]{2}(?<server>[^\\]+)\\(?<share>[^\\]+)(?<rest>.*)$') {
            $server = $matches.server; $share = $matches.share
            $rest = $matches.rest -replace '^[\\/]+', ''
            if ($rest) { $rest = '/' + ($rest -replace '\\', '/') } else { $rest = '' }
            return "/mnt/unc/$server/$share$rest"
        }
        if ($normalized -match '^(?<drive>[a-zA-Z]):[\\/]?(?<rest>.*)$') {
            $driveLetter = $matches.drive.ToLowerInvariant()
            $rest = $matches.rest -replace '^[\\/]+', '' -replace '\\', '/'
            if ($rest) { return "/mnt/$driveLetter/$rest" }
            return "/mnt/$driveLetter"
        }
        return ($normalized -replace '\\', '/')
    }

    $rootFull = $Path
    try { $rootFull = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath } catch { }
    $rootFull = ConvertTo-NativeSeparator $rootFull
    if ($rootFull -and $rootFull.Length -gt 0 -and $rootFull[$rootFull.Length-1] -ne $sep[0]) { $rootFull += $sep }

    $excludePaths = @()
    if ($ExcludePathPatterns) { $excludePaths = @($ExcludePathPatterns | ForEach-Object { ConvertTo-NativeSeparator $_ }) }

    $includeExactNames = @(); $includeWildcardNames = @()
    $includeExactPaths = @(); $includeWildcardPaths = @()
    if ($IncludeFolders) {
        foreach ($entry in $IncludeFolders) {
            if ([string]::IsNullOrWhiteSpace($entry)) { continue }
            $normalizedEntry = (ConvertTo-NativeSeparator $entry).Trim()
            if ($normalizedEntry -match '[\\/]') {
                $normalizedEntry = $normalizedEntry.Trim($sep[0])
                if ($normalizedEntry) {
                    if ($normalizedEntry -notmatch '[\*\?\[\]]') { $includeExactPaths += $normalizedEntry.ToLowerInvariant() }
                    else { $includeWildcardPaths += $normalizedEntry }
                }
            } else {
                if ($normalizedEntry -notmatch '[\*\?\[\]]') { $includeExactNames += $normalizedEntry.ToLowerInvariant() }
                else { $includeWildcardNames += $normalizedEntry }
            }
        }
    }

    if (-not $MatchCache) { $MatchCache = @{} }
    if (-not $IncludeFolderCache) { $IncludeFolderCache = @{} }
    if (-not $SizeCache) { $SizeCache = @{} }
    if (-not $PsCountCache) { $PsCountCache = @{} }
    if (-not $TraversalState) {
        $TraversalState = @{
            FolderCount    = 0
            FileCount      = 0
            SkippedFolders = 0
            SkippedFiles   = 0
            LinkCount      = 0
        }
    }

    if ($CurrentDepth -eq 0 -and $UseRunspaces -and ($effectiveIncludePatterns -or $IncludeExtensions -or $IncludeFolders)) {
        Write-Verbose "Starting parallel pre-scan of '$Path' to populate caches..."

        $preScanScript = {
            param($targetPath, $effectiveIncludePatterns, $normInclude, $normExclude, $excludeExactFiles, $excludeWildFiles, $excludeExact, $excludeWild, $excludePaths, $includeExactNames, $includeWildcardNames, $includeExactPaths, $includeWildcardPaths, $IncludeHidden, $MaxDepth, $FollowReparse, $FoldersOnly)

            $matchPaths = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
            $folderPaths = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)

            function Get-NormalizedExtension { param($ext) if ([string]::IsNullOrEmpty($ext)) { return '' } $ext = $ext.ToLowerInvariant(); if ($ext -notmatch '^\.') { return ".$ext" } else { return $ext } }

            $params = @{ LiteralPath = $targetPath; File = $true; Recurse = $true; ErrorAction = 'SilentlyContinue'; Force = $IncludeHidden }
            if ($MaxDepth -gt 0) { $params['Depth'] = $MaxDepth }

            Get-ChildItem @params | ForEach-Object {
                $file = $_
                $isMatch = $true
                $ext = Get-NormalizedExtension $file.Extension
                if ($normInclude -and ($normInclude -notcontains $ext)) { $isMatch = $false }
                if ($isMatch -and $normExclude -and ($normExclude -contains $ext)) { $isMatch = $false }

                $matchedByPattern = $false
                if ($isMatch -and $effectiveIncludePatterns) {
                    foreach ($p in $effectiveIncludePatterns) { if ($file.Name -like $p) { $matchedByPattern = $true; break } }
                    if (-not $matchedByPattern) { $isMatch = $false }
                }
                if ($isMatch -and -not $matchedByPattern) {
                    if ($excludeExactFiles -and ($excludeExactFiles -contains $file.Name)) { $isMatch = $false }
                    if ($isMatch -and $excludeWildFiles) { foreach ($p in $excludeWildFiles) { if ($file.Name -like $p) { $isMatch = $false; break } } }
                }
                if ($isMatch -and $excludePaths) {
                    $full = $file.FullName
                    foreach ($p in $excludePaths) { if ($full -like "*$p*") { $isMatch = $false; break } }
                }
                if ($isMatch) {
                    $curr = $file.DirectoryName
                    while ($curr -and $curr.Length -ge $targetPath.Length) {
                        [void]$matchPaths.Add($curr)
                        $curr = Split-Path $curr -Parent
                    }
                }
            }
            return @{ MatchPaths = $matchPaths; FolderPaths = $folderPaths }
        }

        $topLevelItems = Get-ChildItem -LiteralPath $Path -Directory -ErrorAction SilentlyContinue
        $scanTargets = @($Path)
        if ($topLevelItems) { $scanTargets += @($topLevelItems.FullName) }

        $pool = [RunspaceFactory]::CreateRunspacePool(1, $MaxThreads)
        $pool.Open()
        $jobs = New-Object System.Collections.ArrayList

        foreach ($target in $scanTargets) {
            $ps = [PowerShell]::Create()
            $ps.RunspacePool = $pool
            [void]$ps.AddScript($preScanScript)
            [void]$ps.AddArgument($target)
            [void]$ps.AddArgument($effectiveIncludePatterns)
            [void]$ps.AddArgument($normInclude)
            [void]$ps.AddArgument($normExclude)
            [void]$ps.AddArgument($excludeExactFiles)
            [void]$ps.AddArgument($excludeWildFiles)
            [void]$ps.AddArgument($excludeExact)
            [void]$ps.AddArgument($excludeWild)
            [void]$ps.AddArgument($excludePaths)
            [void]$ps.AddArgument($includeExactNames)
            [void]$ps.AddArgument($includeWildcardNames)
            [void]$ps.AddArgument($includeExactPaths)
            [void]$ps.AddArgument($includeWildcardPaths)
            [void]$ps.AddArgument($IncludeHidden)
            [void]$ps.AddArgument($MaxDepth)
            [void]$ps.AddArgument($FollowReparse)
            [void]$ps.AddArgument($FoldersOnly)
            [void]$jobs.Add([PSCustomObject]@{ Pipe = $ps; Result = $ps.BeginInvoke() })
        }

        while (@($jobs | Where-Object { -not $_.Result.IsCompleted }).Count -gt 0) { Start-Sleep -Milliseconds 100 }

        foreach ($j in $jobs) {
            try {
                $res = $j.Pipe.EndInvoke($j.Result)
                if ($res.MatchPaths) {
                    foreach ($p in $res.MatchPaths) { $MatchCache[$p.ToLowerInvariant()] = $true }
                }
            } catch {
                Write-Verbose "Error in pre-scan thread: $_"
            } finally { $j.Pipe.Dispose() }
        }
        $pool.Close()
        $pool.Dispose()
        Write-Verbose "Pre-scan complete. Match cache populated with $($MatchCache.Count) folder paths."
    }

    function ConvertTo-RelativePath { param([string]$full)
        if ([string]::IsNullOrEmpty($rootFull)) { return $full }
        if ($full -and $full.Length -ge $rootFull.Length) {
            if ($full.Substring(0, $rootFull.Length) -ieq $rootFull) { return $full.Substring($rootFull.Length) }
        }
        return $full
    }
    function Test-MatchAny { param([string]$value, [string[]]$patterns)
        if (-not $patterns -or (@($patterns).Count -eq 0)) { return $false }
        foreach ($p in $patterns) { if ($value -like $p) { return $true } }
        return $false
    }
    function Test-ExcludeByPath { param($item)
        if (-not $excludePaths -or (@($excludePaths).Count -eq 0)) { return $false }
        $full = ConvertTo-NativeSeparator $item.FullName
        $rel  = ConvertTo-RelativePath $full
        if (Test-MatchAny -value $full -patterns $excludePaths) { return $true }
        if (Test-MatchAny -value $rel  -patterns $excludePaths) { return $true }
        return $false
    }
    function Test-FolderMatchesInclude {
        param($item)
        if (-not $IncludeFolders -or (@($IncludeFolders).Count -eq 0)) { return $true }
        $nameKey = $item.Name.ToLowerInvariant()
        if ((@($includeExactNames).Count -gt 0) -and ($includeExactNames -contains $nameKey)) { return $true }
        if ((@($includeWildcardNames).Count -gt 0)) {
            foreach ($pattern in $includeWildcardNames) { if ($item.Name -like $pattern) { return $true } }
        }
        if ((@($includeExactPaths).Count -gt 0)) {
            foreach ($path in $includeExactPaths) {
                $firstSegment = ($path -split '[\\/]')[0]
                if ($firstSegment -eq $nameKey) { return $true }
            }
        }
        if ((@($includeWildcardPaths).Count -gt 0)) {
            foreach ($pattern in $includeWildcardPaths) {
                $firstPattern = ($pattern -split '[\\/]')[0]
                if ($item.Name -like $firstPattern) { return $true }
            }
        }
        return $false
    }
    function Test-IncludeFile {
        param($item)
        $ext = ConvertTo-NormalizedExtension $item.Extension
        if ($normInclude -and ($normInclude -notcontains $ext)) { return $false }
        if ($normExclude -and ($normExclude -contains $ext)) { return $false }
        if ($effectiveIncludePatterns -and (@($effectiveIncludePatterns).Count -gt 0)) {
            $matched = $false
            foreach ($pattern in $effectiveIncludePatterns) { if ($item.Name -like $pattern) { $matched = $true; break } }
            if (-not $matched) { return $false }
            return $true
        }
        if (@($excludeExactFiles).Count -gt 0 -and ($excludeExactFiles -contains $item.Name)) { return $false }
        if (@($excludeWildFiles).Count -gt 0) {
            foreach ($pattern in $excludeWildFiles) { if ($item.Name -like $pattern) { return $false } }
        }
        return $true
    }
    function Test-ExcludeFolder {
        param($item)
        if ($IncludeFolders -and (@($IncludeFolders).Count -gt 0) -and $CurrentDepth -eq 0) {
            if (Test-IncludeFolder $item) { return $false }
        }
        if (Test-ExcludeByPath $item) { return $true }
        # includehidden was asked for so dont let excludes drop hidden items
        if ($IncludeHidden -and (Test-IsHidden $item)) { return $false }
        if ((@($excludeExact).Count -gt 0) -and ($excludeExact -contains $item.Name)) { return $true }
        if ((@($excludeWild).Count -gt 0)) {
            foreach ($pat in $excludeWild) { if ($item.Name -like $pat) { return $true } }
        }
        return $false
    }
    function Test-IncludeFolder {
        param($item)
        if (-not $IncludeFolders -or (@($IncludeFolders).Count -eq 0)) { return $true }
        if (Test-FolderMatchesInclude $item) { return $true }
        if (Test-FolderContainsIncludedFolder $item.FullName) { return $true }
        return $false
    }
    function Test-ReparsePoint {
        param($item)
        try { return ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 } catch { return $false }
    }
    function Test-IsHidden {
        param($item)
        try { return ($item.Attributes -band [IO.FileAttributes]::Hidden) -ne 0 } catch { return $false }
    }

    function Test-FolderContainsMatchingFiles {
        param([string]$folderPath, [int]$maxDepthToCheck = 50)
        if (-not $effectiveIncludePatterns -and -not $IncludeExtensions) { return $true }
        $normalizedPath = ConvertTo-NativeSeparator $folderPath
        $cacheKey = $normalizedPath.ToLowerInvariant()
        if ($MatchCache.ContainsKey($cacheKey)) { return $MatchCache[$cacheKey] }

        $stack = New-Object 'System.Collections.Generic.Stack[PSObject]'
        $stack.Push([PSCustomObject]@{ Path = $normalizedPath; Depth = 0 })
        while ($stack.Count -gt 0) {
            $current = $stack.Pop()
            if ($current.Depth -ge $maxDepthToCheck) { continue }
            try {
                $items = if ($IncludeHidden) { Get-ChildItem -LiteralPath $current.Path -Force -ErrorAction Stop } else { Get-ChildItem -LiteralPath $current.Path -ErrorAction Stop }
                foreach ($item in $items) {
                    if (-not $item.PSIsContainer) {
                        if (Test-IncludeFile $item) { $MatchCache[$cacheKey] = $true; return $true }
                    } elseif (-not (Test-ExcludeFolder $item) -and (-not (Test-ReparsePoint $item) -or $FollowReparse)) {
                        if ($CurrentDepth -eq 0 -and -not (Test-IncludeFolder $item)) { continue }
                        $stack.Push([PSCustomObject]@{ Path = $item.FullName; Depth = $current.Depth + 1 })
                    }
                }
            } catch { Write-Verbose "Match-cache scan failed for '$($current.Path)': $_" }
        }
        $MatchCache[$cacheKey] = $false
        return $false
    }

    function Test-FolderContainsIncludedFolder {
        param([string]$folderPath, [int]$maxDepthToCheck = 50)
        if (-not $IncludeFolders -or (@($IncludeFolders).Count -eq 0)) { return $true }
        $normalizedPath = ConvertTo-NativeSeparator $folderPath
        $cacheKey = $normalizedPath.ToLowerInvariant()
        if ($IncludeFolderCache.ContainsKey($cacheKey)) { return $IncludeFolderCache[$cacheKey] }

        $stack = New-Object 'System.Collections.Generic.Stack[PSObject]'
        $stack.Push([PSCustomObject]@{ Path = $normalizedPath; Depth = 0 })
        while ($stack.Count -gt 0) {
            $current = $stack.Pop()
            if ($current.Depth -ge $maxDepthToCheck) { continue }
            try {
                $items = if ($IncludeHidden) { Get-ChildItem -LiteralPath $current.Path -Force -Directory -ErrorAction Stop } else { Get-ChildItem -LiteralPath $current.Path -Directory -ErrorAction Stop }
                foreach ($item in $items) {
                    if (-not $FollowReparse -and (Test-ReparsePoint $item)) { continue }
                    if (Test-ExcludeByPath $item) { continue }
                    if (-not ($IncludeHidden -and (Test-IsHidden $item))) {
                        if ((@($excludeExact).Count -gt 0) -and ($excludeExact -contains $item.Name)) { continue }
                        if ((@($excludeWild).Count -gt 0)) { $skip = $false; foreach ($pat in $excludeWild) { if ($item.Name -like $pat) { $skip = $true; break } } if ($skip) { continue } }
                    }
                    if (Test-FolderMatchesInclude $item) { $IncludeFolderCache[$cacheKey] = $true; return $true }
                    $stack.Push([PSCustomObject]@{ Path = $item.FullName; Depth = $current.Depth + 1 })
                }
            } catch { Write-Verbose "Include-folder scan failed for '$($current.Path)': $_" }
        }
        $IncludeFolderCache[$cacheKey] = $false
        return $false
    }

    if (-not $PSBoundParameters.ContainsKey('AsHtml') -and $OutputFile -and ($OutputFile -match '\.html?$')) { $AsHtml = $true }

    $output = @()
    $patternCount = if ($effectiveIncludePatterns) { @($effectiveIncludePatterns).Count } else { 0 }
    $extCount = if ($IncludeExtensions) { @($IncludeExtensions).Count } else { 0 }
    $fileFilterActive = ($patternCount -gt 0 -or $extCount -gt 0)

    # best effort UTF-8 for console unicode rendering
    try {
        if (-not $AsHtml -and -not $Ascii) {
            $isUtf8 = $false
            try { $isUtf8 = ([Console]::OutputEncoding.WebName -eq 'utf-8') } catch {}
            if (-not $isUtf8) { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) }
        }
    } catch {}

    if ($Ascii) {
        $treeChars = @{ Branch = '+-'; Last = '\\-'; Pipe = '| '; Space = '  ' }
        $fileChar = '-'; $folderChar = '+'; $errorChar = 'X'
        $linkChar = '>'; $targetChar = '~'
    } else {
        $branch = if ($AsHtml) { '&#x251C;&#x2500;' } else { [string]([char]0x251C) + [char]0x2500 }
        $last   = if ($AsHtml) { '&#x2514;&#x2500;' } else { [string]([char]0x2514) + [char]0x2500 }
        $pipe   = if ($AsHtml) { '&#x2502; '     } else { [string]([char]0x2502) + ' ' }
        $treeChars = @{ Branch = $branch; Last = $last; Pipe = $pipe; Space = '  ' }
        $fileChar   = if ($AsHtml) { '&#x00B7;' } else { [char]0x00B7 }
        $folderChar = if ($AsHtml) { '&#x25A0;' } else { [char]0x25A0 }
        $errorChar  = if ($AsHtml) { '&#x00D7;' } else { [char]0x00D7 }
        $linkChar   = if ($AsHtml) { '&#x2192;' } else { [char]0x2192 }
        $targetChar = if ($AsHtml) { '&#x21B3;' } else { [char]0x21B3 }
    }
    $esc = [char]0x1b
    $ansiGray = "$esc[90m"; $ansiReset = "$esc[0m"
    if ($AsHtml) { $ansiGray = $null; $ansiReset = $null }

    function Format-HiddenLine {
        param([string]$Line, [bool]$IsHidden)
        if (-not $IncludeHidden -or -not $IsHidden) { return $Line }
        if ($AsHtml) { return "<span style='color:#888888'>$Line</span>" }
        if ($null -ne $ansiGray -and $null -ne $ansiReset) { return "$ansiGray$Line$ansiReset" }
        return $Line
    }
    $folderSuffix = if ($LinuxPaths) { '/' } else { [string][char]92 }

    function Get-Children {
        param([string]$p)
        if ($IncludeHidden) { $allItems = @(Get-ChildItem -Path $p -Force -ErrorAction Stop) }
        else { $allItems = @(Get-ChildItem -Path $p -ErrorAction Stop) }
        $folders = @($allItems | Where-Object { $_.PSIsContainer } | Sort-Object Name)
        $files = @($allItems | Where-Object { -not $_.PSIsContainer } | Sort-Object Name)
        return @($folders + $files)
    }

    function Complete-DirectoryMapOutput {
        param([string[]]$Lines, [string[]]$TreeLines)
        if (-not $TreeLines) { $TreeLines = $Lines }
        $filteredLines = @()
        if ($Lines) { $filteredLines = $Lines | Where-Object { $_ -and $_.Trim() -ne '' } }
        $treeOnly = @()
        if ($TreeLines) { $treeOnly = $TreeLines | Where-Object { $_ -and $_.Trim() -ne '' } }

        $summaryLines = @(); $summaryBullets = @()
        if ($CurrentDepth -eq 0 -and $EmitSummary) {
            $summaryLines += 'Summary:'
            $summaryLines += "  Folders: $($TraversalState.FolderCount)"
            $summaryLines += "  Files: $($TraversalState.FileCount)"
            $skippedFolderCount = [int]$TraversalState.SkippedFolders
            $skippedFileCount = [int]$TraversalState.SkippedFiles
            $linkCount = [int]$TraversalState.LinkCount
            if ($skippedFolderCount -gt 0 -or $skippedFileCount -gt 0) {
                $summaryLines += "  Skipped: $skippedFolderCount folders, $skippedFileCount files"
            }
            if ($linkCount -gt 0) { $summaryLines += "  Symlinks: $linkCount" }
            $summaryBullets += "- Folders: $($TraversalState.FolderCount)"
            $summaryBullets += "- Files: $($TraversalState.FileCount)"
            if ($skippedFolderCount -gt 0 -or $skippedFileCount -gt 0) {
                $summaryBullets += "- Skipped: $skippedFolderCount folders, $skippedFileCount files"
            }
            if ($linkCount -gt 0) { $summaryBullets += "- Symlinks: $linkCount" }
        }
        $finalLines = if ($summaryLines.Count -gt 0) { $filteredLines + $summaryLines } else { $filteredLines }

        if ($CurrentDepth -eq 0) {
            $markdownTarget = $null; $writeTextToOutputFile = $false
            if ($OutputFile) {
                if ($AsMarkdown -and -not $MarkdownFile) { $markdownTarget = $OutputFile }
                else { $writeTextToOutputFile = $true }
            }
            if ($MarkdownFile) { $markdownTarget = $MarkdownFile }

            if ($writeTextToOutputFile) {
                try {
                    $outDir = Split-Path -Path $OutputFile -Parent
                    if ($outDir -and -not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
                    $finalLines | Out-File -FilePath $OutputFile -Encoding UTF8
                } catch { Write-Verbose "Failed to write output file: $_" }
            }
            if ($markdownTarget) {
                try {
                    $mdDir = Split-Path -Path $markdownTarget -Parent
                    if ($mdDir -and -not (Test-Path -LiteralPath $mdDir)) { New-Item -ItemType Directory -Path $mdDir -Force | Out-Null }
                    if ($LinuxPaths) { $displayRoot = ConvertTo-WslPath $Path }
                    else { $displayRoot = if ($rootFull) { $rootFull.TrimEnd($sep[0]) } else { ConvertTo-NativeSeparator $Path } }
                    if (-not $displayRoot) { $displayRoot = $Path }
                    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                    $mdLines = @( '# Directory Map', '', ('**Root:** `{0}`' -f $displayRoot), ('**Generated:** {0}' -f $timestamp) )
                    if ($summaryBullets.Count -gt 0) { $mdLines += ''; $mdLines += '#### Summary'; $mdLines += $summaryBullets }
                    $mdLines += ''; $mdLines += '```text'
                    if ($treeOnly.Count -gt 0) { $mdLines += $treeOnly } else { $mdLines += '(no entries)' }
                    $mdLines += '```'
                    $mdLines | Set-Content -Path $markdownTarget -Encoding UTF8
                } catch { Write-Verbose "Failed to write markdown file: $_" }
            }
        }
        return $finalLines
    }

    if (-not $ShowFullPathTree) {
        $rawItems = @()
        $itemsLoaded = $true
        try { $rawItems = Get-Children -p $Path }
        catch {
            $itemsLoaded = $false
            $deniedPath = if ($LinuxPaths) { ConvertTo-WslPath $Path } else { $Path }
            $errorLines = @("$Indent$errorChar ACCESS DENIED: $deniedPath")
        }
        if (-not $itemsLoaded) {
            return Complete-DirectoryMapOutput -Lines $errorLines -TreeLines $errorLines
        }

        # filter before isLast or connectors break
        $filteredFolders = @(); $filteredLinks = @(); $filteredFiles = @()
        foreach ($item in $rawItems) {
            if (-not $FollowReparse -and (Test-ReparsePoint $item)) {
                $filteredLinks += $item
                continue
            }
            if (Test-ExcludeByPath $item) {
                if ($item.PSIsContainer) { $TraversalState.SkippedFolders++ } else { $TraversalState.SkippedFiles++ }
                continue
            }
            if ($item.PSIsContainer) {
                if (($effectiveIncludePatterns -or $IncludeExtensions)) {
                    if (-not (Test-FolderContainsMatchingFiles $item.FullName)) { $TraversalState.SkippedFolders++; continue }
                }
                if (Test-ExcludeFolder $item) { $TraversalState.SkippedFolders++; continue }
                if (-not (Test-IncludeFolder $item)) { $TraversalState.SkippedFolders++; continue }
                $filteredFolders += $item
            } elseif (-not $FoldersOnly -or $fileFilterActive) {
                if (-not (Test-IncludeFile $item)) { $TraversalState.SkippedFiles++; continue }
                $filteredFiles += $item
            }
        }

        $items = @($filteredFolders) + @($filteredLinks) + @($filteredFiles)
        $count = @($items).Count

        for ($i = 0; $i -lt $count; $i++) {
            $item = $items[$i]
            $isLast = $i -eq ($count - 1)
            $connector = if ($isLast) { $treeChars.Last } else { $treeChars.Branch }
            $nextIndent = if ($isLast) { "$Indent$($treeChars.Space)" } else { "$Indent$($treeChars.Pipe)" }

            if (-not $FollowReparse -and (Test-ReparsePoint $item)) {
                $linkTarget = $item.Target
                if ([string]::IsNullOrWhiteSpace($linkTarget)) { $linkTarget = '(broken link)' }
                $line1 = "$Indent$connector $linkChar $($item.Name)"
                $line2 = "$nextIndent $targetChar $linkTarget"
                $output += Format-HiddenLine -Line $line1 -IsHidden:(Test-IsHidden $item)
                $output += Format-HiddenLine -Line $line2 -IsHidden:(Test-IsHidden $item)
                $TraversalState.LinkCount++
            } elseif ($item.PSIsContainer) {
                $annotation = Get-FolderAnnotation -folderPath $item.FullName
                $line = "$Indent$connector $folderChar $($item.Name)$folderSuffix$annotation"
                $output += Format-HiddenLine -Line $line -IsHidden:(Test-IsHidden $item)
                $TraversalState.FolderCount++
                if ($CurrentDepth -lt $MaxDepth) {
                    $output += Get-DowserMap -Path $item.FullName -Indent $nextIndent -MaxDepth $MaxDepth -CurrentDepth ($CurrentDepth + 1) -IncludeExtensions $IncludeExtensions -ExcludeExtensions $ExcludeExtensions -IncludeFilePatterns $IncludeFilePatterns -ExcludeFiles $ExcludeFiles -ExcludeFolders $ExcludeFolders -IncludeFolders $IncludeFolders -ExcludePathPatterns $ExcludePathPatterns -NoDefaultExcludes:$NoDefaultExcludes -FoldersOnly:$FoldersOnly -AsHtml:$AsHtml -AsMarkdown:$AsMarkdown -Ascii:$Ascii -IncludeHidden:$IncludeHidden -FollowReparse:$FollowReparse -ShowFullPathTree:$ShowFullPathTree -LinuxPaths:$LinuxPaths -OutputFile $OutputFile -MarkdownFile $MarkdownFile -EmitSummary:$EmitSummary -IncludeSize:$IncludeSize -IncludePsCount:$IncludePsCount -MatchCache $MatchCache -IncludeFolderCache $IncludeFolderCache -TraversalState $TraversalState -SizeCache $SizeCache -PsCountCache $PsCountCache
                }
            } else {
                $line = "$Indent$connector $fileChar $($item.Name)"
                $output += Format-HiddenLine -Line $line -IsHidden:(Test-IsHidden $item)
                $TraversalState.FileCount++
            }
        }
        return Complete-DirectoryMapOutput -Lines $output -TreeLines $output
    }

    $segments = @()
    if ($LinuxPaths) {
        $displayPath = ConvertTo-WslPath $Path
        if ($displayPath) {
            if ($displayPath.StartsWith('/')) { $segments += '/' }
            $remaining = $displayPath.TrimStart('/')
            if ($remaining) { $segments += $remaining -split '/' }
        }
    } elseif ($Path -match '^(\\\\|//)([^\\/]+)[\\/]+([^\\/]+)[\\/]*(.*)') {
        $segments += $matches[2]; $segments += $matches[3]
        if ($matches[4]) { $segments += $matches[4] -split '[\\/]' }
    } elseif ($Path -match '^([a-zA-Z]:)[\\/]*(.*)') {
        $segments += $matches[1]
        if ($matches[2]) { $segments += $matches[2] -split '[\\/]' }
    } else { $segments += $Path -split '[\\/]' }
    $segments = $segments | Where-Object { $_ -ne '' -or $_ -eq '/' }

    $currentPathSegmentIndent = ""
    $segmentSlash = if ($LinuxPaths) { '/' } else { [string][char]92 }
    for ($i = 0; $i -lt @($segments).Count; $i++) {
        $segmentName = $segments[$i]
        $connector = $treeChars.Last + " "
        $isLastSegment = ($i -eq @($segments).Count - 1)
        $slash = if (-not $isLastSegment -and $segmentName -ne '/') { $segmentSlash } else { '' }
        $output += "$currentPathSegmentIndent$connector$folderChar $segmentName$slash"
        $currentPathSegmentIndent += "    "
    }

    $childrenBaseIndent = $currentPathSegmentIndent
    $children = @()
    $childrenLoaded = $true
    try { $children = Get-Children -p $Path }
    catch {
        $childrenLoaded = $false
        $deniedPath = if ($LinuxPaths) { ConvertTo-WslPath $Path } else { $Path }
        $errorLines = @("$childrenBaseIndent$errorChar ACCESS DENIED: $deniedPath")
    }
    if (-not $childrenLoaded) {
        return Complete-DirectoryMapOutput -Lines $errorLines -TreeLines $errorLines
    }

    $folders = @(); $links = @()
    foreach ($child in $children) {
        if (-not $child.PSIsContainer) { continue }
        if (-not $FollowReparse -and (Test-ReparsePoint $child)) { $links += $child; continue }
        if (Test-ExcludeByPath $child) { $TraversalState.SkippedFolders++; continue }
        if (($effectiveIncludePatterns -or $IncludeExtensions)) {
            if (-not (Test-FolderContainsMatchingFiles $child.FullName)) { $TraversalState.SkippedFolders++; continue }
        }
        if (Test-ExcludeFolder $child) { $TraversalState.SkippedFolders++; continue }
        if (-not (Test-IncludeFolder $child)) { $TraversalState.SkippedFolders++; continue }
        $folders += $child
    }

    $files = @()
    if (-not $FoldersOnly -or $fileFilterActive) {
        foreach ($child in $children) {
            if ($child.PSIsContainer) { continue }
            if (Test-ExcludeByPath $child) { $TraversalState.SkippedFiles++; continue }
            if (-not (Test-IncludeFile $child)) { $TraversalState.SkippedFiles++; continue }
            $files += $child
        }
    }

    $all = @($folders) + @($links) + @($files)
    $count = @($all).Count
    for ($i = 0; $i -lt $count; $i++) {
        $item = $all[$i]
        $isLast = $i -eq ($count - 1)
        $connector = if ($isLast) { $treeChars.Last } else { $treeChars.Branch }
        $additionalIndent = if ($isLast) { $treeChars.Space } else { $treeChars.Pipe }
        $recursiveIndent = $childrenBaseIndent + $additionalIndent

        if (-not $FollowReparse -and (Test-ReparsePoint $item)) {
            $linkTarget = $item.Target
            if ([string]::IsNullOrWhiteSpace($linkTarget)) { $linkTarget = '(broken link)' }
            $line1 = "$childrenBaseIndent$connector $linkChar $($item.Name)"
            $line2 = "$recursiveIndent $targetChar $linkTarget"
            $output += Format-HiddenLine -Line $line1 -IsHidden:(Test-IsHidden $item)
            $output += Format-HiddenLine -Line $line2 -IsHidden:(Test-IsHidden $item)
            $TraversalState.LinkCount++
        } elseif ($item.PSIsContainer) {
            $annotation = Get-FolderAnnotation -folderPath $item.FullName
            $line = "$childrenBaseIndent$connector $folderChar $($item.Name)$folderSuffix$annotation"
            $line = Format-HiddenLine -Line $line -IsHidden:(Test-IsHidden $item)
            if ($CurrentDepth -lt $MaxDepth) {
                $TraversalState.FolderCount++
                $subTree = Get-DowserMap -Path $item.FullName -Indent $recursiveIndent -MaxDepth $MaxDepth -CurrentDepth ($CurrentDepth + 1) -IncludeExtensions $IncludeExtensions -ExcludeExtensions $ExcludeExtensions -IncludeFilePatterns $IncludeFilePatterns -ExcludeFiles $ExcludeFiles -ExcludeFolders $ExcludeFolders -IncludeFolders $IncludeFolders -ExcludePathPatterns $ExcludePathPatterns -NoDefaultExcludes:$NoDefaultExcludes -FoldersOnly:$FoldersOnly -AsHtml:$AsHtml -AsMarkdown:$AsMarkdown -Ascii:$Ascii -IncludeHidden:$IncludeHidden -FollowReparse:$FollowReparse -ShowFullPathTree:$false -LinuxPaths:$LinuxPaths -OutputFile $OutputFile -MarkdownFile $MarkdownFile -EmitSummary:$EmitSummary -IncludeSize:$IncludeSize -IncludePsCount:$IncludePsCount -MatchCache $MatchCache -IncludeFolderCache $IncludeFolderCache -TraversalState $TraversalState -SizeCache $SizeCache -PsCountCache $PsCountCache
                $output += @($line) + $subTree
            } else {
                $TraversalState.FolderCount++
                $output += $line
            }
        } else {
            $line = "$childrenBaseIndent$connector $fileChar $($item.Name)"
            $line = Format-HiddenLine -Line $line -IsHidden:(Test-IsHidden $item)
            $TraversalState.FileCount++
            $output += $line
        }
    }
    return Complete-DirectoryMapOutput -Lines $output -TreeLines $output
}
