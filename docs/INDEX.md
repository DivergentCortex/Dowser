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

- Purpose: Finds duplicate-file candidates by name or shared chunks, and proves byte-identical files with full SHA content hashes. Shows progress during enumeration and every hash stage.
- Inputs: `Path`, `Exclude`, `MinSize`, `Mode` (`Name`, `PartialName`, `NameSize`, `Content`, `Chunk`, or `All`), `HashAlgorithm`, `ChunkSize`, `ChunkOverlap`, `ReportPath` (CSV), `ExportHtml`, `ReviewBeforeDelete`, `AutoRemove`.
- Outputs: Compact summary objects plus full duplicate sets in `$global:dupObjects`. `ExportHtml` writes an expandable exact-content report ranked by potential reclaimable space and creates its parent directory when needed.
- Note: Only `Content` proves complete byte-for-byte equality. `Chunk` identifies shared blocks and is not a safe deletion decision by itself.
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

### Get-DowserJsonKey

- Purpose: Streams JSON and JSONL tokens to report key paths and per-file occurrence counts. With `-Compare`, groups files by complete key layout and shows the dominant layout with representative variants.
- Inputs: `Path` (JSON or JSONL file, or directory; pipeline), `Recurse` (default true), `Compare`, `ShowKeyComparison`, `IncludeFiles` (opt-in path lists), `ProfileLimit` (default 10), `ThreadCount` (maximum readers; default is the lower of 8 or processor count).
- Outputs: Default rows contain FilePath, Format, Documents, KeyPath, and OccurrenceCount. Compare emits DirectorySummary and SchemaProfile rows including sample files and capped key-difference previews. `ShowKeyComparison` adds individual key-path rows. `IncludeFiles` adds full path lists for drill-down.
- Related: `Export-DowserJsonCsv` for spreadsheet output.
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

### Get-DowserMap

- Purpose: Visual tree renderer for directory structures. Renders folder/file hierarchy using Unicode box-drawing characters with optional size (-IncludeSize) and file count (-IncludeFileCount, alias: -IncludePsCount) annotations. Supports HTML, Markdown, and full-path trunk display modes. Symlinks are shown in place without traversal by default (two-line block: a name line marked U+2192 and a target line marked U+21B3); use -FollowReparse to descend into them.
- Inputs: `Path` (pipeline, FullName alias), `MaxDepth` (default 3), `ShowFullPathTree` / `S`, `LinuxPaths` / `L`, `Ascii`, `AsHtml`, `AsMarkdown`, `IncludeHidden`, `FollowReparse`, `IncludeSize`, `IncludeFileCount` (alias: `IncludePsCount`), `FoldersOnly`, `IncludeFilePatterns`, `IncludeExtensions`, `ExcludeExtensions`, `ExcludeFolders`, `ExcludeFiles`, `IncludeFolders`, `ExcludePathPatterns`, `NoDefaultExcludes`, `OutputFile`, `MarkdownFile`, `EmitSummary`, `UseRunspaces`, `MaxThreads`
- Outputs: String array of tree lines (pipeline). Optional file output via -OutputFile / -MarkdownFile.
- Summary: `EmitSummary` auto-enables when the output is Markdown (-AsMarkdown, -MarkdownFile, or an -OutputFile ending .md) unless the caller explicitly passes -EmitSummary (including :$false, which always wins). Reports the scan parameters (MaxDepth, whether default excludes were bypassed, FoldersOnly), folder/file/skip/symlink counts, and, when -IncludeSize is active, total size plus a top-10 largest-folders table drawn from the same folder-size cache the tree walk already builds (no extra filesystem traversal). In Markdown mode the summary is placed before the tree, under a `#### Summary` heading.
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

- Purpose: Layered corruption + hygiene detection for source trees. Dispatches by file category to the strongest available validator (7z t for archives with ZipFile/expand.exe/MSI-magic fallbacks; PE structural walk for EXE/DLL/SYS; read-accessibility probe for generic files), then runs an always-on hygiene scan for SCCM-distribution killers: hidden/system attributes, Zone.Identifier ADS (Mark-of-the-Web), other alternate data streams, and residue names (Thumbs.db, desktop.ini, .DS*Store, .*_, ~$_, _.tmp, _.bak, _.orig, _.swp, _.lock, _.partial, _.crdownload, _.part). Optional SHA256 hashing and baseline-CSV drift detection.
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

### Start-DowserTransfer

- Purpose: Copies one or more files or directories to a destination with a pre-flight free-space and headroom check, then verifies every copied file by hash before reporting it migrated. Only copies and verifies; never deletes source files.
- Inputs: `Source` (required, pipeline, FullName alias, `string[]` -- file or directory paths; directory sources copy recursively, preserving structure under a folder named after the source directory), `Destination` (required directory, created on demand), `HeadroomPercent` (default 10 -- required free space as a percentage of total bytes to copy, on top of the total itself), `ManifestPath` (optional; defaults to a timestamped JSON file under -Destination; not written on a -WhatIf dry run), `ThreadCount` (default: the lower of 8 or the processor count). Supports -WhatIf/-Confirm (ConfirmImpact Medium).
- Outputs: PSCustomObject with Success, DryRun, FileCount, TotalBytes, BytesCopied, FailureCount, ManifestPath, Destination. Under `-WhatIf`, reports the real file count and byte total it would move and copies nothing.
- Note: Safety order per file, run in parallel across a dedicated runspace pool (Private/Invoke-DowserTransferPool.ps1, Private/Invoke-DowserTransferWorker.ps1): hash the source once (SHA256) -> copy -> hash the destination -> compare -> mark verified only on a match. A hash mismatch is a hard per-file failure; that file is never reported as migrated. A real run writes a JSON verification manifest (Items array with per-file SourcePath/DestinationPath/Success/SourceHash/DestHash), the required input to Remove-DowserTransferSource for a later, separate deletion pass -- the write is wrapped in its own try/catch, so ManifestPath comes back $null if the write itself fails (disk full, permissions).
- Related: `Remove-DowserTransferSource` (manifest-gated deletion of verified source files)
- Source: `Start-DowserTransfer.ps1`

### Remove-DowserTransferSource

- Purpose: Deletes source files recorded as hash-verified in a Start-DowserTransfer manifest. Never runs as a side effect of Start-DowserTransfer.
- Inputs: `ManifestPath` (required -- no implicit "last run" lookup). Supports -WhatIf/-Confirm (ConfirmImpact High).
- Outputs: PSCustomObject with Success, ManifestPath, TotalEntries, DeletedCount, SkippedCount, ReVerifyFailedCount, DeleteFailedCount.
- Note: Manifest entries not marked Success are skipped outright. For every remaining entry, re-hashes the destination file (SHA256) and compares it against the DestHash recorded in the manifest before deleting -- a defense against a stale or tampered manifest. Any entry whose destination hash no longer matches is logged and skipped, never deleted.
- Related: `Start-DowserTransfer` (produces the manifest this function consumes)
- Source: `Remove-DowserTransferSource.ps1`
