# Dowser

Filesystem recon and inspection kit for PowerShell. Point it at a path, get answers.

## Install (dev)

```powershell
Import-Module D:\_REPOS\ToolProjects\Dowser\Dowser.psd1 -Force
Get-Command -Module Dowser
```

## Naming

`Verb-DowserNoun` — approved PS verbs, singular nouns, `Dowser` prefix on every export. Aliases in `Aliases\Aliases.ps1`.

## Structure

```
Dowser.psd1       manifest
Dowser.psm1       loader
Public\           exported cmdlets (one per file)
Private\          internal helpers
Aliases\          alias definitions
Tests\            Pester
docs\INDEX.md     redundancy guard - read before adding
```

See `docs\INDEX.md` before adding anything.
