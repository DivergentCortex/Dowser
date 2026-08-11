# Dowser

> Every folder is a grave pretending to be a drawer.

Filesystem recon for PowerShell. Point Dowser at a path and it tells you what is actually down there: what is duplicated, what changed, what got orphaned, who owns it, how much space it eats, what depends on what, and whether anything is corrupt. It reads and it reports. It does not move your files. The only four functions that write anything are ConvertTo-DowserExe, ConvertTo-DowserIco, New-DowserHiddenFolder, and Expand-DowserExe.

Runs on Windows PowerShell 5.1 and PowerShell 7+, across Windows, Linux, and macOS. The handful of functions that lean on Windows-only facilities warn and step aside on other platforms instead of crashing. See [Platform support](#platform-support).

## Install

```powershell
Import-Module ./Dowser/Dowser.psd1 -Force
Get-Command -Module Dowser
```

No external dependencies on Windows. On Linux and macOS the archive functions want `7z` on PATH (install p7zip-full or whatever your distro calls it).

## Quick start

```powershell
# what is eating the disk, ranked, with an HTML treemap
Measure-DowserDiskUsage -Path . -ExportHtml ./diskusage.html

# search a whole tree for a string
Find-DowserString -Path ~/projects -Pattern "TODO"

# duplicate files, matched by hash not just name
Find-DowserDuplicate -Path ./src

# render a directory as a tree
Get-DowserMap -Path . -IncludeSize

# corruption and hygiene sweep across a release folder
Test-DowserIntegrity -Path ./release -Recurse

# pull one file apart: version info, PE headers, hashes
Get-DowserProperty -Path ./bin/app.exe

# compare the fields present across a JSON or JSONL export
Get-DowserJsonKey -Path ./exports -Compare

# write nested scalar values to an Excel-compatible CSV
Export-DowserJsonCsv -Path ./exports/events.jsonl -OutputPath ./events.csv
```

## What it does

Twenty-nine functions, grouped by the question they answer.

**Find things.** `Find-DowserFile` is a multi-threaded search by attribute, size, and date. `Find-DowserString` runs multi-pattern text search with Aho-Corasick matching; `Invoke-DowserFastSearch` is the single-pattern parallel variant. `Find-DowserDuplicate` catches duplicates by name, size, or chunked hash. `Find-DowserModified` pulls files changed on a given date, `Find-DowserRecentLog` grabs the newest log in a directory, and `Find-DowserScript` walks a tree for script files by type.

**Understand a project.** `Find-DowserOrphan` surfaces files nothing references. `Find-DowserDependency` scans scripts for calls and dot-source links. `Get-DowserReport` builds a file-metrics report with parallel processing and export, and `Compare-DowserReport` diffs two of those snapshots into NEW, CHANGED, REMOVED, and UNCHANGED.

**See the shape of a tree.** `Get-DowserMap` draws a directory tree with optional size and PS1 annotations. `Get-DowserTopology` renders a tree for any PSProvider path, not just the filesystem. `Measure-DowserDirectory` gives a quick size and count summary; `Measure-DowserDiskUsage` is the WinDirStat-style recursive rollup with an HTML treemap.

**Inspect a single file.** `Get-DowserProperty` is the deep inspector: VersionInfo, PE structure, hashes. `Get-DowserOwnership` reports ownership and metadata. `Test-DowserIntegrity` runs layered corruption and hygiene detection, and `Test-DowserExtractable` classifies an EXE as extractable versus decompile-required.

**Convert and tuck away.** `ConvertTo-DowserBase64` moves images to and from Base64. `ConvertTo-DowserExe` wraps a PowerShell script in a C# EXE, `ConvertTo-DowserIco` builds .ico files from images, and `Expand-DowserExe` pulls files out of extractable EXE archives. `New-DowserHiddenFolder` hides a directory the right way per platform (NTFS Hidden plus System on Windows, a leading-dot rename on Linux and macOS). `Invoke-DowserNumericSort` sorts naturally, so Item-2 lands before Item-10. `Get-DowserInfo` reports the module version and latest changelog entry; `Get-DowserTemplate` reads Explorer folder-template configs on Windows.

## Platform support

Everything runs on Windows PowerShell 5.1 and PowerShell 7+. On Linux and macOS (PowerShell 7+ only, since 5.1 is Windows-only) behavior splits three ways:

Windows-only, warns and returns without output: `ConvertTo-DowserIco`, `ConvertTo-DowserExe`, `Get-DowserTemplate`. These need System.Drawing/GDI+, the C# compiler, or Shell.Application COM.

Reduced, runs and returns minus the Windows-only enrichments: `Get-DowserProperty`, `Test-DowserExtractable`, `Expand-DowserExe`, `Test-DowserIntegrity`. The archive functions need `7z` on PATH.

Full cross-platform, same behavior everywhere: everything else, including `Get-DowserOwnership` (Owner, Group, and UnixMode plus a platform note off Windows) and `New-DowserHiddenFolder`.

Platform detection happens at module load. PowerShell 5.1 has no `$IsWindows`/`$IsLinux`/`$IsMacOS`, so the loader defines them (5.1 only runs on Windows). On 7+, the engine's own variables drive the guards.

## Short names

Dowser exports its commands under their full `Verb-DowserNoun` names, so importing the module never drops generic names into your session. Want terser names at the prompt? Run `Enable-DowserAliases` (or put it in your profile) to register brandless aliases like `Find-File`, `Get-Tree`, and `Measure-DiskUsage`. It will not shadow a builtin or another module's command, so the system `pstree` on Linux stays the system `pstree`.

## Project layout

```
Dowser.psd1            Module manifest
Dowser.psm1            Loader: dot-sources Private, Public, Aliases
Public/                Exported functions, one per file
Private/               Internal helpers, not exported
Aliases/Aliases.ps1    Enable-DowserAliases, the opt-in alias set
Tests/                 Pester suites and the test runner
docs/                  Architecture, index, changelog
```

## License

[MIT](LICENSE)

## Further reading

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): component design, data flow, design decisions
- [docs/INDEX.md](docs/INDEX.md): per-function inventory with inputs, outputs, and relationships
- [docs/CHANGELOG.md](docs/CHANGELOG.md): full change history
