# Dowser Architecture

## What it is

Dowser is a PowerShell module that consolidates filesystem recon and inspection tools into one importable kit. It answers questions about directory trees: what exists, what is duplicated, what is orphaned, what changed, what depends on what, who owns files, how large things are, and whether files are corrupt. It does not move or modify files (with the narrow exceptions of ConvertTo-DowserExe, ConvertTo-DowserIco, New-DowserHiddenFolder, and Expand-DowserExe).

The module originated as a port of 22 standalone scripts into a single cohesive module with consistent naming, pipeline support, and shared infrastructure.

## Module structure

```
Dowser.psd1  -->  Dowser.psm1
                    |
                    +-- Private/*.ps1    (35 helpers, not exported)
                    +-- Public/*.ps1     (35 files, one function each, exported)
                    +-- Aliases/Aliases.ps1  ($DowserAliasMap + Enable-DowserAliases, opt-in, sourced last)
```

The manifest (psd1) points to the root module (psm1). The loader dot-sources Private first (so helpers are available to Public functions), then Public, then Aliases. `Export-ModuleMember` exports the 35 Public/ basenames plus `Compare-DowserReport` and `Enable-DowserAliases` (neither has a Public/ basename, so both are named explicitly), plus all aliases. The manifest's `FunctionsToExport` is an explicit 37-name list, not a wildcard.

Logging is `DivergentCortex.Witness`, imported first by Dowser.psm1 from `Modules/DivergentCortex.Witness`, a copy of the module committed with the repo so a clone needs nothing else installed. Only its runtime files are kept: the manifest, loader, Public, Private, config and LICENSE. The loader points Witness at `logs/dowser.module_YYYYMMDD.log` before any helper is dot-sourced, so every function calls `Write-Log` directly.

One function per file in Public. This keeps diffs clean, prevents agents from stomping each other's work, and makes `Get-ChildItem Public` read like a table of contents.

## Component layers

### Private helpers (not exported)

| File                          | Purpose                                                                                                   |
| ----------------------------- | --------------------------------------------------------------------------------------------------------- |
| ConvertTo-DowserBytes.ps1     | Converts human-readable size strings (e.g., "1.5GB") to byte counts                                       |
| Export-DowserDuplicateHtml.ps1 | Renders the expandable duplicate-set HTML report for Find-DowserDuplicate's -ExportHtml                  |
| Format-DowserAge.ps1          | Renders elapsed time as "Nm/Nh/Nd ago" for Measure-DowserDirectory's freshness columns; $null blanks, future timestamps read "in future" |
| Format-DowserSize.ps1         | Formats byte counts into human-readable strings (e.g., "1.5 GB")                                          |
| Get-DowserJsonDiagnosis.ps1   | Probes a JSON/JSONL file and classifies it (valid JSON, valid JSONL, comment-bearing, RECORD banner, tagged transcript, parser error) for Test-DowserJson and Repair-DowserJson |
| Get-DowserSortKey.ps1         | Generates sort keys for natural numeric ordering                                                          |
| Invoke-DowserJsonKeyScan.ps1  | Bounded MTA runspace coordinator for JSON directory scans                                                  |
| Invoke-DowserJsonKeyWorker.ps1 | Queue-consuming JSON scan worker                                                                          |
| Invoke-DowserJsonRepairScan.ps1 | Bounded MTA runspace coordinator that dispatches Invoke-DowserJsonRepairWorker across a repair task queue |
| Invoke-DowserJsonRepairWorker.ps1 | Queue-consuming repair worker: moves unrepairable sources to a triage folder, calls Write-DowserJsonRepair for the rest |
| Invoke-DowserRunspacePool.ps1 | Generic RunspacePool executor used by Find-DowserFile, Find-DowserString, Get-DowserMap, Get-DowserReport |
| Invoke-DowserTransferPool.ps1 | Builds the shared transfer runspace pool and dispatches Invoke-DowserTransferWorker across it              |
| Invoke-DowserTransferWorker.ps1 | Runspace worker: hash-copy-hash-verify for one transfer item, logs through $Sync.LogQueue                 |
| Measure-DowserFileSet.ps1     | Single-pass size/count/largest/newest/oldest/age-bucket math for a file set, used by Measure-DowserDirectory in place of three Sort-Object passes |
| Read-DowserJsonKeyFile.ps1    | Token-streaming JSON and JSONL reader                                                                     |
| Select-DowserUniquePath.ps1   | Deduplicates a path list in O(n), preserving first-seen order                                              |
| Test-DowserHelpers.ps1        | Validation helpers shared across test functions                                                           |
| Write-DowserJsonRepair.ps1    | Writes a diagnosis-approved repaired copy for Repair-DowserJson (RECORD banners, JSON comments)            |
| Get-WindowsErrorCode.ps1      | Maps an exception or HRESULT to a Windows error code; the exit-code vocabulary for cache retention        |
| Get-DowserVersionKey.ps1      | Sort key that orders dotted versions numerically; returns nothing for a version with no numeric order     |
| Get-DowserFilesystemSpace.ps1 | Free and total bytes of the filesystem holding a path (longest mount match on Linux and macOS); shared by Start-DowserTransfer and cache retention |
| Get-DowserRetentionRule.ps1   | Loads and validates Config/CacheRetentionRules.psd1; a rule that fails validation is rejected, never widened |
| Get-DowserInstalledPluginPath.ps1 | Reads the installPath of every plugin in installed_plugins.json                                       |
| Get-DowserProcessReference.ps1 | Reads one /proc/pid folder (cwd, exe, descriptors, maps, cmdline, environ) for strings under given roots, and reports it as a seat when its program name matches |
| Get-DowserProcessStartTime.ps1 | Reads when one Linux process started from /proc/pid/stat                                                  |
| Get-DowserActiveProcessPath.ps1 | Collects the cache paths held by every running process and every running seat with its start time, through Get-DowserProcessReference |
| Get-DowserFolderBirthTime.ps1 | Reads the real birth time of folders with one stat call (.NET reports the earlier of birth and write time on Linux) |
| Get-DowserSeatVersionHold.ps1 | Decides which versions of a plugin the running seats loaded, from seat start times and folder birth times  |
| Get-DowserCacheVersionPlan.ps1 | Lists version folders for a rule and decides Keep or Remove, with the reasons                            |
| Measure-DowserCacheCandidate.ps1 | Sizes one version folder with Measure-DowserFileSet, logging at Verbose, and refuses a result with unreadable paths |
| Remove-DowserCacheVersion.ps1 | Deletes one version folder after re-checking depth under the rule root and that neither it nor its marketplace or plugin folder is a symlink |
| Test-DowserDiskThreshold.ps1  | Checks a DiskThreshold rule against free space                                                            |

Archive-mode rendering for `Get-DowserMap` (auto-detecting a `.zip`/`.7z`/`.rar`/`.tar`/`.gz` `-Path` and rendering its internal contents as a tree) is not in this table: its helpers, `Get-DowserArchiveTreeLines` and `Complete-DowserArchiveMapOutput`, are private functions nested inside `Public/Get-DowserMap.ps1` itself rather than files under `Private/`. See Design decisions below for why, and `docs/INDEX.md`'s Get-DowserMap entry for the feature itself.

### Public functions (exported)

Functions fall into these verb buckets:

- **Find-Dowser\***: Hunt for things (duplicates, strings, orphans, dependencies, scripts, files, recent logs). These are search operations that locate items matching criteria.
- **Get-Dowser\***: Inspect and report (directory maps, file properties, ownership, topology, reports, module info, folder templates, JSON key paths).
- **Compare-Dowser\***: Diff two prior results (Get-DowserReport snapshots).
- **Measure-Dowser\***: Count and size (directory measurement).
- **ConvertTo-Dowser\***: Transform (Base64 encoding, EXE compilation, ICO creation).
- **Export-Dowser\***: Write derived reports without touching the source (JSON values to CSV, JSON directory assessment to CSV).
- **Invoke-Dowser\***: Actions (fast text search, numeric sorting).
- **Test-Dowser\***: Validation (EXE extractability classification, file integrity/corruption detection, JSON/JSONL diagnosis).
- **Repair-Dowser\***: Deterministic, diagnosis-gated fixes (JSON RECORD banners and comments).
- **Expand-Dowser\***: Extraction (EXE archive extraction via 7-Zip).
- **New-Dowser\***: Creation (hidden folder attribute setting).
- **Start-Dowser\***: Begin a tracked, hash-verified operation (file/directory transfer to a destination).
- **Remove-Dowser\***: Deletion gated on prior verification (source cleanup after a verified transfer; never runs as a side effect of Start-Dowser\*).
- **Enable-Dowser\***: Opt-in session setup (brandless alias registration).

`Get-DowserJsonKey` and `Export-DowserJsonCsv` use `Newtonsoft.Json.JsonTextReader` over a file stream. Each JSON reader processes one token at a time. Directory scans use a dedicated MTA runspace pool with a synchronized pending-path queue and a default maximum of eight readers. Workers return results and log messages through synchronized queues; the caller emits logs and progress, preserving a bounded memory and output model.

### Alias layer

All aliases live in `Aliases/Aliases.ps1`. No aliases are defined inside function files. This single-file approach makes the alias surface auditable at a glance. Aliases are short-form (`dmap`, `dgrep`, `ddupe`) while cmdlets use the full `Verb-DowserNoun` pattern.

## Parallelism model

Several functions use RunspacePool-based parallelism for performance on large directory trees:

- **Invoke-DowserRunspacePool** (Private) is the shared executor. It handles pool creation, job dispatch, progress reporting via Write-Progress, and result collection. Functions pass scriptblocks and argument lists; the helper manages the threading lifecycle.
- **Find-DowserString** uses a three-phase model: (1) streaming directory enumeration via `[System.IO.Directory]::EnumerateDirectories`, (2) parallel file gathering, (3) parallel string searching with compiled Aho-Corasick matching for multi-pattern literal search.
- **Get-DowserReport** uses a two-phase RunspacePool: gather files in parallel, then analyze metrics in parallel.
- **Find-DowserFile** and **Get-DowserMap** use the RunspacePool for parallel directory scanning.

Worker runspaces do not have access to module-scope functions. Functions that need formatting inside runspace scriptblocks include local copies of the formatter (e.g., Get-DowserReport includes a local `FormatSizeLocal` function in its scriptblock).

## Platform support model

The module targets Windows PowerShell 5.1 and pwsh 7+ on Windows, Linux, and macOS.

Platform detection happens at module load time in Dowser.psm1. On PS 5.1 (which lacks the `$IsWindows`, `$IsLinux`, `$IsMacOS` automatic variables), the loader defines them at module scope. On pwsh 7+, the engine's automatic variables are used directly.

Functions that depend on Windows-only capabilities (COM objects, System.Drawing, csc.exe) have platform guards:

- **Windows-only** (return null with warning on non-Windows): ConvertTo-DowserIco, ConvertTo-DowserExe, Get-DowserTemplate
- **Reduced** (run, but drop the Windows-only COM/expand.exe enrichments): Get-DowserProperty, Test-DowserExtractable, Expand-DowserExe, Test-DowserIntegrity

Get-DowserOwnership and New-DowserHiddenFolder are not in the reduced set: each has a real non-Windows path. Get-DowserOwnership reads Owner/Group/UnixMode from the .NET FileInfo and tags the result with a PlatformNote (only the extended Shell.Application metadata is Windows-only). New-DowserHiddenFolder applies NTFS Hidden+System on Windows and, on Linux/macOS, hides the folder by renaming it with a leading dot (under -AttributesOnly it cannot rename, so it warns rather than silently no-op); the returned object always reflects the real on-disk attributes.

The platform guards key off `$IsWindows -ne $false` rather than a bare `if ($IsWindows)`, because PS 5.1 has `$IsWindows = $null` and the bare test would wrongly take the non-Windows branch on a real Windows host. This idiom covers the Shell.Application COM reads in Get-DowserProperty and Get-DowserOwnership, the Authenticode signature read in Get-DowserProperty, and the hidden-folder attribute path.

Assembly loads that would fail on Linux (System.Drawing in ConvertTo-DowserIco) are inside the function body behind platform guards, not at file scope.

## Design decisions

**One function per file.** Enforced by convention and the loader's `Get-ChildItem Public/*.ps1` pattern. The single exception is Compare-DowserReport, which is bundled in Get-DowserReport.ps1 because it is tightly coupled to Get-DowserReport's output schema. It is still a full public export: the loader names it explicitly in `Export-ModuleMember` since it has no Public/ basename, and the manifest lists it.

**No Write-Host in public functions.** Diagnostics go through `Write-Log` (Witness); data leaves a function as returned objects and long loops report through `Write-Progress`. This keeps function output streams clean for pipeline consumers. Find-DowserString uses `Write-Information -InformationAction Continue` for phase banners so users see progress without polluting the output stream.

**Cache retention is rule-driven and preview-first.** `Invoke-DowserCacheRetention` reads `Config/CacheRetentionRules.psd1`. A VersionedCache rule covers `<Root>/<marketplace>/<plugin>/<version>`; a version is kept when it is the manifest's installPath, is held by a running process (/proc on Linux; a reduced executable-path check elsewhere), is the version a running seat started on, is one of the newest KeepNewest, is a symlink or under a symlinked folder, has no numeric order, or was written inside QuietMinutes. A seat (a running claude or codex process, named by the rule's SeatProcessNames) reads its plugin files into memory and keeps none open, so its version is worked out from its start time against each folder's birth time: the newest version present at that start and the next older one are kept, and a seat or folder whose time cannot be read keeps every version of the plugin. A rule's RootAliases name other spellings of its root that a process may use. If the installed manifest or the process scan cannot be read, the run removes nothing for it. A DiskThreshold rule only reports. Candidates are sized with Measure-DowserFileSet, the statistics Measure-DowserDirectory uses, without calling the public command per folder. Removal is behind `-Remove` and ShouldProcess, and the process scan is repeated just before deleting. `Invoke-DowserScheduledRetention.ps1` at the repository root is the scheduled entry point (one run, one exit code); `deploy/systemd/` carries the unit text and operator install steps. The command is serial because it has no per-item worker pool: the work is a bounded handful of folders sized one at a time, with Write-Progress and an ETA on the sizing and removal loops.

**Pattern parameters auto-wrap.** Bare strings passed to `-Pattern` or `-Filter` parameters that lack wildcard characters get wrapped in `*...*` before being passed to `Get-ChildItem -Filter`. This prevents the silent "zero results" failure when users pass a substring expecting a contains-match but the underlying API requires exact wildcard syntax.

**Default-on switches.** Parameters that should default to true use `[switch]$Param = $true`, preserving normal switch syntax while allowing callers to disable them with `-Param:$false`.

**Tilde path resolution.** All functions that pass paths to .NET static methods (System.IO.File, System.IO.Directory, System.IO.Path) resolve PowerShell tilde paths first using `Resolve-Path` or `GetUnresolvedProviderPathFromPSPath`. .NET methods do not expand `~`.

**Archive-mode rendering lives inside `Get-DowserMap.ps1`, not in `Private/`.** The original design (`docs/superpowers/specs/2026-07-05-archive-map-design.md`) proposed two new Private files, `Get-DowserArchiveEntry.ps1` and `Get-DowserArchiveMap.ps1`. The shipped implementation instead nests `Get-DowserArchiveTreeLines` (entry listing and tree rendering) and `Complete-DowserArchiveMapOutput` (the archive-mode counterpart to `Complete-DirectoryMapOutput`, handling the Summary block and `-OutputFile`/`-MarkdownFile` writing) directly inside `Get-DowserMap`'s own function body. PowerShell does not hoist function definitions ahead of the sequential statement that defines them, and `Complete-DirectoryMapOutput` sits roughly 900 lines below the archive-mode dispatch check that needs a finisher, so a self-contained nested finisher avoids that ordering hazard rather than restructuring the whole file; the cost is some duplicated summary-text and file-writing logic between the two finishers. `-SevenZipPath` is a real, live parameter on `Get-DowserMap`, resolving 7-Zip for `.7z`/`.rar`/`.tar`/`.gz` entries (`.zip` is read natively via `System.IO.Compression.ZipFile`). A filename search for the separate Private files this feature was originally planned to ship as will not find it and will wrongly read as "never built." Check `Get-DowserMap.ps1` itself for `-SevenZipPath` and `Get-DowserArchiveTreeLines` instead. This gap in ARCHITECTURE.md's coverage is what let that wrong conclusion get drawn twice: once as an actual archive-and-revert of the design docs (`docs/CHANGELOG.md` entries recording the 2026-09-09 incident and its same-day reversal), and once as a Synapse ticket that reached review before the false premise was caught on this pass.

## Naming law

`Verb-DowserNoun`. Approved verbs only (the output of `Get-Verb` is the whitelist). Singular nouns. The `Dowser` prefix on the noun ensures tab-completion on `-Dowser` surfaces the entire module. Aliases carry the personality; cmdlets stay boring and compliant.

## Further reading

- [README.md](README.md) -- install, quick start, function table
- [INDEX.md](INDEX.md) -- per-function inventory with parameters, outputs, and relationships
- [CHANGELOG.md](CHANGELOG.md) -- full change history
- [exe-static-classification-reference.md](exe-static-classification-reference.md) -- canonical reference for EXE static classification logic
