# Dowser

**Location:** `D:\_REPOS\ToolProjects\Dowser`
**Type:** PowerShell module
**Source material:** `D:\_REPOS\General_Scripts\*.ps1`

## What it is

Dowser is a PowerShell module consolidating every file-recon and filesystem-inspection script from `General_Scripts` into one coherent, importable kit. The name comes from the old forked-stick trick for finding water underground — same job, different terrain. You point it at a path and it tells you what's there, what's duplicated, what's orphaned, what changed, what depends on what, who owns it, and how big it is.

Most cmdlets answer questions rather than move files around. This is a tracker's kit, not a mover's kit.

## Naming convention

Approved PowerShell verbs only (no `Dowse-` — PS will nag on every import). Module identity lives in the noun prefix so tab-completion on `-Dowser` surfaces the whole kit at once. Singular nouns even when the cmdlet returns many items (Microsoft convention).

**Pattern:** `Verb-DowserNoun`

Examples:
- `Find-DowserDuplicate`
- `Find-DowserString`
- `Get-DowserTree`
- `Get-DowserOwnership`
- `Measure-DowserDirectory`
- `ConvertTo-DowserBase64`

Aliases get layered on top for day-to-day typing and exported via `Export-ModuleMember -Alias *`. Aliases can be casual (`dmap`, `dfind`, `ddupe`) — underlying cmdlets stay clean and approved.

## Verb buckets

- **Find-Dowser\*** — hunt operations (strings, files, duplicates, orphans, dependencies, modified-on ranges)
- **Get-Dowser\*** — inspection (tree, map, ownership, properties, topology, reports)
- **Measure-Dowser\*** — counting and sizing
- **ConvertTo-Dowser\*** — transformers (Exe, ICO, Base64). Candidates for a submodule later if they grow.
- **Invoke-Dowser\*** — action tools (fast text search, numerical sorting)

New functions must land in an existing bucket or justify a new verb from the approved list. No pseudo-verbs.

## Source inventory (initial port targets)

From `D:\_REPOS\General_Scripts\`:

| Source script | Target cmdlet |
|---|---|
| ConvertTo-Base64.ps1 | ConvertTo-DowserBase64 |
| ConvertTo-Exe.ps1 | ConvertTo-DowserExe |
| ConvertTo-ICO.ps1 | ConvertTo-DowserIco |
| Find-FileDuplicates.ps1 | Find-DowserDuplicate |
| Find-Files.ps1 | Find-DowserFile |
| Find-FilesModifiedOn.ps1 | Find-DowserModified |
| Find-MostRecentLog.ps1 | Find-DowserRecentLog |
| Find-OrphanFiles.ps1 | Find-DowserOrphan |
| Find-ScriptDependencies.ps1 | Find-DowserDependency |
| Find-Scripts.ps1 | Find-DowserScript |
| Find-StringInFiles.ps1 | Find-DowserString |
| Get-DirectoryMap.ps1 | Get-DowserMap |
| Get-DirectorySizeCounts.ps1 | Measure-DowserDirectory |
| Get-DirectoryTreeOutputAndFileCount.ps1 | Get-DowserTree |
| Get-FileOwnership.ps1 | Get-DowserOwnership |
| Get-FilePropertyDetails.ps1 | Get-DowserProperty |
| Get-FileReport.ps1 | Get-DowserReport |
| Get-FolderTemplate.ps1 | Get-DowserTemplate |
| Get-FolderTree.ps1 | (merge into Get-DowserTree — redundant) |
| Get-TreeTopology.ps1 | Get-DowserTopology |
| Invoke-FastTextSearch.ps1 | Invoke-DowserFastSearch |
| Invoke-NumericalSorting.ps1 | Invoke-DowserNumericSort |

Note the merge on `Get-FolderTree` / `Get-DirectoryTreeOutputAndFileCount` / `Get-DirectoryMap` — three scripts doing overlapping tree work. The index (below) exists specifically to catch this kind of drift before it calcifies.

## Project layout

```
D:\_REPOS\ToolProjects\Dowser\
├── Dowser.psd1              # module manifest
├── Dowser.psm1              # root module (dot-sources Public/Private)
├── Public\                  # exported cmdlets, one file per function
├── Private\                 # internal helpers, not exported
├── Aliases\
│   └── Aliases.ps1          # Set-Alias calls, dot-sourced by psm1
├── Tests\                   # Pester tests, mirrors Public\
├── docs\
│   ├── INDEX.md             # the redundancy guard — see below
│   ├── CHANGELOG.md
│   └── CONVENTIONS.md       # naming rules, verb buckets, examples
└── README.md
```

## The Index (redundancy guard)

`docs\INDEX.md` is the single source of truth for what exists in the module. Before any agent adds a function, they read the index. If a similar capability already exists, they extend it instead of adding a parallel implementation. This is the mechanism that keeps Dowser from growing three different tree-walkers over the next year.

Index entry format:

```
### Find-DowserDuplicate
- Purpose: Identify duplicate files by hash within a path
- Inputs: -Path, -Recurse, -Algorithm (default SHA256)
- Outputs: Grouped duplicate sets with paths and hashes
- Related: Find-DowserOrphan (opposite question)
- Source: Find-FileDuplicates.ps1
```

Every cmdlet gets an entry. Updating the index is part of the definition of done — no entry, no merge.

## Conventions (hard rules)

- Approved verbs only. `Get-Verb` is the whitelist.
- Singular nouns.
- `Dowser` noun prefix on every exported cmdlet.
- Comment-based help on every public function (SYNOPSIS, DESCRIPTION, PARAMETER, EXAMPLE minimum).
- Pipeline support where it makes sense — most of these take `-Path` and should accept pipeline input.
- `[CmdletBinding()]` on every function.
- No `Write-Host` in public functions. Use `Write-Verbose`, `Write-Warning`, or proper output.
- Pester test for every public function, even if minimal.
- Aliases defined in one place (`Aliases\Aliases.ps1`), not scattered inside function files.

## Acceptance criteria for the initial port

- Module imports clean with zero warnings: `Import-Module Dowser -Force`
- `Get-Command -Module Dowser` lists every ported cmdlet under the `Verb-DowserNoun` pattern
- `Test-ModuleManifest Dowser.psd1` passes
- Every source script in the inventory above has either been ported or explicitly marked as merged/dropped in the index with rationale
- `docs\INDEX.md` has one entry per exported cmdlet
- README.md covers install, import, and three usage examples
- Pester suite runs green

## Out of scope (for now)

- Publishing to PSGallery
- Cross-platform testing (Windows PowerShell 5.1 + PS 7 on Windows is the target)
- GUI wrappers
- The converter functions (Exe/Ico/Base64) stay in the main module for now but are flagged as potential submodule candidates if they grow past five functions

## Dispatch notes for agents

Do not port scripts one-at-a-time without consulting the index. Do not invent new verbs. Do not add `Write-Host`. Do not skip the Pester tests — even a smoke test that imports the module and asserts the cmdlet exists counts. If a source script does something genuinely redundant with an existing Dowser cmdlet, merge it and document the merge in the index with a note on what was absorbed.

When in doubt on naming, match the closest existing cmdlet in the module and ask before deviating.
