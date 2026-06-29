# Dowser Architecture

## What it is

Dowser is a PowerShell module that consolidates filesystem recon and inspection tools into one importable kit. It answers questions about directory trees: what exists, what is duplicated, what is orphaned, what changed, what depends on what, who owns files, how large things are, and whether files are corrupt. It does not move or modify files (with the narrow exceptions of ConvertTo-DowserExe, ConvertTo-DowserIco, New-DowserHiddenFolder, and Expand-DowserExe).

The module originated as a port of 22 standalone scripts into a single cohesive module with consistent naming, pipeline support, and shared infrastructure.

## Module structure

```
Dowser.psd1  -->  Dowser.psm1
                    |
                    +-- Private/*.ps1    (6 helpers, not exported)
                    +-- Public/*.ps1     (26 files, one function each, exported)
                    +-- Aliases/Aliases.ps1  (Set-Alias calls, sourced last)
```

The manifest (psd1) points to the root module (psm1). The loader dot-sources Private first (so helpers are available to Public functions), then Public, then Aliases. `Export-ModuleMember` exports the 26 Public/ basenames plus `Compare-DowserReport` (the 27th public function, which lives inside Get-DowserReport.ps1 and so is named explicitly), plus all aliases. The manifest's `FunctionsToExport` is an explicit 27-name list, not a wildcard.

One function per file in Public. This keeps diffs clean, prevents agents from stomping each other's work, and makes `Get-ChildItem Public` read like a table of contents.

## Component layers

### Private helpers (not exported)

| File | Purpose |
|------|---------|
| ConvertTo-DowserBytes.ps1 | Converts human-readable size strings (e.g., "1.5GB") to byte counts |
| Format-DowserSize.ps1 | Formats byte counts into human-readable strings (e.g., "1.5 GB") |
| Get-DowserSortKey.ps1 | Generates sort keys for natural numeric ordering |
| Invoke-DowserRunspacePool.ps1 | Generic RunspacePool executor used by Find-DowserFile, Find-DowserString, Get-DowserMap, Get-DowserReport |
| Test-DowserHelpers.ps1 | Validation helpers shared across test functions |
| Write-Log.ps1 | CMTrace-compatible logging with file output and rotation |

### Public functions (exported)

Functions fall into five verb buckets:

- **Find-Dowser***: Hunt for things (duplicates, strings, orphans, dependencies, scripts, files, recent logs). These are search operations that locate items matching criteria.
- **Get-Dowser***: Inspect and report (directory maps, file properties, ownership, topology, reports, module info, folder templates). These read and describe what exists.
- **Measure-Dowser***: Count and size (directory measurement).
- **ConvertTo-Dowser***: Transform (Base64 encoding, EXE compilation, ICO creation).
- **Invoke-Dowser***: Actions (fast text search, numeric sorting).
- **Test-Dowser***: Validation (EXE extractability classification, file integrity/corruption detection).
- **Expand-Dowser***: Extraction (EXE archive extraction via 7-Zip).
- **New-Dowser***: Creation (hidden folder attribute setting).

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

**No Write-Host in public functions.** All user-facing output uses Write-Verbose, Write-Warning, Write-Information, or Write-Progress. This keeps function output streams clean for pipeline consumers. Find-DowserString uses `Write-Information -InformationAction Continue` for phase banners so users see progress without polluting the output stream.

**Pattern parameters auto-wrap.** Bare strings passed to `-Pattern` or `-Filter` parameters that lack wildcard characters get wrapped in `*...*` before being passed to `Get-ChildItem -Filter`. This prevents the silent "zero results" failure when users pass a substring expecting a contains-match but the underlying API requires exact wildcard syntax.

**Switch vs Bool for defaults-true.** PowerShell `[switch]` parameters ignore `= $true` defaults. Parameters that should default to true (like `-Recurse` on search functions and `-UseRunspaces` on parallel functions) use `[bool]$Param = $true` instead of `[switch]`.

**Tilde path resolution.** All functions that pass paths to .NET static methods (System.IO.File, System.IO.Directory, System.IO.Path) resolve PowerShell tilde paths first using `Resolve-Path` or `GetUnresolvedProviderPathFromPSPath`. .NET methods do not expand `~`.

## Naming law

`Verb-DowserNoun`. Approved verbs only (the output of `Get-Verb` is the whitelist). Singular nouns. The `Dowser` prefix on the noun ensures tab-completion on `-Dowser` surfaces the entire module. Aliases carry the personality; cmdlets stay boring and compliant.

## Further reading

- [README.md](README.md) -- install, quick start, function table
- [INDEX.md](INDEX.md) -- per-function inventory with parameters, outputs, and relationships
- [CHANGELOG.md](CHANGELOG.md) -- full change history
- [exe-static-classification-reference.md](exe-static-classification-reference.md) -- canonical reference for EXE static classification logic
