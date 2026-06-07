# Dowser Cross-Platform Compatibility Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Dowser module importable and functional on Linux/macOS under pwsh 7+, while preserving full backward compatibility on Windows PowerShell 5.1.

**Architecture:** Add platform detection at module load time (before dot-sourcing). Move Windows-only assembly loads inside function bodies behind platform guards. Functions that are fundamentally Windows-only emit a descriptive warning and return `$null` on non-Windows. Functions that partially degrade (COM metadata unavailable) continue with reduced output and a verbose message.

**Tech Stack:** PowerShell 5.1+ (Windows), pwsh 7+ (Linux/macOS), Pester 5 for tests.

---

## File Structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Modify | `Dowser.psm1` | Add platform detection variables before dot-sourcing |
| Modify | `Public/ConvertTo-DowserIco.ps1` | Move System.Drawing load inside function, platform guard |
| Modify | `Public/ConvertTo-DowserExe.ps1` | Platform guard with warning |
| Modify | `Public/Get-DowserTemplate.ps1` | Platform guard with warning |
| Modify | `Public/Get-DowserProperty.ps1` | Platform guard on COM/signature paths |
| Modify | `Private/Write-Log.ps1` | Safe identity resolution (4 occurrences) |
| Modify | `Public/Get-DowserInfo.ps1` | Fix backslash path literal |
| Modify | `Public/Expand-DowserExe.ps1` | Platform-aware 7-Zip default |
| Modify | `Public/Test-DowserExtractable.ps1` | Platform-aware 7-Zip + expand.exe defaults |
| Modify | `Public/Test-DowserIntegrity.ps1` | Platform-aware 7-Zip + expand.exe defaults |
| Modify | `Dowser.psd1` | Add CompatiblePSEditions |
| Create | `Tests/Test-DowserCrossPlatform.Tests.ps1` | Platform compat test suite |
| Modify | `docs/INDEX.md` | Document platform support |
| Modify | `docs/CHANGELOG.md` | Record all changes |

---

### Task 1: Platform Detection Foundation

**Files:**
- Modify: `Dowser.psm1` (lines 1-3, insert before existing content)

**Why:** PowerShell 5.1 does not define `$IsWindows`, `$IsLinux`, or `$IsMacOS`. Code that checks these variables needs them to exist regardless of PS version. Setting them at module scope before any dot-sourcing guarantees every function in the module can use `$IsWindows` safely.

- [ ] **Step 1: Write the failing test**

Create `Tests/Test-DowserCrossPlatform.Tests.ps1`:

```powershell
#Requires -Modules Pester

Describe 'Dowser Cross-Platform Support' {
    BeforeAll {
        $modulePath = Split-Path $PSScriptRoot -Parent
        Remove-Module Dowser -Force -ErrorAction SilentlyContinue
        Import-Module "$modulePath/Dowser.psd1" -Force
    }

    Context 'Module Import' {
        It 'Imports without error on any platform' {
            { Import-Module "$modulePath/Dowser.psd1" -Force } | Should -Not -Throw
        }

        It 'Exports expected cross-platform functions' {
            $commands = Get-Command -Module Dowser
            $commands.Name | Should -Contain 'Find-DowserDuplicate'
            $commands.Name | Should -Contain 'Find-DowserFile'
            $commands.Name | Should -Contain 'Measure-DowserDirectory'
            $commands.Name | Should -Contain 'Get-DowserMap'
        }
    }

    Context 'Platform Variables' {
        It 'Has $IsWindows defined after module load' {
            $IsWindows | Should -Not -BeNullOrEmpty -Because 'Platform detection must set this'
            $IsWindows | Should -BeOfType [bool]
        }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `pwsh -Command "Invoke-Pester ./Tests/Test-DowserCrossPlatform.Tests.ps1 -Output Detailed"`

Expected on Linux: FAIL — module import throws due to `System.Drawing` assembly load.

- [ ] **Step 3: Add platform detection to Dowser.psm1**

Replace the full content of `Dowser.psm1` with:

```powershell
#Requires -Version 5.1
# Dowser root module - dot-sources Public/Private/Aliases

# Platform detection: PS 5.1 is Windows-only and lacks these variables.
# Define them at module scope so all functions can use $IsWindows safely.
if (-not (Test-Path variable:global:IsWindows)) {
    $global:IsWindows = $true
    $global:IsLinux   = $false
    $global:IsMacOS   = $false
}

$Public  = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public' '*.ps1') -ErrorAction SilentlyContinue)
$Private = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private' '*.ps1') -ErrorAction SilentlyContinue)

foreach ($file in @($Private + $Public)) {
    try { . $file.FullName }
    catch { Write-Error "Failed to import $($file.FullName): $_" }
}

if (Test-Path (Join-Path $PSScriptRoot 'Aliases' 'Aliases.ps1')) {
    . (Join-Path $PSScriptRoot 'Aliases' 'Aliases.ps1')
}

Export-ModuleMember -Function $Public.BaseName -Alias *
```

Note: Also replaced backslash-only path constructions (`$PSScriptRoot\Public\*.ps1`) with `Join-Path` for cross-platform path resolution.

- [ ] **Step 4: Run test — still fails (import blocker not yet fixed)**

Run: `pwsh -Command "Invoke-Pester ./Tests/Test-DowserCrossPlatform.Tests.ps1 -Output Detailed"`

Expected on Linux: Still FAIL — ConvertTo-DowserIco.ps1 System.Drawing blocks import. Platform variables step passes if tested in isolation.

- [ ] **Step 5: Commit**

```bash
git add Dowser.psm1 Tests/Test-DowserCrossPlatform.Tests.ps1
git commit -m "feat: add platform detection and cross-platform path resolution to module root"
```

---

### Task 2: Fix Import Blocker — ConvertTo-DowserIco.ps1

**Files:**
- Modify: `Public/ConvertTo-DowserIco.ps1` (line 1 — move inside function, add guard)

**Why:** `Add-Type -AssemblyName System.Drawing` on line 1 executes at dot-source time during module import. On Linux, this assembly does not exist, causing the entire module to fail. Moving it inside the function body and guarding with `$IsWindows` means the module imports cleanly and the function only fails when actually called on non-Windows.

- [ ] **Step 1: Write the failing test**

Add to `Tests/Test-DowserCrossPlatform.Tests.ps1`:

```powershell
    Context 'Windows-Only Functions on Non-Windows' -Skip:($IsWindows) {
        It 'ConvertTo-DowserIco returns warning on Linux' {
            $result = ConvertTo-DowserIco -InputFilePath '/tmp/fake.png' -WarningVariable warn 3>$null
            $result | Should -BeNullOrEmpty
            $warn | Should -Not -BeNullOrEmpty
            $warn[0] | Should -BeLike '*Windows*'
        }
    }

    Context 'Windows-Only Functions on Windows' -Skip:(-not $IsWindows) {
        It 'ConvertTo-DowserIco is available' {
            Get-Command ConvertTo-DowserIco -Module Dowser | Should -Not -BeNullOrEmpty
        }
    }
```

- [ ] **Step 2: Run test — fails (import still broken)**

Run: `pwsh -Command "Invoke-Pester ./Tests/Test-DowserCrossPlatform.Tests.ps1 -Output Detailed"`

- [ ] **Step 3: Fix ConvertTo-DowserIco.ps1**

Remove line 1 (`Add-Type -AssemblyName System.Drawing`). Add platform guard at the top of the function body:

```powershell
function ConvertTo-DowserIco {
    param(
        [Parameter(Mandatory=$true)]
        [string]$InputFilePath,
        [Parameter(Mandatory=$false)]
        [string]$OutputFile,
        [Parameter(Mandatory=$false)]
        [Alias('IconSize','Size','Sizes')]
        [int[]]
        $IcoSizes = @(256),
        [Parameter(Mandatory=$false)]
        [int]
        $MaxSize = 0
    )

    # Platform guard: System.Drawing requires Windows GDI+
    if (-not $IsWindows) {
        Write-Warning "ConvertTo-DowserIco requires Windows (System.Drawing/GDI+). Not available on this platform."
        return $null
    }

    Add-Type -AssemblyName System.Drawing

    if (-not (Test-Path $InputFilePath)) {
        Write-Error "Input file '$InputFilePath' does not exist."
        return $false
    }
    # ... rest of function unchanged
```

The key change: `Add-Type` moves from file scope (line 1, outside function) to inside the function body, after the platform check.

- [ ] **Step 4: Run test — module imports, platform tests pass**

Run: `pwsh -Command "Invoke-Pester ./Tests/Test-DowserCrossPlatform.Tests.ps1 -Output Detailed"`

Expected: 'Module Import' context PASSES. 'Windows-Only Functions on Non-Windows' context PASSES on Linux.

- [ ] **Step 5: Commit**

```bash
git add Public/ConvertTo-DowserIco.ps1 Tests/Test-DowserCrossPlatform.Tests.ps1
git commit -m "fix: move System.Drawing load inside ConvertTo-DowserIco body, unblocking Linux import"
```

---

### Task 3: Guard Remaining Windows-Only Functions

**Files:**
- Modify: `Public/ConvertTo-DowserExe.ps1` (insert platform guard after param block)
- Modify: `Public/Get-DowserTemplate.ps1` (insert platform guard after param block)

**Why:** `ConvertTo-DowserExe` compiles Windows PE binaries and hardcodes `powershell.exe`. `Get-DowserTemplate` uses `Shell.Application` COM. Neither can function on Linux. They should emit a clear warning and return `$null` rather than throwing cryptic .NET exceptions.

- [ ] **Step 1: Write failing tests**

Add to `Tests/Test-DowserCrossPlatform.Tests.ps1`:

```powershell
    Context 'Windows-Only Functions on Non-Windows' -Skip:($IsWindows) {
        It 'ConvertTo-DowserExe returns warning on Linux' {
            $result = ConvertTo-DowserExe -ScriptPath '/tmp/fake.ps1' -WarningVariable warn 3>$null
            $result | Should -BeNullOrEmpty
            $warn | Should -Not -BeNullOrEmpty
            $warn[0] | Should -BeLike '*Windows*'
        }

        It 'Get-DowserTemplate returns warning on Linux' {
            $result = Get-DowserTemplate -Path '/tmp' -WarningVariable warn 3>$null
            $result | Should -BeNullOrEmpty
            $warn | Should -Not -BeNullOrEmpty
            $warn[0] | Should -BeLike '*Windows*'
        }
    }
```

- [ ] **Step 2: Run tests — they fail (no guard yet)**

Run: `pwsh -Command "Invoke-Pester ./Tests/Test-DowserCrossPlatform.Tests.ps1 -Output Detailed"`

- [ ] **Step 3: Add platform guard to ConvertTo-DowserExe**

Insert immediately after the param block closing paren:

```powershell
    # Platform guard: produces Windows PE binaries, requires Windows
    if (-not $IsWindows) {
        Write-Warning "ConvertTo-DowserExe produces Windows PE executables and requires Windows. Not available on this platform."
        return $null
    }
```

- [ ] **Step 4: Add platform guard to Get-DowserTemplate**

Insert immediately after the param block closing paren:

```powershell
    # Platform guard: requires Shell.Application COM object (Windows-only)
    if (-not $IsWindows) {
        Write-Warning "Get-DowserTemplate requires Windows Shell.Application COM. Not available on this platform."
        return $null
    }
```

- [ ] **Step 5: Run tests — pass**

Run: `pwsh -Command "Invoke-Pester ./Tests/Test-DowserCrossPlatform.Tests.ps1 -Output Detailed"`

Expected: All 'Windows-Only Functions' tests PASS.

- [ ] **Step 6: Commit**

```bash
git add Public/ConvertTo-DowserExe.ps1 Public/Get-DowserTemplate.ps1 Tests/Test-DowserCrossPlatform.Tests.ps1
git commit -m "feat: add platform guards to ConvertTo-DowserExe and Get-DowserTemplate"
```

---

### Task 4: Fix Write-Log WindowsIdentity

**Files:**
- Modify: `Private/Write-Log.ps1` (4 occurrences of WindowsIdentity)

**Why:** `[System.Security.Principal.WindowsIdentity]::GetCurrent()` throws or returns empty on Linux. The CMTrace log format uses a `context=""` field. On non-Windows, substitute the current username from environment variables. The `Get-ExecutionContextInfo` helper function is entirely Windows-specific and needs a full platform guard.

- [ ] **Step 1: Write failing test**

Add to `Tests/Test-DowserCrossPlatform.Tests.ps1`:

```powershell
    Context 'Write-Log Cross-Platform' {
        It 'Write-Log does not throw on this platform' {
            $testLog = Join-Path $TestDrive 'test.log'
            { Write-Log -Message 'Cross-platform test' -Logfile $testLog } | Should -Not -Throw
        }

        It 'Write-Log produces valid CMTrace output' {
            $testLog = Join-Path $TestDrive 'test.log'
            Write-Log -Message 'Format check' -Logfile $testLog
            $content = Get-Content $testLog -Raw
            $content | Should -Match 'context='
            $content | Should -Match 'LOG\]'
        }
    }
```

- [ ] **Step 2: Run test — fails on Linux (WindowsIdentity throws)**

Run: `pwsh -Command "Invoke-Pester ./Tests/Test-DowserCrossPlatform.Tests.ps1 -Output Detailed"`

- [ ] **Step 3: Create a safe identity resolution helper**

Add this private helper at the top of `Write-Log.ps1` (before the `Write-Log` function definition), or as a script-scoped function inside:

```powershell
function Get-SafeLogIdentity {
    # Returns current user identity string, cross-platform safe
    if ($IsWindows) {
        try {
            return [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        } catch {
            return $env:USERNAME
        }
    }
    # Linux/macOS: use environment variable
    if ($env:USER) { return $env:USER }
    if ($env:LOGNAME) { return $env:LOGNAME }
    return 'unknown'
}
```

- [ ] **Step 4: Replace all 4 WindowsIdentity occurrences**

Replace each instance of:
```powershell
$([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)
```

With:
```powershell
$(Get-SafeLogIdentity)
```

This applies to:
1. Main logline (~line 233): `"context=`"$(Get-SafeLogIdentity)`" "`
2. Rotation message (~line 285): `"context=`"$(Get-SafeLogIdentity)`" "`
3. Retry contention (~line 338): `"context=`"$(Get-SafeLogIdentity)`" "`

For occurrence 4 (`Get-ExecutionContextInfo` function, ~line 488), wrap the function body:

```powershell
function Get-ExecutionContextInfo {
    [CmdletBinding()]
    param()

    if (-not $IsWindows) {
        return [PSCustomObject]@{
            UserName    = Get-SafeLogIdentity
            IsAdmin     = ((id -u) -eq '0')  # root check on Linux
            IsSystem    = $false
            SessionType = 'NonWindows'
        }
    }

    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    # ... rest unchanged
```

- [ ] **Step 5: Run tests — pass**

Run: `pwsh -Command "Invoke-Pester ./Tests/Test-DowserCrossPlatform.Tests.ps1 -Output Detailed"`

Expected: Write-Log tests PASS on all platforms.

- [ ] **Step 6: Commit**

```bash
git add Private/Write-Log.ps1 Tests/Test-DowserCrossPlatform.Tests.ps1
git commit -m "fix: replace WindowsIdentity with cross-platform identity resolution in Write-Log"
```

---

### Task 5: Fix Path Handling

**Files:**
- Modify: `Public/Get-DowserInfo.ps1` (fix backslash path literal)
- Modify: `Public/Expand-DowserExe.ps1` (platform-aware 7-Zip default)
- Modify: `Public/Test-DowserExtractable.ps1` (platform-aware defaults)
- Modify: `Public/Test-DowserIntegrity.ps1` (platform-aware defaults)

**Why:** Hardcoded backslash paths and Windows-specific default tool locations fail silently or throw on Linux. `Join-Path` handles separators correctly cross-platform. 7-Zip on Linux is typically just `7z` on PATH.

- [ ] **Step 1: Write failing test**

Add to `Tests/Test-DowserCrossPlatform.Tests.ps1`:

```powershell
    Context 'Path Handling' {
        It 'Get-DowserInfo resolves changelog path on any platform' {
            # Should not throw regardless of platform
            { Get-DowserInfo } | Should -Not -Throw
        }
    }
```

- [ ] **Step 2: Run test — fails on Linux (backslash path)**

- [ ] **Step 3: Fix Get-DowserInfo.ps1**

Replace:
```powershell
    $changelogPath = Join-Path $moduleRoot 'docs\CHANGELOG.md'
```

With:
```powershell
    $changelogPath = Join-Path $moduleRoot 'docs' 'CHANGELOG.md'
```

- [ ] **Step 4: Fix 7-Zip default in Expand-DowserExe.ps1**

In the param block, replace:
```powershell
.PARAMETER SevenZipPath
    Path to 7z.exe. Defaults to "C:\Program Files\7-Zip\7z.exe".
```

And the parameter default (find the `$SevenZipPath` param declaration):
```powershell
    [string]$SevenZipPath = $(if ($IsWindows) { 'C:\Program Files\7-Zip\7z.exe' } else { (Get-Command 7z -ErrorAction SilentlyContinue).Source ?? '7z' })
```

Update the help text:
```powershell
.PARAMETER SevenZipPath
    Path to 7z executable. On Windows, defaults to "C:\Program Files\7-Zip\7z.exe".
    On Linux/macOS, defaults to '7z' (expected on PATH).
```

- [ ] **Step 5: Fix 7-Zip and expand.exe defaults in Test-DowserExtractable.ps1**

Same pattern for `$SevenZipPath` parameter default:
```powershell
    [string]$SevenZipPath = $(if ($IsWindows) { 'C:\Program Files\7-Zip\7z.exe' } else { (Get-Command 7z -ErrorAction SilentlyContinue).Source ?? '7z' })
```

For the expand.exe path (inside the function body where `$expandExe` is set):
```powershell
    $expandExe = if ($IsWindows) { "$env:SystemRoot\System32\expand.exe" } else { $null }
    $hasExpand = $expandExe -and (Test-Path $expandExe)
```

- [ ] **Step 6: Fix same defaults in Test-DowserIntegrity.ps1**

Apply identical changes as Test-DowserExtractable.ps1 for `$SevenZipPath` and `$expandExe`.

- [ ] **Step 7: Run tests — pass**

Run: `pwsh -Command "Invoke-Pester ./Tests/Test-DowserCrossPlatform.Tests.ps1 -Output Detailed"`

- [ ] **Step 8: Commit**

```bash
git add Public/Get-DowserInfo.ps1 Public/Expand-DowserExe.ps1 Public/Test-DowserExtractable.ps1 Public/Test-DowserIntegrity.ps1
git commit -m "fix: cross-platform path resolution and tool defaults"
```

---

### Task 6: Guard COM-Dependent Functions with Graceful Degradation

**Files:**
- Modify: `Public/Get-DowserProperty.ps1`

**Why:** `Get-DowserProperty` uses Shell.Application COM and `Get-AuthenticodeSignature`, both Windows-only. Unlike the fully-Windows-only functions (Task 3), this one returns useful basic metadata on all platforms — only the extended COM properties and signature data are unavailable. It should degrade gracefully rather than block entirely.

- [ ] **Step 1: Write test**

Add to `Tests/Test-DowserCrossPlatform.Tests.ps1`:

```powershell
    Context 'Graceful Degradation on Non-Windows' -Skip:($IsWindows) {
        It 'Get-DowserProperty returns basic metadata without COM' {
            $testFile = Join-Path $TestDrive 'test.txt'
            'hello' | Set-Content $testFile
            $result = Get-DowserProperty -Path $testFile
            $result | Should -Not -BeNullOrEmpty
            $result.Name | Should -Be 'test.txt'
        }
    }
```

- [ ] **Step 2: Run test — determine current behavior on Linux**

- [ ] **Step 3: Add platform-aware COM and signature sections**

Inside `Get-DowserProperty`, find the Shell.Application section and wrap:

```powershell
    # Extended properties via Shell.Application (Windows-only)
    if ($IsWindows) {
        try {
            $shell = New-Object -ComObject Shell.Application
            # ... existing COM property extraction ...
        } catch {
            Write-Verbose "Shell.Application unavailable: $_"
        }
    } else {
        Write-Verbose "Extended file properties via Shell.Application not available on this platform."
    }
```

For `Get-AuthenticodeSignature` usage, wrap similarly:

```powershell
    if ($IsWindows -and $IncludeSignature) {
        $sig = Get-AuthenticodeSignature -FilePath $filePath
        # ... existing signature handling ...
    } elseif ($IncludeSignature) {
        Write-Verbose "Authenticode signature inspection requires Windows."
    }
```

- [ ] **Step 4: Run tests — pass**

- [ ] **Step 5: Commit**

```bash
git add Public/Get-DowserProperty.ps1 Tests/Test-DowserCrossPlatform.Tests.ps1
git commit -m "feat: graceful degradation for Get-DowserProperty COM features on non-Windows"
```

---

### Task 7: Update Manifest, Documentation, and Final Test Run

**Files:**
- Modify: `Dowser.psd1`
- Modify: `docs/INDEX.md`
- Modify: `docs/CHANGELOG.md`

- [ ] **Step 1: Update Dowser.psd1**

Add `CompatiblePSEditions` and update description:

```powershell
@{
    RootModule        = 'Dowser.psm1'
    ModuleVersion     = '0.2.0'
    GUID              = 'b7e1c9a0-0000-0000-0000-000000000001'
    Author            = 'Curt Leggett'
    CompanyName       = 'Divergent Cortex'
    Copyright         = '(c) Curt Leggett. All rights reserved.'
    Description       = 'Dowser - filesystem recon and inspection kit. Find what you cannot see. Cross-platform (Windows/Linux/macOS).'
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    FunctionsToExport = @('*')
    AliasesToExport   = @('*')
    CmdletsToExport   = @()
    VariablesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('filesystem','recon','search','utility','dowser','cross-platform','linux')
            ProjectUri = ''
        }
    }
}
```

- [ ] **Step 2: Update docs/INDEX.md**

Add a "Platform Support" section documenting:
- Core functions (fully cross-platform)
- Windows-only functions (ConvertTo-DowserExe, ConvertTo-DowserIco, Get-DowserTemplate)
- Degraded functions (Get-DowserProperty, Get-DowserOwnership — COM properties unavailable)
- Tool dependencies on Linux (7z must be on PATH for archive functions)

- [ ] **Step 3: Update docs/CHANGELOG.md**

Entry at TOP with all changes from this plan:

```markdown
## 2026.05.24.XXX - Cross-Platform Compatibility

### Added
- Platform detection in Dowser.psm1 (sets $IsWindows/$IsLinux/$IsMacOS for PS 5.1 compat)
- Platform guards on Windows-only functions: ConvertTo-DowserIco, ConvertTo-DowserExe, Get-DowserTemplate
- Graceful degradation for COM-dependent functions on non-Windows
- Cross-platform identity resolution (Get-SafeLogIdentity) in Write-Log
- Platform-aware 7-Zip defaults (uses PATH-based '7z' on Linux)
- CompatiblePSEditions = @('Desktop', 'Core') in manifest
- Tests/Test-DowserCrossPlatform.Tests.ps1

### Fixed
- Module import failure on Linux caused by System.Drawing assembly load at file scope
- Backslash path literal in Get-DowserInfo.ps1 that failed path resolution on Linux
- WindowsIdentity calls in Write-Log that threw on non-Windows platforms
- Hardcoded Windows paths for 7-Zip and expand.exe

### Changed
- Dowser.psm1 now uses Join-Path for all internal path construction
- ModuleVersion bumped to 0.2.0
```

- [ ] **Step 4: Run full test suite**

Run: `pwsh -Command "Invoke-Pester ./Tests/ -Output Detailed"`

Expected: All tests PASS. No regressions on existing functionality.

- [ ] **Step 5: Final commit**

```bash
git add Dowser.psd1 docs/INDEX.md docs/CHANGELOG.md
git commit -m "docs: update manifest, INDEX, and CHANGELOG for cross-platform support"
```

---

## Summary of Platform Behavior After Implementation

| Function | Windows | Linux/macOS |
|----------|---------|-------------|
| Find-DowserDuplicate | ✅ Full | ✅ Full |
| Find-DowserFile | ✅ Full | ✅ Full |
| Find-DowserOrphan | ✅ Full | ✅ Full |
| Find-DowserDependency | ✅ Full | ✅ Full |
| Invoke-DowserFastSearch | ✅ Full | ✅ Full |
| Measure-DowserDirectory | ✅ Full | ✅ Full |
| Get-DowserMap | ✅ Full | ✅ Full |
| Get-DowserTopology | ✅ Full | ✅ Full |
| ConvertTo-DowserBase64 | ✅ Full | ✅ Full |
| Get-DowserInfo | ✅ Full | ✅ Full |
| Write-Log | ✅ Full | ✅ Full (env-based identity) |
| Get-DowserProperty | ✅ Full | ⚠️ Basic metadata only |
| Get-DowserOwnership | ✅ Full | ⚠️ Basic metadata only |
| Expand-DowserExe | ✅ Full | ⚠️ Requires 7z on PATH |
| Test-DowserExtractable | ✅ Full | ⚠️ No CAB/expand.exe |
| Test-DowserIntegrity | ✅ Full | ⚠️ No CAB/ADS checks |
| ConvertTo-DowserIco | ✅ Full | ❌ Warning + $null |
| ConvertTo-DowserExe | ✅ Full | ❌ Warning + $null |
| Get-DowserTemplate | ✅ Full | ❌ Warning + $null |
