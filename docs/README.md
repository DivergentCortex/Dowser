# Dowser

Filesystem recon and inspection module for PowerShell. Point it at a path and get answers: what is there, what is duplicated, what is orphaned, what changed, what depends on what, who owns it, how big it is, and whether files are corrupt. This is a tracker's kit, not a mover's kit -- it reads and reports, it does not move your files (the only writers are ConvertTo-DowserExe, ConvertTo-DowserIco, New-DowserHiddenFolder, and Expand-DowserExe).

Runs on Windows PowerShell 5.1 and PowerShell 7+ (Windows, Linux, macOS). Functions that depend on Windows-only facilities degrade or warn rather than crash on Linux/macOS; see [Platform support](#platform-support).

## Install

```powershell
# Import from a local clone
Import-Module ./Dowser/Dowser.psd1 -Force

# Confirm the exported surface (27 functions plus aliases)
Get-Command -Module Dowser
```

No external dependencies on Windows. On Linux/macOS the archive functions need `7z` on PATH (install p7zip-full or the equivalent for your distro).

## Quick start

```powershell
# Search for a string across a directory tree
Find-DowserString -Path ~/projects -Pattern "TODO"

# Find duplicate files
Find-DowserDuplicate -Path ./src

# Map a directory tree with sizes
Get-DowserMap -Path . -IncludeSize

# Find what is eating your disk (ranked rollup + HTML treemap)
Measure-DowserDiskUsage -Path . -ExportHtml ./diskusage.html

# Check file integrity in a release package
Test-DowserIntegrity -Path ./release -Recurse

# Generate a file metrics report with CSV export
Get-DowserReport -Path ./src -ExportCsv ./report.csv
```

## Exported functions

27 exported functions. 26 live one-per-file in `Public/`; the 27th, `Compare-DowserReport`, is dot-sourced from `Public/Get-DowserReport.ps1` and exported by name. Each carries one or more short aliases for interactive use.

| Function | Alias | Purpose |
|----------|-------|---------|
| ConvertTo-DowserBase64 | db64 | Convert images to/from Base64 strings |
| ConvertTo-DowserExe | dexe | Generate a C# EXE wrapper for a PS script (Windows) |
| ConvertTo-DowserIco | dico | Create .ico files from images (Windows) |
| Expand-DowserExe | dexpand, dextract | Extract files from extractable EXE archives via 7-Zip |
| Find-DowserDependency | ddep | Scan PS scripts for function calls and dot-source deps |
| Find-DowserDuplicate | ddupe | Detect duplicate files by name, size, or chunked hash |
| Find-DowserFile | dfile, dfind | Multi-threaded file search by attributes, size, date |
| Find-DowserModified | dmod | Find files modified on a specific date |
| Find-DowserOrphan | dorphan | Find unreferenced files in a project directory |
| Find-DowserRecentLog | dlog | Return the most recent log file from a directory |
| Find-DowserScript | dscript | Search directory trees for script files by type |
| Find-DowserString | dstr, dgrep | Multi-pattern text search with Aho-Corasick matching |
| Get-DowserInfo | -- | Report module version and latest changelog entry |
| Get-DowserMap | dmap | Visual directory tree with optional size/PS1 annotations |
| Get-DowserOwnership | down | File ownership and Shell.Application metadata |
| Get-DowserProperty | dprop | Deep single-file inspector (VersionInfo, PE, hashes) |
| Get-DowserReport | dreport | File metrics report with parallel processing and export |
| Get-DowserTemplate | dtemplate | Windows Explorer folder template configs (Windows) |
| Get-DowserTopology | dtree, dtopo, pstree, shtree | Visual tree for any PSProvider path |
| Invoke-DowserFastSearch | dfast | Parallel single-pattern text search |
| Invoke-DowserNumericSort | dsort, dnsort | Natural numeric sort (Item-2 before Item-10) |
| Measure-DowserDirectory | dsize | Directory size and file count summary |
| Measure-DowserDiskUsage | ddu | WinDirStat-style recursive disk-usage report with HTML treemap |
| New-DowserHiddenFolder | -- | Hide a directory: NTFS Hidden+System on Windows, leading-dot rename on Linux/macOS |
| Test-DowserExtractable | dtest, dtestexe | Classify EXEs as extractable vs decompile-required |
| Test-DowserIntegrity | dintegrity, dinteg | Layered corruption and hygiene detection |
| Compare-DowserReport | -- | Diff two Get-DowserReport snapshots (NEW/CHANGED/REMOVED/UNCHANGED) |

`Compare-DowserReport` ships inside `Public/Get-DowserReport.ps1` and diffs two `Get-DowserReport` snapshots. Because it shares a file with `Get-DowserReport` it has no Public/ basename of its own, so the loader exports it by name (`Export-ModuleMember` adds it explicitly) and the manifest's `FunctionsToExport` lists it. It is a normal exported public function.

## Platform support

All functions run on Windows PowerShell 5.1 and PowerShell 7+. On Linux/macOS (PowerShell 7+ only -- 5.1 is Windows-only), behavior splits three ways:

- **Windows-only** -- emit a warning and return without producing output: ConvertTo-DowserIco, ConvertTo-DowserExe, Get-DowserTemplate. These require System.Drawing/GDI+, the C# compiler, or Shell.Application COM.
- **Reduced** -- run and return results, minus the Windows-only enrichments (Shell.Application extended metadata, expand.exe CAB handling): Get-DowserProperty, Test-DowserExtractable, Expand-DowserExe, Test-DowserIntegrity. The archive functions need `7z` on PATH.
- **Full cross-platform** -- identical or platform-equivalent behavior on every supported platform: everything else, including Get-DowserOwnership (returns Owner/Group/UnixMode plus a PlatformNote on Linux/macOS; the extended Shell.Application metadata is the Windows-only enrichment) and New-DowserHiddenFolder (NTFS Hidden+System on Windows, leading-dot rename on Linux/macOS).

Platform detection happens at module load. PowerShell 5.1 lacks the `$IsWindows`/`$IsLinux`/`$IsMacOS` automatic variables, so the loader defines them (5.1 only runs on Windows, so it sets `$IsWindows = $true`). On PowerShell 7+, the engine's own automatic variables drive the guards.

## Naming convention

All exports follow `Verb-DowserNoun` with approved PowerShell verbs and singular nouns. Aliases carry the short-form personality; cmdlets stay boring and compliant. All aliases are defined in `Aliases/Aliases.ps1`.

## Project layout

```
Dowser.psd1            Module manifest (v0.2.0)
Dowser.psm1            Loader: dot-sources Private, Public, Aliases
Public/                Exported functions, one per file (26 files; Get-DowserReport.ps1 also holds Compare-DowserReport)
Private/               Internal helpers (6 files), not exported
Aliases/Aliases.ps1    All alias definitions
Tests/                 Pester suites and test runner
docs/                  Project documentation
```

## Further reading

- [ARCHITECTURE.md](ARCHITECTURE.md) -- component design, data flow, design decisions
- [INDEX.md](INDEX.md) -- per-function inventory with inputs, outputs, and relationships
- [CHANGELOG.md](CHANGELOG.md) -- full change history
- [exe-static-classification-reference.md](exe-static-classification-reference.md) -- EXE static-analysis reference for Test-DowserExtractable
