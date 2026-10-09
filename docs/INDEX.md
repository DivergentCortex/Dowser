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
- `Start-DowserTransfer`, `Remove-DowserTransferSource`
- `Invoke-DowserFastSearch`, `Invoke-DowserNumericSort`, `Measure-DowserDirectory`, `Measure-DowserDiskUsage`
- `Get-DowserMap`, `Get-DowserTopology`, `Get-DowserInfo`, `Get-DowserReport`, `Compare-DowserReport`, `Compare-DowserDirectory`
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
- Aliases: `ConvertTo-Base64` (opt-in via `Enable-DowserAliases`)

### ConvertTo-DowserExe

- Purpose: Generates a C# executable wrapper for a PowerShell script.
- Source: `ConvertTo-Exe.ps1`
- Aliases: `ConvertTo-Exe` (opt-in via `Enable-DowserAliases`)

### ConvertTo-DowserIco

- Purpose: Creates `.ico` files from images using multi-size PNG-compressed layouts.
- Source: `ConvertTo-ICO.ps1`
- Aliases: `ConvertTo-Ico` (opt-in via `Enable-DowserAliases`)

### New-DowserHiddenFolder

- Purpose: Create a folder (or take an existing one) and hide it. Windows: sets NTFS Hidden+System attributes. Linux/macOS: renames the folder with a leading dot, the platform-native way to hide it.
- Inputs: `Path` (required, pipeline, FullName alias), `Force` (suppress already-exists warning), `AttributesOnly` (apply hiding to an existing folder, no creation). Supports -WhatIf/-Confirm.
- Outputs: PSCustomObject with Path and Attributes (the real on-disk attributes, re-read after any change). On Linux/macOS also carries a PlatformNote explaining the leading-dot convention. Under -AttributesOnly on Linux/macOS, the folder cannot be renamed, so it warns that the folder is NOT hidden rather than silently doing nothing.
- Source: `create-hiddenfolder.ps1`
- Aliases: `New-HiddenFolder` (opt-in via `Enable-DowserAliases`)

### Get-DowserTemplate

- Purpose: Gets Windows Explorer folder template configurations via Shell COM object.
- Source: `Get-FolderTemplate.ps1`
- Aliases: `Get-Template` (opt-in via `Enable-DowserAliases`)

### Find-DowserDuplicate

- Purpose: Finds duplicate-file candidates by name or shared chunks, and proves byte-identical files with full SHA content hashes. Shows progress during enumeration and every hash stage.
- Inputs: `Path`, `Exclude`, `MinSize`, `Mode` (`Name`, `PartialName`, `NameSize`, `Content`, `Chunk`, or `All`), `HashAlgorithm`, `ChunkSize`, `ChunkOverlap`, `ReportPath` (CSV), `ExportHtml`, `ReviewBeforeDelete`, `AutoRemove`.
- Outputs: Compact summary objects plus full duplicate sets in `$global:dupObjects`. `ExportHtml` writes an expandable exact-content report ranked by potential reclaimable space and creates its parent directory when needed.
- Note: Only `Content` proves complete byte-for-byte equality. `Chunk` identifies shared blocks and is not a safe deletion decision by itself.
- Source: `Find-FileDuplicates.ps1`
- Aliases: `Find-Duplicate` (opt-in via `Enable-DowserAliases`)

### Find-DowserFile

- Purpose: High-performance multi-threaded file searcher based on name, attributes, size, and modified dates.
- Inputs: `Path` (pipeline), `Pattern` (default `*`; bare strings auto-wrap to `*string*`), `ExcludePattern` (wildcard, tested against both name and full path; matching folders are pruned from the walk, not just filtered from output; auto-wraps the same way `Pattern` does), `Recurse` (default true), `MinSize`, `MaxSize`, `ModifiedAfter`, `ModifiedBefore`, `StopOnFirstMatch`, `UseRunspaces` (default true), `ThreadCount`.
- Outputs: PSCustomObject per matching file -- FullName, Name, Directory, Size, LastWriteTime, CreationTime.
- Note: `ExcludePattern` prunes traversal via a manual directory-stack walk rather than `Get-ChildItem -Recurse`, since `-Exclude` on `Get-ChildItem` only hides a matched item from output and does not stop recursion into it. An excluded folder's contents are never enumerated at all, so excluding a large toolchain or dependency tree also cuts search time, not just result noise. This walk only activates when `-ExcludePattern` is supplied; omitting it keeps the original `Get-ChildItem -Recurse` fast path unchanged.
- Source: `Find-DowserFile.ps1`
- Aliases: `Find-File` (opt-in via `Enable-DowserAliases`)

### Find-DowserModified

- Purpose: Quick search for files modified on a specific exact date.
- Source: `Find-FilesModifiedOn.ps1`
- Aliases: `Find-Modified` (opt-in via `Enable-DowserAliases`)

### Find-DowserOrphan

- Purpose: Scans for non-referenced text files in a project directory using tokenized lookup.
- Source: `Find-OrphanFiles.ps1`
- Aliases: `Find-Orphan` (opt-in via `Enable-DowserAliases`)

### Find-DowserDependency

- Purpose: Scans PowerShell scripts for function calls and dot-sourcing dependencies.
- Source: `Find-ScriptDependencies.ps1`
- Aliases: `Find-Dependency` (opt-in via `Enable-DowserAliases`)

### Find-DowserScript

- Purpose: Searches directory trees for specific script types.
- Source: `Find-Scripts.ps1`
- Aliases: `Find-ScriptFile` (opt-in via `Enable-DowserAliases`)

### Find-DowserRecentLog

- Purpose: Returns the most recent log file from a directory.
- Source: `Find-MostRecentLog.ps1`
- Aliases: `Find-RecentLog` (opt-in via `Enable-DowserAliases`)

### Find-DowserString

- Purpose: Multi-pattern literal text search across a directory tree using compiled Aho-Corasick matching, with three-phase RunspacePool parallelism (streaming directory enumeration, parallel file gathering, parallel searching). Multiple output modes.
- Inputs: `Path` (pipeline), `Pattern` (one or more literal patterns), `Recurse`, `Include`, `Exclude`, `CaseSensitive`, plus output-mode switches.
- Outputs: PSCustomObject per match with file, line number, and matched pattern; a `[READ-ERROR]` sentinel row distinguishes unreadable files from no-match.
- Related: `Invoke-DowserFastSearch` (single-pattern parallel search, simpler output)
- Source: `Find-DowserString.ps1`
- Aliases: `Find-String` (opt-in via `Enable-DowserAliases`)

### Get-DowserOwnership

- Purpose: Gets file ownership and metadata for files in a directory (extension-filtered). On Windows, enriches with Shell.Application extended properties; on Linux/macOS, returns real Unix ownership.
- Inputs: `Directory` (default `$PWD`), `Extension` (wildcard, default `*`)
- Outputs: PSCustomObject per file. On Windows: Shell extended properties, version info, attributes. On Linux/macOS: Owner, Group, UnixMode, Attributes, IsReadOnly/IsHidden/IsSystem, plus a PlatformNote stating Shell.Application metadata is Windows-only and was skipped.
- Related: `Get-DowserProperty` (deeper single-file analysis)
- Source: `Get-FileOwnership.ps1`
- Aliases: `Get-Ownership` (opt-in via `Enable-DowserAliases`)

### Get-DowserProperty

- Purpose: Comprehensive file inspector -- VersionInfo, Shell COM extended props (0-500), hashes, Authenticode, .NET assembly, PE header.
- Inputs: `FilePath` (pipeline-friendly, FullName alias), `IncludeEmptyProperties`, `IncludeSignature`, `IncludeDirectories`
- Outputs: PSCustomObject with all available file metadata.
- Related: `Get-DowserOwnership` (directory-wide scan)
- Source: `Get-FilePropertyDetails.ps1`
- Aliases: `Get-Property` (opt-in via `Enable-DowserAliases`)

### Get-DowserTopology

- Purpose: Renders a visual tree view for any PSProvider path (FileSystem, Registry, Cert:, etc.). Supports ANSI colorization on FileSystem.
- Inputs: `Path` / `LiteralPath` (pipeline), `Depth`, `IndentSize`, `ShowItem`, `ShowProperty`, `InColor` (dynamic, FileSystem only)
- Outputs: Formatted tree strings to pipeline.
- Related: `Get-DowserMap` (richer file-system-only tree with size/count annotations)
- Source: `Get-TreeTopology.ps1`
- Aliases: `Get-Tree`, `pstree`, `shtree` (opt-in via `Enable-DowserAliases`)

### Get-DowserReport

- Note: reads every file's contents for line/word/char counts, so it is slow on large trees. `Depth` defaults to 0 (files directly inside `Path` only); on a folder of folders it now warns to pass `-Depth -1`. For recency questions use `Measure-DowserDirectory` instead.
- Purpose: File metrics report (size, lines, words, chars, timestamps, attrs, optional owner) with parallel RunspacePool processing.
- Inputs: `Path`, `Pattern`, `Extensions`, `Depth`, `IncludeOwner`, `MinSize`, `MaxSize`, `UseRunspaces`, `ThreadCount`, `ExportCsv`, `ExportHtml`, `SortBy`, `Descending`
- Outputs: PSCustomObject per file; grouped table view for multi-depth scans; optional CSV/HTML export.
- Related: `Compare-DowserReport` (companion diff cmdlet bundled in same file)
- Source: `Get-FileReport.ps1`
- Aliases: `Get-Report` (opt-in via `Enable-DowserAliases`)

### Compare-DowserReport

- Purpose: Diffs two Get-DowserReport snapshots -- shows NEW, CHANGED, REMOVED, UNCHANGED files with size/line/word/char deltas.
- Inputs: `Before` (PSCustomObject[]), `After` (PSCustomObject[]), `ShowUnchanged`
- Outputs: PSCustomObject per file with Status and delta fields.
- Related: `Get-DowserReport`
- Source: `Public/Get-DowserReport.ps1` (defined in the same file as Get-DowserReport)
- Aliases: `Compare-Report` (opt-in via `Enable-DowserAliases`)
- Note: Exported public function. It shares a file with Get-DowserReport so it has no Public/ basename; the loader names it explicitly in Export-ModuleMember and the manifest's FunctionsToExport lists it. Available immediately after Import-Module.

### Compare-DowserDirectory

- Purpose: Content diff of two folders (or two files) by SHA256. Pairs files by relative path and reports Same, Changed (Reason Size or Content), MissingFromDifference, ExtraInDifference, or Unreadable. Git-agnostic: typical use is a git checkout vs an installed copy or cache (for example `~/projects/cortex-plugins/<plugin>` vs `~/.claude/plugins/cache/divergentcortex/<plugin>/unknown`). Read-only.
- Inputs: `ReferencePath` (position 0), `DifferencePath` (position 1), `ExcludePattern` (wildcards against name and relative path; matching folders are pruned), `NoDefaultExcludes`, `IncludeSame`, `Summary`. Positional binding is limited to the two paths.
- Outputs: PSCustomObject per differing file (Status, RelativePath, Reason, ReferenceSize, DifferenceSize, ReferenceLastWrite, DifferenceLastWrite); identical files only with `-IncludeSame`. `-Summary` returns one object with the five counts and `InSync`.
- Note: `.git`, `node_modules`, `__pycache__`, `.venv`, and `venv` are pruned on both sides by default (never enumerated). Symlinked directories are not followed. Sizes are compared first; files are hashed only when sizes match. Relative-path matching is case-sensitive on Linux/macOS and case-insensitive on Windows. A folder paired with a file is an error.
- Related: `Compare-DowserReport` (diffs two Get-DowserReport snapshots, not folders), `Find-DowserDuplicate` (duplicates within one tree), `Measure-DowserDirectory` (per-folder recency)
- Source: Original to Dowser (not ported)
- Aliases: `Compare-Directory` (opt-in via `Enable-DowserAliases`)

### Get-DowserInfo

- Purpose: Reports Dowser module identity: manifest version, latest changelog entry version and date, public function count, and module root path.
- Inputs: None (reads Dowser.psd1 and docs/CHANGELOG.md relative to module root)
- Outputs: PSCustomObject with Module, ModuleVersion, LatestChangelogVersion, LatestChangelogDate, LatestChangelogTitle, ModuleRoot, PublicFunctions, ChangelogPath.
- Related: None
- Source: Original to Dowser (not ported)
- Aliases: `Get-Info` (opt-in via `Enable-DowserAliases`)

### Get-DowserJsonKey

- Purpose: Streams JSON and JSONL tokens to report key paths and per-file occurrence counts. With `-Compare`, groups files by complete key layout and shows the dominant layout with representative variants.
- Inputs: `Path` (JSON or JSONL file, or directory; pipeline), `Recurse` (default true), `Compare`, `ShowKeyComparison`, `IncludeFiles` (opt-in path lists), `Validation` (emit per-key file-coverage classification), `ProfileLimit` (default 10), `ThreadCount` (maximum readers; default is the lower of 8 or processor count).
- Outputs: Default rows contain FilePath, Format, Documents, KeyPath, and OccurrenceCount. Compare emits DirectorySummary and SchemaProfile rows including sample files and capped key-difference previews. `ShowKeyComparison` adds individual key-path rows. `IncludeFiles` adds full path lists for drill-down. `Validation` adds KeyValidation rows (Classification: AlwaysPresent, Common, Occasional, Rare; FileCount; MissingFileCount; CoveragePercent). Results from the most recent comparison stay available in `$global:DowserJsonLastComparison` and `$global:DowserJsonLastValidation`; unparseable files are recorded in `$global:DowserJsonLastParseFailures`.
- Related: `Export-DowserJsonCsv` for spreadsheet output; `Export-DowserJsonAssessment` writes this function's comparison and validation output straight to CSV.
- Source: `Get-DowserJsonKey.ps1`
- Alias: `Get-JsonKey` after `Enable-DowserAliases`.

### Export-DowserJsonCsv

- Purpose: Writes JSON or JSONL scalar values as a long-form, Excel-compatible CSV without loading the full document.
- Inputs: `Path` (JSON or JSONL file; pipeline), `OutputPath`, `Force`.
- Outputs: PSCustomObject with SourcePath, OutputPath, Documents, and ValuesWritten. CSV rows contain SourceFile, DocumentNumber, KeyPath, and Value.
- Related: `Get-DowserJsonKey` for key-only inspection and comparison.
- Source: `Export-DowserJsonCsv.ps1`
- Alias: `Export-JsonCsv` after `Enable-DowserAliases`.

### Test-DowserJson

- Purpose: Diagnoses JSON and JSONL files before repair or schema assessment. Distinguishes valid JSON, valid JSONL, comment-bearing JSON, RECORD banner exports, tagged transcript text, and parser syntax errors.
- Inputs: `Path` (file or directory; pipeline), `Recurse` (default true).
- Outputs: One row per file with Classification, Repairable, RepairAction, parser error line and position, and the parser message. Does not change files.
- Related: `Repair-DowserJson` performs only diagnosis-approved repairs; `Get-DowserJsonKey` assesses parseable file schemas.
- Source: `Test-DowserJson.ps1`

### Repair-DowserJson

- Purpose: Diagnoses JSON first and writes a repaired copy only for recognized deterministic cases: Dowser RECORD banners and JSON comments.
- Inputs: `Path` (file or directory; pipeline), `Recurse` (default true), `OutputDirectory` (optional), `Force`.
- Outputs: One row per file with its diagnosis, Result, and OutputPath. By default a repaired file is written as `<name>.repaired.jsonl` under `JSON-Repaired` beside the source. Other syntax errors and tagged transcript text are skipped, never guessed into JSON.
- Related: `Test-DowserJson` for assessment without writes; `Get-DowserJsonKey` for schema inspection afterward.
- Source: `Repair-DowserJson.ps1`

### Export-DowserJsonAssessment

- Purpose: Runs a directory-level JSON assessment (via `Get-DowserJsonKey -Compare`) once and writes three CSV reports: directory summary, representative schema profiles, and per-key-path validation coverage.
- Inputs: `Path` (required, directory or JSON file), `OutputDirectory` (required, created on demand), `ProfileLimit` (default 10), `ThreadCount` (default: the lower of 8 or processor count), `Force` (replace existing report files). Supports -WhatIf/-Confirm.
- Outputs: PSCustomObject with OutputDirectory, SummaryPath, SchemaProfilesPath, KeyValidationPath, and ValidationRows. Writes `directory-summary.csv`, `schema-profiles.csv`, and `key-validation.csv` under `-OutputDirectory`. Refuses to overwrite an existing report file without `-Force`.
- Note: Metadata export only -- it writes assessment reports, not source documents or values.
- Related: `Get-DowserJsonKey` (the scan this function wraps and exports), `Export-DowserJsonCsv` (per-value CSV export instead of schema assessment).
- Source: `Export-DowserJsonAssessment.ps1`

### Get-DowserMap

- Purpose: Visual tree renderer for directory structures. Renders folder/file hierarchy using Unicode box-drawing characters with optional size (-IncludeSize) and file count (-IncludeFileCount, alias: -IncludePsCount) annotations. Supports HTML, Markdown, and full-path trunk display modes. Symlinks are shown in place without traversal by default (two-line block: a name line marked U+2192 and a target line marked U+21B3); use -FollowReparse to descend into them.
- Inputs: `Path` (pipeline, FullName alias), `MaxDepth` (default 3), `ShowFullPathTree` / `S`, `LinuxPaths` / `L`, `Ascii`, `AsHtml`, `AsMarkdown`, `IncludeHidden`, `FollowReparse`, `IncludeSize`, `IncludeFileCount` (alias: `IncludePsCount`), `FoldersOnly`, `IncludeFilePatterns`, `IncludeExtensions`, `ExcludeExtensions`, `ExcludeFolders`, `ExcludeFiles`, `IncludeFolders`, `ExcludePathPatterns`, `NoDefaultExcludes`, `OutputFile`, `MarkdownFile`, `EmitSummary`, `UseRunspaces`, `MaxThreads`, `SevenZipPath`
- Binding: only `Path` binds by position (`PositionalBinding = $false`); a stray bare word such as `max 1` is rejected with a binding error instead of silently becoming a file filter.
- Depth: `MaxDepth` follows the `Get-ChildItem -Depth` convention. 0 lists only the root's immediate contents; each increment adds one level.
- Folder scoping: `IncludeFolders` takes names, wildcards, or paths relative to `-Path` (e.g. `py/pyconfig`). A matching folder renders with its full subtree, subject to `MaxDepth` and the other filters. Folders above a match render only as the route to it, and loose files and unrelated folders at those levels are hidden. Relative `ExcludePathPatterns` also resolve against the scan root at every depth. An included path reaches its target even through default-excluded names (e.g. `logs/target`); ordinary excludes still apply inside the match. `-IncludeSize`/`-IncludeFileCount` annotations and the summary total count only in-scope content: a route folder counts only its matched descendants, and loose root files are left out.
- FoldersOnly: hides files and file symlinks at every depth; folder symlinks still render as link blocks.
- Outputs: String array of tree lines (pipeline). Optional file output via -OutputFile / -MarkdownFile.
- Archive mode: when `-Path` resolves to a leaf file ending `.zip`, `.7z`, `.rar`, `.tar`, or `.gz`, Get-DowserMap renders the archive's internal contents as a tree instead of walking the filesystem, via the private nested `Get-DowserArchiveTreeLines` function. `.zip` is read with `System.IO.Compression.ZipFile`; the other formats shell out to 7-Zip (`-SevenZipPath`, defaulting to the standard Windows install path or bare `7z` on Linux/macOS) and parse `7z l -slt` output. Only the parameters the dispatch call explicitly forwards apply in archive mode: `-IncludeSize`, `-IncludeFileCount`, `-IncludeExtensions`, `-ExcludeExtensions`, `-ExcludeFolders`, `-ExcludeFiles`, `-IncludeFilePatterns`, `-NoDefaultExcludes`, `-FoldersOnly`, `-MaxDepth`, `-ShowFullPathTree`, `-LinuxPaths`, `-Ascii`, `-AsHtml`, and `-SevenZipPath`. Everything else (`-ExcludePathPatterns`, `-IncludeFolders`, `-IncludeHidden`, `-FollowReparse`, `-EmitSummary`, `-AsMarkdown`, `-OutputFile`, `-MarkdownFile`, `-UseRunspaces`, `-MaxThreads`) is silently ignored, since archive mode returns directly and never reaches `Complete-DirectoryMapOutput`. Design history: `docs/superpowers/specs/2026-07-05-archive-map-design.md` and `docs/superpowers/plans/2026-07-05-archive-map-implementation.md`.
- Summary: `EmitSummary` auto-enables when the output is Markdown (-AsMarkdown, -MarkdownFile, or an -OutputFile ending .md) unless the caller explicitly passes -EmitSummary (including :$false, which always wins). Reports the scan parameters (MaxDepth, whether default excludes were bypassed, FoldersOnly), folder/file/skip/symlink counts, and, when -IncludeSize is active, total size (every top-level folder plus any files sitting loose at the scan root) plus a top-10 largest-top-level-folders table -- drawn from the same folder-size cache the tree walk already builds, plus one bounded, non-recursive listing of the root's own files. A folder's cached size already includes everything under it, so the table ranks top-level folders only; ranking nested folders alongside their parents would double-list the same bytes under two labels. A top-level folder rejected by exclusion (default excludes, -ExcludeFolders, or -ExcludePathPatterns) never contributes to the total or the table; the summary names any such folders so a small total is never mistaken for a complete one. A folder left out only because it does not match an active -IncludeFolders allowlist is not named this way -- that is declared scope-narrowing, not a surprise. In Markdown mode the summary is placed before the tree, under a `#### Summary` heading.
- Tree glyphs: `■` folder, `·` file, `→` (U+2192) symlink name, `↳` (U+21B3) symlink target, `×` access denied. Box-drawing: `├─` branch, `└─` last, `│` continuation. HTML mode emits `&#xNNNN;` entities; -Ascii mode uses `+`/`-`/`>`/`~`.
- Related: `Get-DowserTopology` (any PSProvider path, ANSI color, no size/count annotations)
- Source: `Get-DowserMap.ps1`
- Aliases: `Get-Map` (opt-in via `Enable-DowserAliases`)

### Measure-DowserDirectory

- Purpose: Per-folder freshness and size report for each immediate subdirectory under a root path: how many files changed today, within the last N days, and before that, how long ago the newest file was written, plus size and largest/newest/oldest file. The go-to answer for "what changed recently in this directory".
- Inputs: `Path` (position 0, pipeline, FullName alias; defaults to `.`; a file path is skipped with a warning), `RecentDays` (1-36500, default 7; `ModifiedToday` always means since local midnight), `Now` (reference instant, default the current time)
- Outputs: PSCustomObject per subdirectory, plus a `.` row for loose files at the root when any exist: Folder, Directory, FileCount (recursive files), ItemCount (immediate children, folders included; the value FileCount reported before 2026.09.24), ModifiedToday, ModifiedWithinDays, OlderThanDays, RecentDays, NewestFileAge, NewestFileName, NewestFileDate, OldestFileName, OldestFileDate, DataSize, SizeBytes, LargestFile, LargestFileName. Default table view: Folder, FileCount, ModifiedToday, ModifiedWithinDays, OlderThanDays, NewestFileAge, NewestFileName, DataSize.
- Note: `ModifiedWithinDays + OlderThanDays = FileCount`; `ModifiedToday` is a subset of `ModifiedWithinDays`, so do not sum all three. Hidden and dot-prefixed folders (`.git`, `.claude`) get rows like any other. Symlinked directories inside a folder are not followed: PowerShell 6+ uses the native recursive scan (which does not follow them), and Windows PowerShell 5.1, whose -Recurse does follow them, uses the same pruning walker as `Compare-DowserDirectory`, so a link loop cannot hang the scan. Single pass per folder; unreadable subfolders are skipped and logged rather than dropping the row. For a file-level list of what changed, use `Find-DowserFile -ModifiedAfter (Get-Date).AddDays(-N)`.
- Related: `Measure-DowserDiskUsage` (recursive rollup, ranking, treemap), `Get-DowserReport` (per-file metrics)
- Source: `Get-DirectorySizeCounts.ps1`
- Aliases: `Measure-Directory` (opt-in via `Enable-DowserAliases`)

### Measure-DowserDiskUsage

- Purpose: WinDirStat-style recursive disk-usage report: biggest directories (rollup), biggest files, and by-extension breakdown, ranked descending. Optional -ExportHtml produces a self-contained treemap HTML report.
- Inputs: `Path` (pipeline, FullName alias; defaults to `.`), `TopN` (default 15), `MinSize` (file-ranking filter), `ExportHtml` (path), `ExcludePath` (directory names to skip)
- Outputs: PSCustomObject per section (Section = Summary | BiggestDirectories | BiggestFiles | ByExtension) with RelPath, SizeBytes, Size, PctOfTotal, Bar, RootPath fields.
- Related: `Measure-DowserDirectory` (recursive per-folder freshness and size, no ranking or HTML)
- Source: Original to Dowser (not ported)
- Aliases: `Measure-DiskUsage` (opt-in via `Enable-DowserAliases`)

### Invoke-DowserFastSearch

- Purpose: Parallel single-pattern text search across files using a RunspacePool. Returns per-file match objects with line numbers.
- Inputs: `Path` (pipeline), `SearchString` (alias: `Pattern`), `Threads` (default 10), `Include`, `Exclude`, `CaseSensitive`
- Outputs: PSCustomObject per matching file -- FileName, FileType, LineNumbers, FullPath.
- Related: `Find-DowserString` (multi-pattern, Aho-Corasick, multiple output modes)
- Source: `Invoke-FastTextSearch.ps1`
- Aliases: `dfast`, `Invoke-FastSearch` (opt-in via `Enable-DowserAliases`)

### Invoke-DowserNumericSort

- Purpose: Natural numeric sort for strings or objects with embedded numbers (Item-2 before Item-10).
- Inputs: `InputObject` (pipeline), `Property`, `Descending`, `CaseSensitive`, `Unique`, `Top`
- Outputs: Sorted objects (same type as input).
- Related: `Find-DowserFile`, `Find-DowserDuplicate`
- Source: `Invoke-NumericalSorting.ps1` (Sort-Numerical function; Get-SortKey maps to Private\Get-DowserSortKey)
- Aliases: `Invoke-NumericSort` (opt-in via `Enable-DowserAliases`)

### Test-DowserExtractable

- Purpose: Tests whether an EXE can be simply extracted (SFX/installer) or requires decompilation (ps2exe, .NET, native).
- Inputs: `Path` (pipeline, FullName alias), `Recurse`, `Filter`, `SevenZipPath`, `SkipSevenZip`
- Outputs: PSCustomObject per EXE - Path, Extractable (bool), Classification, InstallerType, ArchiveType, Confidence, FileCount, Details.
- Related: `Expand-DowserExe` (extracts files from extractable EXEs), `Get-DowserProperty` (deep file inspection)
- Source: `Test-DowserExtractable.ps1` (classification logic documented in exe-static-classification-reference.md)
- Aliases: `Test-Extractable` (opt-in via `Enable-DowserAliases`)

### Test-DowserIntegrity

- Purpose: Layered corruption + hygiene detection for source trees. Dispatches by file category to the strongest available validator (7z t for archives with ZipFile/expand.exe/MSI-magic fallbacks; PE structural walk for EXE/DLL/SYS; read-accessibility probe for generic files), then runs an always-on hygiene scan for SCCM-distribution killers: hidden/system attributes, Zone.Identifier ADS (Mark-of-the-Web), other alternate data streams, and residue names (Thumbs.db, desktop.ini, .DS*Store, .*_, ~$_, _.tmp, _.bak, _.orig, _.swp, _.lock, _.partial, _.crdownload, _.part). Optional SHA256 hashing and baseline-CSV drift detection.
- Inputs: `Path` (pipeline, FullName alias), `Recurse`, `Filter`, `SevenZipPath`, `SkipSevenZip`, `ComputeHash`, `BaselineCsv`, `Detailed`, `IncludeClean`
- Outputs: Default emits one summary object with TotalFiles, per-Status counts (OK, Corrupt, Error, Warning, Suspicious, Residue, Unverified), ProblemCount, TopProblems[10], DetailsGlobal pointer. Full per-file array always stashed in `$global:DowserIntegrityDetails`. Use `-Detailed` to stream per-file objects (Path, RelativePath, Name, Extension, SizeBytes, Size, Category, Status, Method, Confidence, SHA256, BaselineMatch, Details, Issues[]) instead of the summary. Per-file stream defaults to problems only (Corrupt/Error/Warning/Suspicious/Residue); `-IncludeClean` adds OK and Unverified.
- Related: `Test-DowserExtractable` (EXE classification, not corruption), `Get-DowserReport` (metrics, not validation), `Expand-DowserExe` (extract once integrity confirmed)
- Source: `Test-DowserIntegrity.ps1`
- Aliases: `Test-Integrity` (opt-in via `Enable-DowserAliases`)

### Expand-DowserExe

- Purpose: Extracts files from extractable EXE archives using 7-Zip. Runs Test-DowserExtractable first, then 7z x. ShouldProcess support (-WhatIf, -Confirm).
- Inputs: `Path` (pipeline, FullName alias), `Destination`, `SevenZipPath` (defaults to bare `7z` on non-Windows, the 7-Zip install path on Windows), `Force`, `PassThru`
- Outputs: Nothing by default (writes a one-line Write-Verbose summary). With `-PassThru`, emits one PSCustomObject per EXE: Path, Destination, Success (bool), ExitCode, Classification, FileCount, ArchiveType, Details. Auto-creates a destination folder named `<ExeName>_extracted` when -Destination is not given.
- Note: BEHAVIOR -- `-PassThru` is opt-in. Earlier builds always emitted the result object; it is now suppressed unless `-PassThru` is supplied.
- Related: `Test-DowserExtractable` (classification without extraction), `Test-DowserIntegrity` (corruption detection)
- Source: Original to Dowser (not ported)
- Aliases: `Expand-Exe` (opt-in via `Enable-DowserAliases`)

### Start-DowserTransfer

- Purpose: Copies one or more files or directories to a destination with a pre-flight free-space and headroom check, then verifies every copied file by hash before reporting it migrated. Only copies and verifies; never deletes source files.
- Inputs: `Source` (required, pipeline, FullName alias, `string[]` -- file or directory paths; directory sources copy recursively, preserving structure under a folder named after the source directory), `Destination` (required directory, created on demand), `HeadroomPercent` (default 10 -- required free space as a percentage of total bytes to copy, on top of the total itself), `ManifestPath` (optional; defaults to a timestamped JSON file under -Destination; not written on a -WhatIf dry run), `ThreadCount` (default: the lower of 8 or the processor count). Supports -WhatIf/-Confirm (ConfirmImpact Medium).
- Outputs: PSCustomObject with Success, DryRun, FileCount, TotalBytes, BytesCopied, FailureCount, ManifestPath, Destination. Under `-WhatIf`, reports the real file count and byte total it would move and copies nothing.
- Note: Safety order per file, run in parallel across a dedicated runspace pool (Private/Invoke-DowserTransferPool.ps1, Private/Invoke-DowserTransferWorker.ps1): hash the source once (SHA256) -> copy -> hash the destination -> compare -> mark verified only on a match. A hash mismatch is a hard per-file failure; that file is never reported as migrated. A real run writes a JSON verification manifest (Items array with per-file SourcePath/DestinationPath/Success/SourceHash/DestHash), the required input to Remove-DowserTransferSource for a later, separate deletion pass -- the write is wrapped in its own try/catch, so ManifestPath comes back $null if the write itself fails (disk full, permissions).
- Related: `Remove-DowserTransferSource` (manifest-gated deletion of verified source files)
- Source: `Start-DowserTransfer.ps1`
- Aliases: `Start-Transfer` (opt-in via `Enable-DowserAliases`)

### Remove-DowserTransferSource

- Purpose: Deletes source files recorded as hash-verified in a Start-DowserTransfer manifest. Never runs as a side effect of Start-DowserTransfer.
- Inputs: `ManifestPath` (required -- no implicit "last run" lookup). Supports -WhatIf/-Confirm (ConfirmImpact High).
- Outputs: PSCustomObject with Success, ManifestPath, TotalEntries, DeletedCount, SkippedCount, ReVerifyFailedCount, DeleteFailedCount.
- Note: Manifest entries not marked Success are skipped outright. For every remaining entry, re-hashes the destination file (SHA256) and compares it against the DestHash recorded in the manifest before deleting -- a defense against a stale or tampered manifest. Any entry whose destination hash no longer matches is logged and skipped, never deleted.
- Related: `Start-DowserTransfer` (produces the manifest this function consumes)
- Source: `Remove-DowserTransferSource.ps1`
- Aliases: `Remove-TransferSource` (opt-in via `Enable-DowserAliases`)
