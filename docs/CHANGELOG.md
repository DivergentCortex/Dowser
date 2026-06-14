# Changelog

All notable changes to Dowser land here. Format loosely follows Keep a Changelog. Dates ISO-8601.

## [2026.06.14.020] - 2026-06-14
### fix(Get-DowserMap): Fix -FollowReparse regression and Pester skip-scoping; add ShowFullPathTree symlink test coverage

What changed:
- Fixed AC2 regression: render-loop guards at lines 680 and 782 were unconditional (if (Test-ReparsePoint $item)) so -FollowReparse symlinks were caught by the link-render branch instead of falling through to the folder-descent branch; fixed by adding -not $FollowReparse -and prefix to both guards, matching the pre-filter pattern
- Fixed Pester skip-scoping: -Skip:($script:canSymlink) evaluated at discovery time when $script: set at file scope is not visible inside Pester 5 BeforeAll blocks, causing all 11 tests to skip; fixed by using $global:DowserTestCanSymlink set at file parse scope so the value is available at discovery time; global is cleaned up in AfterAll
- Added ShowFullPathTree context (4 tests) covering the trunk render path (line 782) for both default no-descend and -FollowReparse descend cases; this is the path that carried the AC2 bug
- Pester suite now runs 11/11 passing, 0 skipped on this Linux box where symlink creation is permitted

Why:
- The render-loop FollowReparse guard was missing, causing directory symlinks to always render as two-line link blocks even when -FollowReparse was set, breaking AC2. The Pester $script: scoping issue caused all tests to skip silently, masking the regression. Both defects were caught by the raven pair audit.


## [2026.06.14.019] - 2026-06-14
### feat(Get-DowserMap): Detect and show symlinks as two-line render instead of silently skipping them

What changed:
- Added $linkChar (U+2192 →) and $targetChar (U+21B3 ↳) glyph vars in both the if($Ascii) block (ASCII fallbacks '>' and '~') and the else block (if($AsHtml) entity / else [char] form), matching the existing dual-path codepoint convention at lines 533-546
- Added LinkCount = 0 to the $TraversalState initializer; LinkCount increments per symlink shown and appears in -EmitSummary output when non-zero
- Non-ShowFullPathTree path: replaced the reparse-point SkippedFolders++ guard with $filteredLinks accumulation; $items is now @($filteredFolders) + @($filteredLinks) + @($filteredFiles) so $isLast is correct for the combined list; render loop checks Test-ReparsePoint first and emits line1 ($Indent$connector $linkChar $name) and line2 ($nextIndent $targetChar $target), both passed through Format-HiddenLine
- ShowFullPathTree path: same pattern using $childrenBaseIndent/$recursiveIndent; $all is now @($folders) + @($links) + @($files); folder render block restructured so Format-HiddenLine and the MaxDepth branch are self-contained in the elseif
- Broken/dangling symlinks: $item.Target null/empty falls back to string '(broken link)'
- All three output modes handled: console emits [char] glyphs, -AsHtml emits &#x2192;/&#x21B3; entities (set at glyph-var init time), -AsMarkdown uses console chars inside the fenced block
- -FollowReparse behavior unchanged: symlinks in $filteredLinks / $links are only accumulated when -not $FollowReparse; with -FollowReparse the original guard is not reached so links fall through to normal folder handling
- Added Tests/Get-DowserMap.Tests.ps1: Pester 5 suite; target dir created outside the mapped root so inner.txt appearance uniquely proves traversal; $canSymlink guard skips suite if symlink creation is not permitted; tests cover: arrow line emitted, target line emitted with resolved path, no-descend by default, continuation bar present on non-last-child target line, -FollowReparse descends, -AsHtml entities correct

Why:
- Default behavior silently dropped symlinks from the tree output (SkippedFolders++), making them invisible. Task #1 requires showing them as a two-line block (→ name / ↳ target) without descending, so users can see what links exist and where they point without the tree recursing into them.


## [2026.06.07.018] - 2026-06-07
### fix(Measure-DowserDiskUsage): Fix treemap double-count, symlink root skipped, case-sensitive dir keys on Linux

What changed:
- Fix #1 (Linux case-sensitive dir keys): $dirSizes now uses Ordinal comparer on non-Windows (where $IsWindows -eq $false) and OrdinalIgnoreCase on Windows/PS-5.1 ($IsWindows is $null on 5.1, treated as Windows); ancestor-walk stop test updated to use the same comparer via $dirComparer.Equals(); Phase 2 root-exclusion filter also updated to use $dirComparer.Equals() -- prevents sibling dirs Foo/foo collapsing to one key on Linux and prevents the ancestor loop overshooting on case-diverged paths
- Fix #2 (symlink/reparse root dropped): reparse-point skip guard now checks $isRoot first and only skips descendant reparse points, so a symlink or junction passed as -Path is scanned correctly rather than silently returning empty results
- Fix #3 (treemap double-count + proportionality): treemap rebuilt from IMMEDIATE children of root only (keys in $dirSizes whose GetDirectoryName == resolvedRoot), producing a non-overlapping partition with no double-counting; widths = SizeBytes / TotalBytes * 100 so area is honestly proportional to real disk usage; a remainder block (ddu-remainder class) covers root-level files and any items beyond TopN; $dirSizes and $dirComparer passed into _Build-DduHtml for this computation
- Tests: all Join-Path paths use nested form for cross-platform correctness; added extensionless file noext and <none> extension assertions; added treemap-proportionality assertions (block widths sum to ~100%, largest block >= 98%, remainder block present); added symlink-root test (skipped on Windows or when symlink creation is not permitted)

Why:
- Codex review (FIX-THEN-SHIP) identified three real defects: the treemap drew overlapping nested dirs producing misleading area proportions, a symlinked root was silently skipped producing empty results, and $dirSizes used OrdinalIgnoreCase on case-sensitive Linux filesystems causing sibling dirs with different casing to merge into one bucket


## [2026.06.07.017] - 2026-06-07
### feat(Measure-DowserDiskUsage): Add Measure-DowserDiskUsage (ddu) -- WinDirStat-style recursive disk-usage report with HTML treemap

What changed:
- Created Public/Measure-DowserDiskUsage.ps1: recursive directory scan, biggest-dirs rollup ranked by size, biggest-files ranking, by-extension aggregation; all size strings via Format-DowserSize
- Added -ExportHtml: self-contained HTML report with slice-and-dice treemap (block area proportional to disk usage), three ranked tables, dark palette matching Get-DowserReport.ps1 (#1e1e1e, #569cd6, #4ec9b0)
- Added -MinSize filter (parsed by ConvertTo-DowserBytes), -ExcludePath for skipping named dirs, -TopN (default 15)
- Created Tests/Measure-DowserDiskUsage.Tests.ps1: temp tree with known byte sizes; asserts total, dir-rollup order, file-ranking order, extension aggregation, HTML treemap markup and palette colors
- Added Set-Alias ddu Measure-DowserDiskUsage to Aliases/Aliases.ps1
- Added full INDEX.md entries for Measure-DowserDiskUsage and the previously platform-table-only Measure-DowserDirectory

Why:
- User has directories ballooning to tens of GB and needs a WinDirStat-style 'what is eating my space' answer built into Dowser; Measure-DowserDirectory covers immediate subdirs only with no ranking, no extension breakdown, and no HTML output


## [2026.06.07.016] - 2026-06-07
### docs(project-wide): Full documentation pass: rewrite README, ARCHITECTURE; fix INDEX; archive spent artifacts

What changed:
- README.md rewritten: removed stale Windows D:\ import path, added project description, quick start examples, full exported function table with aliases, platform support section, accurate project layout
- ARCHITECTURE.md rewritten: added executive summary, private helper inventory, parallelism model, platform support model, design decisions with rationale (switch vs bool, tilde resolution, pattern auto-wrap, Write-Information for banners), removed stale 'cross-platform is out of scope' claim
- INDEX.md: added missing Get-DowserInfo entry, fixed truncated Expand-DowserExe entry (completed outputs, related, source, aliases fields)
- Archived spent working artifacts to .archives/_archive.zip: PORTING_OUTLINE.md (porting complete at 21/21), docs/superpowers/plans/2026-05-24-cross-platform-compat.md (plan fully implemented), DOWSER_PROJECT_OUTLINE.md (superseded by README + ARCHITECTURE)
- Created .gitignore with entries for .archives/, Tests/Reports/, .firecrawl/

Why:
- Documentation was stale: README had hardcoded Windows paths and no function inventory, ARCHITECTURE claimed cross-platform was out of scope (contradicted by changelog 013), INDEX was missing Get-DowserInfo and had a truncated Expand-DowserExe entry, and three spent design artifacts cluttered the docs surface


## [2026.06.04.015] - 2026-06-04
### fix(module-wide): Fix [switch] defaults, pattern matching, and silent error swallowing across 7 functions

**Bug class 1: `[switch]$Param = $true` silently ignored (7 params across 5 files)**

PowerShell `[switch]` parameters ignore `= $true` defaults -- they always evaluate as `$false` unless the caller explicitly passes the flag. Changed to `[bool]` in all affected parameters:

- `Find-DowserFile.ps1`: `$Recurse`, `$UseRunspaces`
- `Find-DowserModified.ps1`: `$Recurse`
- `Find-DowserRecentLog.ps1`: `$Recurse`
- `Find-DowserScript.ps1`: `$Recurse`
- `Get-DowserMap.ps1`: `$UseRunspaces`
- `Get-DowserReport.ps1`: `$UseRunspaces`

Impact: all of these functions silently ran non-recursive / single-threaded unless the caller explicitly passed `-Recurse` or `-UseRunspaces`, despite docs and intent saying "default $true".

**Bug class 2: Pattern parameters require exact filename match (2 files)**

`-Pattern` passed raw to `Get-ChildItem -Filter`, which requires exact wildcard syntax. A bare string like `cortex-mcp` matched nothing unless a file was named exactly that. Added auto-wrap: bare strings without `*` or `?` get wrapped in `*...*` before being passed to `-Filter`.

- `Find-DowserFile.ps1`: auto-wrap in `begin` block
- `Get-DowserReport.ps1`: auto-wrap in `begin` block

**Bug class 3: Silent error swallowing producing wrong results (3 files)**

- `Find-DowserOrphan.ps1`: `Get-Content -ErrorAction SilentlyContinue` bypassed the existing try/catch, making unreadable scanner files invisible. Files only referenced in unreadable files would be false-positive orphans. Changed to `-ErrorAction Stop` so the catch block fires and emits `Write-Warning`.
- `Find-DowserString.ps1`: empty catch in worker runspace scriptblock silently swallowed read failures. Added error sentinel row (`Pattern = '[READ-ERROR]'`) so callers can distinguish "no matches" from "could not read file".
- `Get-DowserMap.ps1`: four empty `catch { }` blocks in annotation helpers and cache builders (size measurement, PS1 count, match-cache scan, include-folder scan). Failed measurements rendered as 0 or $false silently. Added `Write-Verbose` to all four so failures surface with `-Verbose`.


## [2026.06.02.014] - 2026-06-02
### fix(path-resolution): Fix tilde (~) path resolution for .NET System.IO API calls across 4 modules

What changed:
- Find-DowserString: resolve $Path via Resolve-Path before [System.IO.File]::Exists and [System.IO.Directory]::EnumerateDirectories -- fixes -Recurse reporting 1 directory for ~/paths
- ConvertTo-DowserBase64: replace [System.IO.Path]::GetFullPath with GetUnresolvedProviderPathFromPSPath for $OutputFile -- GetFullPath does not expand tilde
- ConvertTo-DowserIco: resolve $OutputFile via GetUnresolvedProviderPathFromPSPath before [System.IO.File]::Open
- Write-Log: resolve $Logfile via GetUnresolvedProviderPathFromPSPath before [System.IO.File]::WriteAllText and System.IO.FileStream

Why:
- PowerShell tilde (~) is shell-only expansion; .NET static methods receive the literal string and silently fail or write to wrong locations. Audited all 31 files in Public/ and Private/ -- these 4 were the only affected modules.


## [2026.05.24.013] - Cross-Platform Compatibility

### Added
- Platform detection in Dowser.psm1 (defines $IsWindows/$IsLinux/$IsMacOS for PS 5.1 compatibility)
- Platform guards on Windows-only functions: ConvertTo-DowserIco, ConvertTo-DowserExe, Get-DowserTemplate
- Graceful degradation for COM-dependent Get-DowserProperty on non-Windows
- Cross-platform identity resolution (Get-SafeLogIdentity) in Write-Log
- Platform-aware 7-Zip defaults (uses PATH-based '7z' on Linux/macOS)
- CompatiblePSEditions = @('Desktop', 'Core') in module manifest
- Tests/Test-DowserCrossPlatform.Tests.ps1 test suite
- Platform Support section in docs/INDEX.md

### Fixed
- Module import failure on Linux caused by System.Drawing assembly load at file scope in ConvertTo-DowserIco
- Backslash path literal in Get-DowserInfo that failed path resolution on Linux
- WindowsIdentity calls in Write-Log that are unavailable on non-Windows platforms
- Hardcoded Windows paths for 7-Zip and expand.exe in Expand-DowserExe, Test-DowserExtractable, Test-DowserIntegrity
- 3-argument Join-Path in Dowser.psm1 that broke PS 5.1 (replaced with nested 2-argument calls)

### Changed
- Dowser.psm1 uses Join-Path for all internal path construction (cross-platform safe)
- ModuleVersion bumped from 0.1.0 to 0.2.0
- Module description updated to note cross-platform support

## [2026.05.04.012] - [2026-05-04] - Find-DowserString: single-file mode

### Fixed
- `Public/Find-DowserString.ps1` - When `-Path` is a file (not a directory), the function
  now short-circuits the directory enumeration and runspace-based file gathering and
  searches that single file directly. Previously the file path was fed into Phase 2's
  `Get-ChildItem -Path $dir -File` running inside a runspace that did not always inherit
  the caller's mapped drives (e.g. H:), silently returning zero files and emitting
  "No matches found" against files that obviously contained matches.
- Mapped-drive paths are resolved to their provider path up front so Phase 3 worker
  runspaces can read them reliably.

### Added
- New `OutputMode = 'singlefile'` (auto-selected when `-Path` is a file and `-OutputMode`
  was not explicitly set). Emits one header (file path, patterns, total match count,
  unique line count) followed by up to 25 sample matches as `lineNumber: truncated-line`,
  with whitespace collapsed and content clipped at 160 chars. Tail line indicates how
  many additional match rows exist if the cap was hit.

## [2026.04.29.011] - [2026-04-29] - Find-DowserString: grouped output mode (new default)

### Changed
- `Public/Find-DowserString.ps1` - Output reorganized to group results by parent directory.

  Was: default `OutputMode = 'counts'` emitted one PSCustomObject per file. PowerShell's
  default table formatter then truncated the FilePath column on long UNC paths,
  producing rows like:

      \\wsl.localhost\...\runtime_cortex\dist\comm...
      \\wsl.localhost\...\runtime_cortex\dist\comm...

  with the same parent dir repeated and the actual filename clipped.

  Now: new `OutputMode = 'grouped'` is the default. Output is text (Write-Output strings),
  formatted as a directory header with files listed underneath:

      \\wsl.localhost\...\runtime_cortex\dist  (5 files, 14 matches)
          commands-registry-BKukdIJg.js                         [   1]  line 584
          commands-registry-DaH1KNEE.js                         [   1]  line 544
          pi-embedded-CblkcCno.js                               [   6]  lines 41772, 42016, 42032, 42044, 42050, 42058

      \\wsl.localhost\...\runtime_cortex\dist\plugin-sdk  (2 files, 7 matches)
          commands-registry-DfTR18y4.js                         [   1]  line 584
          reply-BbVFaxrJ.js                                     [   6]  lines 43591, 70345, 79000, ...

  Filenames left-padded to widest in each group, clamped 30..80 chars.
  Line numbers truncate to first 8 with `(+N more)` suffix when over.

### Breaking
- The default `OutputMode` changed from `counts` to `grouped`. Pipeline consumers that
  relied on the object stream (`Find-DowserString ... | Where-Object MatchCount -gt 5`)
  must now pass `-OutputMode counts` explicitly. The `counts` mode itself is unchanged.

### Added
- `OutputMode = 'grouped'` value added to ValidateSet. Comment-based help for
  `-OutputMode` updated to describe all four modes including defaults.

---

## [2026.04.29.010] - [2026-04-29] - Find-DowserString: phase banners + streaming directory enumeration

### Changed
- `Public/Find-DowserString.ps1` - 3-phase status model with immediate visible feedback.

  Was: a blocking `Get-ChildItem -Directory -Recurse -Force` that ran silently before any
  progress could fire. On large trees (e.g. AppData\Roaming\Code - Insiders) this looked
  frozen for tens of seconds because Write-Progress had no chance to render until the
  recursive enum returned.

  Now:
  - Phase 1/3: Directory enumeration via streaming
    `[System.IO.Directory]::EnumerateDirectories` stack-walk.
    - Write-Progress fires before any directory I/O begins.
    - Updates throttled to ~5 Hz with running directory count and current branch leaf.
    - Excluded folders (`.git`, `node_modules`, `bin`, `obj` by default) pruned at
      branch level - we never descend into them, where the prior code walked them and
      filtered after. Net win on speed for repos and AppData trees.
    - Access-denied / reparse / vanished dirs swallowed silently as before.
  - Phase 2/3: File gathering. Existing runspace pool retained; ProgressStatus
    relabeled `Phase 2/3: Gathering files`.
  - Phase 3/3: String searching. Existing runspace pool retained; ProgressStatus
    relabeled `Phase 3/3: Searching files`.

  Per-phase banner via `Write-Information -InformationAction Continue` so the user
  sees a labeled status line at the start and end of each phase regardless of
  `$ProgressPreference`. Format:

      [Find-DowserString] Phase 1/3: Enumerating directories under '<path>'
      [Find-DowserString] Phase 1/3: Found N directories in Xs
      [Find-DowserString] Phase 2/3: Gathering files in N directories
      [Find-DowserString] Phase 2/3: Matched N files in Xs
      [Find-DowserString] Phase 3/3: Searching N files for K pattern(s)
      [Find-DowserString] Phase 3/3: Done. M match rows from N files in Xs

  No new files. No new helpers. No public-API surface change. `-Verbose` still works
  for the existing diagnostic stream; the new banners are independent of it.

### Notes
- Write-Information chosen over Write-Host to respect Dowser's `[FORBIDDEN] Write-Host
  in public functions` rule from project CLAUDE.md. The forced `-InformationAction
  Continue` makes the messages visible without polluting the function's output stream.

---

## [2026.04.21.009] - [2026-04-21] - Corrupted File Detection (Test-DowserIntegrity)

### Added
- `Public/Test-DowserIntegrity.ps1` - Layered file-corruption detection.
  Dispatches by category to the strongest available validator; never one magic test.

  Detection tiers:
  - Zero-byte check (all files, high confidence)
  - Archive category (.zip, .7z, .rar, .cab, .msu, .tar, .gz, .bz2, .xz, .wim, .msi,
    .iso, .nupkg, .jar, .apk, etc.): 7-Zip `7z t` when available (definitive,
    non-zero exit = corrupt). Falls back in order to:
    native `[System.IO.Compression.ZipFile]` full-stream read for ZIP family,
    `expand.exe -D` for CAB/MSU, OLE compound-file magic for MSI, then read-access probe.
  - PE category (.exe, .dll, .sys, .ocx, .drv, .scr, .cpl, .ax, .efi, .mui):
    MZ header, e_lfanew bounds, PE signature, COFF sanity (1..96 sections),
    Optional Header magic (0x10B / 0x20B / 0x107), section-table bounds, and
    per-section rawOffset + rawSize must not exceed file length. Catches truncation,
    header overwrites, and malformed SFX stubs.
  - Generic files: first + last 512-byte read-access probe.

  Hygiene scan (always on, added to address SCCM source-package pain):
  - Hidden / System attribute detection
  - Zone.Identifier ADS (Mark-of-the-Web) - the classic blocker that makes SCCM
    or Windows refuse to distribute/execute content
  - Any other alternate data stream
  - Residue filename patterns: Thumbs.db, desktop.ini, .DS_Store, ._*, ~$*,
    *.tmp, *.bak, *.orig, *.swp, *.swo, *.lock, *.partial, *.crdownload, *.part
  - Any hygiene finding on an otherwise-OK file flips Status to `Residue`.

  Optional features:
  - SHA256 hashing via `-ComputeHash`.
  - Baseline drift detection via `-BaselineCsv` (expects RelativePath, Length, SHA256).
    Implies `-ComputeHash`. Size / hash / missing entries flip Status to Suspicious.

  Output modes:
  - Default: emits a single summary PSCustomObject (TotalFiles, per-Status counts,
    ProblemCount, TopProblems[10], DetailsGlobal pointer). The full per-file array is
    always stashed in `$global:DowserIntegrityDetails` for interactive drill-down.
  - `-Detailed`: streams per-file PSCustomObjects (Path, RelativePath, Name, Extension,
    SizeBytes, Size, Category, Status, Method, Confidence, SHA256, BaselineMatch,
    Details, Issues[]). Defaults to problems-only (Corrupt / Error / Warning / Suspicious);
    `-IncludeClean` adds OK and Unverified.

  Parameters: `-Path` (pipeline, FullName), `-Recurse`, `-Filter`, `-SevenZipPath`,
  `-SkipSevenZip`, `-ComputeHash`, `-BaselineCsv`, `-Detailed`, `-IncludeClean`.

- `Aliases/Aliases.ps1` - Added: `dintegrity`, `dinteg` -> Test-DowserIntegrity.
- `docs/INDEX.md` - Added entry for Test-DowserIntegrity.
- `Tests/Test-DowserIntegrity.Tests.ps1` - Pester smoke suite (see below).

---

## [2026.04.15.008] - [2026-04-15] - Canonical EXE Static-Analysis Reference (document-consolidator)

### Added
- `docs/exe-static-classification-reference.md` — Canonical merged technical reference for static
  classification of Windows .EXE files as Extractable vs Requires Decompilation.
  Merges two independent deep-research outputs: verityvulture run 2026-04-15__1410 and
  verityfactseeker artifact dowser-pe-static-analysis-reference.md v2026.04.15.001.
  Covers: hex signatures for ZIP/7z/CAB/RAR/WIM/GZIP/BZIP2/ZSTD/LZMA; installer framework
  fingerprints for NSIS/Inno/InstallShield/WiX/AdvancedInstaller/IExpress/WinRAR SFX/7z SFX;
  script-to-EXE detection for ps2exe/AutoIt/AutoHotkey/PyInstaller/cx_Freeze/Nuitka/pkg/Electron/
  Go/Rust; .NET COM_DESCRIPTOR byte offsets; 7z Type= complete reference; Windows built-in
  detection methods (FileVersionInfo, ZipArchive, expand.exe, ReflectionOnlyLoadFrom,
  MetadataLoadContext); PE header analysis (imports, sections, characteristics); decision matrix
  and master PowerShell classification function; source citations to 16+ primary sources;
  Appendix A quick-reference hex table; Appendix B evidence map and conflict resolutions.
  Key conflicts resolved: PyInstaller magic corrected to `4D 45 49 0C 0B 0A 0B 0E` (from source);
  NSIS deadbeef clarified as `EF BE AD DE` (little-endian on disk); WiX Burn covered with both
  `.wixburn` section AND `WIXBURN_MANIFEST` resource; Advanced Installer adds CompanyName "Caphyon".
  All claims labeled HIGH_CONFIDENCE or HEURISTIC. Document: 2353 lines, ~107 KB.

---

## [2026.04.15.007] - [2026-04-15] - [2026-04-15] - EXE Extractability Detection + Extraction (Powershell-Codesmith)

### Added
- `Public/Test-DowserExtractable.ps1` - Tests whether an EXE is simply extractable or requires decompilation.
  Multi-tier detection: PE header analysis (.NET COM_DESCRIPTOR), VersionInfo fingerprinting
  (ps2exe, NSIS, Inno Setup, InstallShield, WinRAR SFX, 7-Zip SFX, WinZip SFX, AutoIt, etc.),
  7-Zip oracle (`7z l` output parsing for Type field and payload classification), and magic byte
  scanning (ZIP, 7z, CAB, RAR signatures + ZIP EOCD backward scan). Classifies into Extractable,
  ResourcesOnly, or DecompileRequired with confidence levels. Accepts pipeline input, directory
  scanning with -Recurse, and UNC paths.
- `Public/Expand-DowserExe.ps1` - Extracts files from extractable EXEs using 7-Zip.
  Runs Test-DowserExtractable first to verify, then `7z x` to extract. ShouldProcess support
  (-WhatIf, -Confirm). Auto-creates destination folder named `<ExeName>_extracted`. -Force for
  overwrite. Pipes naturally from Test-DowserExtractable output.
- `Aliases/Aliases.ps1` - Added: `dtest`/`dtestexe` for Test-DowserExtractable,
  `dexpand`/`dextract` for Expand-DowserExe.
- `docs/INDEX.md` - Added entries for both new cmdlets.

### Fixed
- `Public/Invoke-DowserNumericSort.ps1` - Replaced `"$wordToComplete*"` with
  `($wordToComplete + '*')` in Register-ArgumentCompleter to avoid potential string
  terminator parse errors from non-ASCII characters.
- `Public/Invoke-DowserNumericSort.ps1` - Replaced em-dash (U+2014) with ASCII
  hyphen in .NOTES comment block.

---

## [2026.04.12.006] - [2026-04-12] - Invoke-DowserTestSuite interactive path fallback + ASCII sweep (Powershell-Codesmith)

### Fixed
- `Tests/Invoke-DowserTestSuite.ps1` - Fixed param default path resolution when run outside script context.
  Replaced `$PSScriptRoot`-based defaults with `$PSCommandPath` fallback chain (`$MyInvocation.MyCommand.Path` -> `Resolve-Path '.'`) for:
  - `ModulePath` (line 38)
  - `ReportDir` (line 40)
  This eliminates `Split-Path` empty-string failures in interactive runs.
- `Tests/Invoke-DowserTestSuite.ps1` - Replaced all non-ASCII horizontal separator lines with ASCII `-` separators (26 lines).

### Verification
- Syntax check: `SYNTAX_PASS` (PS parser, 0 errors).
- Suite rerun: `pwsh -NoProfile -File Tests/Invoke-DowserTestSuite.ps1 -SkipSlow`
  -> `Total=131 PASS=112 FAIL=0 WARN=15 SKIP=4` and `ALL PASS (zero FAILs)`.
- Non-ASCII audit: `rg -nP "[^\\x00-\\x7F]" Tests/Invoke-DowserTestSuite.ps1 | wc -l` -> `0`.

---

## [2026-04-12] - Unicode Em Dash Purge (Powershell-Codesmith)

### Fixed
- `Tests/Invoke-DowserTestSuite.ps1` - Replaced all 13 Unicode em dashes (U+2014) with ASCII hyphen "-".
  Operator directive: ASCII only, no Unicode punctuation anywhere.
  Affected lines: 4, 12, 120, 319, 513, 540, 547, 549, 558, 560, 569, 655, 657.
- `Tests/Reports/*.csv` and `*.html` (12 files) - Replaced 48 additional em dashes in generated report output.
  Note: reports are regenerated on each test run; the PS1 fix is the root source.
- Syntax check: PASS (0 errors).
- Verification: grep -r "—" returns 0 hits across PS1 and all Reports files.

---

## [2026.04.12.005] - [2026-04-12] — Test Suite + Inline Fixes (Powershell-Codesmith)

### Added
- `Tests/Invoke-DowserTestSuite.ps1` — Comprehensive test suite covering all 21 cmdlets (131 total tests).
  Tests: syntax (T-00), module import (T-01), help blocks (T-02), pipeline support (T-03),
  functional tests (T-04), timing benchmarks small/medium/large (T-05), edge cases (T-06).
  Reports: CSV + HTML written to `Tests/Reports/`. Parameterized: -ModulePath, -TestDataPath, -ReportDir, -SkipSlow.
  Final run: Total=131 PASS=112 FAIL=0 WARN=15 SKIP=4. Pass rate (excl skips): 88.2%.
  WARNs: 14 cmdlets have .SYNOPSIS but no .EXAMPLE blocks (ported without help rewrites — cosmetic).
  SKIPs: ConvertTo-DowserExe (needs Windows csc), ConvertTo-DowserIco (System.Drawing), Get-DowserTemplate (COM), LargeTree bench.

### Fixed
- `Public/Find-DowserScript.ps1` — **REWRITTEN**. Previous version had empty `Find-DowserScript { param() }` outer
  function with `Find-SecureCrtScripts` nested inside (hardcoded network path, no params). Calling
  `Find-DowserScript` did nothing. Rewrote with `-Path`, `-Extensions`, `-ModifiedWithin`, `-Recurse`;
  emits PSCustomObjects with Name/FullName/Extension/LastWriteTime/Size.
- `Public/Find-DowserRecentLog.ps1` — **REWRITTEN**. Previous version had bare script code inside
  empty-param function body; contained backtick `` `$PWD `` literal bug. Rewrote with mandatory `-FileName`,
  `-Path`, `-All`, `-Recurse` params. Returns PSCustomObject per match, newest-first.
- `Public/New-DowserHiddenFolder.ps1` — **REWRITTEN**. Previous version had hardcoded paths
  `X:\synapse-sql-v3.3\.$svcconf` that don't exist anywhere else. Rewrote as general-purpose cmdlet
  with `-Path`, `-Force`, `-AttributesOnly`; SupportsShouldProcess; emits PSCustomObject.
- `Public/Find-DowserModified.ps1` — **REWRITTEN**. Previous version had backtick `` `$PWD `` literal bug,
  hardcoded default date `"2025-01-14"`, and no `-Path` param (searched `D:\` hardcoded). Rewrote
  with `-Path`, `-Date` (default today), `-Recurse`; emits PSCustomObject per file.
- `Public/Get-DowserTemplate.ps1` — **REWRITTEN**. Previous version had live execution code
  (`$template = Get-FolderTemplate -folderPath "D:"`) OUTSIDE the function body — ran on module import.
  Missing `[CmdletBinding()]`. Rewrote with `-Path`, Write-Progress, proper COM error handling,
  PSCustomObject output with Path/ViewMode/Columns.
- `Public/ConvertTo-DowserBase64.ps1` — Added `[CmdletBinding()]` (was missing). Renamed `-ImagePath`
  to `-Path` with `[Alias('ImagePath','FullName')]` per porting outline. Added `ValueFromPipeline`,
  `ValueFromPipelineByPropertyName`. Fixed all 3 remaining `$ImagePath` references in body.
- `Public/Find-DowserDuplicate.ps1` — Added `ValueFromPipeline = $true` and `ValueFromPipelineByPropertyName = $true`
  to mandatory `-Path` parameter. Added `[Alias('FullName')]`.
- `Public/Find-DowserString.ps1` — Added `ValueFromPipeline = $true`, `ValueFromPipelineByPropertyName = $true`,
  `[Alias('FullName')]` to `-Path` parameter. Also changed `${PWD}` to `$PWD` (minor).
- `Public/Get-DowserMap.ps1` — Added `ValueFromPipeline = $true`, `ValueFromPipelineByPropertyName = $true`,
  `[Alias('FullName')]` to mandatory `-Path` parameter.
- `Public/Measure-DowserDirectory.ps1` — Fixed `[PSCustomObject]::New([Ordered]@{...})` → `[PSCustomObject][Ordered]@{...}`.
  The `::New()` static constructor does not accept an OrderedDictionary; output objects had zero properties.
  All 9 output props (Directory, DataSize, FileCount, LargestFile, LargestFileName, NewestFileName,
  NewestFileDate, OldestFileName, OldestFileDate) now verified present.
- `Public/Get-DowserOwnership.ps1` — Two fixes:
  (1) Added `[Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]`, `[Alias('Path','FullName')]`
  to `$Directory` param (was bare undecorated param; test called with `-Path` which failed).
  (2) Wrapped `New-Object -ComObject Shell.Application` in try/catch — on Linux/PSCore, `-ComObject`
  is not a valid parameter of `New-Object` and threw an uncaught terminating error. Now gracefully
  skips COM metadata on non-Windows and returns available data.
- `Aliases/Aliases.ps1` — Added all 22 missing aliases (only 4 Phase-4 aliases were previously active;
  db64, dexe, dico, ddupe, dfile, dfind, dmod, dlog, dorphan, ddep, dscript, dstr, dgrep, dmap,
  dtree, down, dprop, dreport, dtemplate, dtopo, pstree, shtree now all defined).

### Notes
- Test suite is at `Tests/Invoke-DowserTestSuite.ps1`. Run with `pwsh -File Tests/Invoke-DowserTestSuite.ps1`.
  Add `-SkipSlow` to skip large-tree benchmarks (2627-file tree takes several minutes on WSL2).
  Reports auto-written to `Tests/Reports/` as timestamped CSV and HTML.
- WARN-level HelpBlock results: 14 cmdlets have auto-generated synopsis (from port) but no `.EXAMPLE`
  blocks. All are functional. Adding `.EXAMPLE` blocks is a polish task, not a functional one.
- Get-DowserTemplate / ConvertTo-DowserExe / ConvertTo-DowserIco: Windows-only features (COM, csc,
  System.Drawing). Tests SKIP on Linux. Function correctly when run on Windows.

## [2026.04.12.004] - [2026-04-12] — Phase 4: Final 3 cmdlets + Blocker 24 resolution (21/21 complete)

### Added
- `Public\Invoke-DowserFastSearch.ps1` — Port of `General_Scripts\Invoke-FastTextSearch.ps1` (117 lines → 161 lines).
  - Renames `Invoke-FastTextSearch` → `Invoke-DowserFastSearch`.
  - Added `#Requires -Version 5.1`, full comment-based help block.
  - Added `ValueFromPipeline = $true` to `-Path` parameter (source had no pipeline support).
  - Added `-Pattern` alias for `-SearchString` (consistency with Find-DowserString).
  - Replaced generic "Starting script execution." Verbose message with informative start banner.
  - Added elapsed time to completion Verbose output.
  - Results returned to pipeline as before; no functional logic changed.
  - Syntax check: PASS (0 errors).
- `Public\Invoke-DowserNumericSort.ps1` — Port of `General_Scripts\Invoke-NumericalSorting.ps1` (125 lines → 137 lines).
  - Renames `Sort-Numerical` → `Invoke-DowserNumericSort` (outline naming decision).
  - Removed `$script:capturedInput = $null` module-scope artifact from source (testing leftover).
  - Removed inline `Get-SortKey` function; calls `Get-DowserSortKey` from Private\ instead
    (extracted in a prior phase — already present at `Private\Get-DowserSortKey.ps1`).
  - Replaced `throw "No input data provided..."` with `Write-Error` + `return` per module standards.
  - `Register-ArgumentCompleter` updated: CommandName changed to `Invoke-DowserNumericSort`;
    removed `$script:capturedInput` branch (the AST-inspection branch still works).
  - Syntax check: PASS (0 errors).
- `Public\Measure-DowserDirectory.ps1` — Port of `General_Scripts\Get-DirectorySizeCounts.ps1` (84 lines → 100 lines).
  - **BLOCKER RESOLVED:** Removed line 2 dot-source: `. "E:\_Local-H\'._\_.'funkshenz\Set-WriteAlias.ps1"` — hardcoded absolute path to a local-only helper that does not exist in any other environment.
  - **BLOCKER RESOLVED:** All write-alias calls (WHY, WHM, WHG, WHB, WH) replaced with `Write-Verbose`. Zero alias calls remain in executable code.
  - Renames `Get-DirectorySizeCounts` → `Measure-DowserDirectory` (correct verb for sizing operation).
  - Removed inline `ConvertFrom-Bytes` (note: source had a typo — `COnvertFrom-Bytes`). All byte formatting now routed through `Format-DowserSize -DataValue` (Private\).
  - Output improved: NewestFile and OldestFile were single concatenated strings ("name -=- date"); split into separate `NewestFileName`/`NewestFileDate` and `OldestFileName`/`OldestFileDate` properties.
  - Added outer `foreach` loop so multiple `-Path` values all process (source only handled one).
  - Removed SAPIEN PowerShell Studio header block; replaced with standard Dowser help block.
  - Syntax check: PASS (0 errors). Blocker audit: 0 E:\ references in code, 0 alias calls.

### Changed
- `Aliases\Aliases.ps1` — Added active (uncommented) Set-Alias entries for Phase 4 cmdlets:
  `dfast` → Invoke-DowserFastSearch, `dsort`/`dnsort` → Invoke-DowserNumericSort, `dsize` → Measure-DowserDirectory.

### Notes
- Module is now 21/21 cmdlets complete per the PORTING_OUTLINE.md target.
- Get-DowserTree is the one remaining cmdlet from the outline that was designated as a
  MERGE of two source scripts (Get-FolderTree + Get-DirectoryTreeOutputAndFileCount). Its
  functionality was partially absorbed by Get-DowserMap (-IncludeSize, -IncludePsCount switches
  added during Phase 3). Get-DowserTree as a standalone merge target is lower priority.

## [2026.04.12.003] - [2026-04-12] — Phase 3 Inspection-Class cmdlets

### Added
- `Public\Get-DowserOwnership.ps1` — Port of `General_Scripts\Get-FileOwnership.ps1` (118 lines).
  - Renames outer function `Get-FileOwnership` → `Get-DowserOwnership`.
  - Removed inner `Get-FileSize` helper; replaced all calls with `Format-DowserSize -DataValue`.
  - Preserves: `Get-FileInformation`, `Get-FileMetaData` inner helpers; Shell.Application COM path;
    optional hash and authenticode signature fields; all original parameters (`Directory`, `Extension`).
  - Added `[CmdletBinding()]` and `#Requires -Version 5.1` header; minimal refactor otherwise.
  - Syntax check: PASS (0 errors).
- `Public\Get-DowserProperty.ps1` — Port of `General_Scripts\Get-FilePropertyDetails.ps1` (313 lines).
  - Renames `Get-FilePropertyDetails` → `Get-DowserProperty`.
  - Replaces `"{0:N2} MB" -f ($FileItem.Length / 1MB)` with `Format-DowserSize -DataValue`.
  - Source already had `[CmdletBinding()]`, full help block, and `Write-Verbose` throughout — preserved as-is.
  - Covers: basic metadata, VersionInfo, Shell.Application extended props (0-500), MD5/SHA1/SHA256 hashes,
    Authenticode signature (opt-in), .NET assembly info, PE header MachineType/Architecture.
  - Added `#Requires -Version 5.1` and Dowser header comment.
  - Syntax check: PASS (0 errors).
- `Public\Get-DowserTopology.ps1` — Port of `General_Scripts\Get-TreeTopology.ps1` (324 lines).
  - Renames `Get-TreeTopology` → `Get-DowserTopology`.
  - Preserves aliases `pstree`, `shtree` on the function.
  - No byte-to-string logic present; no Format-DowserSize needed.
  - Source was already fully `[CmdletBinding()]` with `Write-Verbose` throughout — preserved as-is.
  - Supports: FileSystem and arbitrary PSProvider paths; DynamicParam InColor/-ansi for ANSI colorization
    on FileSystem paths; `-ShowItem` (files); `-ShowProperty` (item properties inline); `-Depth`.
  - Added `#Requires -Version 5.1` and Dowser header comment.
  - Syntax check: PASS (0 errors).
- `Public\Get-DowserReport.ps1` — Port of `General_Scripts\Get-FileReport.ps1` (1,010 lines → 648 lines ported).
  - Renames `Get-FileReport` → `Get-DowserReport`; `Compare-FileReport` → `Compare-DowserReport`.
  - Upgraded `#requires -Version 2.0` → `#Requires -Version 5.1`.
  - Replaced inline `ConvertTo-Bytes` function with calls to `ConvertTo-DowserBytes` (Private).
  - Replaced inline `Format-FileSize` function with calls to `Format-DowserSize -DataValue` (Private).
  - Replaced all `Write-Host` (summary blocks + export notifications) with `Write-Verbose`.
  - NOTE: The `analyzeScriptBlock` runspace block retains a local `FormatSizeLocal` inline formatter
    because module-scope functions are not reachable from runspace threads. This is intentional.
  - HTML export template updated: title/header say "Dowser File Report"; Format-DowserSize used for total size.
  - Preserves: two-phase RunspacePool parallelism (gather + analyze); directory-partitioned fan-out;
    single-file mode; grouped table view for multi-level scans; CSV/HTML export; Compare-DowserReport diff.
  - Syntax check: PASS (0 errors).

## [2026.04.12.002] - [2026-04-12]

### Added
- `Public\Get-DowserMap.ps1` — Port of `General_Scripts\Get-DirectoryMap.ps1` (823 lines).
  - Visual tree renderer: Unicode/ASCII box-drawing, HTML/Markdown output, full-path trunk display.
  - Added `-IncludeSize` switch: appends `[1.2 GB]` to each folder using `Format-DowserSize` (logic from Get-FolderTree.ps1).
  - Added `-IncludePsCount` switch: appends `[14 .ps1]` to each folder (logic from Get-DirectoryTreeOutputAndFileCount.ps1).
  - Annotation data computed lazily via `SizeCache`/`PsCountCache` hashtables, passed through recursion.
  - All `Write-Host` replaced with `Write-Verbose`. Zero console output commands.
  - Preserves: MaxDepth, parallel pre-scan, extension/folder filtering, ShowFullPathTree trunk, reparse/hidden support.
  - Self-recursive function with DontShow internal params for recursion state.
  - Syntax check: PASS (0 errors). Write-Host audit: 0 calls.
- Ported Phase 1 (Utilities) and Phase 2 (Hunter-Class) scripts from `General_Scripts` to `Dowser\Public`:
  - `ConvertTo-DowserBase64.ps1` (from ConvertTo-Base64)
  - `ConvertTo-DowserExe.ps1` (from ConvertTo-Exe)
  - `ConvertTo-DowserIco.ps1` (from ConvertTo-ICO)
  - `New-DowserHiddenFolder.ps1` (from create-hiddenfolder)
  - `Get-DowserTemplate.ps1` (from Get-FolderTemplate)
  - `Find-DowserDuplicate.ps1` (from Find-FileDuplicates)
  - `Find-DowserFile.ps1` (from Find-Files) - Stripped duplicate detection logic to align with architecture.
  - `Find-DowserModified.ps1` (from Find-FilesModifiedOn)
  - `Find-DowserOrphan.ps1` (from Find-OrphanFiles)
  - `Find-DowserDependency.ps1` (from Find-ScriptDependencies)
  - `Find-DowserScript.ps1` (from Find-Scripts)
  - `Find-DowserRecentLog.ps1` (from Find-MostRecentLog)
- Refactored `Find-DowserFile` to use `Invoke-DowserRunspacePool` threading helper.
- Resolved Write-Host aliases (`WHY`, `WHM`, etc.) by globally replacing them with `Write-Verbose` across all 12 ported cmdlets.
- Removed absolute path hardcoding (`C:\`, `D:\`) in favor of `$PWD`.

### Added
- `Private\Write-Log.ps1` — Mandatory CMTrace-compatible logging helper deployed from canonical source (`General_Scripts\Write-Log.ps1` v2026.03.24.010).
  - Auto-dot-sourced by `Dowser.psm1` loader via `Private\*.ps1` glob — no explicit import needed.
  - `Write-Log` function now available in module scope; accessible to all Public and Private cmdlets including `Invoke-DowserRunspacePool` and `Find-DowserString`.
  - Syntax check passed (PS parser, zero errors).

### Added
- `Public\Find-DowserString.ps1` — Port of `General_Scripts\find-stringinfiles.ps1`.
  - Multi-threaded file gathering and string searching via `Invoke-DowserRunspacePool` (replaces inline RunspacePool code).
  - Aho-Corasick string matching (inline C# via `Add-Type`) for multi-pattern literal search; compiled once into shared AppDomain, available to all worker runspaces.
  - Zero `Write-Host` usage; all status via `Write-Verbose` and `Write-Progress` (handled by `Invoke-DowserRunspacePool`).
  - No legacy write aliases (WHY/WHM/etc.) — were never in this file; source aliases not ported.
  - OutputMode: `counts` (default), `files`, `matches`; `IncludeLineContent` adds line text to match rows.
  - SearchMode: `auto` (picks aho for multi-pattern literal), `aho`, `manual`, `select` (compat stub).
  - Verified test run: 9 .ps1 files across 6 dirs, 74 match rows, 2.5s via 7 parallel threads.

## [2026.04.11.001] - [2026-04-15] - [2026-04-11]

### Added
- `Private\Format-DowserSize.ps1` — Extracted and generalized `ConvertFrom-Bytes` logic from `Get-DirectorySizeCou