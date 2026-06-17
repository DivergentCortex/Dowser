# Dowser Index

Single source of truth for what exists in the module. **Read this before adding anything.** If a similar capability already exists, extend it -- do not add a parallel implementation.

## Format

### Verb-DowserNoun
- Purpose:
- Inputs:
- Outputs:
- Related:
- Source:

---

## Platform Support

Dowser runs on PowerShell 5.1 (Windows) and pwsh 7+ (Windows/Linux/macOS).

### Fully Cross-Platform
These functions work identically (or with a platform-equivalent path) on all supported platforms:
- `Find-DowserDuplicate`, `Find-DowserFile`, `Find-DowserModified`, `Find-DowserOrphan`, `Find-DowserDependency`, `Find-DowserScript`, `Find-DowserString`, `Find-DowserRecentLog`
- `Invoke-DowserFastSearch`, `Invoke-DowserNumericSort`, `Measure-DowserDirectory`, `Measure-DowserDiskUsage`
- `Get-DowserMap`, `Get-DowserTopology`, `Get-DowserInfo`, `Get-DowserReport`, `Compare-DowserReport`
- `ConvertTo-DowserBase64`
- `Get-DowserOwnership` - returns Owner/Group/UnixMode plus a PlatformNote on non-Windows (the Shell.Application extended metadata is the Windows-only enrichment)
- `New-DowserHiddenFolder` - NTFS Hidden+System on Windows, leading-dot rename on Linux/macOS

### Reduced on Non-Windows
These functions run but drop the Windows-only enrichments:
- `Get-DowserProperty` - Shell.Application extended properties and Authenticode signature unavailable; core metadata, hashes, and PE walk still run
- `Expand-DowserExe` - requires `7z` on PATH (install via package manager)
- `Test-DowserExtractable` - CAB/expand.exe detection unavailable
- `Test-DowserIntegrity` - CAB and Alternate Data Stream checks unavailable

### Windows-Only
These functions emit a warning and return `$null` on non-Windows:
- `ConvertTo-DowserIco` - requires System.Drawing (GDI+)
- `ConvertTo-DowserExe` - produces Windows PE binaries
- `Get-DowserTemplate` - requires Shell.Application COM

### Linux/macOS Dependencies
- `7z` (p7zip-full package) for archive extraction functions

---

## Exported cmdlets

### ConvertTo-DowserBase64
- Purpose: Converts images to Base64 strings and vice-versa using pure PowerShell.
- Inputs: `Path` (required, pipeline, ImagePath/FullName aliases), `OutputFile`, `Decode`, `IncludeHeader`, `CopyToClipboard`
- Outputs: With no `-OutputFile` and no `-CopyToClipboard`, emits the Base64 string to the pipeline. `-OutputFile` writes the string to disk; `-CopyToClipboard` copies it. Decode mode writes the image to `-OutputFile` (required for decode).
- Note: `-CopyToClipboard` is guarded for headless sessions: if Set-Clipboard is unavailable or fails (common on Linux with no display), it warns and, when no -OutputFile was given, falls back to emitting the Base64 to the pipeline.
- Source: `ConvertTo-Base64.ps1`

### ConvertTo-DowserExe
- Purpose: Generates a C# executable wrapper for a PowerShell script.
- Source: `ConvertTo-Exe.ps1`

### ConvertTo-DowserIco
- Purpose: Creates `.ico` files from images using multi-size PNG-compressed layouts.
- Source: `ConvertTo-ICO.ps1`

### New-DowserHiddenFolder
- Purpose: Create a folder (or take an existing one) and hide it. Windows: sets NTFS Hidden+System attributes. Linux/macOS: renames the folder with a leading dot, the platform-native way to hide it.
- Inputs: `Path` (required, pipeline, FullName alias), `Force` (suppress already-exists warning), `AttributesOnly` (apply hiding to an existing folder, no creation). Supports -WhatIf/-Confirm.
- Outputs: PSCustomObject with Path and Attributes (the real on-disk attributes, re-read after any change). On Linux/macOS also carries a PlatformNote explaining the leading-dot convention. Under -AttributesOnly on Linux/macOS, the folder cannot be renamed, so it warns that the folder is NOT hidden rather than silently doing nothing.
- Source: `create-hiddenfolder.ps1`

### Get-DowserTemplate
- Purpose: Gets Windows Explorer folder template configurations via Shell COM object.
- Source: `Get-FolderTemplate.ps1`

### Find-DowserDuplicate
- Purpose: Detects duplicate files using Name, Size, and Chunked Hash algorithms.
- Source: `Find-FileDuplicates.ps1`

### Find-DowserFile
- Purpose: High-performance multi-threaded file searcher based on attributes, size, and modified dates.
- Source: `Find-Files.ps1`

### Find-DowserModified
- Purpose: Quick search for files modified on a specific exact date.
- Source: `Find-FilesModifiedOn.ps1`

### Find-DowserOrphan
- Purpose: Scans for non-referenced text files in a project directory using tokenized lookup.
- Source: `Find-OrphanFiles.ps1`

### Find-DowserDependency
- Purpose: Scans PowerShell scripts for function calls and dot-sourcing dependencies.
- Source: `Find-ScriptDependencies.ps1`

### Find-DowserScript
- Purpose: Searches directory trees for specific script types.
- Source: `Find-Scripts.ps1`

### Find-DowserRecentLog
- Purpose: Returns the most recent log file from a directory.
- Source: `Find-MostRecentLog.ps1`

### Find-DowserString
- Purpose: Multi-pattern literal text search across a directory tree using compiled Aho-Corasick matching, with three-phase RunspacePool parallelism (streaming directory enumeration, parallel file gathering, parallel searching). Multiple output modes.
- Inputs: `Path` (pipeline), `Pattern` (one or more literal patterns), `Recurse`, `Include`, `Exclude`, `CaseSensitive`, plus output-mode switches.
- Outputs: PSCustomObject per match with file, line number, and matched pattern; a `[READ-ERROR]` sentinel row distinguishes unreadable files from no-match.
- Related: `Invoke-DowserFastSearch` (single-pattern parallel search, simpler output)
- Source: `Find-DowserString.ps1`
- Aliases: `dstr`, `dgrep`

### Get-DowserOwnership
- Purpose: Gets file ownership and metadata for files in a directory (extension-filtered). On Windows, enriches with Shell.Application extended properties; on Linux/macOS, returns real Unix ownership.
- Inputs: `Directory` (default `$PWD`), `Extension` (wildcard, default `*`)
- Outputs: PSCustomObject per file. On Windows: Shell extended properties, version info, attributes. On Linux/macOS: Owner, Group, UnixMode, Attributes, IsReadOnly/IsHidden/IsSystem, plus a PlatformNote stating Shell.Application metadata is Windows-only and was skipped.
- Related: `Get-DowserProperty` (deeper single-file analysis)
- Source: `Get-FileOwnership.ps1`

### Get-DowserProperty
- Purpose: Comprehensive file inspector -- VersionInfo, Shell COM extended props (0-500), hashes, Authenticode, .NET assembly, PE header.
- Inputs: `FilePath` (pipeline-friendly, FullName alias), `IncludeEmptyProperties`, `IncludeSignature`, `IncludeDirectories`
- Outputs: PSCustomObject with all available file metadata.
- Related: `Get-DowserOwnership` (directory-wide scan)
- Source: `Get-FilePropertyDetails.ps1`

### Get-DowserTopology
- Purpose: Renders a visual tree view for any PSProvider path (FileSystem, Registry, Cert:, etc.). Supports ANSI colorization on FileSystem.
- Inputs: `Path` / `LiteralPath` (pipeline), `Depth`, `IndentSize`, `ShowItem`, `ShowProperty`, `InColor` (dynamic, FileSystem only)
- Outputs: Formatted tree strings to pipeline.
- Related: `Get-DowserMap` (richer file-system-only tree with size/count annotations)
- Source: `Get-TreeTopology.ps1`
- Aliases: `pstree`, `shtree`

### Get-DowserReport
- Purpose: File metrics report (size, lines, words, chars, timestamps, attrs, optional owner) with parallel RunspacePool processing.
- Inputs: `Path`, `Pattern`, `Extensions`, `Depth`, `IncludeOwner`, `MinSize`, `MaxSize`, `UseRunspaces`, `ThreadCount`, `ExportCsv`, `ExportHtml`, `SortBy`, `Descending`
- Outputs: PSCustomObject per file; grouped table view for multi-depth scans; optional CSV/HTML export.
- Related: `Compare-DowserReport` (companion diff cmdlet bundled in same file)
- Source: `Get-FileReport.ps1`

### Compare-DowserReport
- Purpose: Diffs two Get-DowserReport snapshots -- shows NEW, CHANGED, REMOVED, UNCHANGED files with size/line/word/char deltas.
- Inputs: `Before` (PSCustomObject[]), `After` (PSCustomObject[]), `ShowUnchanged`
- Outputs: PSCustomObject per file with Status and delta fields.
- Related: `Get-DowserReport`
- Source: `Public/Get-DowserReport.ps1` (defined in the same file as Get-DowserReport)
- Note: Exported public function. It shares a file with Get-DowserReport so it has no Public/ basename; the loader names it explicitly in Export-ModuleMember and the manifest's FunctionsToExport lists it (27th export). Available immediately after Import-Module.

### Get-DowserInfo
- Purpose: Reports Dowser module identity: manifest version, latest changelog entry version and date, public function count, and module root path.
- Inputs: None (reads Dowser.psd1 and docs/CHANGELOG.md relative to module root)
- Outputs: PSCustomObject with Module, ModuleVersion, LatestChangelogVersion, LatestChangelogDate, LatestChangelogTitle, ModuleRoot, PublicFunctions, ChangelogPath.
- Related: None
- Source: Original to Dowser (not ported)

### Get-DowserMap
- Purpose: Visual tree renderer for directory structures. Renders folder/file hierarchy using Unicode box-drawing characters with optional size (-IncludeSize) and .ps1 count (-IncludePsCount) annotations. Supports HTML, Markdown, and full-path trunk display modes. Symlinks are shown in place without traversal by default (two-line block: a name line marked U+2192 and a target line marked U+21B3); use -FollowReparse to descend into them.
- Inputs: `Path` (pipeline, FullName alias), `MaxDepth` (default 3), `ShowFullPathTree` / `S`, `LinuxPaths` / `L`, `Ascii`, `AsHtml`, `AsMarkdown`, `IncludeHidden`, `FollowReparse`, `IncludeSize`, `IncludePsCount`, `FoldersOnly`, `IncludeFilePatterns`, `IncludeExtensions`, `ExcludeExtensions`, `ExcludeFolders`, `ExcludeFiles`, `IncludeFolders`, `ExcludePathPatterns`, `NoDefaultExcludes`, `OutputFile`, `MarkdownFile`, `EmitSummary`, `UseRunspaces`, `MaxThreads`
- Outputs: String array of tree lines (pipeline). Optional file output via -OutputFile / -MarkdownFile.
- Tree glyphs: `■` folder, `·` file, `→` (U+2192) symlink name, `↳` (U+21B3) symlink target, `×` access denied. Box-drawing: `├─` branch, `└─` last, `│` continuation. HTML mode emits `&#xNNNN;` entities; -Ascii mode uses `+`/`-`/`>`/`~`.
- Related: `Get-DowserTopology` (any PSProvider path, ANSI color, no size/count annotations)
- Source: `Get-DowserMap.ps1`
- Aliases: `dmap`

### Measure-DowserDirectory
- Purpose: Measures size, file count, and key file timestamps for each immediate subdirectory under a root path.
- Inputs: `Path` (pipeline, FullName alias; defaults to `.`)
- Outputs: PSCustomObject per subdirectory with Directory, DataSize, FileCount, LargestFile, LargestFileName, NewestFileName, NewestFileDate, OldestFileName, OldestFileDate.
- Related: `Measure-DowserDiskUsage` (recursive rollup, ranking, treemap), `Get-DowserReport` (per-file metrics)
- Source: `Get-DirectorySizeCounts.ps1`
- Aliases: `dsize`

### Measure-DowserDiskUsage
- Purpose: WinDirStat-style recursive disk-usage report: biggest directories (rollup), biggest files, and by-extension breakdown, ranked descending. Optional -ExportHtml produces a self-contained treemap HTML report.
- Inputs: `Path` (pipeline, FullName alias; defaults to `.`), `TopN` (default 15), `MinSize` (file-ranking filter), `ExportHtml` (path), `ExcludePath` (directory names to skip)
- Outputs: PSCustomObject per section (Section = Summary | BiggestDirectories | BiggestFiles | ByExtension) with RelPath, SizeBytes, Size, PctOfTotal, Bar, RootPath fields.
- Related: `Measure-DowserDirectory` (immediate-subdir sizing only, no ranking or HTML)
- Source: Original to Dowser (not ported)
- Aliases: `ddu`

### Invoke-DowserFastSearch
- Purpose: Parallel single-pattern text search across files using a RunspacePool. Returns per-file match objects with line numbers.
- Inputs: `Path` (pipeline), `SearchString` (alias: `Pattern`), `Threads` (default 10), `Include`, `Exclude`, `CaseSensitive`
- Outputs: PSCustomObject per matching file -- FileName, FileType, LineNumbers, FullPath.
- Related: `Find-DowserString` (multi-pattern, Aho-Corasick, multiple output modes)
- Source: `Invoke-FastTextSearch.ps1`
- Aliases: `dfast`

### Invoke-DowserNumericSort
- Purpose: Natural numeric sort for strings or objects with embedded numbers (Item-2 before Item-10).
- Inputs: `InputObject` (pipeline), `Property`, `Descending`, `CaseSensitive`, `Unique`, `Top`
- Outputs: Sorted objects (same type as input).
- Related: `Find-DowserFile`, `Find-DowserDuplicate`
- Source: `Invoke-NumericalSorting.ps1` (Sort-Numerical function; Get-SortKey maps to Private\Get-DowserSortKey)
- Aliases: `dsort`, `dnsort`

### Test-DowserExtractable
- Purpose: Tests whether an EXE can be simply extracted (SFX/installer) or requires decompilation (ps2exe, .NET, native).
- Inputs: `Path` (pipeline, FullName alias), `Recurse`, `Filter`, `SevenZipPath`, `SkipSevenZip`
- Outputs: PSCustomObject per EXE - Path, Extractable (bool), Classification, InstallerType, ArchiveType, Confidence, FileCount, Details.
- Related: `Expand-DowserExe` (extracts files from extractable EXEs), `Get-DowserProperty` (deep file inspection)
- Source: `Test-DowserExtractable.ps1` (classification logic documented in exe-static-classification-reference.md)
- Aliases: `dtest`, `dtestexe`

### Test-DowserIntegrity
- Purpose: Layered corruption + hygiene detection for source trees. Dispatches by file category to the strongest available validator (7z t for archives with ZipFile/expand.exe/MSI-magic fallbacks; PE structural walk for EXE/DLL/SYS; read-accessibility probe for generic files), then runs an always-on hygiene scan for SCCM-distribution killers: hidden/system attributes, Zone.Identifier ADS (Mark-of-the-Web), other alternate data streams, and residue names (Thumbs.db, desktop.ini, .DS_Store, ._*, ~$*, *.tmp, *.bak, *.orig, *.swp, *.lock, *.partial, *.crdownload, *.part). Optional SHA256 hashing and baseline-CSV drift detection.
- Inputs: `Path` (pipeline, FullName alias), `Recurse`, `Filter`, `SevenZipPath`, `SkipSevenZip`, `ComputeHash`, `BaselineCsv`, `Detailed`, `IncludeClean`
- Outputs: Default emits one summary object with TotalFiles, per-Status counts (OK, Corrupt, Error, Warning, Suspicious, Residue, Unverified), ProblemCount, TopProblems[10], DetailsGlobal pointer. Full per-file array always stashed in `$global:DowserIntegrityDetails`. Use `-Detailed` to stream per-file objects (Path, RelativePath, Name, Extension, SizeBytes, Size, Category, Status, Method, Confidence, SHA256, BaselineMatch, Details, Issues[]) instead of the summary. Per-file stream defaults to problems only (Corrupt/Error/Warning/Suspicious/Residue); `-IncludeClean` adds OK and Unverified.
- Related: `Test-DowserExtractable` (EXE classification, not corruption), `Get-DowserReport` (metrics, not validation), `Expand-DowserExe` (extract once integrity confirmed)
- Source: `Test-DowserIntegrity.ps1`
- Aliases: `dintegrity`, `dinteg`

### Expand-DowserExe
- Purpose: Extracts files from extractable EXE archives using 7-Zip. Runs Test-DowserExtractable first, then 7z x. ShouldProcess support (-WhatIf, -Confirm).
- Inputs: `Path` (pipeline, FullName alias), `Destination`, `SevenZipPath` (defaults to bare `7z` on non-Windows, the 7-Zip install path on Windows), `Force`, `PassThru`
- Outputs: Nothing by default (writes a one-line Write-Verbose summary). With `-PassThru`, emits one PSCustomObject per EXE: Path, Destination, Success (bool), ExitCode, Classification, FileCount, ArchiveType, Details. Auto-creates a destination folder named `<ExeName>_extracted` when -Destination is not given.
- Note: BEHAVIOR -- `-PassThru` is opt-in. Earlier builds always emitted the result object; it is now suppressed unless `-PassThru` is supplied.
- Related: `Test-DowserExtractable` (classification without extraction), `Test-DowserIntegrity` (corruption detection)
- Source: Original to Dowser (not ported)
- Aliases: `dexpand`, `dextract`