# Dowser Index

Single source of truth for what exists in the module. **Read this before adding anything.** If a similar capability already exists, extend it — do not add a parallel implementation.

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
These functions work identically on all supported platforms:
- `Find-DowserDuplicate`, `Find-DowserFile`, `Find-DowserOrphan`, `Find-DowserDependency`
- `Invoke-DowserFastSearch`, `Measure-DowserDirectory`
- `Get-DowserMap`, `Get-DowserTopology`, `Get-DowserInfo`
- `ConvertTo-DowserBase64`

### Degraded on Non-Windows
These functions return partial results (basic metadata without COM-sourced properties):
- `Get-DowserProperty` - Shell.Application extended properties unavailable
- `Get-DowserOwnership` - Shell.Application metadata unavailable
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
- Source: `ConvertTo-Base64.ps1`

### ConvertTo-DowserExe
- Purpose: Generates a C# executable wrapper for a PowerShell script.
- Source: `ConvertTo-Exe.ps1`

### ConvertTo-DowserIco
- Purpose: Creates `.ico` files from images using multi-size PNG-compressed layouts.
- Source: `ConvertTo-ICO.ps1`

### New-DowserHiddenFolder
- Purpose: Modifies directory attributes to Hidden and System.
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

### Get-DowserOwnership
- Purpose: Gets file ownership and extended Shell.Application metadata for files in a directory (extension-filtered).
- Inputs: `Directory` (required), `Extension` (wildcard, default `*`)
- Outputs: PSCustomObject per file with Shell metadata, hashes, signature, version info.
- Related: `Get-DowserProperty` (deeper single-file analysis)
- Source: `Get-FileOwnership.ps1`

### Get-DowserProperty
- Purpose: Comprehensive file inspector — VersionInfo, Shell COM extended props (0-500), hashes, Authenticode, .NET assembly, PE header.
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
- Purpose: Diffs two Get-DowserReport snapshots — shows NEW, CHANGED, REMOVED, UNCHANGED files with size/line/word/char deltas.
- Inputs: `Before` (PSCustomObject[]), `After` (PSCustomObject[]), `ShowUnchanged`
- Outputs: PSCustomObject per file with Status and delta fields.
- Related: `Get-DowserReport`
- Source: `Get-FileReport.ps1` (bundled in `Get-DowserReport.ps1`)

### Invoke-DowserFastSearch
- Purpose: Parallel single-pattern text search across files using a RunspacePool. Returns per-file match objects with line numbers.
- Inputs: `Path` (pipeline), `SearchString` (alias: `Pattern`), `Threads` (default 10), `Include`, `Exclude`, `CaseSensitive`
- Outputs: PSCustomObject per matching file — FileName, FileType, LineNumbers, FullPath.
- Related: `Find-DowserString` (multi-pattern, Aho-Corasick, multiple output modes)
- Source: `Invoke-FastTextSearch.ps1`
- Aliases: `dfast`

### Invoke-DowserNumericSort
- Purpose: Natural numeric sort for strings or objects with embedded numbers (Item-2 before Item-10).
- Inputs: `InputObject` (pipeline), `Property`, `Descending`, `CaseSensitive`, `Unique`, `Top`
- Outputs: Sorted objects (same type as input).
- Related: `Find-DowserFile`, `Find-DowserDuplicate`
- Source: `Invoke-NumericalSorting.ps1` (Sort-Numerical function; Get-SortKey → Private\Get-DowserSortKey)
- Aliases: `dsort`, `dnsort`

### Test-DowserExtractable
- Purpose: Tests whether an EXE can be simply extracted (SFX/installer) or requires decompilation (ps2exe, .NET, native).
- Inputs: `Path` (pipeline, FullName alias), `Recurse`, `Filter`, `SevenZipPath`, `SkipSevenZip`
- Outputs: PSCustomObject per EXE - Path, Extractable (bool), Classification, InstallerType, ArchiveType, Confidence, FileCount, Details.
- Related: `Expand-DowserExe` (extracts files from extractable EXEs), `Get-DowserProperty` (deep file inspection)
- Aliases: `dtest`, `dtestexe`

### Test-DowserIntegrity
- Purpose: Layered corruption + hygiene detection for source trees. Dispatches by file category to the strongest available validator (7z t for archives with ZipFile/expand.exe/MSI-magic fallbacks; PE structural walk for EXE/DLL/SYS; read-accessibility probe for generic files), then runs an always-on hygiene scan for SCCM-distribution killers: hidden/system attributes, Zone.Identifier ADS (Mark-of-the-Web), other alternate data streams, and residue names (Thumbs.db, desktop.ini, .DS_Store, ._*, ~$*, *.tmp, *.bak, *.orig, *.swp, *.lock, *.partial, *.crdownload, *.part). Optional SHA256 hashing and baseline-CSV drift detection.
- Inputs: `Path` (pipeline, FullName alias), `Recurse`, `Filter`, `SevenZipPath`, `SkipSevenZip`, `ComputeHash`, `BaselineCsv`, `Detailed`, `IncludeClean`
- Outputs: Default emits one summary object with TotalFiles, per-Status counts (OK, Corrupt, Error, Warning, Suspicious, Residue, Unverified), ProblemCount, TopProblems[10], DetailsGlobal pointer. Full per-file array always stashed in `$global:DowserIntegrityDetails`. Use `-Detailed` to stream per-file objects (Path, RelativePath, Name, Extension, SizeBytes, Size, Category, Status, Method, Confidence, SHA256, BaselineMatch, Details, Issues[]) instead of the summary. Per-file stream defaults to problems only (Corrupt/Error/Warning/Suspicious/Residue); `-IncludeClean` adds OK and Unverified.
- Related: `Test-DowserExtractable` (EXE classification, not corruption), `Get-DowserReport` (metrics, not validation), `Expand-DowserExe` (extract once integrity confirmed)
- Aliases: `dintegrity`, `dinteg`

### Expand-DowserExe
- Purpose: Extracts files from extractable EXE archives using 7-Zip. Runs Test-DowserExtractable first, then 7z x.
- Inputs: `Path` (pipeline, FullName alias), `Destination`, `SevenZipPath`, `Force`, `PassThru`
- Outputs: PSCustomObject per EXE - Path, Destinat