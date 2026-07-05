# Archive-mode for Get-DowserMap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `Get-DowserMap -Path archive.zip` (and `.7z`/`.rar`/`.tar`/`.gz`) auto-detect an archive file and render its internal contents as a tree, with the same visual style and much of the same filtering as real-folder mode.

**Architecture:** Archive mode is a separate rendering path (new Private helpers `Get-DowserArchiveEntry` and `Get-DowserArchiveMap`) delegated to from one early check in `Get-DowserMap.ps1`, never woven into the existing filesystem-recursion code. Three pieces of Get-DowserMap's existing logic (default exclude lists, box-drawing char selection, output-finishing) are extracted into shared Private helpers first so both rendering paths stay identical and don't drift.

**Tech Stack:** PowerShell 5.1+/7+, Pester 5, System.IO.Compression.ZipFile (native zip), 7-Zip CLI (`7z l -slt`) for .7z/.rar/.tar/.gz.

---

## Task 1: Extract Get-DowserDefaultExclude

**Files:**
- Create: `Private/Get-DowserDefaultExclude.ps1`
- Modify: `Public/Get-DowserMap.ps1`
- Test: `Tests/Get-DowserMap.Tests.ps1` (existing, run only, not modified in this task)

- [ ] **Step 1: Run the baseline test suite**

  Run:
  ```
  Invoke-Pester -Path ./Tests/Get-DowserMap.Tests.ps1 -Output Detailed
  ```
  Expected: all existing tests PASS. Record the pass count as the baseline before touching any code; Task 1's final verification compares against this number.

- [ ] **Step 2: Create the shared default-exclude helper**

  Create `Private/Get-DowserDefaultExclude.ps1` with exactly this content:
  ```powershell
  #Requires -Version 5.1

  # Single source of truth for Get-DowserMap's default exclude lists (extensions/folders/files).
  # Both real-folder mode and archive mode pull from here so the two rendering paths can't
  # silently drift apart as new defaults get added.

  function Get-DowserDefaultExclude {
      [CmdletBinding()]
      param()

      [PSCustomObject]@{
          Extensions = @(
              '.pyc', '.pyo', '.pyd', '.so', '.dll', '.dylib', '.obj', '.o', '.a', '.lib',
              '.class', '.jar', '.war', '.ear', '.whl', '.egg', '.zip', '.tar', '.gz', '.bz2',
              '.7z', '.rar', '.iso', '.dmg', '.pkg', '.deb', '.rpm',
              '.bak', '.tmp', '.temp', '.log', '.swp', '.swo', '~', '.DS_Store', 'Thumbs.db',
              '.cache', '.eslintcache', '.parcel-cache'
          )
          Folders    = @(
              '__pycache__', 'node_modules', '.git', '.svn', '.hg', '.vs', '.vscode', 'obj', '.idea',
              'dist', '.pytest_cache', '.mypy_cache', '.tox', 'venv', '.venv', 'env', '.env',
              'Lib', 'lib', 'Include', 'include', 'share', 'man',
              '.next', '.nuxt', 'target', 'vendor', 'packages',
              '.angular', '.sass-cache', 'bower_components', 'jspm_packages',
              '.gradle', '.maven', '.m2', '.cache', '__MACOSX', 'Thumbs.db',
              '.DS_Store', '.eggs', '*.egg-info', '.pytest_cache', 'htmlcov', 'coverage',
              '.nyc_output', 'logs', 'log', 'tmp', 'temp', '.tmp', '.temp',
              'site-packages', 'dist-info', '.dist-info', '.claude'
          )
          Files      = @( 'settings.local.json', '.env', 'sccm.code-workspace', '*.code-workspace' )
      }
  }
  ```

- [ ] **Step 3: Replace the inline extension-exclude block in Get-DowserMap.ps1**

  In `Public/Get-DowserMap.ps1`, find this exact block (it appears once, right after the "Precompute normalized extension filters" comment):
  ```
      # Precompute normalized extension filters
      $normInclude = @()
      if ($IncludeExtensions) {
          $normInclude = @($IncludeExtensions | ForEach-Object { ConvertTo-NormalizedExtension $_ }) 
      }

      $defaultExcludeExts = @(
          '.pyc', '.pyo', '.pyd', '.so', '.dll', '.dylib', '.obj', '.o', '.a', '.lib',
          '.class', '.jar', '.war', '.ear', '.whl', '.egg', '.zip', '.tar', '.gz', '.bz2',
          '.7z', '.rar', '.iso', '.dmg', '.pkg', '.deb', '.rpm',
          '.bak', '.tmp', '.temp', '.log', '.swp', '.swo', '~', '.DS_Store', 'Thumbs.db',
          '.cache', '.eslintcache', '.parcel-cache'
      )
  ```
  Replace it with:
  ```
      # Precompute normalized extension filters
      $normInclude = @()
      if ($IncludeExtensions) {
          $normInclude = @($IncludeExtensions | ForEach-Object { ConvertTo-NormalizedExtension $_ }) 
      }

      $dowserDefaults = Get-DowserDefaultExclude
      $defaultExcludeExts = $dowserDefaults.Extensions
  ```

- [ ] **Step 4: Replace the inline folder-exclude block**

  Find this exact block:
  ```
      # folder exclude defaults, opinionated but documented. use -NoDefaultExcludes to bypass.
      $defaultExcludes = @(
          '__pycache__', 'node_modules', '.git', '.svn', '.hg', '.vs', '.vscode', 'obj', '.idea',
          'dist', '.pytest_cache', '.mypy_cache', '.tox', 'venv', '.venv', 'env', '.env',
          'Lib', 'lib', 'Include', 'include', 'share', 'man',
          '.next', '.nuxt', 'target', 'vendor', 'packages',
          '.angular', '.sass-cache', 'bower_components', 'jspm_packages',
          '.gradle', '.maven', '.m2', '.cache', '__MACOSX', 'Thumbs.db',
          '.DS_Store', '.eggs', '*.egg-info', '.pytest_cache', 'htmlcov', 'coverage',
          '.nyc_output', 'logs', 'log', 'tmp', 'temp', '.tmp', '.temp',
          'site-packages', 'dist-info', '.dist-info', '.claude'
      )
  ```
  Replace with:
  ```
      # folder exclude defaults, opinionated but documented. use -NoDefaultExcludes to bypass.
      $defaultExcludes = $dowserDefaults.Folders
  ```

- [ ] **Step 5: Replace the inline file-exclude line**

  Find this exact line:
  ```
      # file-level excludes
      $defaultExcludeFiles = @( 'settings.local.json', '.env', 'sccm.code-workspace', '*.code-workspace' )
  ```
  Replace with:
  ```
      # file-level excludes
      $defaultExcludeFiles = $dowserDefaults.Files
  ```

- [ ] **Step 6: Re-run the test suite to confirm behavior-preserving refactor**

  Run:
  ```
  Invoke-Pester -Path ./Tests/Get-DowserMap.Tests.ps1 -Output Detailed
  ```
  Expected: same PASS count as the Step 1 baseline. This is a pure extraction; no test outcome should change.

- [ ] **Step 7: Commit**
  ```
  git add Private/Get-DowserDefaultExclude.ps1 Public/Get-DowserMap.ps1 && git commit -m "refactor(Get-DowserMap): extract default exclude lists into Private/Get-DowserDefaultExclude"
  ```

---

## Task 2: Extract Get-DowserTreeChars

**Files:**
- Create: `Private/Get-DowserTreeChars.ps1`
- Modify: `Public/Get-DowserMap.ps1`

- [ ] **Step 1: Create the shared tree-char helper**

  Create `Private/Get-DowserTreeChars.ps1`:
  ```powershell
  #Requires -Version 5.1

  # Shared box-drawing character/icon set for Get-DowserMap's tree renderers (real-folder mode
  # and archive mode). One source of truth keeps both visually identical.

  function Get-DowserTreeChars {
      [CmdletBinding()]
      param(
          [switch]$Ascii,
          [switch]$AsHtml
      )

      if ($Ascii) {
          return [PSCustomObject]@{
              TreeChars  = @{ Branch = '+-'; Last = '\\-'; Pipe = '| '; Space = '  ' }
              FileChar   = '-'
              FolderChar = '+'
              ErrorChar  = 'X'
              LinkChar   = '>'
              TargetChar = '~'
          }
      }

      $branch = if ($AsHtml) { '&#x251C;&#x2500;' } else { [string]([char]0x251C) + [char]0x2500 }
      $last = if ($AsHtml) { '&#x2514;&#x2500;' } else { [string]([char]0x2514) + [char]0x2500 }
      $pipe = if ($AsHtml) { '&#x2502; ' } else { [string]([char]0x2502) + ' ' }
      $fileChar = if ($AsHtml) { '&#x00B7;' } else { [char]0x00B7 }
      $folderChar = if ($AsHtml) { '&#x25A0;' } else { [char]0x25A0 }
      $errorChar = if ($AsHtml) { '&#x00D7;' } else { [char]0x00D7 }
      $linkChar = if ($AsHtml) { '&#x2192;' } else { [char]0x2192 }
      $targetChar = if ($AsHtml) { '&#x21B3;' } else { [char]0x21B3 }

      [PSCustomObject]@{
          TreeChars  = @{ Branch = $branch; Last = $last; Pipe = $pipe; Space = '  ' }
          FileChar   = $fileChar
          FolderChar = $folderChar
          ErrorChar  = $errorChar
          LinkChar   = $linkChar
          TargetChar = $targetChar
      }
  }
  ```

- [ ] **Step 2: Replace the inline box-drawing block in Get-DowserMap.ps1**

  Find this exact block (starts with the comment `# box-drawing characters`):
  ```
      # box-drawing characters
      if ($Ascii) {
          $treeChars = @{ Branch = '+-'; Last = '\\-'; Pipe = '| '; Space = '  ' }
          $fileChar = '-'; $folderChar = '+'; $errorChar = 'X'
          $linkChar = '>'; $targetChar = '~'
      }
      else {
          $branch = if ($AsHtml) {
              '&#x251C;&#x2500;' 
          }
          else {
              [string]([char]0x251C) + [char]0x2500 
          }
          $last = if ($AsHtml) {
              '&#x2514;&#x2500;' 
          }
          else {
              [string]([char]0x2514) + [char]0x2500 
          }
          $pipe = if ($AsHtml) {
              '&#x2502; '     
          }
          else {
              [string]([char]0x2502) + ' ' 
          }
          $treeChars = @{ Branch = $branch; Last = $last; Pipe = $pipe; Space = '  ' }
          $fileChar = if ($AsHtml) {
              '&#x00B7;' 
          }
          else {
              [char]0x00B7 
          }
          $folderChar = if ($AsHtml) {
              '&#x25A0;' 
          }
          else {
              [char]0x25A0 
          }
          $errorChar = if ($AsHtml) {
              '&#x00D7;' 
          }
          else {
              [char]0x00D7 
          }
          $linkChar = if ($AsHtml) {
              '&#x2192;' 
          }
          else {
              [char]0x2192 
          }
          $targetChar = if ($AsHtml) {
              '&#x21B3;' 
          }
          else {
              [char]0x21B3 
          }
      }
  ```
  Replace with:
  ```
      # box-drawing characters (shared with archive-mode rendering via Get-DowserTreeChars)
      $treeCharSet = Get-DowserTreeChars -Ascii:$Ascii -AsHtml:$AsHtml
      $treeChars = $treeCharSet.TreeChars
      $fileChar = $treeCharSet.FileChar
      $folderChar = $treeCharSet.FolderChar
      $errorChar = $treeCharSet.ErrorChar
      $linkChar = $treeCharSet.LinkChar
      $targetChar = $treeCharSet.TargetChar
  ```
  All downstream variable names ($treeChars, $fileChar, $folderChar, $errorChar, $linkChar, $targetChar) are unchanged, so nothing else in the file needs editing.

- [ ] **Step 3: Re-run the test suite**

  Run:
  ```
  Invoke-Pester -Path ./Tests/Get-DowserMap.Tests.ps1 -Output Detailed
  ```
  Expected: same PASS count as Task 1's baseline.

- [ ] **Step 4: Commit**
  ```
  git add Private/Get-DowserTreeChars.ps1 Public/Get-DowserMap.ps1 && git commit -m "refactor(Get-DowserMap): extract box-drawing char selection into Private/Get-DowserTreeChars"
  ```

---

## Task 3: Extract Complete-DowserMapOutput

**Files:**
- Create: `Private/Complete-DowserMapOutput.ps1`
- Modify: `Public/Get-DowserMap.ps1`

- [ ] **Step 1: Create the shared output-finisher helper**

  Create `Private/Complete-DowserMapOutput.ps1`:
  ```powershell
  #Requires -Version 5.1

  # Shared output finisher for Get-DowserMap's tree renderers (real-folder mode and archive mode).
  # Appends the -EmitSummary block, writes -OutputFile/-MarkdownFile, and returns the final lines.

  function Complete-DowserMapOutput {
      [CmdletBinding()]
      param(
          [string[]]$Lines,
          [string[]]$TreeLines,
          [bool]$IsRootCall,
          [bool]$EmitSummary,
          [hashtable]$TraversalState,
          [string]$OutputFile,
          [string]$MarkdownFile,
          [bool]$AsMarkdown,
          [string]$DisplayRoot
      )

      if (-not $TreeLines) {
          $TreeLines = $Lines
      }
      $filteredLines = @()
      if ($Lines) {
          $filteredLines = $Lines | Where-Object { $_ -and $_.Trim() -ne '' }
      }
      $treeOnly = @()
      if ($TreeLines) {
          $treeOnly = $TreeLines | Where-Object { $_ -and $_.Trim() -ne '' }
      }

      $summaryLines = @(); $summaryBullets = @()
      if ($IsRootCall -and $EmitSummary) {
          $summaryLines += 'Summary:'
          $summaryLines += "  Folders: $($TraversalState.FolderCount)"
          $summaryLines += "  Files: $($TraversalState.FileCount)"
          $skippedFolderCount = [int]$TraversalState.SkippedFolders
          $skippedFileCount = [int]$TraversalState.SkippedFiles
          $linkCount = [int]$TraversalState.LinkCount
          if ($skippedFolderCount -gt 0 -or $skippedFileCount -gt 0) {
              $summaryLines += "  Skipped: $skippedFolderCount folders, $skippedFileCount files"
          }
          if ($linkCount -gt 0) {
              $summaryLines += "  Symlinks: $linkCount"
          }
          $summaryBullets += "- Folders: $($TraversalState.FolderCount)"
          $summaryBullets += "- Files: $($TraversalState.FileCount)"
          if ($skippedFolderCount -gt 0 -or $skippedFileCount -gt 0) {
              $summaryBullets += "- Skipped: $skippedFolderCount folders, $skippedFileCount files"
          }
          if ($linkCount -gt 0) {
              $summaryBullets += "- Symlinks: $linkCount"
          }
      }
      $finalLines = if ($summaryLines.Count -gt 0) {
          $filteredLines + $summaryLines
      }
      else {
          $filteredLines
      }

      if ($IsRootCall) {
          $markdownTarget = $null; $writeTextToOutputFile = $false
          if ($OutputFile) {
              if ($AsMarkdown -and -not $MarkdownFile) {
                  $markdownTarget = $OutputFile
              }
              else {
                  $writeTextToOutputFile = $true
              }
          }
          if ($MarkdownFile) {
              $markdownTarget = $MarkdownFile
          }

          if ($writeTextToOutputFile) {
              try {
                  $outDir = Split-Path -Path $OutputFile -Parent
                  if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
                      New-Item -ItemType Directory -Path $outDir -Force | Out-Null
                  }
                  $finalLines | Out-File -FilePath $OutputFile -Encoding UTF8
              }
              catch {
                  Write-Log "Get-DowserMap failed writing output file '$OutputFile': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Warning
              }
          }
          if ($markdownTarget) {
              try {
                  $mdDir = Split-Path -Path $markdownTarget -Parent
                  if ($mdDir -and -not (Test-Path -LiteralPath $mdDir)) {
                      New-Item -ItemType Directory -Path $mdDir -Force | Out-Null
                  }
                  $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                  $mdLines = @( '# Directory Map', '', ('**Root:** `{0}`' -f $DisplayRoot), ('**Generated:** {0}' -f $timestamp) )
                  if ($summaryBullets.Count -gt 0) {
                      $mdLines += ''; $mdLines += '#### Summary'; $mdLines += $summaryBullets
                  }
                  $mdLines += ''; $mdLines += '```text'
                  if ($treeOnly.Count -gt 0) {
                      $mdLines += $treeOnly
                  }
                  else {
                      $mdLines += '(no entries)'
                  }
                  $mdLines += '```'
                  $mdLines | Set-Content -Path $markdownTarget -Encoding UTF8
              }
              catch {
                  Write-Log "Get-DowserMap failed writing markdown file '$markdownTarget': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Warning
              }
          }
      }

      return $finalLines
  }
  ```

- [ ] **Step 2: Replace the nested Complete-DirectoryMapOutput function in Get-DowserMap.ps1**

  Find the entire nested function `Complete-DirectoryMapOutput` (it starts with `function Complete-DirectoryMapOutput {` and ends with the matching closing `}` right before the comment `# --- Non-ShowFullPathTree rendering ---`; the exact original body follows, match and replace the whole function):
  ```
      function Complete-DirectoryMapOutput {
          param([string[]]$Lines, [string[]]$TreeLines)
          if (-not $TreeLines) {
              $TreeLines = $Lines 
          }
          $filteredLines = @()
          if ($Lines) {
              $filteredLines = $Lines | Where-Object { $_ -and $_.Trim() -ne '' } 
          }
          $treeOnly = @()
          if ($TreeLines) {
              $treeOnly = $TreeLines | Where-Object { $_ -and $_.Trim() -ne '' } 
          }

          $summaryLines = @(); $summaryBullets = @()
          if ($CurrentDepth -eq 0 -and $EmitSummary) {
              $summaryLines += 'Summary:'
              $summaryLines += "  Folders: $($TraversalState.FolderCount)"
              $summaryLines += "  Files: $($TraversalState.FileCount)"
              $skippedFolderCount = [int]$TraversalState.SkippedFolders
              $skippedFileCount = [int]$TraversalState.SkippedFiles
              $linkCount = [int]$TraversalState.LinkCount
              if ($skippedFolderCount -gt 0 -or $skippedFileCount -gt 0) {
                  $summaryLines += "  Skipped: $skippedFolderCount folders, $skippedFileCount files"
              }
              if ($linkCount -gt 0) {
                  $summaryLines += "  Symlinks: $linkCount" 
              }
              $summaryBullets += "- Folders: $($TraversalState.FolderCount)"
              $summaryBullets += "- Files: $($TraversalState.FileCount)"
              if ($skippedFolderCount -gt 0 -or $skippedFileCount -gt 0) {
                  $summaryBullets += "- Skipped: $skippedFolderCount folders, $skippedFileCount files"
              }
              if ($linkCount -gt 0) {
                  $summaryBullets += "- Symlinks: $linkCount" 
              }
          }
          $finalLines = if ($summaryLines.Count -gt 0) {
              $filteredLines + $summaryLines 
          }
          else {
              $filteredLines 
          }

          if ($CurrentDepth -eq 0) {
              $markdownTarget = $null; $writeTextToOutputFile = $false
              if ($OutputFile) {
                  if ($AsMarkdown -and -not $MarkdownFile) {
                      $markdownTarget = $OutputFile 
                  }
                  else {
                      $writeTextToOutputFile = $true 
                  }
              }
              if ($MarkdownFile) {
                  $markdownTarget = $MarkdownFile 
              }

              if ($writeTextToOutputFile) {
                  try {
                      $outDir = Split-Path -Path $OutputFile -Parent
                      if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
                          New-Item -ItemType Directory -Path $outDir -Force | Out-Null 
                      }
                      $finalLines | Out-File -FilePath $OutputFile -Encoding UTF8
                  }
                  catch {
                      Write-Log "Get-DowserMap failed writing output file '$OutputFile': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Warning
                  }
              }
              if ($markdownTarget) {
                  try {
                      $mdDir = Split-Path -Path $markdownTarget -Parent
                      if ($mdDir -and -not (Test-Path -LiteralPath $mdDir)) {
                          New-Item -ItemType Directory -Path $mdDir -Force | Out-Null 
                      }
                      if ($LinuxPaths) {
                          $displayRoot = ConvertTo-WslPath $Path 
                      }
                      else {
                          $rootDisplay = if ($IsWindows) {
                              ($rootFull -replace '/', '\').TrimEnd('\')
                          } else {
                              $rootFull.TrimEnd('/')
                          }
                          $displayRoot = if ($rootDisplay) {
                              $rootDisplay
                          }
                          else {
                              ConvertTo-NativeSeparator $Path 
                          } 
                      }
                      if (-not $displayRoot) {
                          $displayRoot = $Path 
                      }
                      $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                      $mdLines = @( '# Directory Map', '', ('**Root:** `{0}`' -f $displayRoot), ('**Generated:** {0}' -f $timestamp) )
                      if ($summaryBullets.Count -gt 0) {
                          $mdLines += ''; $mdLines += '#### Summary'; $mdLines += $summaryBullets 
                      }
                      $mdLines += ''; $mdLines += '```text'
                      if ($treeOnly.Count -gt 0) {
                          $mdLines += $treeOnly 
                      }
                      else {
                          $mdLines += '(no entries)' 
                      }
                      $mdLines += '```'
                      $mdLines | Set-Content -Path $markdownTarget -Encoding UTF8
                  }
                  catch {
                      Write-Log "Get-DowserMap failed writing markdown file '$markdownTarget': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Warning
                  }
              }
          }
          if ($CurrentDepth -eq 0) {
              Write-Log "Ending Get-DowserMap"
          }
          return $finalLines
      }
  ```
  Replace with:
  ```
      function Complete-DirectoryMapOutput {
          param([string[]]$Lines, [string[]]$TreeLines)

          $displayRoot = $null
          if ($CurrentDepth -eq 0) {
              if ($LinuxPaths) {
                  $displayRoot = ConvertTo-WslPath $Path
              }
              else {
                  $rootDisplay = if ($IsWindows) {
                      ($rootFull -replace '/', '\').TrimEnd('\')
                  }
                  else {
                      $rootFull.TrimEnd('/')
                  }
                  $displayRoot = if ($rootDisplay) {
                      $rootDisplay
                  }
                  else {
                      ConvertTo-NativeSeparator $Path
                  }
              }
              if (-not $displayRoot) {
                  $displayRoot = $Path
              }
          }

          $result = Complete-DowserMapOutput -Lines $Lines -TreeLines $TreeLines -IsRootCall ($CurrentDepth -eq 0) -EmitSummary:$EmitSummary -TraversalState $TraversalState -OutputFile $OutputFile -MarkdownFile $MarkdownFile -AsMarkdown:$AsMarkdown -DisplayRoot $displayRoot
          if ($CurrentDepth -eq 0) {
              Write-Log "Ending Get-DowserMap"
          }
          return $result
      }
  ```

- [ ] **Step 3: Re-run the test suite**

  Run:
  ```
  Invoke-Pester -Path ./Tests/Get-DowserMap.Tests.ps1 -Output Detailed
  ```
  Expected: same PASS count as the Task 1 baseline.

- [ ] **Step 4: Commit**
  ```
  git add Private/Complete-DowserMapOutput.ps1 Public/Get-DowserMap.ps1 && git commit -m "refactor(Get-DowserMap): extract output-finishing logic into Private/Complete-DowserMapOutput"
  ```

---

## Task 4: Get-DowserArchiveEntry (new capability, TDD)

**Files:**
- Create: `Private/Get-DowserArchiveEntry.ps1`
- Test: Create `Tests/Get-DowserArchiveEntry.Tests.ps1`

- [ ] **Step 1: Write the failing test file**

  Create `Tests/Get-DowserArchiveEntry.Tests.ps1`:
  ```powershell
  #Requires -Modules @{ModuleName='Pester';ModuleVersion='5.0'}

  Describe 'Get-DowserArchiveEntry' {
      BeforeAll {
          $modulePath = Split-Path $PSScriptRoot -Parent
          Remove-Module Dowser -Force -ErrorAction SilentlyContinue
          Import-Module (Join-Path $modulePath 'Dowser.psd1') -Force -ErrorAction Stop

          Add-Type -AssemblyName System.IO.Compression -ErrorAction SilentlyContinue

          $script:tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "DowserArchiveEntryTest_$([guid]::NewGuid().Guid)"
          New-Item -ItemType Directory -Path $script:tmpDir -Force | Out-Null

          $script:zipPath = Join-Path $script:tmpDir 'sample.zip'
          $archive = [System.IO.Compression.ZipFile]::Open($script:zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
          try {
              $rootEntry = $archive.CreateEntry('root.txt')
              $rootWriter = New-Object System.IO.StreamWriter($rootEntry.Open())
              $rootWriter.Write('root'); $rootWriter.Close()

              $nestedEntry = $archive.CreateEntry('src/nested.ps1')
              $nestedWriter = New-Object System.IO.StreamWriter($nestedEntry.Open())
              $nestedWriter.Write('nested-body'); $nestedWriter.Close()
          }
          finally {
              $archive.Dispose()
          }

          $script:corruptZipPath = Join-Path $script:tmpDir 'corrupt.zip'
          [System.IO.File]::WriteAllText($script:corruptZipPath, 'not a zip')

          $script:fakeSevenZTarget = Join-Path $script:tmpDir 'sample.7z'
          [System.IO.File]::WriteAllText($script:fakeSevenZTarget, 'placeholder')
          $script:missingSevenZipPath = Join-Path $script:tmpDir 'no-such-7z-binary'
      }

      AfterAll {
          if (Test-Path -LiteralPath $script:tmpDir) {
              Remove-Item -LiteralPath $script:tmpDir -Recurse -Force -ErrorAction SilentlyContinue
          }
          Remove-Module Dowser -Force -ErrorAction SilentlyContinue
      }

      It 'Lists a top-level file entry from a zip' {
          $entries = InModuleScope Dowser -Parameters @{ ZipPath = $script:zipPath } { param($ZipPath) Get-DowserArchiveEntry -Path $ZipPath }
          ($entries | Where-Object { $_.RelativePath -eq 'root.txt' }) | Should -Not -BeNullOrEmpty
      }

      It 'Lists a nested file entry with no explicit directory entry (implied folder case)' {
          $entries = InModuleScope Dowser -Parameters @{ ZipPath = $script:zipPath } { param($ZipPath) Get-DowserArchiveEntry -Path $ZipPath }
          ($entries | Where-Object { $_.RelativePath -eq 'src/nested.ps1' }) | Should -Not -BeNullOrEmpty
      }

      It 'Reports correct uncompressed size and IsDirectory = false for a file entry' {
          $entries = InModuleScope Dowser -Parameters @{ ZipPath = $script:zipPath } { param($ZipPath) Get-DowserArchiveEntry -Path $ZipPath }
          $rootEntry = $entries | Where-Object { $_.RelativePath -eq 'root.txt' }
          $rootEntry.Size | Should -Be 4
          $rootEntry.IsDirectory | Should -Be $false
      }

      It 'Throws a clear error for a corrupt zip' {
          { InModuleScope Dowser -Parameters @{ ZipPath = $script:corruptZipPath } { param($ZipPath) Get-DowserArchiveEntry -Path $ZipPath } } | Should -Throw
      }

      It 'Throws a clear error when 7-Zip is missing for a .7z path' {
          { InModuleScope Dowser -Parameters @{ SevenZPath = $script:fakeSevenZTarget; MissingTool = $script:missingSevenZipPath } { param($SevenZPath, $MissingTool) Get-DowserArchiveEntry -Path $SevenZPath -SevenZipPath $MissingTool } } | Should -Throw
      }

      It 'Throws a clear error for an unrecognized archive extension' {
          $txtPath = Join-Path $script:tmpDir 'plain.txt'
          [System.IO.File]::WriteAllText($txtPath, 'hello')
          { InModuleScope Dowser -Parameters @{ TxtPath = $txtPath } { param($TxtPath) Get-DowserArchiveEntry -Path $TxtPath } } | Should -Throw
      }
  }
  ```

- [ ] **Step 2: Confirm the test fails (function does not exist yet)**

  Run:
  ```
  Invoke-Pester -Path ./Tests/Get-DowserArchiveEntry.Tests.ps1 -Output Detailed
  ```
  Expected: FAIL on all 6 It-blocks with "The term 'Get-DowserArchiveEntry' is not recognized" or an InModuleScope resolution failure, because the function does not exist yet.

- [ ] **Step 3: Create the archive-entry listing helper**

  Create `Private/Get-DowserArchiveEntry.ps1`:
  ```powershell
  #Requires -Version 5.1

  # Lists normalized flat entries from an archive file. .zip is read natively via
  # System.IO.Compression.ZipFile (no external dependency, same assembly Test-DowserExtractable
  # already loads). .7z/.rar/.tar/.gz are listed via the 7-Zip CLI ('7z l -slt', structured
  # block-per-entry output -- far more reliable to parse than the columnar '7z l' table format).

  function Get-DowserArchiveEntry {
      [CmdletBinding()]
      param(
          [Parameter(Mandatory = $true)]
          [string]$Path,

          [string]$SevenZipPath = $(if ($IsWindows -eq $false) {
                  '7z'
              }
              else {
                  Join-Path ${env:ProgramFiles} '7-Zip\7z.exe'
              })
      )

      $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
      $entries = @()

      if ($ext -eq '.zip') {
          try {
              Add-Type -AssemblyName System.IO.Compression -ErrorAction SilentlyContinue
              $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
          }
          catch {
              throw "Could not open zip '$Path': $($_.Exception.Message)"
          }
          try {
              foreach ($e in $zip.Entries) {
                  $relPath = ($e.FullName -replace '\\', '/')
                  $isDir = $relPath.EndsWith('/')
                  $entries += [PSCustomObject]@{
                      RelativePath = $relPath.TrimEnd('/')
                      IsDirectory  = $isDir
                      Size         = if ($isDir) { 0 } else { $e.Length }
                  }
              }
          }
          finally {
              $zip.Dispose()
          }
          return , $entries
      }

      if ($ext -notin @('.7z', '.rar', '.tar', '.gz')) {
          throw "Get-DowserArchiveEntry: unrecognized archive extension '$ext' for '$Path'."
      }

      if (-not (Test-Path -LiteralPath $SevenZipPath)) {
          throw "Get-DowserArchiveEntry: 7-Zip not found at '$SevenZipPath'. Install 7-Zip or specify -SevenZipPath to list '$ext' archives."
      }

      $listing = & $SevenZipPath 'l' '-slt' $Path 2>&1 | Out-String
      if ($LASTEXITCODE -ne 0) {
          throw "Get-DowserArchiveEntry: 7-Zip exited with code $LASTEXITCODE listing '$Path'."
      }

      $blocks = [regex]::Split($listing, '(?:\r?\n){2,}')
      foreach ($block in $blocks) {
          if ($block -notmatch '(?m)^Path\s*=\s*(.+)$') {
              continue
          }
          $entryPath = $Matches[1].Trim()
          if ($block -match '(?m)^Type\s*=\s*') {
              continue
          }
          $isDir = $false
          if ($block -match '(?m)^Folder\s*=\s*\+') {
              $isDir = $true
          }
          elseif ($block -match '(?m)^Attributes\s*=\s*D') {
              $isDir = $true
          }
          $size = 0
          if (-not $isDir -and $block -match '(?m)^Size\s*=\s*(\d+)') {
              $size = [int64]$Matches[1]
          }
          $entries += [PSCustomObject]@{
              RelativePath = ($entryPath -replace '\\', '/').TrimEnd('/')
              IsDirectory  = $isDir
              Size         = $size
          }
      }
      return , $entries
  }
  ```

- [ ] **Step 4: Confirm the tests pass**

  Run:
  ```
  Invoke-Pester -Path ./Tests/Get-DowserArchiveEntry.Tests.ps1 -Output Detailed
  ```
  Expected: all 6 It-blocks PASS. If the zip-related tests fail with an assembly/type error, check that `Add-Type -AssemblyName System.IO.Compression` resolved on this platform (it is the same call already proven working in `Public/Test-DowserExtractable.ps1`); do not add `System.IO.Compression.FileSystem`, it is not used elsewhere in this codebase and is unnecessary since only `ZipFile.OpenRead`/`ZipFile.Open`/`ZipArchiveEntry` (base `System.IO.Compression` types) are used here.

- [ ] **Step 5: Commit**
  ```
  git add Private/Get-DowserArchiveEntry.ps1 Tests/Get-DowserArchiveEntry.Tests.ps1 && git commit -m "feat(Get-DowserMap): add Get-DowserArchiveEntry private helper for zip/7z-backed archive listing"
  ```

---

## Task 5: Get-DowserArchiveMap (new capability, TDD)

**Files:**
- Create: `Private/Get-DowserArchiveMap.ps1`
- Test: Create `Tests/Get-DowserArchiveMap.Tests.ps1`

- [ ] **Step 1: Write the failing test file**

  Create `Tests/Get-DowserArchiveMap.Tests.ps1`:
  ```powershell
  #Requires -Modules @{ModuleName='Pester';ModuleVersion='5.0'}

  Describe 'Get-DowserArchiveMap' {
      BeforeAll {
          $modulePath = Split-Path $PSScriptRoot -Parent
          Remove-Module Dowser -Force -ErrorAction SilentlyContinue
          Import-Module (Join-Path $modulePath 'Dowser.psd1') -Force -ErrorAction Stop

          Add-Type -AssemblyName System.IO.Compression -ErrorAction SilentlyContinue

          $script:tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "DowserArchiveMapTest_$([guid]::NewGuid().Guid)"
          New-Item -ItemType Directory -Path $script:tmpDir -Force | Out-Null

          # nested.zip: file-only entries, no explicit directory entries, exercising both
          # nested-folder rendering and implied-folder synthesis at once.
          $script:nestedZipPath = Join-Path $script:tmpDir 'nested.zip'
          $nestedArchive = [System.IO.Compression.ZipFile]::Open($script:nestedZipPath, [System.IO.Compression.ZipArchiveMode]::Create)
          try {
              $aEntry = $nestedArchive.CreateEntry('src/a.ps1')
              $aWriter = New-Object System.IO.StreamWriter($aEntry.Open())
              $aWriter.Write('a-body'); $aWriter.Close()

              $bEntry = $nestedArchive.CreateEntry('src/lib/b.ps1')
              $bWriter = New-Object System.IO.StreamWriter($bEntry.Open())
              $bWriter.Write('b-body-longer'); $bWriter.Close()

              $readmeEntry = $nestedArchive.CreateEntry('readme.md')
              $readmeWriter = New-Object System.IO.StreamWriter($readmeEntry.Open())
              $readmeWriter.Write('read me'); $readmeWriter.Close()
          }
          finally {
              $nestedArchive.Dispose()
          }

          # withexcludes.zip: a top-level node_modules/ entry that must be filtered by default.
          $script:excludeZipPath = Join-Path $script:tmpDir 'withexcludes.zip'
          $excludeArchive = [System.IO.Compression.ZipFile]::Open($script:excludeZipPath, [System.IO.Compression.ZipArchiveMode]::Create)
          try {
              $ignoredEntry = $excludeArchive.CreateEntry('node_modules/ignored.js')
              $ignoredWriter = New-Object System.IO.StreamWriter($ignoredEntry.Open())
              $ignoredWriter.Write('ignored'); $ignoredWriter.Close()

              $keepEntry = $excludeArchive.CreateEntry('keep.txt')
              $keepWriter = New-Object System.IO.StreamWriter($keepEntry.Open())
              $keepWriter.Write('keep'); $keepWriter.Close()
          }
          finally {
              $excludeArchive.Dispose()
          }

          # fake .tar target plus a deliberately-wrong -SevenZipPath, for the unreadable-archive test.
          $script:fakeTarPath = Join-Path $script:tmpDir 'sample.tar'
          [System.IO.File]::WriteAllText($script:fakeTarPath, 'placeholder, never actually read because -SevenZipPath is wrong')
          $script:missingSevenZipPath = Join-Path $script:tmpDir 'no-such-7z-binary'
      }

      AfterAll {
          if (Test-Path -LiteralPath $script:tmpDir) {
              Remove-Item -LiteralPath $script:tmpDir -Recurse -Force -ErrorAction SilentlyContinue
          }
          Remove-Module Dowser -Force -ErrorAction SilentlyContinue
      }

      It 'Renders all files and both folder names for a zip with nested folders' {
          $lines = InModuleScope Dowser -Parameters @{ ZipPath = $script:nestedZipPath } { param($ZipPath) Get-DowserArchiveMap -ArchivePath $ZipPath -ShowFullPathTree:$false }
          $joined = $lines -join "`n"
          $joined | Should -Match 'a\.ps1'
          $joined | Should -Match 'b\.ps1'
          $joined | Should -Match 'readme\.md'
          $joined | Should -Match 'src'
          $joined | Should -Match 'lib'
      }

      It 'Synthesizes the implied src folder from file-only entries with no explicit directory entry' {
          $lines = InModuleScope Dowser -Parameters @{ ZipPath = $script:nestedZipPath } { param($ZipPath) Get-DowserArchiveMap -ArchivePath $ZipPath -ShowFullPathTree:$false }
          ($lines | Where-Object { $_ -match '\bsrc\b' }) | Should -Not -BeNullOrEmpty
      }

      It '-IncludeExtensions narrows the tree to only matching files' {
          $lines = InModuleScope Dowser -Parameters @{ ZipPath = $script:nestedZipPath } { param($ZipPath) Get-DowserArchiveMap -ArchivePath $ZipPath -ShowFullPathTree:$false -IncludeExtensions '.ps1' }
          $joined = $lines -join "`n"
          $joined | Should -Match 'a\.ps1'
          $joined | Should -Not -Match 'readme\.md'
      }

      It '-IncludeSize annotates the src folder with a non-empty bracketed size' {
          $lines = InModuleScope Dowser -Parameters @{ ZipPath = $script:nestedZipPath } { param($ZipPath) Get-DowserArchiveMap -ArchivePath $ZipPath -ShowFullPathTree:$false -IncludeSize }
          $srcLine = $lines | Where-Object { $_ -match 'src' } | Select-Object -First 1
          $srcLine | Should -Match '\[\d'
      }

      It '-IncludeFileCount annotates the src folder with the correct recursive file count' {
          $lines = InModuleScope Dowser -Parameters @{ ZipPath = $script:nestedZipPath } { param($ZipPath) Get-DowserArchiveMap -ArchivePath $ZipPath -ShowFullPathTree:$false -IncludeFileCount }
          $srcLine = $lines | Where-Object { $_ -match 'src' -and $_ -match 'files\]' } | Select-Object -First 1
          $srcLine | Should -Match '\[2 files\]'
      }

      It '-MaxDepth 0 renders top-level entries only, no descent into nested folder contents' {
          $lines = InModuleScope Dowser -Parameters @{ ZipPath = $script:nestedZipPath } { param($ZipPath) Get-DowserArchiveMap -ArchivePath $ZipPath -ShowFullPathTree:$false -MaxDepth 0 }
          $joined = $lines -join "`n"
          $joined | Should -Match 'readme\.md'
          $joined | Should -Match 'src'
          $joined | Should -Not -Match 'a\.ps1'
          $joined | Should -Not -Match 'b\.ps1'
      }

      It 'Excludes node_modules by default and includes it with -NoDefaultExcludes' {
          $defaultLines = InModuleScope Dowser -Parameters @{ ZipPath = $script:excludeZipPath } { param($ZipPath) Get-DowserArchiveMap -ArchivePath $ZipPath -ShowFullPathTree:$false }
          ($defaultLines -join "`n") | Should -Not -Match 'node_modules'
          ($defaultLines -join "`n") | Should -Not -Match 'ignored\.js'

          $noExcludeLines = InModuleScope Dowser -Parameters @{ ZipPath = $script:excludeZipPath } { param($ZipPath) Get-DowserArchiveMap -ArchivePath $ZipPath -ShowFullPathTree:$false -NoDefaultExcludes }
          ($noExcludeLines -join "`n") | Should -Match 'node_modules'
          ($noExcludeLines -join "`n") | Should -Match 'ignored\.js'
      }

      It 'Produces an ARCHIVE UNREADABLE line instead of throwing for a non-zip format with a wrong -SevenZipPath' {
          $lines = InModuleScope Dowser -Parameters @{ TarPath = $script:fakeTarPath; MissingTool = $script:missingSevenZipPath } { param($TarPath, $MissingTool) Get-DowserArchiveMap -ArchivePath $TarPath -SevenZipPath $MissingTool -ShowFullPathTree:$false }
          ($lines -join "`n") | Should -Match 'ARCHIVE UNREADABLE'
      }
  }
  ```

- [ ] **Step 2: Confirm the test fails (function does not exist yet)**

  Run:
  ```
  Invoke-Pester -Path ./Tests/Get-DowserArchiveMap.Tests.ps1 -Output Detailed
  ```
  Expected: FAIL on all 8 It-blocks with "The term 'Get-DowserArchiveMap' is not recognized" or an InModuleScope resolution failure, because the function does not exist yet.

- [ ] **Step 3: Create the archive tree-synthesis and rendering helper**

  Create `Private/Get-DowserArchiveMap.ps1`:
  ```powershell
  #Requires -Version 5.1

  # Archive-mode tree renderer. Takes flat entries from Get-DowserArchiveEntry, synthesizes an
  # in-memory nested tree (most archives, especially zips, don't list folder entries explicitly,
  # so folders are inferred from file paths), applies the same-style filters as Get-DowserMap's
  # real-folder mode, and renders via the shared Get-DowserTreeChars/Complete-DowserMapOutput
  # helpers so the two rendering paths stay visually identical. No runspace pool: the full entry
  # list is already known up front, so "does this folder contain a matching descendant" is a
  # cheap recursive check over an in-memory tree, not a filesystem walk needing a prescan cache.

  function Get-DowserArchiveMap {
      [CmdletBinding()]
      param(
          [Parameter(Mandatory = $true)]
          [string]$ArchivePath,

          [switch]$IncludeSize,
          [switch]$IncludeFileCount,
          [string[]]$IncludeFilePatterns,
          [string[]]$IncludeExtensions,
          [string[]]$ExcludeExtensions,
          [string[]]$ExcludeFolders,
          [string[]]$ExcludeFiles,
          [string[]]$IncludeFolders,
          [switch]$NoDefaultExcludes,
          [switch]$FoldersOnly,
          [int]$MaxDepth = 3,
          [switch]$ShowFullPathTree,
          [switch]$LinuxPaths,
          [switch]$Ascii,
          [switch]$AsHtml,
          [switch]$AsMarkdown,
          [string]$OutputFile,
          [string]$MarkdownFile,
          [switch]$EmitSummary,
          [string]$SevenZipPath
      )

      Write-Log "Starting Get-DowserArchiveMap for '$ArchivePath'" -Severity Verbose

      try {
          if ($PSBoundParameters.ContainsKey('SevenZipPath') -and $SevenZipPath) {
              $entries = Get-DowserArchiveEntry -Path $ArchivePath -SevenZipPath $SevenZipPath
          }
          else {
              $entries = Get-DowserArchiveEntry -Path $ArchivePath
          }
      }
      catch {
          $errTreeCharSet = Get-DowserTreeChars -Ascii:$Ascii -AsHtml:$AsHtml
          $errorLines = @("$($errTreeCharSet.ErrorChar) ARCHIVE UNREADABLE: $ArchivePath ($($_.Exception.Message))")
          Write-Log "Get-DowserArchiveMap failed to list entries for '$ArchivePath': $($_.Exception.Message)" -Severity Warning
          return Complete-DowserMapOutput -Lines $errorLines -TreeLines $errorLines -IsRootCall $true -EmitSummary:$EmitSummary -TraversalState @{FolderCount = 0; FileCount = 0; SkippedFolders = 0; SkippedFiles = 0; LinkCount = 0 } -OutputFile $OutputFile -MarkdownFile $MarkdownFile -AsMarkdown:$AsMarkdown -DisplayRoot $ArchivePath
      }

      function ConvertTo-NormalizedExtension {
          param([string]$ext)
          if ([string]::IsNullOrEmpty($ext)) {
              return ''
          }
          $ext = $ext.ToLowerInvariant()
          if ($ext -notmatch '^\.') {
              return ".$ext"
          }
          else {
              return $ext
          }
      }

      # Precompute normalized extension filters (mirrors Get-DowserMap.ps1's own normalization)
      $normInclude = @()
      if ($IncludeExtensions) {
          $normInclude = @($IncludeExtensions | ForEach-Object { ConvertTo-NormalizedExtension $_ })
      }

      $dowserDefaults = Get-DowserDefaultExclude
      $allExcludeExts = @()
      if (-not $NoDefaultExcludes) {
          $allExcludeExts += $dowserDefaults.Extensions
      }
      if ($ExcludeExtensions) {
          $allExcludeExts += @($ExcludeExtensions)
      }
      $allExcludeExts = $allExcludeExts | Select-Object -Unique
      $normExclude = @()
      if ($allExcludeExts) {
          $normExclude = @($allExcludeExts | ForEach-Object { ConvertTo-NormalizedExtension $_ })
      }

      $allExcludes = @()
      if (-not $NoDefaultExcludes) {
          $allExcludes += $dowserDefaults.Folders
      }
      if ($ExcludeFolders) {
          $allExcludes += @($ExcludeFolders)
      }
      $allExcludes = $allExcludes | Select-Object -Unique
      $excludeExact = @()
      $excludeWild = @()
      if ($allExcludes) {
          $excludeExact = @($allExcludes | Where-Object { $_ -notmatch '[\*\?\[\]]' })
          $excludeWild = @($allExcludes | Where-Object { $_ -match '[\*\?\[\]]' })
      }

      $allExcludeFiles = @()
      if (-not $NoDefaultExcludes) {
          $allExcludeFiles += $dowserDefaults.Files
      }
      if ($ExcludeFiles) {
          $allExcludeFiles += @($ExcludeFiles)
      }
      $allExcludeFiles = $allExcludeFiles | Select-Object -Unique
      $excludeExactFiles = @()
      $excludeWildFiles = @()
      if ($allExcludeFiles) {
          $excludeExactFiles = @($allExcludeFiles | Where-Object { $_ -notmatch '[\*\?\[\]]' })
          $excludeWildFiles = @($allExcludeFiles | Where-Object { $_ -match '[\*\?\[\]]' })
      }

      $effectiveIncludePatterns = @()
      if ($IncludeFilePatterns) {
          foreach ($pattern in $IncludeFilePatterns) {
              if ([string]::IsNullOrWhiteSpace($pattern)) {
                  continue
              }
              $p = $pattern.Trim()
              if ($p -notmatch '[\*\?\[\]]') {
                  if ($p.StartsWith('.')) {
                      $p = "*$p"
                  }
                  else {
                      $p = "*$p*"
                  }
              }
              $effectiveIncludePatterns += $p
          }
      }

      $includeExactNames = @(); $includeWildcardNames = @()
      if ($IncludeFolders) {
          foreach ($entry in $IncludeFolders) {
              if ([string]::IsNullOrWhiteSpace($entry)) {
                  continue
              }
              $normalizedEntry = $entry.Trim()
              if ($normalizedEntry -notmatch '[\*\?\[\]]') {
                  $includeExactNames += $normalizedEntry.ToLowerInvariant()
              }
              else {
                  $includeWildcardNames += $normalizedEntry
              }
          }
      }

      $fileFilterActive = (@($effectiveIncludePatterns).Count -gt 0 -or @($IncludeExtensions).Count -gt 0)

      $treeCharSet = Get-DowserTreeChars -Ascii:$Ascii -AsHtml:$AsHtml
      $treeChars = $treeCharSet.TreeChars
      $fileChar = $treeCharSet.FileChar
      $folderChar = $treeCharSet.FolderChar

      $traversalState = @{ FolderCount = 0; FileCount = 0; SkippedFolders = 0; SkippedFiles = 0; LinkCount = 0 }

      # --- Build the synthetic tree from flat entries ---
      $root = [ordered]@{}
      foreach ($entry in $entries) {
          if ([string]::IsNullOrWhiteSpace($entry.RelativePath)) {
              continue
          }
          $segments = $entry.RelativePath -split '/'
          $cursor = $root
          $broke = $false
          for ($i = 0; $i -lt $segments.Count; $i++) {
              $segName = $segments[$i]
              if ([string]::IsNullOrEmpty($segName)) {
                  continue
              }
              $isLastSegment = ($i -eq $segments.Count - 1)
              if (-not $cursor.Contains($segName)) {
                  if ($isLastSegment) {
                      $cursor[$segName] = [PSCustomObject]@{
                          Name        = $segName
                          IsDirectory = $entry.IsDirectory
                          Size        = $entry.Size
                          Children    = if ($entry.IsDirectory) { [ordered]@{} } else { $null }
                      }
                  }
                  else {
                      $cursor[$segName] = [PSCustomObject]@{
                          Name        = $segName
                          IsDirectory = $true
                          Size        = 0
                          Children    = [ordered]@{}
                      }
                  }
              }
              # else: a node already exists at this segment (folder created by an earlier entry,
              # or a folder entry arriving after its own children) -- keep the existing node,
              # a later file entry landing on an existing folder path never overwrites it.

              $node = $cursor[$segName]
              if (-not $node.IsDirectory -and -not $isLastSegment) {
                  # intermediate segment is already a file node in this archive's listing --
                  # pathological archive data, stop descending rather than throw.
                  $broke = $true
                  break
              }
              if (-not $isLastSegment) {
                  $cursor = $node.Children
              }
          }
          if ($broke) {
              continue
          }
      }

      # --- Recursive filter/measure helpers over the in-memory tree ---
      function Test-ArchiveIncludeFile {
          param([string]$Name)
          $ext = ConvertTo-NormalizedExtension ([System.IO.Path]::GetExtension($Name))
          if ($normInclude -and ($normInclude -notcontains $ext)) {
              return $false
          }
          if ($normExclude -and ($normExclude -contains $ext)) {
              return $false
          }
          if (@($effectiveIncludePatterns).Count -gt 0) {
              foreach ($pattern in $effectiveIncludePatterns) {
                  if ($Name -like $pattern) {
                      return $true
                  }
              }
              return $false
          }
          if (@($excludeExactFiles).Count -gt 0 -and ($excludeExactFiles -contains $Name)) {
              return $false
          }
          if (@($excludeWildFiles).Count -gt 0) {
              foreach ($pattern in $excludeWildFiles) {
                  if ($Name -like $pattern) {
                      return $false
                  }
              }
          }
          return $true
      }

      function Test-ArchiveExcludeFolder {
          param([string]$Name)
          if (@($excludeExact).Count -gt 0 -and ($excludeExact -contains $Name)) {
              return $true
          }
          if (@($excludeWild).Count -gt 0) {
              foreach ($pattern in $excludeWild) {
                  if ($Name -like $pattern) {
                      return $true
                  }
              }
          }
          return $false
      }

      function Test-ArchiveFolderNameMatchesInclude {
          param([string]$Name)
          if (@($IncludeFolders).Count -eq 0) {
              return $true
          }
          $nameKey = $Name.ToLowerInvariant()
          if (@($includeExactNames).Count -gt 0 -and ($includeExactNames -contains $nameKey)) {
              return $true
          }
          if (@($includeWildcardNames).Count -gt 0) {
              foreach ($pattern in $includeWildcardNames) {
                  if ($Name -like $pattern) {
                      return $true
                  }
              }
          }
          return $false
      }

      function Test-ArchiveFolderInclude {
          param($Node)
          if (@($IncludeFolders).Count -eq 0) {
              return $true
          }
          if (Test-ArchiveFolderNameMatchesInclude -Name $Node.Name) {
              return $true
          }
          if ($Node.Children) {
              foreach ($child in $Node.Children.Values) {
                  if ($child.IsDirectory -and (Test-ArchiveFolderInclude -Node $child)) {
                      return $true
                  }
              }
          }
          return $false
      }

      function Test-ArchiveNodeHasMatch {
          param($Node)
          if (-not $fileFilterActive) {
              return $true
          }
          if (-not $Node.IsDirectory) {
              return (Test-ArchiveIncludeFile -Name $Node.Name)
          }
          if ($Node.Children) {
              foreach ($child in $Node.Children.Values) {
                  if (Test-ArchiveNodeHasMatch -Node $child) {
                      return $true
                  }
              }
          }
          return $false
      }

      function Get-ArchiveFolderSize {
          param($Node)
          if (-not $Node.IsDirectory) {
              if ($fileFilterActive -and -not (Test-ArchiveIncludeFile -Name $Node.Name)) {
                  return 0
              }
              return $Node.Size
          }
          $total = 0
          if ($Node.Children) {
              foreach ($child in $Node.Children.Values) {
                  $total += (Get-ArchiveFolderSize -Node $child)
              }
          }
          return $total
      }

      function Get-ArchiveFolderFileCount {
          param($Node)
          if (-not $Node.IsDirectory) {
              if ($fileFilterActive -and -not (Test-ArchiveIncludeFile -Name $Node.Name)) {
                  return 0
              }
              return 1
          }
          $total = 0
          if ($Node.Children) {
              foreach ($child in $Node.Children.Values) {
                  $total += (Get-ArchiveFolderFileCount -Node $child)
              }
          }
          return $total
      }

      # Write-ArchiveNode returns its rendered lines rather than mutating a shared array --
      # PowerShell's default scoping would otherwise shadow a $script-less `$output += ...`
      # inside a nested function with a new local variable instead of updating the caller's.
      function Write-ArchiveNode {
          param($Node, [string]$Indent, [int]$Depth)

          $result = @()
          $allChildren = @()
          if ($Node.Children) {
              $allChildren = @($Node.Children.Values)
          }
          $childFolders = @($allChildren | Where-Object { $_.IsDirectory } | Sort-Object Name)
          $childFiles = @($allChildren | Where-Object { -not $_.IsDirectory } | Sort-Object Name)

          $keptFolders = @()
          foreach ($folder in $childFolders) {
              if (Test-ArchiveExcludeFolder -Name $folder.Name) {
                  $traversalState.SkippedFolders++
                  continue
              }
              if ($fileFilterActive -and -not (Test-ArchiveNodeHasMatch -Node $folder)) {
                  $traversalState.SkippedFolders++
                  continue
              }
              if (-not (Test-ArchiveFolderInclude -Node $folder)) {
                  $traversalState.SkippedFolders++
                  continue
              }
              $keptFolders += $folder
          }

          $keptFiles = @()
          if (-not $FoldersOnly -or $fileFilterActive) {
              foreach ($file in $childFiles) {
                  if (-not (Test-ArchiveIncludeFile -Name $file.Name)) {
                      $traversalState.SkippedFiles++
                      continue
                  }
                  $keptFiles += $file
              }
          }

          $items = @($keptFolders) + @($keptFiles)
          $count = @($items).Count

          for ($i = 0; $i -lt $count; $i++) {
              $item = $items[$i]
              $isLast = ($i -eq $count - 1)
              $connector = if ($isLast) { $treeChars.Last } else { $treeChars.Branch }
              $nextIndent = if ($isLast) { "$Indent$($treeChars.Space)" } else { "$Indent$($treeChars.Pipe)" }

              if ($item.IsDirectory) {
                  $annotation = ''
                  if ($IncludeSize) {
                      $annotation += " [$(Format-DowserSize (Get-ArchiveFolderSize -Node $item))]"
                  }
                  if ($IncludeFileCount) {
                      $annotation += " [$(Get-ArchiveFolderFileCount -Node $item) files]"
                  }
                  $result += "$Indent$connector $folderChar $($item.Name)/$annotation"
                  $traversalState.FolderCount++
                  if ($Depth -lt $MaxDepth) {
                      $result += Write-ArchiveNode -Node $item -Indent $nextIndent -Depth ($Depth + 1)
                  }
              }
              else {
                  $result += "$Indent$connector $fileChar $($item.Name)"
                  $traversalState.FileCount++
              }
          }

          return $result
      }

      $rootNode = [PSCustomObject]@{ Name = ''; IsDirectory = $true; Size = 0; Children = $root }

      $output = @()
      $baseIndent = ""
      if ($ShowFullPathTree) {
          $trunkPath = if ($LinuxPaths) { ($ArchivePath -replace '\\', '/') } else { $ArchivePath }
          $segments = @()
          if ($LinuxPaths) {
              if ($trunkPath.StartsWith('/')) {
                  $segments += '/'
              }
              $remaining = $trunkPath.TrimStart('/')
              if ($remaining) {
                  $segments += $remaining -split '/'
              }
          }
          elseif ($trunkPath -match '^(\\\\|//)([^\\/]+)[\\/]+([^\\/]+)[\\/]*(.*)') {
              $segments += $matches[2]; $segments += $matches[3]
              if ($matches[4]) {
                  $segments += $matches[4] -split '[\\/]'
              }
          }
          elseif ($trunkPath -match '^([a-zA-Z]:)[\\/]*(.*)') {
              $segments += $matches[1]
              if ($matches[2]) {
                  $segments += $matches[2] -split '[\\/]'
              }
          }
          else {
              $segments += $trunkPath -split '[\\/]'
          }
          $segments = $segments | Where-Object { $_ -ne '' -or $_ -eq '/' }

          $currentIndent = ""
          for ($i = 0; $i -lt @($segments).Count; $i++) {
              $segmentName = $segments[$i]
              $connector = $treeChars.Last + " "
              $output += "$currentIndent$connector$folderChar $segmentName"
              $currentIndent += "    "
          }
          $baseIndent = $currentIndent
      }

      $output += Write-ArchiveNode -Node $rootNode -Indent $baseIndent -Depth 0

      $displayRoot = if ($LinuxPaths) { ($ArchivePath -replace '\\', '/') } else { $ArchivePath }
      $result = Complete-DowserMapOutput -Lines $output -TreeLines $output -IsRootCall $true -EmitSummary:$EmitSummary -TraversalState $traversalState -OutputFile $OutputFile -MarkdownFile $MarkdownFile -AsMarkdown:$AsMarkdown -DisplayRoot $displayRoot

      Write-Log "Ending Get-DowserArchiveMap" -Severity Verbose
      return $result
  }
  ```

- [ ] **Step 4: Confirm the tests pass**

  Run:
  ```
  Invoke-Pester -Path ./Tests/Get-DowserArchiveMap.Tests.ps1 -Output Detailed
  ```
  Expected: all 8 It-blocks PASS.

- [ ] **Step 5: Commit**
  ```
  git add Private/Get-DowserArchiveMap.ps1 Tests/Get-DowserArchiveMap.Tests.ps1 && git commit -m "feat(Get-DowserMap): add Get-DowserArchiveMap private helper for archive tree synthesis and rendering"
  ```

---

## Task 6: Wire archive-mode into Get-DowserMap.ps1

**Files:**
- Modify: `Public/Get-DowserMap.ps1`
- Modify: `Tests/Get-DowserMap.Tests.ps1` (add a new `Describe` block; do not touch existing ones)

- [ ] **Step 1: Add the -SevenZipPath parameter**

  In `Public/Get-DowserMap.ps1`'s param block, add a new `# Archive Options` group right after the existing `# Performance Options` group (after `$MaxThreads`):
  ```powershell
          # Archive Options
          [string]$SevenZipPath = $(if ($IsWindows -eq $false) {
                  '7z'
              }
              else {
                  Join-Path ${env:ProgramFiles} '7-Zip\7z.exe'
              }),
  ```

- [ ] **Step 2: Add the comment-based help entries**

  Add a `.PARAMETER SevenZipPath` block to the comment-based help, right after the existing `.PARAMETER MaxThreads` entry:
  ```
      .PARAMETER SevenZipPath
          Path to 7z executable, used only when -Path resolves to a non-.zip archive file (.7z/.rar/.tar/.gz). On Windows, defaults to the standard 7-Zip install path. On Linux/macOS, defaults to '7z' (expected on PATH).
  ```
  Add one new `.EXAMPLE` block after the existing last `.EXAMPLE`:
  ```
      .EXAMPLE
          Get-DowserMap -Path D:\Downloads\project.zip

          Auto-detects the .zip archive and renders its internal folder/file structure as a tree.
  ```

- [ ] **Step 3: Insert the archive-detection branch**

  Insert this block immediately after the existing `if ($AsHtml -and $AsMarkdown) { ...; return }` block and before the `function ConvertTo-NormalizedExtension { ... }` definition (i.e., right after the exact existing lines: `Write-Log "Get-DowserMap called with both -AsHtml and -AsMarkdown; these are mutually exclusive" -Severity Warning` followed by `return` and the closing `}`):
  ```powershell
      if ($CurrentDepth -eq 0) {
          $resolvedLeafPath = $Path
          try {
              $resolvedLeafPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
          }
          catch {
          }
          if (Test-Path -LiteralPath $resolvedLeafPath -PathType Leaf) {
              $archiveExt = [System.IO.Path]::GetExtension($resolvedLeafPath).ToLowerInvariant()
              if ($archiveExt -in @('.zip', '.7z', '.rar', '.tar', '.gz')) {
                  $archiveMapParams = @{
                      ArchivePath         = $resolvedLeafPath
                      IncludeSize         = $IncludeSize
                      IncludeFileCount    = $IncludeFileCount
                      IncludeFilePatterns = $IncludeFilePatterns
                      IncludeExtensions   = $IncludeExtensions
                      ExcludeExtensions   = $ExcludeExtensions
                      ExcludeFolders      = $ExcludeFolders
                      ExcludeFiles        = $ExcludeFiles
                      IncludeFolders      = $IncludeFolders
                      NoDefaultExcludes   = $NoDefaultExcludes
                      FoldersOnly         = $FoldersOnly
                      MaxDepth            = $MaxDepth
                      ShowFullPathTree    = $ShowFullPathTree
                      LinuxPaths          = $LinuxPaths
                      Ascii               = $Ascii
                      AsHtml              = $AsHtml
                      AsMarkdown          = $AsMarkdown
                      OutputFile          = $OutputFile
                      MarkdownFile        = $MarkdownFile
                      EmitSummary         = $EmitSummary
                      SevenZipPath        = $SevenZipPath
                  }
                  return Get-DowserArchiveMap @archiveMapParams
              }
          }
      }
  ```
  This must be placed so it only runs once per top-level `Get-DowserMap` invocation (`$CurrentDepth -eq 0`), never during the function's own recursive self-calls into real subfolders (those always operate on already-known real directory paths from a real-folder-mode call; archive mode never recurses back into `Get-DowserMap`, so there is no case where a recursive self-call needs the archive check).

- [ ] **Step 4: Write the failing end-to-end test**

  Append this `Describe` block to the end of `Tests/Get-DowserMap.Tests.ps1` (after the file's existing final closing brace; do not touch anything above it):
  ```powershell
  Describe 'Get-DowserMap archive-mode auto-detection' {
      BeforeAll {
          $modulePath = Split-Path $PSScriptRoot -Parent
          Remove-Module Dowser -Force -ErrorAction SilentlyContinue
          Import-Module (Join-Path $modulePath 'Dowser.psd1') -Force -ErrorAction Stop

          Add-Type -AssemblyName System.IO.Compression -ErrorAction SilentlyContinue

          $script:tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "DowserMapArchiveE2E_$([guid]::NewGuid().Guid)"
          New-Item -ItemType Directory -Path $script:tmpDir -Force | Out-Null
          $script:zipPath = Join-Path $script:tmpDir 'e2e.zip'
          $archive = [System.IO.Compression.ZipFile]::Open($script:zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
          try {
              $entry = $archive.CreateEntry('inside.txt')
              $writer = New-Object System.IO.StreamWriter($entry.Open())
              $writer.Write('hello'); $writer.Close()
          }
          finally {
              $archive.Dispose()
          }
      }

      AfterAll {
          if (Test-Path -LiteralPath $script:tmpDir) {
              Remove-Item -LiteralPath $script:tmpDir -Recurse -Force -ErrorAction SilentlyContinue
          }
      }

      It 'Renders the zip contents when -Path points at a .zip file' {
          $out = Get-DowserMap -Path $script:zipPath -ShowFullPathTree:$false
          ($out -join "`n") | Should -Match 'inside\.txt'
      }
  }
  ```

  Run this before applying Step 1-3's wiring changes (with only the new `Describe` block added and the archive-detection branch not yet in the file):
  ```
  Invoke-Pester -Path ./Tests/Get-DowserMap.Tests.ps1 -Output Detailed
  ```
  Expected: the new test FAILS (the zip renders as a broken single-line node, not containing `inside.txt` as a tree entry, or errors), because `Get-DowserMap` does not yet detect archive files.

- [ ] **Step 5: Apply the wiring changes and confirm all tests pass**

  Apply the param-block edit (Step 1), the comment-help edit (Step 2), and the archive-detection branch edit (Step 3) to `Public/Get-DowserMap.ps1`, then run:
  ```
  Invoke-Pester -Path ./Tests/Get-DowserMap.Tests.ps1 -Output Detailed
  ```
  Expected: ALL tests in the file (existing + new) PASS.

- [ ] **Step 6: Commit**
  ```
  git add Public/Get-DowserMap.ps1 Tests/Get-DowserMap.Tests.ps1 && git commit -m "feat(Get-DowserMap): auto-detect archive files and render internal contents as a tree"
  ```

- [ ] **Step 7: Run the full test suite to confirm no regressions**

  Run:
  ```
  Invoke-Pester -Path ./Tests/ -Output Detailed
  ```
  Expected: zero failures across the whole `Tests/` directory. This confirms Tasks 1-6 together did not regress anything else (e.g. `Test-DowserExtractable`/`Expand-DowserExe` tests that also touch zip/7z code).

---

## Task 7: Documentation updates

**Files:**
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/INDEX.md`
- Modify: `docs/CHANGELOG.md`
- Modify: `README.md`

No tests in this task (docs-only).

- [ ] **Step 1: Update the Private helpers table and module-structure comment in docs/ARCHITECTURE.md**

  In the Private helpers table (columns `| File | Purpose |`, currently 6 data rows ending with the `Write-Log.ps1` row), add 5 new rows right after the existing `Test-DowserHelpers.ps1` row and before the `Write-Log.ps1` row (keep `Write-Log.ps1` last since the surrounding prose already describes it as the always-first-loaded file):
  ```
  | Get-DowserDefaultExclude.ps1  | Shared default exclude lists (extensions/folders/files) for Get-DowserMap's real-folder and archive-mode renderers                |
  | Get-DowserTreeChars.ps1       | Shared box-drawing character/icon set (Ascii/Unicode/HTML) for Get-DowserMap's real-folder and archive-mode renderers             |
  | Complete-DowserMapOutput.ps1  | Shared output finisher (EmitSummary block, -OutputFile/-MarkdownFile writing) for Get-DowserMap's real-folder and archive-mode renderers |
  | Get-DowserArchiveEntry.ps1    | Lists normalized flat entries from an archive file (.zip natively, .7z/.rar/.tar/.gz via 7-Zip CLI)                               |
  | Get-DowserArchiveMap.ps1      | Builds a synthetic tree from archive entries and renders it in Get-DowserMap's tree-output style                                 |
  ```

  Update the module-structure code fence comment from:
  ```
                      +-- Private/*.ps1    (6 helpers, not exported)
  ```
  to:
  ```
                      +-- Private/*.ps1    (11 helpers, not exported)
  ```

  Add one sentence to the "Design decisions" section:
  ```
  **Archive-mode is a separate rendering path.** Get-DowserMap delegates to Get-DowserArchiveMap (a dedicated Private renderer) when -Path resolves to a recognized archive file, rather than integrating archive listing into the real-folder recursive walk -- this keeps the existing, well-tested filesystem-traversal code path completely untouched.
  ```

- [ ] **Step 2: Update the Get-DowserMap entry in docs/INDEX.md**

  Find this exact block (the current `### Get-DowserMap` entry):
  ```
  ### Get-DowserMap

  - Purpose: Visual tree renderer for directory structures. Renders folder/file hierarchy using Unicode box-drawing characters with optional size (-IncludeSize) and file count (-IncludeFileCount, alias: -IncludePsCount) annotations. Supports HTML, Markdown, and full-path trunk display modes. Symlinks are shown in place without traversal by default (two-line block: a name line marked U+2192 and a target line marked U+21B3); use -FollowReparse to descend into them.
  - Inputs: `Path` (pipeline, FullName alias), `MaxDepth` (default 3), `ShowFullPathTree` / `S`, `LinuxPaths` / `L`, `Ascii`, `AsHtml`, `AsMarkdown`, `IncludeHidden`, `FollowReparse`, `IncludeSize`, `IncludeFileCount` (alias: `IncludePsCount`), `FoldersOnly`, `IncludeFilePatterns`, `IncludeExtensions`, `ExcludeExtensions`, `ExcludeFolders`, `ExcludeFiles`, `IncludeFolders`, `ExcludePathPatterns`, `NoDefaultExcludes`, `OutputFile`, `MarkdownFile`, `EmitSummary`, `UseRunspaces`, `MaxThreads`
  - Outputs: String array of tree lines (pipeline). Optional file output via -OutputFile / -MarkdownFile.
  - Tree glyphs: `■` folder, `·` file, `→` (U+2192) symlink name, `↳` (U+21B3) symlink target, `×` access denied. Box-drawing: `├─` branch, `└─` last, `│` continuation. HTML mode emits `&#xNNNN;` entities; -Ascii mode uses `+`/`-`/`>`/`~`.
  - Related: `Get-DowserTopology` (any PSProvider path, ANSI color, no size/count annotations)
  - Source: `Get-DowserMap.ps1`
  - Aliases: `dmap`
  ```
  Replace with:
  ```
  ### Get-DowserMap

  - Purpose: Visual tree renderer for directory structures. Renders folder/file hierarchy using Unicode box-drawing characters with optional size (-IncludeSize) and file count (-IncludeFileCount, alias: -IncludePsCount) annotations. Supports HTML, Markdown, and full-path trunk display modes. Symlinks are shown in place without traversal by default (two-line block: a name line marked U+2192 and a target line marked U+21B3); use -FollowReparse to descend into them. When -Path points at an archive file (`.zip`, `.7z`, `.rar`, `.tar`, `.gz`) instead of a directory, archive mode auto-activates and renders the archive's internal contents as the same style of tree, applying MaxDepth/size/count/extension/pattern/folder filters against the archive entries. `.zip` is read natively; other formats use the 7-Zip CLI via -SevenZipPath. -IncludeHidden, -FollowReparse, and -UseRunspaces/-MaxThreads do not apply in archive mode.
  - Inputs: `Path` (pipeline, FullName alias), `MaxDepth` (default 3), `ShowFullPathTree` / `S`, `LinuxPaths` / `L`, `Ascii`, `AsHtml`, `AsMarkdown`, `IncludeHidden`, `FollowReparse`, `IncludeSize`, `IncludeFileCount` (alias: `IncludePsCount`), `FoldersOnly`, `IncludeFilePatterns`, `IncludeExtensions`, `ExcludeExtensions`, `ExcludeFolders`, `ExcludeFiles`, `IncludeFolders`, `ExcludePathPatterns`, `NoDefaultExcludes`, `OutputFile`, `MarkdownFile`, `EmitSummary`, `UseRunspaces`, `MaxThreads`, `SevenZipPath` (archive mode only, for `.7z`/`.rar`/`.tar`/`.gz`)
  - Outputs: String array of tree lines (pipeline). Optional file output via -OutputFile / -MarkdownFile.
  - Tree glyphs: `■` folder, `·` file, `→` (U+2192) symlink name, `↳` (U+21B3) symlink target, `×` access denied/archive unreadable. Box-drawing: `├─` branch, `└─` last, `│` continuation. HTML mode emits `&#xNNNN;` entities; -Ascii mode uses `+`/`-`/`>`/`~`.
  - Related: `Get-DowserTopology` (any PSProvider path, ANSI color, no size/count annotations)
  - Source: `Get-DowserMap.ps1`, `Get-DowserArchiveEntry.ps1` (Private), `Get-DowserArchiveMap.ps1` (Private)
  - Aliases: `dmap`
  ```

- [ ] **Step 3: Add a new entry to docs/CHANGELOG.md**

  Add a new entry at the top of the file, right after the `# Changelog` header and its description line (i.e., right before the first existing `## [...]` entry). No `2026-07-05` entry exists yet in this file, so this is `.001`:
  ```
  ## [2026.07.05.001] - 2026-07-05
  ### feat(Get-DowserMap): Archive-mode -- render .zip/.7z/.rar/.tar/.gz contents as a tree

  What changed:
  - Get-DowserMap now auto-detects when -Path resolves to a recognized archive file (.zip, .7z, .rar, .tar, .gz) and renders its internal contents as a tree, instead of the previous broken single-line output for a leaf-file path.
  - .zip is read natively via System.IO.Compression.ZipFile (no external dependency). .7z/.rar/.tar/.gz are listed via the 7-Zip CLI (`7z l -slt`), using the same -SevenZipPath convention as Test-DowserExtractable/Expand-DowserExe.
  - Archive mode supports -MaxDepth, -IncludeSize, -IncludeFileCount, -IncludeExtensions/-ExcludeExtensions/-IncludeFilePatterns/-ExcludeFiles/-ExcludeFolders/-IncludeFolders, -Ascii/-AsHtml/-AsMarkdown, -OutputFile/-MarkdownFile, -EmitSummary, -NoDefaultExcludes, and -LinuxPaths/-ShowFullPathTree. It does not support -IncludeHidden, -FollowReparse, or -UseRunspaces/-MaxThreads (no parallel prescan needed; archive listing is already a single pass).
  - New Private helpers: Get-DowserArchiveEntry.ps1 (flat entry listing), Get-DowserArchiveMap.ps1 (tree synthesis and rendering).
  - Extracted three pieces of Get-DowserMap's existing logic into shared Private helpers so both rendering paths stay identical: Get-DowserDefaultExclude.ps1 (default exclude lists), Get-DowserTreeChars.ps1 (box-drawing char selection), Complete-DowserMapOutput.ps1 (output-finishing/-EmitSummary/-OutputFile/-MarkdownFile logic). Get-DowserMap.ps1's own real-folder rendering behavior is unchanged (verified by the existing Pester suite passing unchanged).
  - Known v1 limitation: gzip-wrapped tarballs (.tar.gz/.tgz) are not unwrapped two levels deep -- the inner .tar shows as one opaque entry rather than being descended into.

  Files changed:
  - Public/Get-DowserMap.ps1 -- added -SevenZipPath parameter, added archive-detection branch, refactored to consume the three extracted shared helpers.
  - Private/Get-DowserArchiveEntry.ps1, Private/Get-DowserArchiveMap.ps1, Private/Get-DowserDefaultExclude.ps1, Private/Get-DowserTreeChars.ps1, Private/Complete-DowserMapOutput.ps1 -- new.
  - Tests/Get-DowserArchiveEntry.Tests.ps1, Tests/Get-DowserArchiveMap.Tests.ps1 -- new. Tests/Get-DowserMap.Tests.ps1 -- added archive-mode auto-detection Describe block.
  - docs/ARCHITECTURE.md, docs/INDEX.md, README.md -- documented archive mode.

  ```

- [ ] **Step 4: Add an archive-mode example to README.md**

  Find this exact block:
  ```
  # render a directory as a tree
  Get-DowserMap -Path . -IncludeSize
  ```
  Replace with:
  ```
  # render a directory as a tree
  Get-DowserMap -Path . -IncludeSize

  # ...or point it at an archive and get the same tree for what's inside
  Get-DowserMap -Path ./release.zip -IncludeSize
  ```

- [ ] **Step 5: Commit**
  ```
  git add docs/ARCHITECTURE.md docs/INDEX.md docs/CHANGELOG.md README.md && git commit -m "docs: document Get-DowserMap archive-mode"
  ```

---

## Self-Review

**Spec coverage against `docs/superpowers/specs/2026-07-05-archive-map-design.md`:**
- Formats (.zip native, .7z/.rar/.tar/.gz via 7-Zip CLI with `-SevenZipPath`) -- covered in Task 4 (`Get-DowserArchiveEntry`).
- Auto-detect trigger at `$CurrentDepth -eq 0` with no new opt-in switch -- covered in Task 6, Step 3.
- Core-parity filter/annotation surface (`-MaxDepth`, `-IncludeSize`, `-IncludeFileCount`, extension/pattern/folder filters, `-Ascii`/`-AsHtml`/`-AsMarkdown`, `-OutputFile`/`-MarkdownFile`, `-EmitSummary`, `-NoDefaultExcludes`, `-LinuxPaths`/`-ShowFullPathTree`) -- covered in Task 5's `Get-DowserArchiveMap` signature and body. Out-of-scope items (`-IncludeHidden`, `-FollowReparse`, `-UseRunspaces`/`-MaxThreads`) are correctly absent from that signature and from the Task 6 splat.
- Nested compound archives (`.tar.gz`/`.tgz` two-layer unwrap) explicitly out of scope for v1 -- documented as a known limitation in Task 7's changelog entry; no code in Task 4/5 attempts double-unwrapping.
- New Private helpers `Get-DowserArchiveEntry`/`Get-DowserArchiveMap` -- Tasks 4 and 5.
- Extracted shared Private helpers `Get-DowserDefaultExclude`/`Get-DowserTreeChars`/`Complete-DowserMapOutput` -- Tasks 1-3, each verified behavior-preserving against the existing Pester suite before the new capability is built on top of them.
- Error handling (`ARCHIVE UNREADABLE` line, no throw; missing-7z clear error) -- covered by `Get-DowserArchiveEntry`'s throws (Task 4) being caught and converted to the `ARCHIVE UNREADABLE` line inside `Get-DowserArchiveMap` (Task 5), with a dedicated Pester assertion in both tasks' test files plus the Task 6 end-to-end Describe block.
- Documentation updates (ARCHITECTURE.md, INDEX.md, CHANGELOG.md, README.md) -- Task 7, one step per file.

**Placeholder scan:** no `TBD`, `add appropriate X`, or `similar to Task N` shortcuts appear anywhere above; every code step in every task carries full, verbatim, runnable content, including Task 5's complete `Get-DowserArchiveMap` body (all seven nested helper functions fully implemented, no stubs).

**Type/signature consistency check (`Get-DowserArchiveMap` across Task 5 and Task 6):**
Task 5's param block declares exactly these 21 parameters: `ArchivePath`, `IncludeSize`, `IncludeFileCount`, `IncludeFilePatterns`, `IncludeExtensions`, `ExcludeExtensions`, `ExcludeFolders`, `ExcludeFiles`, `IncludeFolders`, `NoDefaultExcludes`, `FoldersOnly`, `MaxDepth`, `ShowFullPathTree`, `LinuxPaths`, `Ascii`, `AsHtml`, `AsMarkdown`, `OutputFile`, `MarkdownFile`, `EmitSummary`, `SevenZipPath`. Task 6's `$archiveMapParams` splat in the archive-detection branch supplies the identical 21 keys, one-to-one, with matching casing and no extras or omissions. Verified by direct comparison during authoring; no drift found.

**Internal fix applied during authoring (not a spec change, a correctness fix within the given design):** the original design sketch for `Write-ArchiveNode` in Task 5 risked an `$output +=` mutation from inside a nested function, which PowerShell's scoping rules would silently shadow with a new local variable instead of updating the caller's array (the same reason the real `Get-DowserMap.ps1` only ever appends to `$output` from the top-level function body, never from inside one of its own nested helper functions). `Write-ArchiveNode` is written to return its lines and have the caller accumulate them (`$output += Write-ArchiveNode ...`), matching the existing codebase's own pattern and avoiding that pitfall. `Test-ArchiveFolderInclude`'s recursion was similarly tightened to only recurse into directory children (matching the design's "or any descendant folder does" wording) rather than re-testing the parent node's own name against file children, which would have been redundant and misleading.
