# Dowser Architecture

## Shape

Classic PS module layout. Manifest points at loader, loader dot-sources everything under Public and Private, aliases get layered on last, Export-ModuleMember ships Public functions plus all aliases.

```
Dowser.psd1  -> Dowser.psm1
                  |
                  +-- Private\*.ps1   (helpers, not exported)
                  +-- Public\*.ps1    (one function per file, exported)
                  +-- Aliases\Aliases.ps1  (Set-Alias calls, sourced last)
```

One function per file in Public. Makes diffs clean, keeps agents from stomping each other, and `Get-ChildItem Public` reads like a table of contents.

## Naming law

`Verb-DowserNoun`. Approved verbs only (`Get-Verb` is the whitelist). Singular nouns. No exceptions, no pseudo-verbs, no `Dowse-` cute stuff because PS will nag on every import and linters will flag it.

Aliases carry the personality. Cmdlets stay boring and compliant.

## Buckets

- `Find-Dowser*` - hunt (duplicates, strings, orphans, dependencies)
- `Get-Dowser*` - inspect (tree, map, ownership, properties, reports)
- `Measure-Dowser*` - count and size
- `ConvertTo-Dowser*` - transform (Base64, Exe, Ico) — submodule candidate if it grows past five
- `Invoke-Dowser*` - action (fast search, sorting)

## Redundancy guard

`docs\INDEX.md` is the single source of truth. Every exported cmdlet gets an entry. Agents read the index before adding anything. If the capability exists, extend it — do not fork a parallel implementation. No index entry, no merge.

## Conventions (hard rules)

- `[CmdletBinding()]` on every function
- Comment-based help minimum: SYNOPSIS, DESCRIPTION, PARAMETER, EXAMPLE
- Pipeline input on `-Path` where it makes sense
- No `Write-Host` in public functions — use `Write-Verbose` / `Write-Warning` / proper output
- Pester smoke test per public function at minimum
- Aliases live in `Aliases\Aliases.ps1`, nowhere else

## Target runtime

Windows PowerShell 5.1 and PowerShell 7 on Windows. Cross-platform is out of scope until it is not.
