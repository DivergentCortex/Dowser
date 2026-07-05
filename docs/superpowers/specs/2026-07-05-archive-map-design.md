# Design: Archive-mode for Get-DowserMap

Date: 2026-07-05
Status: Approved, ready for implementation planning

## Problem

`Get-DowserMap` renders a directory tree for a real folder `-Path`. When `-Path` points at an archive file (`.zip`, `.7z`, `.rar`, `.tar`, `.gz`) instead of a directory, it currently produces broken/nonsensical output: `Get-ChildItem` on a leaf file path returns the file itself (not its contents), so the renderer shows a single confusing line rather than erroring cleanly or doing anything useful.

## Goal

`Get-DowserMap -Path archive.zip` (or `.7z`/`.rar`/`.tar`/`.gz`) should auto-detect that `-Path` is an archive file and render the archive's *internal* contents as a tree, using the same visual style (box-drawing chars, Ascii/HTML/Markdown modes) and much of the same filtering/annotation surface as real-folder mode, with zero new flags required to opt in.

## Scope decisions (from user Q&A)

1. **Formats:** `.zip` (native, via `System.IO.Compression.ZipFile`, no external dependency) plus `.7z`/`.rar`/`.tar`/`.gz` via the 7-Zip CLI (same `-SevenZipPath` convention already used by `Test-DowserExtractable`/`Expand-DowserExe`).
2. **Trigger:** Auto-detect. If `-Path` resolves to a file (not a directory) with a recognized archive extension, switch to archive-tree rendering automatically. No new switch parameter needed for the common case.
3. **Filter/annotation parity ("core parity"):** Archive mode supports `-MaxDepth`, `-IncludeSize` (uncompressed size; folder = recursive sum of contained entries), `-IncludeFileCount`, `-IncludeExtensions`, `-ExcludeExtensions`, `-IncludeFilePatterns`, `-ExcludeFiles`, `-ExcludeFolders`, `-IncludeFolders`, `-Ascii`, `-AsHtml`, `-AsMarkdown`, `-OutputFile`, `-MarkdownFile`, `-EmitSummary`, `-NoDefaultExcludes`, `-LinuxPaths`/`-ShowFullPathTree` (trunk display of the archive's own on-disk path). Explicitly OUT of scope for archive mode: `-IncludeHidden`, `-FollowReparse`, `-UseRunspaces`/`-MaxThreads` (no parallel prescan needed -- entry listing is already a single pass, not a lazy filesystem walk).
4. **Nested compound archives** (`.tar.gz`/`.tgz` unwrapping two layers deep) are explicitly OUT of scope for v1. A `.gz` lists its one wrapped entry (correct for a plain gzipped file); a gzip-wrapped tarball will show its inner `.tar` as one opaque entry rather than descending into it. Document this as a known v1 limitation.

## Architecture

Archive mode is a **separate rendering path**, not woven into `Get-DowserMap`'s existing self-recursive filesystem walk (which is entangled with `Get-ChildItem`, the parallel prescan runspace pool, and hidden/reparse-point handling -- too risky to touch for this feature). `Get-DowserMap` gains one early check at `$CurrentDepth -eq 0`: if `-Path` resolves to a file with a recognized archive extension, it delegates entirely to the new private renderer and returns its output directly. The existing directory-walking code path for real folders is untouched.

### New Private helpers (new capability)

- **`Private/Get-DowserArchiveEntry.ps1`** -- given an archive path, returns a flat, normalized list of entries: `RelativePath` (forward-slash), `IsDirectory`, `Size` (bytes). `.zip` is read natively via `System.IO.Compression.ZipFile` (same assembly `Test-DowserExtractable` already loads). `.7z`/`.rar`/`.tar`/`.gz` are listed via `7z l -slt <path>` (structured, block-per-entry output: `Path =`, `Folder = +/-`, `Size =`, `Attributes =`), which is far more reliable to parse than the columnar `7z l` table format. Takes `-Path` and `-SevenZipPath` (same default-resolution pattern as `Test-DowserExtractable`/`Expand-DowserExe`: `7z` bare token on non-Windows, `Program Files\7-Zip\7z.exe` on Windows).
- **`Private/Get-DowserArchiveMap.ps1`** -- takes the flat entries, synthesizes the implied folder structure (most archives, especially zips, don't list folder entries explicitly -- folders must be inferred from file paths), applies the "core parity" filters, and walks the resulting in-memory tree to produce tree-output lines. No runspace pool: the full entry list is already known up front, so "does this folder contain a matching descendant" is a cheap recursive check over an in-memory tree, not a filesystem walk needing a prescan cache.

### Extracted shared Private helpers (existing logic, pulled out so both renderers stay identical and don't drift)

- **`Private/Get-DowserDefaultExclude.ps1`** -- the default exclude lists (extensions/folders/files -- e.g. `node_modules`, `.git`, `.pyc`) currently hardcoded inline in `Get-DowserMap.ps1` (lines ~281-338). Archive mode needs the exact same defaults (a zipped repo should get `.git`/`node_modules` filtered the same as a real one); pulling them into one source of truth avoids two copies silently diverging over time.
- **`Private/Get-DowserTreeChars.ps1`** -- the Ascii/Unicode/HTML box-drawing character selection currently inline in `Get-DowserMap.ps1` (lines ~936-997).
- **`Private/Complete-DowserMapOutput.ps1`** -- the shared "finalize lines, append `-EmitSummary` block, write `-OutputFile`/`-MarkdownFile`" tail logic currently inline as the nested `Complete-DirectoryMapOutput` function in `Get-DowserMap.ps1` (lines ~1032-1151).

`Get-DowserMap.ps1` is refactored to call these three extracted helpers instead of its inline copies -- behavior-preserving for real-folder mode, verified by the existing Pester suite (`Tests/Get-DowserMap.Tests.ps1`) passing unchanged.

### Modified: `Public/Get-DowserMap.ps1`

- Add `-SevenZipPath` parameter (same default-resolution expression as `Test-DowserExtractable`).
- At `$CurrentDepth -eq 0`, after resolving `$rootFull`: if the resolved path is a `Leaf` (file) and its extension matches a recognized archive extension (`.zip`, `.7z`, `.rar`, `.tar`, `.gz`), call `Get-DowserArchiveMap` with the relevant passthrough parameters and `return` its output. Skip this check entirely at `$CurrentDepth -gt 0` (recursive self-calls always operate on real folders already, from either mode).
- Refactor the char-selection block and `Complete-DirectoryMapOutput` to call the three extracted shared helpers.

## Data flow

1. `Get-DowserMap -Path foo.zip` -> resolve path -> detect `.zip` extension -> `Get-DowserArchiveEntry -Path foo.zip` -> flat entry list.
2. `Get-DowserArchiveMap` builds a synthetic tree, synthesizing missing intermediate folders from entry paths (e.g. entries `src/a.ps1` and `src/b.ps1` with no explicit `src/` directory entry still produce a `src` folder node).
3. Applies `-MaxDepth`, `-IncludeSize` (uncompressed, folder = recursive sum), `-IncludeFileCount`, extension/pattern/folder include-exclude (folder shown if it matches directly or contains a matching descendant -- same rule as real-folder mode), default excludes via `Get-DowserDefaultExclude` unless `-NoDefaultExcludes`.
4. Renders via `Get-DowserTreeChars` for the char set, honors `-Ascii`/`-AsHtml`/`-AsMarkdown`, writes `-OutputFile`/`-MarkdownFile` and appends `-EmitSummary` via `Complete-DowserMapOutput` -- output is visually indistinguishable in style from folder-tree output.
5. Dotfiles inside archives render normally unless their name is in the default exclude-files list (e.g. `.env`) -- same outcome as real-folder mode without `-IncludeHidden`, just because the module already excludes dotfolders like `.git` by name rather than by OS hidden-attribute.

## Error handling

- Archive fails to open (corrupt zip, unreadable) -> an error line using the existing `$errorChar`, matching the visual language of today's "ACCESS DENIED" line: `<errorChar> ARCHIVE UNREADABLE: <path> (<reason>)`.
- Non-`.zip` format requested but 7-Zip isn't found at `-SevenZipPath` -> a clear error line plus `Write-Log -Severity Warning`, mirroring the pattern `Expand-DowserExe` already uses when 7-Zip is missing. Never a silently empty tree.
- Unrecognized extension on a leaf-file `-Path` (e.g. `.exe`, `.txt`) -> falls through to whatever `Get-DowserMap` does today for a non-directory, non-archive leaf path. Out of scope for this feature; not touched.

## Testing plan

New/extended Pester coverage, following the existing conventions in `Tests/Get-DowserMap.Tests.ps1` (temp fixtures created in `BeforeAll`, cleaned up in `AfterAll`, skip gracefully when a capability -- like 7-Zip -- isn't available, matching how the symlink tests skip when symlink creation isn't permitted):

- `.zip` with nested folders renders the correct tree shape.
- `.zip` containing only file entries (no explicit directory entries -- the common real-world case) correctly synthesizes implied folders.
- Extension/pattern/folder filters narrow the archive tree the same way they narrow a real one.
- `-IncludeSize`/`-IncludeFileCount` annotate folders correctly from entry metadata.
- `-MaxDepth` truncates archive descent.
- Missing-7z path for a `.7z`/`.tar`/etc. input produces the clean error line instead of throwing.
- At least one 7z-backed format test (`.7z` or `.tar`), skipped gracefully if 7-Zip isn't present in the test environment.
- Existing `Tests/Get-DowserMap.Tests.ps1` suite continues to pass unchanged (verifies the extracted shared helpers didn't change real-folder-mode behavior).

## Documentation updates required

- `docs/ARCHITECTURE.md`: component layers table (new Private helpers), design decisions section (archive-mode note).
- `docs/INDEX.md`: `Get-DowserMap` entry gets the new `-SevenZipPath` param and an archive-mode description.
- `docs/CHANGELOG.md`: new entry for this feature.
- `README.md`: add an archive-mode example if the function table/examples section covers `Get-DowserMap` today.
