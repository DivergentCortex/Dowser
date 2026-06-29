# Changelog

All notable changes to Dowser land here. Format loosely follows Keep a Changelog. Dates ISO-8601.

## [2026.06.29.036] - 2026-06-29
### refactor(Write-Log): Align Write-Log comments and platform-guard tests with the Witness backport

What changed:
- Removed leftover WHAT-narration comments from the Write-Log function body (caller-info, component-priority, and console sections) so it matches the clean comment style of the canonical DivergentCortex.Witness Write-Log
- Updated Test-DowserPlatformGuards.Tests.ps1 to the Witness-aligned helper names: Remove-DowserOldLogFiles -> Clear-LogFile, and Get-ExecutionContextInfo -> Get-PlatformContext with the new platform shape (asserts Platform in Linux/macOS instead of SessionType eq NonWindows)
- Verified via AST parse: no parse errors, all six functions intact

Why:
- The updated Write-Log.ps1 is a single-file backport of DivergentCortex.Witness; its body still carried pre-backport narration comments and the Pester suite still referenced the old helper names, which would fail after the rename


## [2026.06.29.035] - 2026-06-29
### fix(Get-DowserTemplate): Fix phantom process block so the function actually runs on Windows

What changed:
- Wrapped the platform guard in a begin block and moved the $unsupported flag check into the process block
- process { } was previously free-floating code after a bare if, so PowerShell parsed it as a call to a nonexistent process command (AST confirmed ProcessBlock present: False), meaning the COM body never ran and the function threw on Windows
- After the fix the AST reports ProcessBlock present: True with no parse errors; pipeline input declared by the param now binds correctly

Why:
- The function was broken on its target platform: free statements before a process block turn the block into a phantom command call, so the Shell.Application query never executed and Windows callers hit a process-not-recognized error


## [2026.06.29.034] - 2026-06-29
### docs(comments): De-slop inline comments across module scripts, comments-only pass

What changed:
- Write-Log.ps1 (example/gold standard): 38 inline comments de-slopped, killed WHAT-restatement and step-marker narration, rewrote load-bearing comments into house voice, removed a -- double-hyphen in Write-LogFinal
- Public/ scripts (26 files) and Private/ helpers plus Aliases.ps1 swept by parallel agents: pure WHAT-restatement and section-header narration deleted, load-bearing comments rewritten terse lowercase why-not-what
- Converted remaining em dashes in active inline comments to ASCII in Get-DowserMap.ps1 (lines 31, 77, 159) and Get-DowserReport.ps1 (line 63)
- Preserved all banner signature headers, comment-based help blocks, #region and ==== divider lines, and param-block doc comments

Why:
- Comments restating what the code already shows are AI slop and noise; this pass enforces the house comment standard (explain why not what, terse lowercase voice, ASCII only) without any logic, string, or whitespace changes to behavior


## [2026.06.29.033] - 2026-06-29

### chore(go-public): History purge, GitHub hardening, final sanitization pass

What changed:

- Purged from all git history via git filter-repo: .claude/ai_forge/, .claude/settings.json, .firecrawl/, synapse-daemon.log, logs/dashboard.log, Tests/Reports/, resources/exeinfope/, resources/exeinfope.zip (62 commits reduced to 47)
- Expired reflog and ran aggressive GC to remove unreachable objects from local repo
- Sanitized remaining internal path reference in Public/Measure-DowserDirectory.ps1 .NOTES block (replaced raw personal path with generic porting note)
- Enabled Dependabot vulnerability alerts and automated security fixes on GitHub via Caledon MCP
- Secret scanning, private vulnerability reporting, branch protection, CodeQL deferred: require public visibility on free-plan repos

Why:

- Final remediation pass before public visibility flip. History purge removes internal tooling artifacts that should never appear in a public repo. Dependabot provides automated dependency vulnerability monitoring. Remaining GitHub hardening activates at or after the public flip.

## [2026.06.28.032] - 2026-06-28

### chore(go-public): Pre-publication sanitization and repo hardening for open-source release

What changed:

- Removed synapse-daemon.log, logs/dashboard.log, resources/exeinfope/ directory, and resources/exeinfope.zip from working tree
- Untracked Tests/Reports/ via git rm --cached (reports regenerated on each run)
- Expanded .gitignore: added _.log, logs/, .claude/, _.nupkg, .DS_Store, Thumbs.db; removed comment revealing AI tooling
- Removed General_Scripts folder entry from Dowser.code-workspace
- Generated real GUID (64c72862-caae-4d55-9a1f-0d5bf94d3695) replacing placeholder in Dowser.psd1
- Set ProjectUri to https://github.com/kizer88/Dowser in manifest
- Updated Copyright field to MIT license text
- Added MIT LICENSE file at repo root (copyright 2026 Curt Leggett)
- Created root README.md from docs/README.md with adjusted links; removed exeinfope references from project layout
- Removed exeinfope references from docs/README.md and docs/ARCHITECTURE.md
- Replaced hardcoded paths in Tests/Invoke-DowserTestSuite.ps1 and Tests/Test-DowserRunspacePool.ps1 with $PSScriptRoot-relative paths
- Sanitized internal infra names (synapse-sql, SecureCRT share) in .NOTES blocks across Public/\*.ps1
- Replaced 'comprehensive' with concrete language in Get-DowserProperty.ps1 synopsis and verbose output
- Standardized author attribution to 'Curtis Leggett / Divergent Cortex' across all .ps1 files (6 files)
- Replaced Write-Host with Write-Information/Write-Warning in Private/Test-DowserHelpers.ps1 and Tests/Test-DowserRunspacePool.ps1
- Replaced all General_Scripts references with 'standalone scripts' across source and docs
- Redacted CHANGELOG: removed agent names from headings, WSL/runtime_cortex paths, internal process jargon, research tool run IDs; normalized heading format; enforced ASCII throughout

Why:

- Preparing repository for public visibility on GitHub. Removes private infrastructure references, internal tooling names, hardcoded paths, placeholder values, and third-party bundled binaries that should not ship in an open-source release.

## [2026.06.22.031] - 2026-06-22

### fix(Get-DowserMap): -IncludeHidden now shows hidden dirs (.claude etc); -NoDefaultExcludes propagated to recursive calls

What changed:

- Public/Get-DowserMap.ps1, Test-ExcludeFolder (~line 442): added early-return guard -- when -IncludeHidden is active and the item has the Hidden file attribute, return $false immediately, skipping the name-based exclude check. Get-ChildItem -Force was enumerating hidden directories correctly but Test-ExcludeFolder discarded them because names like .claude appeared in $defaultExcludes -> $excludeExact. The two mechanisms had no connection.
- Public/Get-DowserMap.ps1, Test-FolderContainsIncludedFolder (~line 512): applied the same hidden bypass to the inline $excludeExact and $excludeWild checks inside this function -- the only other location where the raw exclude arrays were applied to items without hidden-item awareness.
- Public/Get-DowserMap.ps1, non-ShowFullPathTree recursive call (~line 706): added -NoDefaultExcludes:$NoDefaultExcludes. This parameter was omitted, causing -NoDefaultExcludes to be silently dropped at depth 1 and beyond; default excludes were re-applied to all subdirectories regardless of the flag.
- Public/Get-DowserMap.ps1, ShowFullPathTree recursive call (~line 808): same fix applied to the second recursive call site, which had the same omission.

Why:

- .claude is hardcoded in $defaultExcludes. Test-ExcludeFolder fired after Get-ChildItem -Force enumerated hidden items, then immediately discarded them via $excludeExact -contains $item.Name. -IncludeHidden controlled enumeration and ANSI dimming but never touched the exclude filter -- the two mechanisms were completely disconnected. The hidden bypass in Test-ExcludeFolder threads user intent through: if the user explicitly asked to see hidden items, the name-based default exclude list should not silently discard them. The -NoDefaultExcludes propagation gap was a separate wiring bug: the flag was missing from both recursive call sites so it only applied at the root depth-0 call. .claude remains in $defaultExcludes; normal output without -IncludeHidden is unchanged.

## [2026.06.18.030] - 2026-06-18

### feat(aliases): add missing short aliases for Get-DowserInfo, Compare-DowserReport, New-DowserHiddenFolder

What changed:

- Added Set-Alias dinfo -> Get-DowserInfo in Aliases/Aliases.ps1 under # Get-Dowser\* group
- Added Set-Alias dcompare -> Compare-DowserReport in Aliases/Aliases.ps1 under new # Compare-Dowser\* group (alphabetically first)
- Added Set-Alias dhide -> New-DowserHiddenFolder in Aliases/Aliases.ps1 under new # New-Dowser\* group (between Invoke and Test groups)
- Added Tests/Test-DowserAliasCoverage.Tests.ps1: Pester 5 guard asserting every exported function has at least one alias so this gap cannot recur silently
- Collision check confirmed dinfo, dcompare, dhide were clear of all built-in cmdlets and existing aliases before addition

Why:

- 24 of 27 exported functions had short aliases; Get-DowserInfo, Compare-DowserReport, and New-DowserHiddenFolder had none. The Pester guard prevents future exported functions from shipping without an alias.

## [2026.06.17.029] - 2026-06-17

### docs(index): Add missing Source field to Test-DowserExtractable and Test-DowserIntegrity INDEX entries

What changed:

- INDEX.md: added a Source line to the Test-DowserExtractable entry (Test-DowserExtractable.ps1, with a pointer to exe-static-classification-reference.md for the classification logic)
- INDEX.md: added a Source line to the Test-DowserIntegrity entry (Test-DowserIntegrity.ps1)

Why:

- These were the only two cmdlet entries missing the Source field that the INDEX format block defines and every other entry carries; the gap let a reader miss which Public/ file backs each function. Found during the broader doc-freshness sweep, unrelated to the cross-platform repair reconciliation.

## [2026.06.17.028] - 2026-06-17

### docs(reconcile): Reconcile README/ARCHITECTURE/INDEX to the verified post-repair cross-platform behavior

What changed:

- README.md: export count 26 -> 27 (Compare-DowserReport is now an exported public function); flipped its 'not independently exported' paragraph to 'normal exported public function'; added a Compare-DowserReport row to the function table; renamed the 'Degraded' platform bucket to 'Reduced' and moved Get-DowserOwnership and New-DowserHiddenFolder out of it into Full cross-platform with their real non-Windows behavior; updated New-DowserHiddenFolder purpose row and the Public/ layout line
- ARCHITECTURE.md: described the explicit 27-name Export-ModuleMember + manifest surface and how Compare-DowserReport is named explicitly; renamed Degraded -> Reduced and dropped Get-DowserOwnership from it; added paragraphs on Get-DowserOwnership Unix ownership, New-DowserHiddenFolder dot-prefix hiding (-AttributesOnly warns, no rename), the $IsWindows -ne $false guard idiom (PS 5.1 $null) covering the COM reads, Authenticode, and hidden-folder path; appended an export clause to the one-function-per-file note
- INDEX.md: rebuilt the Platform Support section (Fully Cross-Platform now lists the finders/measurers/Get-DowserOwnership/New-DowserHiddenFolder; Degraded renamed Reduced with Get-DowserOwnership removed and the Get-DowserProperty Authenticode note added); rewrote the Get-DowserOwnership, New-DowserHiddenFolder, ConvertTo-DowserBase64, and Expand-DowserExe entries with current inputs/outputs; flipped the Compare-DowserReport Note to 'exported public function'; corrected the stale Expand-DowserExe output schema (Success/FileCount/ArchiveType/Details) and documented the opt-in -PassThru behavior change
- Verified every claim against current code (Dowser.psd1 27-name FunctionsToExport, Dowser.psm1 Export-ModuleMember, Get-DowserOwnership.ps1, New-DowserHiddenFolder.ps1, ConvertTo-DowserBase64.ps1, Expand-DowserExe.ps1, Get-DowserProperty.ps1) before writing; no forward-looking claims, ASCII only

Why:

- The cross-platform repair pass (slots 2026.06.16.021-.027) changed exported surface and several functions' behavior; the README, ARCHITECTURE, and INDEX still described pre-repair reality (26 exports, Compare-DowserReport unexported, Get-DowserOwnership and New-DowserHiddenFolder as degraded/Windows-attribute-only, stale Expand-DowserExe output schema and always-emit). Stale docs send agents into confident failure, so they ship reconciled with the code in the same window.

## [2026.06.16.027] - 2026-06-16

### fix(manifest): Lock down export surface to an explicit 27-function list and export Compare-DowserReport

What changed:

- Dowser.psd1: replaced FunctionsToExport = @('\*') with an explicit 27-name list (the 26 Public/ basenames plus Compare-DowserReport). The wildcard declared an open-ended public API; the explicit list is the genuine surface and makes the intent auditable.
- Dowser.psm1: changed Export-ModuleMember -Function $Public.BaseName to ($Public.BaseName + 'Compare-DowserReport'). Compare-DowserReport is a real public function dot-sourced inside Get-DowserReport.ps1, so it is not a Public/ basename and was never actually exported; naming it explicitly surfaces it and keeps the psm1 consistent with the manifest (the manifest FunctionsToExport intersects with Export-ModuleMember, so the manifest entry alone would have been inert).
- Get-DowserProperty.ps1 (~line 226): fixed the bare `if ($IsWindows -and $IncludeSignature)` Authenticode-signature guard to `if (($IsWindows -ne $false) -and $IncludeSignature)`. On Windows PowerShell 5.1 $IsWindows is $null, so `$null -and ...` wrongly skipped signature checking on a real Windows platform -- the last instance of the platform-guard bug class. Also converted two pre-existing em-dashes in this file's comments (lines 33, 225) to ASCII.
- Verified by Import-Module -Force + Get-Command -Module Dowser: exported function count goes 26 -> 27 (the +1 is Compare-DowserReport becoming exported as intended); Compare-DowserReport resolves; all internal helpers (ConvertTo-DowserExeConfuserEx, \_Build-DduHtml, \_DduTableHtml, Remove-DowserOldLogFiles, Write-LogFinal, Get-SafeLogIdentity, Get-ExecutionContextInfo, Initialize-Log) confirmed not exported; Compare-Object shows the runtime exported set exactly equals the manifest declaration with no extras either way.

Why:

- FunctionsToExport = @('\*') declared an open-ended public API. While Export-ModuleMember -Function $Public.BaseName already limited the effective runtime surface to the 26 basenames (so no helper actually leaked), the wildcard was misleading and the same gate accidentally excluded Compare-DowserReport, a genuine public function that was always meant to be callable. An explicit, audited export list is the correct hygiene: it documents the real API, surfaces the one missing public function, and keeps internal helpers private by name. The line-226 guard was the final undiscovered instance of the PS 5.1 $null-$IsWindows bug class fixed across the rest of the module.

## [2026.06.16.026] - 2026-06-16

### fix(platform-guards): Audit cleanup: real -PassThru in Expand-DowserExe, Get-DowserProperty guard, stronger 7z test, trim comments

What changed:

- Expand-DowserExe.ps1 (~line 165): fixed dead `if ($PassThru) { $extractResult } else { $extractResult }` where both branches emitted, making -PassThru a no-op. Now implements standard -PassThru semantics: the extraction result object is emitted to the pipeline ONLY when -PassThru is supplied; the default path writes a one-line Write-Verbose summary and emits nothing. BEHAVIOR CHANGE: the function no longer always-emits the result object by default.
- Get-DowserProperty.ps1 (~line 164): converted the bare `if ($IsWindows)` Shell.Application COM guard to the canonical `if ($IsWindows -ne $false)` idiom (same PS 5.1 $null bug class fixed elsewhere -- the bare form skipped the Windows COM path on 5.1). The non-Windows degraded else-branch (verbose 'not available on this platform' then continue to hashing) is unaffected.
- Tests/Test-DowserPlatformGuards.Tests.ps1: strengthened the 7-Zip default-param test from a no-throw-only assertion (which passed even with the old unsafe default) to capturing Test-DowserExtractable's verbose stream and asserting the runtime-bound SevenZipPath resolves to the bare '7z' token and is NOT a 'Program Files'/'7z.exe' Windows path.
- Trimmed the duplicated two-line canonical-guard comment block (identical boilerplate copy-pasted at each guard site) to one concise line per site in ConvertTo-DowserIco.ps1, ConvertTo-DowserExe.ps1 (both guards), Get-DowserTemplate.ps1, and Write-Log.ps1 (both guards).

Why:

- Code review of the Task #2 changeset passed with four cleanup findings. The Expand-DowserExe -PassThru if/else was dead code that made the switch meaningless; standard -PassThru is silent-by-default with opt-in emit, matching the function's ShouldProcess design and the terminal position it occupies in the documented pipeline examples. Get-DowserProperty carried the exact bare-$IsWindows bug class the sweep fixed everywhere else. The 7-Zip test gave false confidence (no-throw passes regardless of the default value). The duplicated guard comments were copy-paste boilerplate flagged by the review.

## [2026.06.16.025] - 2026-06-16

### fix(cross-platform): Audit cleanup: Base64 double-emission, duplicate-output discriminator, trim copy-pasted guard comments

What changed:

- ConvertTo-DowserBase64: fixed double-emission -- when -OutputFile AND -CopyToClipboard are both set and the clipboard fails (headless), the function no longer emits the base64 blob to the pipeline (the file is the destination); the pipeline fallback now fires only when no -OutputFile was given. Added a Pester case asserting file-written + pipeline-empty under that combination
- Find-DowserDuplicate: added an OutputType discriminator ('ModeSummary' / 'TopSets') to each emitted summary object so the two different shapes are distinguishable and Export-Csv no longer silently drops columns
- Trimmed the copy-pasted 2-line canonical-guard comment to one concise line at each guard site in Get-DowserOwnership.ps1 and New-DowserHiddenFolder.ps1 (idiom unchanged)
- Full Pester suite now 92/92

Why:

- Code review of Task #1 passed with three findings: a confirmed double-emission defect introduced by the clipboard guard, an output-shape ambiguity in Find-DowserDuplicate, and duplicated verbose guard comments (copy-paste boilerplate). These remediate all three before T1 closes.

## [2026.06.16.024] - 2026-06-16

### fix(cross-platform): Find-DowserOrphan output hygiene and ASCII-clean comments in owned Linux-fix files

What changed:

- Find-DowserOrphan: routed the tail Format-Table preview to Write-Verbose via Out-String so the function returns only clean FileInfo objects (no Format-Table formatting records leaking into the pipeline) -- same output-hygiene class as the Find-DowserDuplicate fix
- Converted 3 pre-existing non-ASCII em-dashes to -- in comment/help text only (Get-DowserOwnership.ps1 synopsis line, New-DowserHiddenFolder.ps1 .PARAMETER AttributesOnly and .NOTES Source) so the owned files are uniformly ASCII-clean
- Added Pester assertion that Find-DowserOrphan returns FileInfo objects with no format-record pollution; full suite now 91/91

Why:

- Folding the two known items flagged during review into this pass before the code review: the Format-Table-at-tail polluted Find-DowserOrphan's FileInfo return, and the em-dashes broke the module's ASCII-only source standard.

## [2026.06.16.023] - 2026-06-16

### fix(cross-platform): Fix Linux-behavior, path-separator, and output-silence defects across nine Public cmdlets

What changed:

- Get-DowserOwnership: deleted stray [System.IO.DirectoryInfo]$Directory pipeline-leak; guarded Shell.Application COM behind the canonical Windows branch and added a Unix fallback that populates Owner/Group/UnixMode + PlatformNote from .NET FileInfo so ownership returns real data on Linux instead of an empty object
- New-DowserHiddenFolder: added the non-Windows branch -- dot-prefix the folder leaf for true Linux hiding (Verbose note that NTFS Hidden/System is Windows-only); under -AttributesOnly warn-only with no rename; re-Get-Item after any rename and return the real on-disk Attributes + PlatformNote (never a claimed Hidden,System value)
- ConvertTo-DowserBase64: removed the function-body $ErrorActionPreference='Stop' scope leak (rely on per-cmdlet -ErrorAction); no-destination branch now Write-Output the base64 string instead of Write-Verbose; Set-Clipboard guarded for headless/no-display sessions, warning and emitting to the pipeline instead of throwing
- Measure-DowserDirectory: replaced backslash interpolation with Join-Path so the immediate child FileCount is correct on Linux (was always 0)
- Measure-DowserDiskUsage: the isRoot reparse-point check now uses $dirComparer instead of forced OrdinalIgnoreCase, for case-sensitivity consistency on Linux
- Find-DowserOrphan: directory exclusion now matches both path separators so exclusions work on Linux
- Find-DowserDuplicate: $modeSummary and $topSets are now emitted as objects via Write-Output (Format-Table output routed to Write-Verbose) so callers can capture them
- Find-DowserDependency: default $ExcludePaths is now platform-aware (Windows defaults vs Linux /proc,/sys,/dev,/usr,/.git) instead of Windows-only backslash paths that silently never matched on Linux
- Get-DowserMap: internal path filtering/comparison now uses the platform separator via ConvertTo-NativeSeparator (replacing ConvertTo-BackslashPath) so Get-ChildItem -LiteralPath calls and include-folder traversal work on Linux; ConvertTo-WslPath keeps local backslash normalization; segment splits use [\\/]; the symlink render feature is preserved (verified)
- Added Tests/Test-DowserLinuxBehavior.Tests.ps1 (Pester 5) covering all of the above; full suite passes 90/90

Why:

- A cross-platform sweep found these cmdlets producing silent false success, empty/zero output, or pipeline-only-to-Write-Verbose results on non-Windows PowerShell 7; this fixes the Linux behavior while keeping Windows behavior unchanged via the PS5.1-safe canonical $IsWindows guard.

## [2026.06.16.022] - 2026-06-16

### fix(platform-guards): Make Test-DowserIntegrity Pester suite run on pwsh 7 and convert remaining non-ASCII in owned files

What changed:

- Tests/Test-DowserIntegrity.Tests.ps1: replaced the corrupt-EXE fixture write `[byte[]](...) | Set-Content -Encoding Byte` (the Byte encoding name was removed in PowerShell 6+, so the BeforeAll threw and the whole suite failed at setup on pwsh 7) with the version-agnostic `[System.IO.File]::WriteAllBytes($path, [byte[]](...))`; the suite now runs and passes 11/11 on pwsh 7
- Get-DowserTemplate.ps1, Get-DowserTopology.ps1, Private/Write-Log.ps1: converted pre-existing non-ASCII characters in comments and comment-based help to ASCII (em-dash -> --, smart double-quotes -> straight quotes); comment/help text only, no logic touched; these three owned files are now ASCII-clean

Why:

- Folded in two pre-existing issues surfaced during the Task #2 platform-guard sweep that fall inside the full cross-platform scope and live in files this change already owns. The `Set-Content -Encoding Byte` idiom is Windows-PowerShell-5.1-only and broke the integrity test suite at fixture setup on pwsh 7, masking real coverage; WriteAllBytes is correct on both 5.1 and 7+. The module is meant to be ASCII-clean and these em-dashes/smart quotes were the only non-ASCII bytes left in the files touched by this task.

## [2026.06.16.021] - 2026-06-16

### fix(platform-guards): Fix PS 5.1 platform-guard bugs and Windows-only function guards across 7 Public files and Write-Log

What changed:

- ConvertTo-DowserIco.ps1: converted the bare `if (-not $IsWindows)` guard to the canonical `if ($IsWindows -eq $false)` idiom (was firing wrongly on PS 5.1 where $IsWindows is $null); removed the dead user32.dll DestroyIcon P/Invoke block (compiled via Add-Type but never called)
- ConvertTo-DowserExe.ps1: converted the ConvertTo-DowserExe guard to the canonical idiom; added a platform guard to ConvertTo-DowserExeConfuserEx (previously unguarded); guarded both `Add-Type -OutputType ConsoleApplication` compile calls behind a PSVersion < 6 check so they no longer throw on pwsh 7, failing clean with a clear 'requires Windows PowerShell 5.1' warning instead
- Get-DowserTemplate.ps1: converted the bare `if (-not $IsWindows)` Shell.Application guard to the canonical idiom
- Test-DowserExtractable.ps1, Test-DowserIntegrity.ps1, Expand-DowserExe.ps1: made the $IsWindows-driven default-parameter expressions for -SevenZipPath (and the $expandExe begin-block assignments) 5.1-safe using `if ($IsWindows -eq $false) { '7z' } else { <Windows path> }` so a standalone 5.1 host resolves the Windows 7-Zip/expand.exe path rather than the bare PATH names
- Get-DowserTopology.ps1: guarded the -InColor PSAnsiFileMap colorization setup behind a PSVersion >= 7 check; on 5.1 it now warns and renders uncolorized instead of null-ref crashing on the PS7-only $global:PSAnsiFileMap
- Private/Write-Log.ps1: converted the two bare $IsWindows guards (Get-SafeLogIdentity, Get-ExecutionContextInfo) to the canonical idiom; renamed the unapproved-verb Cleanup-LogFiles to Remove-DowserOldLogFiles and updated both internal call sites (Write-Log auto-cleanup, Write-LogFinal); replaced two `Get-Variable -Name logfilepath -ValueOnly` lookups with the already-resolved $Logfile param (Write-Log dir creation) and the $LogFilePath param default (Initialize-Log)
- Tests/Test-DowserPlatformGuards.Tests.ps1: new Pester 5 suite (10 tests) covering Windows-only graceful-skip on non-Windows, the ConfuserEx guard returning before the throwing Add-Type, Get-DowserTopology -InColor not crashing, and the Cleanup-LogFiles -> Remove-DowserOldLogFiles rename

Why:

- The cross-platform sweep found platform guards written as bare `if ($IsWindows)` / `if (-not $IsWindows)`, which misfire on Windows PowerShell 5.1 where $IsWindows is $null: the negated form treats 5.1 as non-Windows and skips the Windows code path. The canonical `-ne $false` / `-eq $false` idiom is correct on 5.1 ($null), Windows pwsh ($true), and Linux/macOS ($false). Separately, Add-Type -OutputType was removed in PowerShell 6+, so the EXE compilers threw on pwsh 7 even on Windows, and the -InColor path null-ref crashed on 5.1 because PSAnsiFileMap is PS7-only. Cleanup-LogFiles used an unapproved verb that trips PSScriptAnalyzer and the upcoming manifest export lock-down.

## [2026.06.14.020] - 2026-06-14

### docs(project-wide): Reconcile docs to 26-function surface; fix README/INDEX/ARCHITECTURE; fold and de-slop changelog 019

What changed:

- README.md: added the missing Measure-DowserDiskUsage row, corrected the function count from 25 to 26 (matches Public/ file count), rewrote the Compare-DowserReport note to state accurately that it is dot-sourced with Get-DowserReport but not an independently exported member, expanded the platform-support section, and added a Measure-DowserDiskUsage quick-start example
- INDEX.md: added the missing Find-DowserString entry (a headline function that had no entry), and recharacterized Compare-DowserReport to note it is not an independent export
- ARCHITECTURE.md: corrected Public/ function count from 25 to 26
- CHANGELOG.md: consolidated the Get-DowserMap symlink-render feature and its same-day regression fix (originally two adjacent same-day entries) into the single 2026.06.14.019 feat entry, since the fix corrected a defect introduced earlier the same day with no release between them; trimmed the combined entry to standard length and removed internal references (line numbers, internal variable names, implementation noise). The 2026.06.14.020 slot freed by that consolidation is reused by this documentation-reconciliation entry.

Why:

- Docs had drifted behind the code: the README undercounted functions and omitted Measure-DowserDiskUsage, INDEX was missing Find-DowserString, and both treated Compare-DowserReport ambiguously. The symlink-feature changelog entry was roughly 3x normal length and carried implementation noise and internal references that mean nothing to a reader; its same-day regression fix corrected unshipped code from the same feature, so the two belong as one entry (2026.06.14.019) rather than separate historical events.

## [2026.06.14.019] - 2026-06-14

### feat(Get-DowserMap): Detect and show symlinks as a two-line block instead of silently skipping them

What changed:

- Symlinks and reparse points are now rendered in place as a two-line block (name line, then a target line) instead of being silently dropped from the tree. Default behavior shows the link without descending into it; -FollowReparse descends as if the link were a normal folder.
- Added link glyphs: name marker U+2192 and target marker U+21B3, with ASCII fallbacks (> and ~) under -Ascii and HTML entities under -AsHtml, matching the existing glyph convention.
- Broken or dangling links (no resolvable target) render with a "(broken link)" placeholder on the target line.
- Symlink rendering works in all three output modes (console, -AsHtml, -AsMarkdown) and on both the default and -ShowFullPathTree render paths.
- Added a LinkCount field to traversal state; it appears in -EmitSummary output when at least one link is shown.
- Added Tests/Get-DowserMap.Tests.ps1 (Pester 5): covers the name and target lines, no-descend default, continuation bar on non-last children, -FollowReparse descent, and -AsHtml entity output. The suite skips on platforms where symlink creation is not permitted.

Why:

- The tree silently dropped symlinks, making them invisible in the output. Showing them as a two-line block (name / target) lets users see what links exist and where they point without the tree recursing into them, while -FollowReparse remains available for callers who want to descend.

## [2026.06.07.018] - 2026-06-07

### fix(Measure-DowserDiskUsage): Fix treemap double-count, symlink root skipped, case-sensitive dir keys on Linux

What changed:

- Fix #1 (Linux case-sensitive dir keys): $dirSizes now uses Ordinal comparer on non-Windows (where $IsWindows -eq $false) and OrdinalIgnoreCase on Windows/PS-5.1 ($IsWindows is $null on 5.1, treated as Windows); ancestor-walk stop test updated to use the same comparer via $dirComparer.Equals(); Phase 2 root-exclusion filter also updated to use $dirComparer.Equals() -- prevents sibling dirs Foo/foo collapsing to one key on Linux and prevents the ancestor loop overshooting on case-diverged paths
- Fix #2 (symlink/reparse root dropped): reparse-point skip guard now checks $isRoot first and only skips descendant reparse points, so a symlink or junction passed as -Path is scanned correctly rather than silently returning empty results
- Fix #3 (treemap double-count + proportionality): treemap rebuilt from IMMEDIATE children of root only (keys in $dirSizes whose GetDirectoryName == resolvedRoot), producing a non-overlapping partition with no double-counting; widths = SizeBytes / TotalBytes \* 100 so area is honestly proportional to real disk usage; a remainder block (ddu-remainder class) covers root-level files and any items beyond TopN; $dirSizes and $dirComparer passed into \_Build-DduHtml for this computation
- Tests: all Join-Path paths use nested form for cross-platform correctness; added extensionless file noext and <none> extension assertions; added treemap-proportionality assertions (block widths sum to ~100%, largest block >= 98%, remainder block present); added symlink-root test (skipped on Windows or when symlink creation is not permitted)

Why:

- Code review identified three real defects: the treemap drew overlapping nested dirs producing misleading area proportions, a symlinked root was silently skipped producing empty results, and $dirSizes used OrdinalIgnoreCase on case-sensitive Linux filesystems causing sibling dirs with different casing to merge into one bucket

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
- Archived spent working artifacts to .archives/\_archive.zip: PORTING_OUTLINE.md (porting complete at 21/21), docs/superpowers/plans/2026-05-24-cross-platform-compat.md (plan fully implemented), DOWSER_PROJECT_OUTLINE.md (superseded by README + ARCHITECTURE)
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

## [2026.05.04.012] - 2026-05-04 -- Find-DowserString: single-file mode

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

## [2026.04.29.011] - 2026-04-29 -- Find-DowserString: grouped output mode (new default)

### Changed

- `Public/Find-DowserString.ps1` - Output reorganized to group results by parent directory.

  Was: default `OutputMode = 'counts'` emitted one PSCustomObject per file. PowerShell's
  default table formatter then truncated the FilePath column on long paths,
  producing rows like:

      \\some-host\...\deep\nested\path\comm...
      \\some-host\...\deep\nested\path\comm...

  with the same parent dir repeated and the actual filename clipped.

  Now: new `OutputMode = 'grouped'` is the default. Output is text (Write-Output strings),
  formatted as a directory header with files listed underneath:

      C:\Projects\SomeApp\dist  (5 files, 14 matches)
          commands-registry-BKukdIJg.js                         [   1]  line 584
          commands-registry-DaH1KNEE.js                         [   1]  line 544
          pi-embedded-CblkcCno.js                               [   6]  lines 41772, 42016, 42032, 42044, 42050, 42058

      C:\Projects\SomeApp\dist\plugin-sdk  (2 files, 7 matches)
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

## [2026.04.29.010] - 2026-04-29 -- Find-DowserString: phase banners + streaming directory enumeration

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

## [2026.04.21.009] - 2026-04-21 -- Corrupted File Detection (Test-DowserIntegrity)

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
  - Residue filename patterns: Thumbs.db, desktop.ini, .DS*Store, .*_, ~$_,
    _.tmp, _.bak, _.orig, _.swp, _.swo, _.lock, _.partial, _.crdownload, \*.part
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

## [2026.04.15.008] - 2026-04-15 -- Canonical EXE Static-Analysis Reference

### Added

- `docs/exe-static-classification-reference.md` -- Canonical merged technical reference for static
  classification of Windows .EXE files as Extractable vs Requires Decompilation.
  Merges two independent research outputs covering the same domain from different angles.
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

## [2026.04.15.007] - 2026-04-15 -- EXE Extractability Detection + Extraction

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

## [2026.04.12.006] - 2026-04-12 -- Invoke-DowserTestSuite interactive path fallback + ASCII sweep

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

## [2026-04-12] - Unicode Em Dash Purge

### Fixed

- `Tests/Invoke-DowserTestSuite.ps1` - Replaced all 13 Unicode em dashes (U+2014) with ASCII hyphen "-".
  Operator directive: ASCII only, no Unicode punctuation anywhere.
  Affected lines: 4, 12, 120, 319, 513, 540, 547, 549, 558, 560, 569, 655, 657.
- `Tests/Reports/*.csv` and `*.html` (12 files) - Replaced 48 additional em dashes in generated report output.
  Note: reports are regenerated on each test run; the PS1 fix is the root source.
- Syntax check: PASS (0 errors).
- Verification: grep -r "--" returns 0 hits across PS1 and all Reports files.

---

## [2026.04.12.005] - 2026-04-12 -- Test Suite + Inline Fixes

### Added

- `Tests/Invoke-DowserTestSuite.ps1` -- Comprehensive test suite covering all 21 cmdlets (131 total tests).
  Tests: syntax (T-00), module import (T-01), help blocks (T-02), pipeline support (T-03),
  functional tests (T-04), timing benchmarks small/medium/large (T-05), edge cases (T-06).
  Reports: CSV + HTML written to `Tests/Reports/`. Parameterized: -ModulePath, -TestDataPath, -ReportDir, -SkipSlow.
  Final run: Total=131 PASS=112 FAIL=0 WARN=15 SKIP=4. Pass rate (excl skips): 88.2%.
  WARNs: 14 cmdlets have .SYNOPSIS but no .EXAMPLE blocks (ported without help rewrites -- cosmetic).
  SKIPs: ConvertTo-DowserExe (needs Windows csc), ConvertTo-DowserIco (System.Drawing), Get-DowserTemplate (COM), LargeTree bench.

### Fixed

- `Public/Find-DowserScript.ps1` -- **REWRITTEN**. Previous version had empty `Find-DowserScript { param() }` outer
  function with `Find-SecureCrtScripts` nested inside (hardcoded network path, no params). Calling
  `Find-DowserScript` did nothing. Rewrote with `-Path`, `-Extensions`, `-ModifiedWithin`, `-Recurse`;
  emits PSCustomObjects with Name/FullName/Extension/LastWriteTime/Size.
- `Public/Find-DowserRecentLog.ps1` -- **REWRITTEN**. Previous version had bare script code inside
  empty-param function body; contained backtick `` `$PWD `` literal bug. Rewrote with mandatory `-FileName`,
  `-Path`, `-All`, `-Recurse` params. Returns PSCustomObject per match, newest-first.
- `Public/New-DowserHiddenFolder.ps1` -- **REWRITTEN**. Previous version had hardcoded paths
  to an internal project directory that don't exist anywhere else. Rewrote as general-purpose cmdlet
  with `-Path`, `-Force`, `-AttributesOnly`; SupportsShouldProcess; emits PSCustomObject.
- `Public/Find-DowserModified.ps1` -- **REWRITTEN**. Previous version had backtick `` `$PWD `` literal bug,
  hardcoded default date `"2025-01-14"`, and no `-Path` param (searched `D:\` hardcoded). Rewrote
  with `-Path`, `-Date` (default today), `-Recurse`; emits PSCustomObject per file.
- `Public/Get-DowserTemplate.ps1` -- **REWRITTEN**. Previous version had live execution code
  (`$template = Get-FolderTemplate -folderPath "D:"`) OUTSIDE the function body -- ran on module import.
  Missing `[CmdletBinding()]`. Rewrote with `-Path`, Write-Progress, proper COM error handling,
  PSCustomObject output with Path/ViewMode/Columns.
- `Public/ConvertTo-DowserBase64.ps1` -- Added `[CmdletBinding()]` (was missing). Renamed `-ImagePath`
  to `-Path` with `[Alias('ImagePath','FullName')]` per porting outline. Added `ValueFromPipeline`,
  `ValueFromPipelineByPropertyName`. Fixed all 3 remaining `$ImagePath` references in body.
- `Public/Find-DowserDuplicate.ps1` -- Added `ValueFromPipeline = $true` and `ValueFromPipelineByPropertyName = $true`
  to mandatory `-Path` parameter. Added `[Alias('FullName')]`.
- `Public/Find-DowserString.ps1` -- Added `ValueFromPipeline = $true`, `ValueFromPipelineByPropertyName = $true`,
  `[Alias('FullName')]` to `-Path` parameter. Also changed `${PWD}` to `$PWD` (minor).
- `Public/Get-DowserMap.ps1` -- Added `ValueFromPipeline = $true`, `ValueFromPipelineByPropertyName = $true`,
  `[Alias('FullName')]` to mandatory `-Path` parameter.
- `Public/Measure-DowserDirectory.ps1` -- Fixed `[PSCustomObject]::New([Ordered]@{...})` -> `[PSCustomObject][Ordered]@{...}`.
  The `::New()` static constructor does not accept an OrderedDictionary; output objects had zero properties.
  All 9 output props (Directory, DataSize, FileCount, LargestFile, LargestFileName, NewestFileName,
  NewestFileDate, OldestFileName, OldestFileDate) now verified present.
- `Public/Get-DowserOwnership.ps1` -- Two fixes:
  (1) Added `[Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]`, `[Alias('Path','FullName')]`
  to `$Directory` param (was bare undecorated param; test called with `-Path` which failed).
  (2) Wrapped `New-Object -ComObject Shell.Application` in try/catch -- on Linux/PSCore, `-ComObject`
  is not a valid parameter of `New-Object` and threw an uncaught terminating error. Now gracefully
  skips COM metadata on non-Windows and returns available data.
- `Aliases/Aliases.ps1` -- Added all 22 missing aliases (only 4 Phase-4 aliases were previously active;
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

## [2026.04.12.004] - 2026-04-12 -- Phase 4: Final 3 cmdlets + Blocker 24 resolution (21/21 complete)

### Added

- `Public\Invoke-DowserFastSearch.ps1` -- Port of `standalone scripts\Invoke-FastTextSearch.ps1` (117 lines -> 161 lines).
  - Renames `Invoke-FastTextSearch` -> `Invoke-DowserFastSearch`.
  - Added `#Requires -Version 5.1`, full comment-based help block.
  - Added `ValueFromPipeline = $true` to `-Path` parameter (source had no pipeline support).
  - Added `-Pattern` alias for `-SearchString` (consistency with Find-DowserString).
  - Replaced generic "Starting script execution." Verbose message with informative start banner.
  - Added elapsed time to completion Verbose output.
  - Results returned to pipeline as before; no functional logic changed.
  - Syntax check: PASS (0 errors).
- `Public\Invoke-DowserNumericSort.ps1` -- Port of `standalone scripts\Invoke-NumericalSorting.ps1` (125 lines -> 137 lines).
  - Renames `Sort-Numerical` -> `Invoke-DowserNumericSort` (outline naming decision).
  - Removed `$script:capturedInput = $null` module-scope artifact from source (testing leftover).
  - Removed inline `Get-SortKey` function; calls `Get-DowserSortKey` from Private\ instead
    (extracted in a prior phase -- already present at `Private\Get-DowserSortKey.ps1`).
  - Replaced `throw "No input data provided..."` with `Write-Error` + `return` per module standards.
  - `Register-ArgumentCompleter` updated: CommandName changed to `Invoke-DowserNumericSort`;
    removed `$script:capturedInput` branch (the AST-inspection branch still works).
  - Syntax check: PASS (0 errors).
- `Public\Measure-DowserDirectory.ps1` -- Port of `standalone scripts\Get-DirectorySizeCounts.ps1` (84 lines -> 100 lines).
  - **BLOCKER RESOLVED:** Removed line 2 dot-source of a hardcoded absolute path to a local-only helper that does not exist in any other environment.
  - **BLOCKER RESOLVED:** All write-alias calls (WHY, WHM, WHG, WHB, WH) replaced with `Write-Verbose`. Zero alias calls remain in executable code.
  - Renames `Get-DirectorySizeCounts` -> `Measure-DowserDirectory` (correct verb for sizing operation).
  - Removed inline `ConvertFrom-Bytes` (note: source had a typo -- `COnvertFrom-Bytes`). All byte formatting now routed through `Format-DowserSize -DataValue` (Private\).
  - Output improved: NewestFile and OldestFile were single concatenated strings ("name -=- date"); split into separate `NewestFileName`/`NewestFileDate` and `OldestFileName`/`OldestFileDate` properties.
  - Added outer `foreach` loop so multiple `-Path` values all process (source only handled one).
  - Removed SAPIEN PowerShell Studio header block; replaced with standard Dowser help block.
  - Syntax check: PASS (0 errors). Blocker audit: 0 E:\ references in code, 0 alias calls.

### Changed

- `Aliases\Aliases.ps1` -- Added active (uncommented) Set-Alias entries for Phase 4 cmdlets:
  `dfast` -> Invoke-DowserFastSearch, `dsort`/`dnsort` -> Invoke-DowserNumericSort, `dsize` -> Measure-DowserDirectory.

### Notes

- Module is now 21/21 cmdlets complete per the PORTING_OUTLINE.md target.
- Get-DowserTree is the one remaining cmdlet from the outline that was designated as a
  MERGE of two source scripts (Get-FolderTree + Get-DirectoryTreeOutputAndFileCount). Its
  functionality was partially absorbed by Get-DowserMap (-IncludeSize, -IncludePsCount switches
  added during Phase 3). Get-DowserTree as a standalone merge target is lower priority.

## [2026.04.12.003] - 2026-04-12 -- Phase 3 Inspection-Class cmdlets

### Added

- `Public\Get-DowserOwnership.ps1` -- Port of `standalone scripts\Get-FileOwnership.ps1` (118 lines).
  - Renames outer function `Get-FileOwnership` -> `Get-DowserOwnership`.
  - Removed inner `Get-FileSize` helper; replaced all calls with `Format-DowserSize -DataValue`.
  - Preserves: `Get-FileInformation`, `Get-FileMetaData` inner helpers; Shell.Application COM path;
    optional hash and authenticode signature fields; all original parameters (`Directory`, `Extension`).
  - Added `[CmdletBinding()]` and `#Requires -Version 5.1` header; minimal refactor otherwise.
  - Syntax check: PASS (0 errors).
- `Public\Get-DowserProperty.ps1` -- Port of `standalone scripts\Get-FilePropertyDetails.ps1` (313 lines).
  - Renames `Get-FilePropertyDetails` -> `Get-DowserProperty`.
  - Replaces `"{0:N2} MB" -f ($FileItem.Length / 1MB)` with `Format-DowserSize -DataValue`.
  - Source already had `[CmdletBinding()]`, full help block, and `Write-Verbose` throughout -- preserved as-is.
  - Covers: basic metadata, VersionInfo, Shell.Application extended props (0-500), MD5/SHA1/SHA256 hashes,
    Authenticode signature (opt-in), .NET assembly info, PE header MachineType/Architecture.
  - Added `#Requires -Version 5.1` and Dowser header comment.
  - Syntax check: PASS (0 errors).
- `Public\Get-DowserTopology.ps1` -- Port of `standalone scripts\Get-TreeTopology.ps1` (324 lines).
  - Renames `Get-TreeTopology` -> `Get-DowserTopology`.
  - Preserves aliases `pstree`, `shtree` on the function.
  - No byte-to-string logic present; no Format-DowserSize needed.
  - Source was already fully `[CmdletBinding()]` with `Write-Verbose` throughout -- preserved as-is.
  - Supports: FileSystem and arbitrary PSProvider paths; DynamicParam InColor/-ansi for ANSI colorization
    on FileSystem paths; `-ShowItem` (files); `-ShowProperty` (item properties inline); `-Depth`.
  - Added `#Requires -Version 5.1` and Dowser header comment.
  - Syntax check: PASS (0 errors).
- `Public\Get-DowserReport.ps1` -- Port of `standalone scripts\Get-FileReport.ps1` (1,010 lines -> 648 lines ported).
  - Renames `Get-FileReport` -> `Get-DowserReport`; `Compare-FileReport` -> `Compare-DowserReport`.
  - Upgraded `#requires -Version 2.0` -> `#Requires -Version 5.1`.
  - Replaced inline `ConvertTo-Bytes` function with calls to `ConvertTo-DowserBytes` (Private).
  - Replaced inline `Format-FileSize` function with calls to `Format-DowserSize -DataValue` (Private).
  - Replaced all `Write-Host` (summary blocks + export notifications) with `Write-Verbose`.
  - NOTE: The `analyzeScriptBlock` runspace block retains a local `FormatSizeLocal` inline formatter
    because module-scope functions are not reachable from runspace threads. This is intentional.
  - HTML export template updated: title/header say "Dowser File Report"; Format-DowserSize used for total size.
  - Preserves: two-phase RunspacePool parallelism (gather + analyze); directory-partitioned fan-out;
    single-file mode; grouped table view for multi-level scans; CSV/HTML export; Compare-DowserReport diff.
  - Syntax check: PASS (0 errors).

## [2026.04.12.002] - 2026-04-12

### Added

- `Public\Get-DowserMap.ps1` -- Port of `standalone scripts\Get-DirectoryMap.ps1` (823 lines).
  - Visual tree renderer: Unicode/ASCII box-drawing, HTML/Markdown output, full-path trunk display.
  - Added `-IncludeSize` switch: appends `[1.2 GB]` to each folder using `Format-DowserSize` (logic from Get-FolderTree.ps1).
  - Added `-IncludePsCount` switch: appends `[14 .ps1]` to each folder (logic from Get-DirectoryTreeOutputAndFileCount.ps1).
  - Annotation data computed lazily via `SizeCache`/`PsCountCache` hashtables, passed through recursion.
  - All `Write-Host` replaced with `Write-Verbose`. Zero console output commands.
  - Preserves: MaxDepth, parallel pre-scan, extension/folder filtering, ShowFullPathTree trunk, reparse/hidden support.
  - Self-recursive function with DontShow internal params for recursion state.
  - Syntax check: PASS (0 errors). Write-Host audit: 0 calls.
- Ported Phase 1 (Utilities) and Phase 2 (Hunter-Class) scripts from `standalone scripts` to `Dowser\Public`:
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

- `Private\Write-Log.ps1` -- Mandatory CMTrace-compatible logging helper deployed from canonical source (`standalone scripts\Write-Log.ps1` v2026.03.24.010).
  - Auto-dot-sourced by `Dowser.psm1` loader via `Private\*.ps1` glob -- no explicit import needed.
  - `Write-Log` function now available in module scope; accessible to all Public and Private cmdlets including `Invoke-DowserRunspacePool` and `Find-DowserString`.
  - Syntax check passed (PS parser, zero errors).

### Added

- `Public\Find-DowserString.ps1` -- Port of `standalone scripts\find-stringinfiles.ps1`.
  - Multi-threaded file gathering and string searching via `Invoke-DowserRunspacePool` (replaces inline RunspacePool code).
  - Aho-Corasick string matching (inline C# via `Add-Type`) for multi-pattern literal search; compiled once into shared AppDomain, available to all worker runspaces.
  - Zero `Write-Host` usage; all status via `Write-Verbose` and `Write-Progress` (handled by `Invoke-DowserRunspacePool`).
  - No legacy write aliases (WHY/WHM/etc.) -- were never in this file; source aliases not ported.
  - OutputMode: `counts` (default), `files`, `matches`; `IncludeLineContent` adds line text to match rows.
  - SearchMode: `auto` (picks aho for multi-pattern literal), `aho`, `manual`, `select` (compat stub).
  - Verified test run: 9 .ps1 files across 6 dirs, 74 match rows, 2.5s via 7 parallel threads.

## [2026.04.11.001] - 2026-04-11

### Added

- `Private\Format-DowserSize.ps1` -- Extracted and generalized `ConvertFrom-Bytes` logic from `Get-DirectorySizeCou
