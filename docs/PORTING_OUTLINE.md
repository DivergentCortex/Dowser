# Dowser Porting Outline

**Generated:** 2026-04-11  
**Scope:** 22 source scripts from `D:\_REPOS\General_Scripts\`  
**Target:** `D:\_REPOS\ToolProjects\Dowser\` module  
**Convention:** `Verb-DowserNoun` — approved PS verbs only, singular nouns

---

## Source File Verification

All 22 target scripts confirmed present in `D:\_REPOS\General_Scripts\`:

| # | Source File | Status |
|---|-------------|--------|
| 1 | ConvertTo-Base64.ps1 | ✓ Found |
| 2 | ConvertTo-Exe.ps1 | ✓ Found |
| 3 | ConvertTo-ICO.ps1 | ✓ Found |
| 4 | Find-FileDuplicates.ps1 | ✓ Found |
| 5 | Find-Files.ps1 | ✓ Found |
| 6 | Find-FilesModifiedOn.ps1 | ✓ Found |
| 7 | Find-MostRecentLog.ps1 | ✓ Found |
| 8 | Find-OrphanFiles.ps1 | ✓ Found |
| 9 | Find-ScriptDependencies.ps1 | ✓ Found |
| 10 | Find-Scripts.ps1 | ✓ Found |
| 11 | Find-StringInFiles.ps1 | ✓ Found |
| 12 | Get-DirectoryMap.ps1 | ✓ Found |
| 13 | Get-DirectorySizeCounts.ps1 | ✓ Found |
| 14 | Get-DirectoryTreeOutputAndFileCount.ps1 | ✓ Found |
| 15 | Get-FileOwnership.ps1 | ✓ Found |
| 16 | Get-FilePropertyDetails.ps1 | ✓ Found |
| 17 | Get-FileReport.ps1 | ✓ Found |
| 18 | Get-FolderTemplate.ps1 | ✓ Found |
| 19 | Get-FolderTree.ps1 | ✓ Found |
| 20 | Get-TreeTopology.ps1 | ✓ Found |
| 21 | Invoke-FastTextSearch.ps1 | ✓ Found |
| 22 | Invoke-NumericalSorting.ps1 | ✓ Found |

**Missing source files:** None. All 22 present.

---

## Merge / Consolidation Decisions

Before per-script entries, the merge picture:

### Get-DowserTree — 2-into-1 merge (from 3 source scripts)

The outline called `Get-FolderTree` a merge candidate. Reading both scripts confirms it:

- **Get-DirectoryTreeOutputAndFileCount.ps1** — bare function, hardcoded E:\ root, counts .ps1 files per subdirectory, prints to console. 33 lines. Zero reusable as-is.
- **Get-FolderTree.ps1** — bare function, hardcoded E:\ root and C:\Temp HTML template paths, calculates per-folder size in GB/MB/KB, emits PSObjects and was wired to build an HTML report. 118 lines. No parameters except FolderPath.

Both are: walk a tree, collect per-folder stats, emit results. Neither is ready to port standalone.

**Decision:** Both merge into `Get-DowserTree`. The target cmdlet takes `-Path`, `-Recurse`, optional `-IncludePsCount` and `-Html` switches. Absorbs the size-reporting behavior of Get-FolderTree and the file-count behavior of Get-DirectoryTreeOutputAndFileCount. Get-DirectoryMap (which does the visual tree *display*) stays separate as `Get-DowserMap`.

### Find-DowserDuplicate absorbs Find-Files duplicate mode

**Find-Files.ps1** has two parameter sets: `Search` (file hunting) and `Duplicates` (hash/name/size dedup). The duplicate mode overlaps directly with **Find-FileDuplicates.ps1**. Find-FileDuplicates is the richer implementation (5 detection modes vs 4, chunk-level hashing, AutoRemove, ReviewBeforeDelete, CSV export).

**Decision:** Find-Files ports as `Find-DowserFile` (search/filter mode only — Pattern, size, date filters, -StopOnFirstMatch). The duplicate parameter set is dropped from Find-DowserFile; `Find-DowserDuplicate` covers that ground. Document this in the index for Find-DowserFile so nobody re-adds it.

---

## Verb Buckets — All 21 Target Cmdlets

22 source scripts → 21 cmdlets (1 merge). Summary by bucket:

| Bucket | Count |
|--------|-------|
| ConvertTo-Dowser* | 3 |
| Find-Dowser* | 8 |
| Get-Dowser* | 7 |
| Measure-Dowser* | 1 |
| Invoke-Dowser* | 2 |
| **Total** | **21** |

---

## Per-Script Porting Entries

---

### ConvertTo-DowserBase64

| Field | Value |
|-------|-------|
| **Source** | `ConvertTo-Base64.ps1` |
| **Visibility** | Public |
| **Alias** | `db64` |
| **Source type** | Bare script (no function wrapper) — needs function wrapping |

**Purpose:** Encode any file (image or binary) to Base64 string, or decode a Base64 string/file back to binary. Clipboard support; optional Data URI header (`data:image/png;base64,...`); pure .NET, no external deps.

**Parameters to preserve:**
- `-Path` (was `-ImagePath`) — mandatory, input file or raw Base64 string when decoding
- `-OutputFile` — optional output path
- `-Decode` switch — flip to decode mode
- `-IncludeHeader` switch — prepend Data URI header on encode
- `-CopyToClipboard` switch — copy result to clipboard after encode

**Pipeline:** `-Path` accepts pipeline input (`ValueFromPipeline`)

**Outputs:** `[string]` (Base64 or file path)

**Porting notes:**
- Wrap entire script body in `[CmdletBinding()]` function
- Replace `Write-Host`/`Write-Error` with `Write-Verbose`/`Write-Warning`
- Rename `-ImagePath` to `-Path` (more general — works on any file, not just images)
- MIME type switch block is fine; keep it

**Related:** none in module

---

### ConvertTo-DowserExe

| Field | Value |
|-------|-------|
| **Source** | `ConvertTo-Exe.ps1` |
| **Visibility** | Public |
| **Alias** | `dexe` |
| **Source type** | Two functions: `ConvertTo-Exe` and `ConvertTo-ExeConfuserEx` |

**Purpose:** Compile a PowerShell script into a standalone `.exe` by wrapping it in a C# console application and invoking `Add-Type -OutputType ConsoleApplication`. A second variant runs ConfuserEx obfuscation on the resulting binary.

**Parameters to preserve:**
- `-ScriptPath` — mandatory, path to .ps1 file
- `-ConfuserExPath` — optional, path to ConfuserEx install dir (enables obfuscation variant)

**Pipeline:** `-ScriptPath` accepts pipeline (`ValueFromPipelineByPropertyName`, alias `FullName`)

**Outputs:** `[string]` output exe path on success; `[bool]` or terminating error on failure

**Porting notes:**
- Merge both source functions into one cmdlet with an `-Obfuscate` switch that enables the ConfuserEx path; `-ConfuserExPath` implies `-Obfuscate`
- Second source function has a typo: `COnvertTo-ExeConfuserEx` (capital O) — do not carry the typo
- C# string-literal quoting logic for `$($scriptContent -replace '"', '""')` is correct; leave it
- Add `-OutputPath` param to control where the exe lands (currently always current dir)
- Add error handling around `Add-Type` — it throws on compile errors

**Related:** none in module

---

### ConvertTo-DowserIco

| Field | Value |
|-------|-------|
| **Source** | `ConvertTo-ICO.ps1` |
| **Visibility** | Public |
| **Alias** | `dico` |
| **Source type** | Function `ConvertTo-Ico` |

**Purpose:** Convert any image file (PNG, JPG, BMP, etc.) to a Windows `.ico` file. Supports multi-size ICO (16, 32, 48, 64, 128, 256, 512px), UNC paths (auto-copies to temp), PNG-compression for large sizes, proper ICO binary format via BinaryWriter.

**Parameters to preserve:**
- `-InputFilePath` — mandatory, source image
- `-OutputFile` — optional, defaults to same dir as source with .ico extension
- `-IcoSizes` (alias: `-IconSize`, `-Size`, `-Sizes`) — int array, valid: 16/32/48/64/128/256/512; default 256
- `-MaxSize` — int, >256 produces a separate PNG alongside ICO; default 0 (disabled)

**Pipeline:** `-InputFilePath` accepts pipeline (`ValueFromPipeline`, alias `FullName`)

**Outputs:** `[bool]` — `$true` on success, `$false` on failure. Also `Write-Output` the output path.

**Porting notes:**
- Source uses `Add-Type` for both `System.Drawing` and a P/Invoke `DestroyIcon` wrapper. Both are fine.
- `Add-Type` at module scope is preferred over inside the function — move assembly loads to module init or use `#Requires -Assembly` comment
- UNC temp-copy logic is solid; preserve it
- Replace `Write-Host`/`Write-Error` with `Write-Verbose`/`Write-Warning`/`Write-Error -ErrorRecord`
- Source has a usage comment at the bottom (`# Usage: ConvertTo-Ico ...`) — remove from module file, move to `.EXAMPLE` in comment-based help

**Related:** ConvertTo-DowserBase64 (both are format converters; potential future submodule)

---

### Find-DowserDuplicate

| Field | Value |
|-------|-------|
| **Source** | `Find-FileDuplicates.ps1` |
| **Visibility** | Public |
| **Alias** | `ddupe` |
| **Source type** | Function `Find-FileDuplicates` — well-structured, mostly ready |

**Purpose:** Scan a directory for duplicate files using one or more detection strategies: exact Name, PartialName (normalized stem), NameSize (name+size combo), Content (full file hash), Chunk (block-level hash). Returns grouped duplicate sets. Optionally deletes duplicates interactively or automatically. Exports CSV report.

**Parameters to preserve:**
- `-Path` — mandatory, root to scan
- `-Exclude` — wildcard exclusion patterns
- `-MinSize` — minimum file size in bytes
- `-Mode` — ValidateSet: Name, PartialName, NameSize, Content, Chunk, All (default All)
- `-HashAlgorithm` — SHA256/SHA1/MD5 (default SHA256)
- `-ChunkSize` — block size for Chunk mode (default 1MB)
- `-ChunkOverlap` — overlap bytes between chunks (default 0)
- `-ReportPath` — CSV export path
- `-AutoRemove` — delete duplicates automatically (keep first)
- `-ReviewBeforeDelete` — interactive per-file prompt
- `-ChunkSequenceLength` — sequential chunk match count (default 3, range 1-32)

**Pipeline:** `-Path` accepts pipeline input

**Outputs:** `[PSCustomObject]` grouped duplicate sets to pipeline; full set stored in `$global:dupObjects` (this needs redesign — see Porting notes)

**Porting notes:**
- `$global:dupObjects` is a smell. Replace with `-PassThru` switch that returns the full object graph, or just always return to pipeline and let caller capture. Don't pollute global scope in a module.
- Internal helpers `Get-NormalizedStem` and `Get-ChunkHashes` should move to Private\ as shared helpers if other cmdlets need them, otherwise keep inline as nested functions
- `Write-Host` calls used for progress/status — replace with `Write-Progress` + `Write-Verbose`
- `AutoRemove`/`ReviewBeforeDelete` are destructive — add `SupportsShouldProcess` and `[CmdletBinding(SupportsShouldProcess)]`
- Absorbs the duplicate detection capability from Find-Files.ps1's `-FindDuplicates` parameter set

**Related:** Find-DowserOrphan (opposite question — orphans vs duplicates)

---

### Find-DowserFile

| Field | Value |
|-------|-------|
| **Source** | `Find-Files.ps1` (search parameter set only) |
| **Visibility** | Public |
| **Alias** | `dfile`, `dfind` |
| **Source type** | Function `Find-Files` — multi-threaded with RunspacePool |

**Purpose:** High-performance recursive file search by name pattern, size range, and date range. Uses RunspacePool for parallel directory scanning. Supports pipeline input for multiple root paths, early-exit on first match.

**Parameters to preserve (search set only):**
- `-Path` — mandatory, one or more root directories; pipeline input
- `-Pattern` — wildcard filename filter (default `*`)
- `-Recurse` — switch, default true
- `-MinSize` / `-MaxSize` — size filters (e.g., `1MB`, `500KB`)
- `-ModifiedAfter` / `-ModifiedBefore` — date range filters
- `-StopOnFirstMatch` — return first match only
- `-UseRunspaces` — toggle parallel processing (default true)
- `-ThreadCount` — runspace count (default: processor count)

**Parameters to DROP (handled by Find-DowserDuplicate):**
- `-FindDuplicates`, `-DuplicateBy`, `-DeleteDuplicates`, `-KeepStrategy`, `-HashAlgorithm`, `-DuplicatesOnly`, `-ExcludePathPattern`, `-SimpleOutput`

**Pipeline:** `-Path` accepts pipeline (`ValueFromPipeline`)

**Outputs:** `[PSCustomObject]` with FullName, Name, Directory, Size, LastWriteTime, CreationTime

**Porting notes:**
- Runspace pattern is solid; leave threading as-is
- `ExcludePathPattern` (regex exclude) is useful enough to keep even without the duplicate set — add it back as a general `-ExcludePath` regex filter
- Replace `Write-Host` with `Write-Verbose`; keep `Write-Progress`
- `ConvertTo-Bytes` nested helper: move to Private\ as `ConvertTo-DowserBytes` if other cmdlets need size parsing, otherwise keep inline

**Related:** Find-DowserDuplicate, Find-DowserString, Find-DowserScript

---

### Find-DowserModified

| Field | Value |
|-------|-------|
| **Source** | `Find-FilesModifiedOn.ps1` |
| **Visibility** | Public |
| **Alias** | `dmod` |
| **Source type** | Function `Find-FilesModifiedOn` — minimal, hardcoded path |

**Purpose:** Find files modified on a specific calendar date. Currently hardcoded to D:\ — needs generalization.

**Parameters to preserve/add:**
- `-Path` — root to search (was hardcoded `D:\` in source; make mandatory)
- `-Date` — DateTime, the target date; default was `2025-01-14` (remove default, make mandatory or default to today)
- `-Recurse` — switch (implicit in source via `-Recurse`; make explicit)

**Pipeline:** `-Path` accepts pipeline

**Outputs:** `[PSCustomObject]` with FullName, LastWriteTime, Size

**Porting notes:**
- Source has no function structure at all — just `function Find-FilesModifiedOn { param([DateTime]$Date = "2025-01-14") ... }` with a hardcoded D:\ in the body. Entire path logic must be rewritten.
- Remove the hardcoded `D:\` — replace with `-Path` parameter
- Remove the default date (`2025-01-14`) — either make mandatory or default to `(Get-Date).Date`
- Replace `Write-Host`/`Write-Error` with `Write-Verbose`/`Write-Warning`
- Output objects to pipeline instead of Write-Host foreach loop

**Related:** Find-DowserFile (date filter is a subset of Find-DowserFile's `-ModifiedAfter`/`-ModifiedBefore` — consider whether this cmdlet adds enough standalone value; keep for discoverability)

---

### Find-DowserRecentLog

| Field | Value |
|-------|-------|
| **Source** | `Find-MostRecentLog.ps1` |
| **Visibility** | Public |
| **Alias** | `dlog` |
| **Source type** | Bare script — NOT a function. Hardcoded to hunt for `Write-Log_Ps20.ps1` |

**Purpose (as-written):** Find all copies of `Write-Log_Ps20.ps1` on D:\, return the most recently modified one. Very internal.

**Purpose (ported):** Find the most recently modified copy of any named file across one or more search paths. Returns the newest match and optionally all matches ranked by modification date.

**Parameters (new — source has none):**
- `-FileName` — mandatory, file name to search for (e.g., `Write-Log.ps1`, `*.config`)
- `-Path` — root path(s) to search; default `D:\`
- `-All` switch — emit all found copies (ranked by LastWriteTime desc), not just the newest
- `-Recurse` — default true

**Pipeline:** `-Path` accepts pipeline

**Outputs:** `[PSCustomObject]` with FullName, LastWriteTime, Length; sorted newest-first

**Porting notes:**
- Source is 27 lines of bare script with no function wrapper — essentially a one-liner that needs to become a general-purpose cmdlet
- Generalize from `Write-Log_Ps20.ps1` to `-FileName` parameter
- Generalize from D:\ to `-Path` parameter
- `-All` switch controls whether you get one result or all matches
- Useful in practice for finding the canonical copy of a shared helper

**Related:** Find-DowserFile, Find-DowserScript

---

### Find-DowserOrphan

| Field | Value |
|-------|-------|
| **Source** | `Find-OrphanFiles.ps1` |
| **Visibility** | Public |
| **Alias** | `dorphan` |
| **Source type** | Function `Find-OrphanFiles` — solid structure |

**Purpose:** Identify files in a directory that are not referenced by any text-based source file in the same tree. Tokenizes all "scanner" files (ps1, xml, json, sql, md, etc.) and cross-checks filenames against those token sets. Files with zero external references are reported as orphan candidates.

**Parameters to preserve:**
- `-SearchPath` → rename to `-Path` (convention)
- `-ExcludePaths` — folder name/path exclusions; default includes .git, .vscode, bin, obj, node_modules
- `-TextExtensions` — extensions to treat as scanner files (files whose content is read); broad default list

**Pipeline:** `-Path` accepts pipeline

**Outputs:** `[PSCustomObject]` with orphan file info (FullName, references found)

**Porting notes:**
- Rename `-SearchPath` to `-Path` (module convention)
- Replace `Write-Host` with `Write-Verbose`/`Write-Progress`
- Good candidate for `-ExcludeExtensions` param to filter out binary files from the orphan list
- The tokenization approach is heuristic — add `-Verbose` output explaining methodology

**Related:** Find-DowserDuplicate (opposite angle — orphan vs redundant)

---

### Find-DowserDependency

| Field | Value |
|-------|-------|
| **Source** | `Find-ScriptDependencies.ps1` |
| **Visibility** | Public |
| **Alias** | `ddep` |
| **Source type** | Function `Find-ScriptDependencies` |

**Purpose:** Scan PowerShell scripts for dependency patterns: dot-sourcing (`'. "..."'`), `Import-Module` calls, function definitions, and references to specific named functions. Reports where each dependency appears and optionally includes matched content.

**Parameters to preserve:**
- `-Path` (was `-SearchPath`) — root directory to scan; default `D:\`
- `-AdditionalPaths` — extra paths to include in scan
- `-FunctionNames` — optional list of specific function names to hunt for; if omitted, scans for all dot-sourcing and Import-Module patterns
- `-ExcludePaths` — path fragments to skip (default: Recycle.Bin, Windows, Program Files, Users)
- `-IncludeContent` switch — include matched line content in output
- `-ExportResults` switch — export to CSV

**Pipeline:** `-Path` accepts pipeline

**Outputs:** `[PSCustomObject]` with file path, matched pattern, line number, optionally content

**Porting notes:**
- Rename `-SearchPath` to `-Path`
- Source default of `"D:\"` for `-Path` is too broad — change default to `$PWD`
- ExcludePaths defaults include `\Users\` which may be too aggressive depending on context — document this
- Replace `Write-Host` with `Write-Verbose`
- Add `-Extension` param to restrict which file types are scanned (default `.ps1`, `.psm1`, `.psd1`)

**Related:** Find-DowserOrphan, Find-DowserScript

---

### Find-DowserScript

| Field | Value |
|-------|-------|
| **Source** | `Find-Scripts.ps1` |
| **Visibility** | Public |
| **Alias** | `dscript` |
| **Source type** | Function `Find-SecureCrtScripts` — name mismatch, hardcoded behavior |

**Purpose (as-written):** Find script files (.vbs, .py, .ps1, .sh) modified within the last 6 months, hardcoded for a specific network path.

**Purpose (ported):** General script-file finder by extension set and optional recency window. Path-agnostic.

**Parameters (generalized):**
- `-Path` — mandatory, root path(s) to search (was hardcoded network path)
- `-Extensions` — script extension filter; default `@('.vbs', '.py', '.ps1', '.psm1', '.sh', '.bat', '.cmd')`
- `-ModifiedWithin` — [TimeSpan] or [int] days; optional recency filter (was hardcoded 6 months)
- `-Recurse` — default true

**Pipeline:** `-Path` accepts pipeline

**Outputs:** `[string]` FullName (source outputs bare FullName — consider emitting PSCustomObject with Name, FullName, Extension, LastWriteTime)

**Porting notes:**
- Source internal function name is `Find-SecureCrtScripts` — do NOT carry that name. New public function name is `Find-DowserScript`.
- Source is specific to SecureCRT terminal scripts on a network share — generalize entirely
- Remove 6-month hardcoded filter; make `-ModifiedWithin` optional (no filter by default)
- Write-Progress is already present; keep it
- Replace `Write-Error` with `Write-Warning` for non-fatal path errors

**Related:** Find-DowserFile, Find-DowserDependency, Find-DowserRecentLog

---

### Find-DowserString

| Field | Value |
|-------|-------|
| **Source** | `Find-StringInFiles.ps1` |
| **Visibility** | Public |
| **Alias** | `dstr`, `dgrep` |
| **Source type** | Function `Find-StringInFiles` — large, well-structured, runspace-based |

**Purpose:** Multi-threaded pattern search across files in a directory. Supports multiple simultaneous search patterns, optional Aho-Corasick multi-pattern matching, regex or literal search, case sensitivity control, file extension filter, and multiple output modes (matches, counts, files-only).

**Parameters to preserve:**
- `-Path` — root directory (default `$PWD`)
- `-Patterns` — array of search strings/patterns
- `-Extensions` — file glob filter (e.g., `'*.ps1'`, `'*.cs'`)
- `-MaxThreads` — runspace count (default: CPU cores - 1)
- `-MaxFileSizeMB` — skip large files (default 10MB)
- `-UseRegex` — treat Patterns as regex (default false = literal)
- `-CaseSensitive` — default false
- `-Recurse` — default true
- `-ExcludeFolders` — folder names to skip
- `-SearchMode` — auto/aho/select/manual
- `-UseRunspaces` — toggle threading

**Pipeline:** `-Path` accepts pipeline

**Outputs:** `[PSCustomObject]` with file path, line number, matched pattern, matched text

**Porting notes:**
- This is the most sophisticated Find-Dowser* script — minimal rewrite needed
- Replace `Write-Host` with `Write-Verbose`
- The `-OutputMode` / `-FilesOnly` / `-CountsOnly` flags from the source should be preserved; confirm their param names against the full source before finalizing
- Aho-Corasick mode is a private implementation inside the script; keep inline initially, move to Private\ if it grows or is reused

**Related:** Invoke-DowserFastSearch (faster but simpler — single pattern, no multi-mode)

---

### Get-DowserMap

| Field | Value |
|-------|-------|
| **Source** | `Get-DirectoryMap.ps1` |
| **Visibility** | Public |
| **Alias** | `dmap` |
| **Source type** | Function `Get-DirectoryMap` — very large (823 lines), recursive self-call |

**Purpose:** Visual tree renderer for directory structures. Box-drawing Unicode characters or ASCII fallback. Supports HTML and Markdown output, full-path trunk display, filtering by extension/pattern/folder, parallel pre-scan for large trees, WSL/Linux path display mode.

**Parameters to preserve:**
- `-Path` — mandatory, root to render
- `-MaxDepth` (alias `-Max`) — default 3
- `-IncludeFilePatterns` — wildcard filename filters
- `-IncludeExtensions` / `-ExcludeExtensions` — extension lists
- `-ExcludeFolders` / `-IncludeFolders` / `-ExcludeFiles` — folder/file filters
- `-ExcludePathPatterns` — full path exclusions
- `-NoDefaultExcludes` — disable auto-exclusion of node_modules, .git, etc.
- `-FoldersOnly` — omit files
- `-ShowFullPathTree` (alias `-S`) — trunk display; default true
- `-LinuxPaths` (alias `-L`) — WSL path rendering
- `-Ascii` — use ASCII box chars instead of Unicode
- `-AsHtml` / `-AsMarkdown` — output format switches
- `-IncludeHidden` — include hidden items
- `-FollowReparse` — follow symlinks/junctions
- `-OutputFile` / `-MarkdownFile` — file output
- `-EmitSummary` — append folder/file counts
- `-UseRunspaces` — parallel pre-scan (default true)
- `-MaxThreads` — pre-scan thread count

**Pipeline:** `-Path` accepts pipeline (add)

**Outputs:** `[string[]]` tree lines to pipeline; optionally writes file

**Porting notes:**
- This is the most complex script in the set. It is self-recursive — the function calls itself. This works fine in a module; just ensure it is not accidentally shadowed by the module's dot-source order.
- Internal parameters (`-Indent`, `-CurrentDepth`, `-MatchCache`, `-IncludeFolderCache`, `-TraversalState`) are needed for recursion; mark with `[Parameter(DontShow = $true)]` — already done in source.
- `Add-Type` for `Win32.NativeMethods` is in the ICO script, not here; this script has no Add-Type.
- Auto-enables HTML when OutputFile ends in `.html` — keep that smart default.
- Default exclusion lists for folders/extensions are extensive and opinionated; keep them, document them, expose `-NoDefaultExcludes`.
- Replace `Write-Host` with `Write-Verbose`; keep `Write-Progress` equivalent logic.

**Related:** Get-DowserTree, Get-DowserTopology (all three render tree structure; this one is the richest)

---

### Get-DowserTree

| Field | Value |
|-------|-------|
| **Source (merged)** | `Get-DirectoryTreeOutputAndFileCount.ps1` + `Get-FolderTree.ps1` |
| **Visibility** | Public |
| **Alias** | `dtree` |
| **Source type** | MERGE — both sources are bare functions with hardcoded paths |

**Purpose (synthesized):** Walk a directory tree and return per-folder statistics: total size, file count, optionally broken down by extension or type. Optionally count specific file types (e.g., `.ps1` files per folder). Replaces both source scripts with a clean, parameterized implementation.

**Parameters (synthesized from both sources):**
- `-Path` — mandatory, root directory (replaces hardcoded `E:\` in both)
- `-Depth` — max recursion depth (default: unlimited)
- `-IncludePsCount` switch — add .ps1 file count per folder (from Get-DirectoryTreeOutputAndFileCount)
- `-ExtensionCount` — string[], count files of these extensions per folder
- `-ExcludePaths` — string array, exact paths to skip (replaces hardcoded `$excludedDirs`)
- `-Html` switch — emit HTML report (replaces Get-FolderTree's HTML template logic)
- `-HtmlTemplate` — path to HTML template file (from Get-FolderTree)

**Pipeline:** `-Path` accepts pipeline

**Outputs:** `[PSCustomObject]` with FolderPath, FolderSizeRaw, FolderSizeFormatted, FileCount, ExtensionCounts (hashtable)

**Porting notes:**
- **Get-DirectoryTreeOutputAndFileCount.ps1:** 33-line script, hardcoded `E:\` and `$excludedDirs`, prints to console with Write-Host. All behavior must be rewritten. Save only the `.ps1 file count per folder` concept.
- **Get-FolderTree.ps1:** 118-line script, hardcoded `E:\`, `C:\Temp\finalTemplate.html`, and `C:\Temp\final.html`. The size calculation logic (GB/MB/KB formatting) is the keeper. The HTML template mechanism requires a template file that doesn't travel with the module — simplify to self-contained HTML generation or drop it.
- Neither source has `[CmdletBinding()]` or proper params — full rewrite of the skeleton
- The `$IgnoreList` variable in Get-FolderTree is a module-level var leak; fix with proper param
- `ConvertFrom-Bytes` nested function in Get-DirectorySizeCounts is the same concept as size formatting in Get-FolderTree — unify into one Private\ helper `Format-DowserSize`

**Merge rationale:** Both scripts answer "how big is each folder?" and "what's in each folder?" They have no meaningful standalone value in their current form and fully overlap in purpose.

---

### Get-DowserOwnership

| Field | Value |
|-------|-------|
| **Source** | `Get-FileOwnership.ps1` |
| **Visibility** | Public |
| **Alias** | `down` |
| **Source type** | Function `Get-FileOwnership` with three embedded helpers |

**Purpose:** Return ACL owner and extended Shell.Application metadata for files. Includes file size (human-readable), read-only status, LastWriteTime, and all Windows Explorer extended properties (author, dimensions, bit rate, camera model, etc.) via COM `Shell.Application.Namespace`.

**Parameters to preserve:**
- `-Directory` (rename to `-Path`) — root directory to scan
- `-Extension` — file extension filter; default `*`

**Pipeline:** `-Path` accepts pipeline

**Outputs:** `[PSCustomObject]` with Name, FullName, Size, IsReadOnly, LastWriteTime, Owner, plus all Shell.Application extended properties

**Porting notes:**
- Three embedded helpers (`Get-FileInformation`, `Get-FileSize`, `Get-FileMetaData`) should be evaluated: `Get-FileSize` is a byte-formatter — same concept as in Get-DirectorySizeCounts; move to Private\ as `Format-DowserSize`. `Get-FileMetaData` is the Shell.Application COM query; move to Private\ if reused elsewhere. `Get-FileInformation` is a thin wrapper — can stay inline.
- Shell.Application COM is Windows-only; add `#Requires -OS Windows` note in help
- Replace `Write-Warning` with module-standard logging
- Rename `-Directory` to `-Path` for module convention consistency

**Related:** Get-DowserProperty (Get-DowserProperty goes deeper into version/PE info; Get-DowserOwnership focuses on ACL + Shell metadata)

---

### Get-DowserProperty

| Field | Value |
|-------|-------|
| **Source** | `Get-FilePropertyDetails.ps1` |
| **Visibility** | Public |
| **Alias** | `dprop` |
| **Source type** | Function `Get-FilePropertyDetails` |

**Purpose:** Deep file metadata extraction: PE headers, version info (FileVersion, ProductVersion, CompanyName, etc.), COM Shell.Application extended properties, .NET assembly metadata, digital signature info. Handles executables, DLLs, and general files. Directory-aware (can skip dirs or include them).

**Parameters to preserve:**
- `-FilePath` (alias `-Path`, `-FullName`) — mandatory, pipeline-ready
- `-IncludeEmptyProperties` switch — include properties with null/empty values
- `-IncludeSignature` switch — add digital signature info (slower, uses Get-AuthenticodeSignature)
- `-IncludeDirectories` switch — don't skip directory objects when piping Get-ChildItem

**Pipeline:** `-FilePath` accepts pipeline (`ValueFromPipeline`, `ValueFromPipelineByPropertyName`)

**Outputs:** `[PSCustomObject]` / `[hashtable]` (rich metadata object, varies by file type)

**Porting notes:**
- 346 lines — well-structured, mostly ready
- Uses multiple .NET methods (VersionInfo, Assembly.ReflectionOnlyLoadFrom, Shell.Application COM)
- Assembly reflection (`Assembly.ReflectionOnlyLoadFrom`) can lock files on some PS versions — test and add fallback
- Replace `Write-Error`/`Write-Verbose` (already has Write-Verbose) — fix Write-Error calls
- `-FilePath` parameter naming conflicts with module convention of `-Path` — add alias; keep `-FilePath` as primary since it's a file-only operation (directories have different behavior)

**Related:** Get-DowserOwnership (ownership/ACL focus), Get-DowserReport (metrics focus)

---

### Get-DowserReport

| Field | Value |
|-------|-------|
| **Source** | `Get-FileReport.ps1` |
| **Visibility** | Public |
| **Alias** | `dreport` |
| **Source type** | Function (1010-line source, large but structured) |

**Purpose:** Produce a detailed file metrics report for a file, folder, or directory tree. Per-file stats: size, line count, word count, character count, timestamps, attributes, optionally ACL owner. Parallel RunspacePool processing for directory scans. Export to CSV or self-contained HTML report.

**Parameters to preserve:**
- `-Path` — file or directory path(s); pipeline input
- `-Pattern` — wildcard filter (default `*`)
- `-Extensions` — extension array filter
- `-Depth` — recursion depth; 0=flat, -1=full recursive
- `-IncludeOwner` switch — add ACL owner (slower)
- `-MinSize` / `-MaxSize` — size filters
- `-UseRunspaces` — default true
- `-ThreadCount` — default processor count
- `-ExportCsv` — auto-export CSV path
- `-ExportHtml` — auto-export HTML report path
- `-SortBy` — sort property (Name, Size, LineCount, WordCount, etc.)

**Pipeline:** `-Path` accepts pipeline (`ValueFromPipeline`)

**Outputs:** `[PSCustomObject]` per file with all metrics

**Porting notes:**
- 1010 lines — largest source file. Review for `Write-Host` replacements before porting (there will be many)
- Runspace pattern matches Find-Files.ps1 pattern — same structure to verify against module standards
- HTML report is self-contained (inline CSS/JS) — good, no template dependency
- `#requires -Version 2.0` at top of source — update to `#Requires -Version 5.1` for the module
- Parallel processing of text file reading (line/word/char counting) may have encoding edge cases — test on non-ASCII content

**Related:** Get-DowserProperty (deep per-file metadata), Measure-DowserDirectory (aggregate totals)

---

### Get-DowserTemplate

| Field | Value |
|-------|-------|
| **Source** | `Get-FolderTemplate.ps1` |
| **Visibility** | Public |
| **Alias** | `dtemplate` |
| **Source type** | Function `Get-FolderTemplate` — short (31 lines), COM-based |

**Purpose:** Retrieve a Windows Explorer folder's current view settings: view mode (Details/Tiles/Icons/etc.) and visible column definitions with index and name. Useful for understanding or cloning a folder's Explorer template for automated folder setup.

**Parameters to preserve:**
- `-Path` (was `-folderPath`) — the folder path to inspect

**Pipeline:** `-Path` accepts pipeline (`ValueFromPipeline`)

**Outputs:** `[hashtable]` with `ViewMode` and `Columns` array; consider converting to `[PSCustomObject]` for pipeline friendliness

**Porting notes:**
- 31 lines — almost trivial. Main work is renaming param and adding `[CmdletBinding()]` + help block
- Rename `-folderPath` to `-Path` (camelCase param is a minor style issue; fix it)
- Output is a bare `@{ ViewMode; Columns }` hashtable — wrap in `[PSCustomObject]` for consistent module output
- Shell.Application COM — Windows only; note in help
- The bottom of the source file has live execution code (`$template = Get-FolderTemplate -folderPath "D:" ...`) — remove from module file; move to `.EXAMPLE` in help
- `GetDetailsOf($folder.Items, $_)` iterates 0..500 — this can be slow; add `Write-Progress` loop

**Related:** Get-DowserMap (both deal with folder presentation, different angle)

---

### Get-DowserTopology

| Field | Value |
|-------|-------|
| **Source** | `Get-TreeTopology.ps1` |
| **Visibility** | Public |
| **Alias** | `dtopo`, `pstree`, `shtree` |
| **Source type** | Function `Get-TreeTopology` with aliases `pstree` and `shtree` |

**Purpose:** Indented tree display of a path's structure, similar to Unix `pstree`/`tree`. Supports showing files alongside directories (`-ShowItem`), displaying item properties, configurable indent size, depth limit, and optional color output (dynamic parameter).

**Parameters to preserve:**
- `-Path` (alias `-FullName`) — pipeline input, default `.`
- `-LiteralPath` — alternate parameter set
- `-Depth` — max depth (default: MaxValue = unlimited)
- `-IndentSize` — spaces per indent level (default 3, range 1-100)
- `-ShowItem` (alias `-files`) — include files in output
- `-ShowProperty` (alias `-properties`) — display item properties; `*` for all

**Pipeline:** `-Path` and `-LiteralPath` accept pipeline by property name

**Outputs:** Formatted string lines to host (this renders to console — consider whether to also emit PSObjects for programmatic use)

**Porting notes:**
- Uses `DynamicParam` for an `-InColor` switch (added only when path is FileSystem). This pattern is fine in a module.
- Existing aliases `pstree` and `shtree` should be preserved in `Aliases\Aliases.ps1` — do not define inside the function
- Source was created with SAPIEN PowerShell Studio 2023 headers — remove the SAPIEN header block; replace with standard Dowser comment-based help
- Inspect remainder of the 339-line source for `Write-Host` before porting

**Related:** Get-DowserMap (richer visual tree), Get-DowserTree (per-folder stats)

---

### Measure-DowserDirectory

| Field | Value |
|-------|-------|
| **Source** | `Get-DirectorySizeCounts.ps1` |
| **Visibility** | Public |
| **Alias** | `dsize` |
| **Source type** | Function `Get-DirectorySizeCounts` — requires cleanup before port |

**Purpose:** For each subdirectory under a root path, compute: total size (human-readable), file count, largest file, newest file, oldest file. Returns one PSCustomObject per subdirectory.

**Parameters to preserve:**
- `-Path` (was `-Path` / alias `FullName`) — root directory; default `.`

**Pipeline:** `-Path` accepts pipeline (`ValueFromPipeline`, `ValueFromPipelineByPropertyName`)

**Outputs:** `[PSCustomObject]` with Directory, DataSize, FileCount, LargestFile, FileName (largest), NewestFile, OldestFile

**Porting notes:**
- **BLOCKER: Legacy write aliases.** Source uses `WHY`, `WHM`, `WHG`, `WHB`, `WH` — shorthand Write-* aliases sourced from a local helper at `E:\_Local-H\...`. These will fail in any other environment. Replace with `Write-Verbose` before porting.
- **BLOCKER: Dot-sourced local helper.** Line 1 of source: `. "E:\_Local-H\'._\_.'funkshenz\Set-WriteAlias.ps1"` — hardcoded absolute path. Remove entirely.
- `ConvertFrom-Bytes` nested function: same byte-formatting logic appears in Get-FolderTree and Get-FileOwnership. Extract to Private\ as `Format-DowserSize` during port.
- Output `NewestFile`/`OldestFile` are currently strings like `"filename.txt -=- 2025-01-01"` — replace with a proper PSCustomObject per file entry or split into `NewestFileName`/`NewestFileDate` properties
- Note the verb mismatch: source is `Get-DirectorySizeCounts` but the target is `Measure-DowserDirectory` (`Measure-` is the correct verb for sizing/counting operations)

**Related:** Get-DowserTree (tree traversal), Get-DowserReport (per-file metrics)

---

### Invoke-DowserFastSearch

| Field | Value |
|-------|-------|
| **Source** | `Invoke-FastTextSearch.ps1` |
| **Visibility** | Public |
| **Alias** | `dfast` |
| **Source type** | Function `Invoke-FastTextSearch` — runspace-based, clean |

**Purpose:** Parallel text search across files using RunspacePool. Single search string, supports include/exclude file type filters, case sensitivity, configurable thread count. Returns file path + matching line numbers.

**Parameters to preserve:**
- `-Path` — root directory to search
- `-SearchString` — the string to find (mandatory)
- `-Threads` — concurrent workers (default 10)
- `-Include` — file type filter (e.g., `'*.txt'`, `'*.log'`); default `*.*`
- `-Exclude` — file type exclusion
- `-CaseSensitive` switch

**Pipeline:** `-Path` accepts pipeline (add)

**Outputs:** `[PSCustomObject]` with file path, line numbers array, match count

**Porting notes:**
- Clean source — mostly rename param to `-Path` and add `[CmdletBinding()]` / help block
- Replace `Write-Verbose "Starting script execution."` with a proper `Write-Verbose` message
- The `$results` synchronized ArrayList is returned at end — confirm it's emitted to pipeline, not just stored
- Rename `-SearchString` to `-Pattern` for consistency with Find-DowserString (or keep `-SearchString` and add `-Pattern` alias)
- Stopwatch timing currently just starts/stops — add `-Verbose` output with elapsed time

**Related:** Find-DowserString (more capable — multi-pattern, Aho-Corasick, multiple output modes)

---

### Invoke-DowserNumericSort

| Field | Value |
|-------|-------|
| **Source** | `Invoke-NumericalSorting.ps1` |
| **Visibility** | Public |
| **Alias** | `dsort`, `dnsort` |
| **Source type** | Two functions: `Get-SortKey` (private helper) + `Sort-Numerical` (main) |

**Purpose:** Sort strings or objects that contain mixed alphanumeric identifiers correctly. Standard `Sort-Object` would sort "Item-10" before "Item-2"; this cmdlet pads numeric segments so natural order is preserved. Supports sort by property, descending, unique, top-N.

**Parameters to preserve (from `Sort-Numerical`):**
- `-InputObject` — pipeline input, mandatory
- `-Property` — property name(s) to sort by
- `-Descending` switch
- `-CaseSensitive` switch
- `-Unique` switch
- `-Top` — return only top N results (range 1+)

**Pipeline:** `-InputObject` accepts pipeline (`ValueFromPipeline`)

**Outputs:** sorted objects (same type as input)

**Porting notes:**
- Source has two functions: `Get-SortKey` (the numeric padding logic) and `Sort-Numerical` (the Sort-Object wrapper). `Get-SortKey` goes to Private\ as an internal helper.
- The main exported function is named `Sort-Numerical` in the source but the outline maps it to `Invoke-DowserNumericSort`. `Sort-` is actually a valid PS verb — consider whether `Sort-DowserNumerical` is better than `Invoke-DowserNumericSort`. Either is valid; `Invoke-DowserNumericSort` matches the existing outline decision and avoids confusion with `Sort-Object`.
- The script also has `$script:capturedInput = $null` at module scope — that's a leftover artifact from testing. Remove it.
- `throw "No input data provided. Can't sort nothin', bro."` — replace `throw` with `Write-Error -ErrorRecord` per module standards
- Add input type flexibility: source currently handles strings and objects; verify it handles FileInfo objects piped from Get-ChildItem

**Related:** Find-DowserFile, Find-DowserDuplicate (both return sortable result sets)

---

## Alias Definitions

All aliases land in `Aliases\Aliases.ps1`. None defined inside function files.

```powershell
# Aliases\Aliases.ps1
# Generated from porting outline 2026-04-11
# Casual aliases for day-to-day use. Underlying cmdlets follow Verb-DowserNoun.

Set-Alias -Name db64      -Value ConvertTo-DowserBase64
Set-Alias -Name dexe      -Value ConvertTo-DowserExe
Set-Alias -Name dico      -Value ConvertTo-DowserIco

Set-Alias -Name ddupe     -Value Find-DowserDuplicate
Set-Alias -Name dfile     -Value Find-DowserFile
Set-Alias -Name dfind     -Value Find-DowserFile
Set-Alias -Name dmod      -Value Find-DowserModified
Set-Alias -Name dlog      -Value Find-DowserRecentLog
Set-Alias -Name dorphan   -Value Find-DowserOrphan
Set-Alias -Name ddep      -Value Find-DowserDependency
Set-Alias -Name dscript   -Value Find-DowserScript
Set-Alias -Name dstr      -Value Find-DowserString
Set-Alias -Name dgrep     -Value Find-DowserString

Set-Alias -Name dmap      -Value Get-DowserMap
Set-Alias -Name dtree     -Value Get-DowserTree
Set-Alias -Name down      -Value Get-DowserOwnership
Set-Alias -Name dprop     -Value Get-DowserProperty
Set-Alias -Name dreport   -Value Get-DowserReport
Set-Alias -Name dtemplate -Value Get-DowserTemplate
Set-Alias -Name dtopo     -Value Get-DowserTopology
Set-Alias -Name pstree    -Value Get-DowserTopology
Set-Alias -Name shtree    -Value Get-DowserTopology

Set-Alias -Name dsize     -Value Measure-DowserDirectory

Set-Alias -Name dfast     -Value Invoke-DowserFastSearch
Set-Alias -Name dsort     -Value Invoke-DowserNumericSort
Set-Alias -Name dnsort    -Value Invoke-DowserNumericSort
```

---

## Shared Private Helpers to Extract

These helpers appear in multiple source scripts and should land in `Private\` rather than being duplicated:

| Private Helper | Purpose | Sources That Need It |
|----------------|---------|----------------------|
| `Format-DowserSize` | Convert byte count to human-readable string (B/KB/MB/GB/TB) | Get-DirectorySizeCounts, Get-FolderTree, Get-FileOwnership |
| `ConvertTo-DowserBytes` | Parse size strings like "10MB" to byte count | Find-Files (search mode), Get-FileReport |
| `Get-DowserSortKey` | Numeric padding for natural sort | Invoke-NumericalSorting |

Internal helpers unique to one cmdlet (e.g., `Get-NormalizedStem`, `Get-ChunkHashes` in Find-FileDuplicates; `Get-SortKey` in Invoke-NumericalSorting) stay as nested functions inside their parent unless they grow or are needed elsewhere.

---

## Porting Flags Summary

Issues that will block a clean port if not addressed:

| Script | Flag | Severity |
|--------|------|----------|
| Get-DirectorySizeCounts.ps1 | Uses WHY/WHM/WHG/WHB/WH write aliases from hardcoded local helper | BLOCKER |
| Get-DirectorySizeCounts.ps1 | Dot-sources `E:\_Local-H\...\Set-WriteAlias.ps1` | BLOCKER |
| Find-MostRecentLog.ps1 | Not a function — bare script. No parameters. Needs full rewrite skeleton | HIGH |
| Find-FilesModifiedOn.ps1 | Hardcoded `D:\` in function body | HIGH |
| Get-FolderTree.ps1 | Hardcoded `E:\`, `C:\Temp\finalTemplate.html`, `C:\Temp\final.html` | HIGH |
| Get-DirectoryTreeOutputAndFileCount.ps1 | Hardcoded `E:\` and exclude paths | HIGH |
| Find-Scripts.ps1 | Function name `Find-SecureCrtScripts` doesn't match file name; behavior hardcoded to SecureCRT use case | HIGH |
| Invoke-NumericalSorting.ps1 | `throw` in catch — violates module standards; replace with Write-Error | MEDIUM |
| Find-FileDuplicates.ps1 | `$global:dupObjects` side effect — remove global var pollution | MEDIUM |
| ConvertTo-Base64.ps1 | Not a function — bare script; needs function wrapper | MEDIUM |
| All scripts | `Write-Host` calls throughout — replace with Write-Verbose/Write-Warning | MEDIUM |
| Multiple scripts | Hardcoded absolute paths in comments or defaults | LOW |

---

## Port Order Recommendation

Sequence based on: dependencies between scripts, complexity, and standalone testability.

**Phase 1 — Low complexity, no blockers:**
1. `ConvertTo-DowserIco` (clean function, just needs Write-Host swap)
2. `Find-DowserModified` (small, rewrite is trivial)
3. `Get-DowserTemplate` (31 lines, mostly renaming)
4. `Find-DowserOrphan` (solid function, minimal changes)
5. `Get-DowserTopology` (clean function, mostly header cleanup)

**Phase 2 — Medium complexity:**
6. `ConvertTo-DowserBase64` (needs function wrapper)
7. `ConvertTo-DowserExe` (merge two functions + add param)
8. `Find-DowserDuplicate` (remove global var, add SupportsShouldProcess)
9. `Find-DowserFile` (strip duplicate mode, keep search)
10. `Find-DowserScript` (rename + generalize)
11. `Find-DowserRecentLog` (full rewrite of skeleton around bare script logic)
12. `Find-DowserDependency` (minor cleanup)

**Phase 3 — Blockers to resolve first, then port:**
13. `Measure-DowserDirectory` (resolve write-alias blocker, extract Format-DowserSize to Private\)
14. `Get-DowserTree` (MERGE — full rewrite skeleton from two sources)

**Phase 4 — Large/complex:**
15. `Get-DowserOwnership` (extract helpers to Private\)
16. `Get-DowserProperty` (346 lines, mostly clean)
17. `Invoke-DowserFastSearch` (clean but needs thorough testing)
18. `Invoke-DowserNumericSort` (extract Get-SortKey to Private\)
19. `Find-DowserString` (large, thorough Write-Host audit needed)
20. `Get-DowserMap` (largest script — 823 lines, recursive self-call, careful testing)
21. `Get-DowserReport` (1010 lines — port last, most complex)

---

## Index Stubs (paste into docs\INDEX.md)

```markdown
### ConvertTo-DowserBase64
- Purpose: Encode any file to Base64 string or decode Base64 back to binary; clipboard and Data URI support
- Inputs: -Path, -OutputFile, -Decode, -IncludeHeader, -CopyToClipboard
- Outputs: [string] Base64 string or decoded file path
- Related: none
- Source: ConvertTo-Base64.ps1

### ConvertTo-DowserExe
- Purpose: Compile a PowerShell script into a standalone Windows .exe via C# wrapper and Add-Type
- Inputs: -ScriptPath, -OutputPath, -ConfuserExPath, -Obfuscate
- Outputs: [string] path to compiled exe
- Related: none
- Source: ConvertTo-Exe.ps1

### ConvertTo-DowserIco
- Purpose: Convert any image file to multi-size Windows .ico; supports UNC paths and PNG compression
- Inputs: -InputFilePath, -OutputFile, -IcoSizes, -MaxSize
- Outputs: [bool] success; writes .ico file to disk
- Related: ConvertTo-DowserBase64
- Source: ConvertTo-ICO.ps1

### Find-DowserDuplicate
- Purpose: Detect duplicate files by Name, PartialName, NameSize, Content hash, or Chunk hash
- Inputs: -Path, -Exclude, -MinSize, -Mode, -HashAlgorithm, -ChunkSize, -ReportPath, -AutoRemove, -ReviewBeforeDelete
- Outputs: [PSCustomObject] grouped duplicate sets
- Related: Find-DowserOrphan
- Source: Find-FileDuplicates.ps1

### Find-DowserFile
- Purpose: High-performance parallel file search by name pattern, size range, and date range
- Inputs: -Path, -Pattern, -Recurse, -MinSize, -MaxSize, -ModifiedAfter, -ModifiedBefore, -StopOnFirstMatch, -UseRunspaces, -ThreadCount
- Outputs: [PSCustomObject] file objects with FullName, Name, Directory, Size, timestamps
- Related: Find-DowserDuplicate, Find-DowserString
- Source: Find-Files.ps1 (search parameter set only; duplicate set absorbed by Find-DowserDuplicate)

### Find-DowserModified
- Purpose: Find files modified on a specific calendar date
- Inputs: -Path, -Date, -Recurse
- Outputs: [PSCustomObject] with FullName, LastWriteTime, Size
- Related: Find-DowserFile
- Source: Find-FilesModifiedOn.ps1

### Find-DowserRecentLog
- Purpose: Find the most recently modified copy of a named file across one or more search paths
- Inputs: -FileName, -Path, -All, -Recurse
- Outputs: [PSCustomObject] with FullName, LastWriteTime, Length; newest first
- Related: Find-DowserFile, Find-DowserScript
- Source: Find-MostRecentLog.ps1 (bare script; full function rewrite)

### Find-DowserOrphan
- Purpose: Identify files not referenced by any text-based source file in a directory tree
- Inputs: -Path, -ExcludePaths, -TextExtensions
- Outputs: [PSCustomObject] orphan files with FullName and reference count
- Related: Find-DowserDuplicate
- Source: Find-OrphanFiles.ps1

### Find-DowserDependency
- Purpose: Scan scripts for dot-sourcing, Import-Module calls, and specific function references
- Inputs: -Path, -AdditionalPaths, -FunctionNames, -ExcludePaths, -IncludeContent, -ExportResults
- Outputs: [PSCustomObject] with file path, matched pattern, line number
- Related: Find-DowserOrphan, Find-DowserScript
- Source: Find-ScriptDependencies.ps1

### Find-DowserScript
- Purpose: Find script files by extension set, with optional recency filter
- Inputs: -Path, -Extensions, -ModifiedWithin, -Recurse
- Outputs: [PSCustomObject] with Name, FullName, Extension, LastWriteTime
- Related: Find-DowserFile, Find-DowserDependency, Find-DowserRecentLog
- Source: Find-Scripts.ps1 (function was named Find-SecureCrtScripts; fully generalized)

### Find-DowserString
- Purpose: Multi-threaded pattern search across files; multi-pattern, regex or literal, multiple output modes
- Inputs: -Path, -Patterns, -Extensions, -MaxThreads, -MaxFileSizeMB, -UseRegex, -CaseSensitive, -ExcludeFolders, -SearchMode, -UseRunspaces
- Outputs: [PSCustomObject] with file path, line number, matched pattern, matched text
- Related: Invoke-DowserFastSearch
- Source: Find-StringInFiles.ps1

### Get-DowserMap
- Purpose: Visual tree renderer with Unicode/ASCII box-drawing, HTML/Markdown export, extension/folder filtering, parallel pre-scan
- Inputs: -Path, -MaxDepth, -IncludeFilePatterns, -IncludeExtensions, -ExcludeExtensions, -ExcludeFolders, -IncludeFolders, -FoldersOnly, -ShowFullPathTree, -LinuxPaths, -Ascii, -AsHtml, -AsMarkdown, -IncludeHidden, -OutputFile, -EmitSummary, -UseRunspaces
- Outputs: [string[]] tree lines; optional file write
- Related: Get-DowserTree, Get-DowserTopology
- Source: Get-DirectoryMap.ps1

### Get-DowserTree
- Purpose: Per-folder statistics: total size, file count, extension breakdown; optional HTML output
- Inputs: -Path, -Depth, -IncludePsCount, -ExtensionCount, -ExcludePaths, -Html
- Outputs: [PSCustomObject] per folder with FolderPath, size, file count
- Related: Get-DowserMap, Measure-DowserDirectory
- Source: Get-DirectoryTreeOutputAndFileCount.ps1 + Get-FolderTree.ps1 (MERGED)

### Get-DowserOwnership
- Purpose: Return ACL owner and Shell.Application extended metadata for files in a directory
- Inputs: -Path, -Extension
- Outputs: [PSCustomObject] with Name, FullName, Size, IsReadOnly, LastWriteTime, Owner, Shell properties
- Related: Get-DowserProperty
- Source: Get-FileOwnership.ps1

### Get-DowserProperty
- Purpose: Deep metadata extraction — PE headers, version info, COM Shell properties, .NET assembly info, digital signatures
- Inputs: -FilePath, -IncludeEmptyProperties, -IncludeSignature, -IncludeDirectories
- Outputs: [PSCustomObject] rich metadata object (varies by file type)
- Related: Get-DowserOwnership, Get-DowserReport
- Source: Get-FilePropertyDetails.ps1

### Get-DowserReport
- Purpose: File metrics report with parallel processing — size, line/word/char counts, timestamps, ACL; CSV/HTML export
- Inputs: -Path, -Pattern, -Extensions, -Depth, -IncludeOwner, -MinSize, -MaxSize, -UseRunspaces, -ThreadCount, -ExportCsv, -ExportHtml, -SortBy
- Outputs: [PSCustomObject] per file with full metrics
- Related: Get-DowserProperty, Measure-DowserDirectory
- Source: Get-FileReport.ps1

### Get-DowserTemplate
- Purpose: Retrieve Windows Explorer folder view mode and column definitions via Shell.Application COM
- Inputs: -Path
- Outputs: [PSCustomObject] with ViewMode and Columns array
- Related: Get-DowserMap
- Source: Get-FolderTemplate.ps1

### Get-DowserTopology
- Purpose: Indented pstree-style directory display with optional file listing and item property output
- Inputs: -Path, -LiteralPath, -Depth, -IndentSize, -ShowItem, -ShowProperty
- Outputs: formatted string lines
- Related: Get-DowserMap, Get-DowserTree
- Source: Get-TreeTopology.ps1

### Measure-DowserDirectory
- Purpose: Per-subdirectory size, file count, largest file, newest and oldest file stats
- Inputs: -Path
- Outputs: [PSCustomObject] per subdirectory with Directory, DataSize, FileCount, LargestFile, NewestFile, OldestFile
- Related: Get-DowserTree, Get-DowserReport
- Source: Get-DirectorySizeCounts.ps1

### Invoke-DowserFastSearch
- Purpose: Parallel single-string text search across files using RunspacePool; returns file path and matching line numbers
- Inputs: -Path, -SearchString, -Threads, -Include, -Exclude, -CaseSensitive
- Outputs: [PSCustomObject] with file path, line numbers, match count
- Related: Find-DowserString
- Source: Invoke-FastTextSearch.ps1

### Invoke-DowserNumericSort
- Purpose: Natural/numeric sort for mixed alphanumeric strings; prevents "Item-10 before Item-2" ordering errors
- Inputs: -InputObject (pipeline), -Property, -Descending, -CaseSensitive, -Unique, -Top
- Outputs: sorted objects (same type as input)
- Related: none
- Source: Invoke-NumericalSorting.ps1
```
