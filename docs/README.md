# Dowser

Filesystem recon and inspection module for PowerShell. Point it at a path, get answers: what is there, what is duplicated, what is orphaned, what changed, what depends on what, who owns it, how big it is, and whether files are corrupt. This is a tracker's kit, not a mover's kit.

Runs on Windows PowerShell 5.1 and pwsh 7+ (Windows, Linux, macOS).

## Install

```powershell
# Import from local clone
Import-Module /path/to/Dowser/Dowser.psd1 -Force

# Verify loaded functions
Get-Command -Module Dowser
```

## Quick start

```powershell
# Search for a string across a directory tree
Find-DowserString -Path ~/projects -Pattern "TODO"

# Find duplicate files
Find-DowserDuplicate -Path ./src

# Map a directory tree with sizes
Get-DowserMap -Path . -IncludeSize

# Check file integrity in a source package
Test-DowserIntegrity -Path ./release -Recurse

# Get a file metrics report with CSV export
Get-DowserReport -Path ./src -ExportCsv ./report.csv
```

## Exported functions

| Function | Alias | Purpose |
|----------|-------|---------|
| ConvertTo-DowserBase64 | db64 | Convert images to/from Base64 strings |
| ConvertTo-DowserExe | dexe | Generate C# EXE wrapper for a PS script (Windows) |
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
| New-DowserHiddenFolder | -- | Set Hidden+System attributes on a directory |
| Test-DowserExtractable | dtest, dtestexe | Classify EXEs as extractable vs decompile-required |
| Test-DowserIntegrity | dintegrity, dinteg | Layered corruption and hygiene detection |

Compare-DowserReport is bundled in Get-DowserReport.ps1 and diffs two report snapshots.

## Platform support

All functions work on Windows. On Linux/macOS:

- **Windows-only** (emit warning, return null): ConvertTo-DowserIco, ConvertTo-DowserExe, Get-DowserTemplate
- **Degraded** (partial results without COM metadata): Get-DowserProperty, Get-DowserOwnership, Test-DowserExtractable, Expand-DowserExe, Test-DowserIntegrity
- **Full cross-platform**: everything else

Linux/macOS users who need archive functions should install 7z (p7zip-full or equivalent).

## Naming convention

All exports follow `Verb-DowserNoun` with approved PowerShell verbs and singular nouns. Aliases carry the short-form personality; cmdlets stay boring and compliant. All aliases are defined in `Aliases/Aliases.ps1`.

## Project layout

```
Dowser.psd1            Module manifest (v0.2.0)
Dowser.psm1            Loader: dot-sources Private, Public, Aliases
Public/                One exported function per file (25 files)
Private/               Internal helpers (6 files), not exported
Aliases/Aliases.ps1    All alias definitions
Tests/                 Test suite and reports
docs/                  Project documentation
resources/             Bundled tools (exeinfope)
```

## Further reading

- [ARCHITECTURE.md](ARCHITECTURE.md) -- component design, data flow, design decisions
- [INDEX.md](INDEX.md) -- per-function inventory with inputs, outputs, and relationships
- [CHANGELOG.md](CHANGELOG.md) -- full change history
- [exe-static-classification-reference.md](exe-static-classification-reference.md) -- EXE static analysis reference for Test-DowserExtractable
