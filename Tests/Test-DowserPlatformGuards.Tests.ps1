#Requires -Version 5.1
<#
.SYNOPSIS
    Pester coverage for the PS 5.1 platform-guard and Windows-only-function fixes.

.DESCRIPTION
    Verifies the cross-platform sweep fixes that this suite can exercise on a
    non-Windows host (pwsh 7 on Linux):
    - Windows-only public functions graceful-skip with a warning and return null
      on a non-Windows platform (ConvertTo-DowserIco, ConvertTo-DowserExe,
      Get-DowserTemplate).
    - ConvertTo-DowserExeConfuserEx is guarded and returns before the
      Add-Type -OutputType compile that throws on pwsh 7.
    - Get-DowserTopology -InColor does not crash on this host.
    - The 7-Zip default-parameter expression resolves to the bare '7z' on Linux.
    - The log-cleanup function was renamed to the approved-verb name
      Remove-DowserOldLogFiles and the old Cleanup-LogFiles name is gone.
    - Get-ExecutionContextInfo returns the NonWindows shape on Linux.

    The PS 5.1 ($IsWindows = $null) and Windows ($IsWindows = $true) branches
    cannot be executed on this host; they are covered by reasoning in the
    implementer report and by the canonical guard idiom truth table.

.NOTES
    Run from the module root:
        Invoke-Pester -Path ./Tests/Test-DowserPlatformGuards.Tests.ps1 -Output Detailed
#>

BeforeAll {
    $script:ModuleRoot   = Split-Path -Parent $PSScriptRoot
    $script:ManifestPath = Join-Path $script:ModuleRoot 'Dowser.psd1'

    Remove-Module Dowser -Force -ErrorAction SilentlyContinue
    Import-Module $script:ManifestPath -Force -ErrorAction Stop

    # ConfuserEx variant and the log helpers are defined-but-not-exported
    # (they live inside files whose basename is the exported command name),
    # so dot-source the files directly to reach them.
    . (Join-Path $script:ModuleRoot 'Public/ConvertTo-DowserExe.ps1')
    . (Join-Path $script:ModuleRoot 'Private/Write-Log.ps1')

    $script:WorkDir = Join-Path ([System.IO.Path]::GetTempPath()) ("dowserguard_" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:WorkDir -Force | Out-Null
    $script:SampleFile = Join-Path $script:WorkDir 'sample.txt'
    'sample content' | Set-Content -LiteralPath $script:SampleFile
}

AfterAll {
    if ($script:WorkDir -and (Test-Path $script:WorkDir)) {
        Remove-Item -LiteralPath $script:WorkDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Windows-only public functions on non-Windows' -Skip:($IsWindows -ne $false) {

    It 'ConvertTo-DowserIco warns and returns null' {
        $w = $null
        $r = ConvertTo-DowserIco -InputFilePath $script:SampleFile -WarningVariable w -WarningAction SilentlyContinue
        $r | Should -BeNullOrEmpty
        $w -join ' ' | Should -Match 'requires Windows'
    }

    It 'ConvertTo-DowserExe warns and returns null' {
        $w = $null
        $r = ConvertTo-DowserExe -ScriptPath $script:SampleFile -WarningVariable w -WarningAction SilentlyContinue
        $r | Should -BeNullOrEmpty
        $w -join ' ' | Should -Match 'requires Windows'
    }

    It 'Get-DowserTemplate warns and returns null' {
        $w = $null
        $r = Get-DowserTemplate -Path $script:WorkDir -WarningVariable w -WarningAction SilentlyContinue
        $r | Should -BeNullOrEmpty
        $w -join ' ' | Should -Match 'requires Windows'
    }

    It 'ConvertTo-DowserExeConfuserEx is guarded before the Add-Type compile' {
        # On pwsh 7 the unguarded Add-Type -OutputType ConsoleApplication throws;
        # the platform guard must return first with a warning, no exception.
        $threw = $false
        $cfx = $null
        $w = $null
        try {
            $cfx = ConvertTo-DowserExeConfuserEx -ScriptPath $script:SampleFile -ConfuserExPath $script:WorkDir -WarningVariable w -WarningAction SilentlyContinue
        }
        catch {
            $threw = $true
        }
        $threw | Should -BeFalse
        $cfx | Should -BeNullOrEmpty
        $w -join ' ' | Should -Match 'requires Windows'
    }
}

Describe 'Get-DowserTopology -InColor cross-platform' {
    It 'does not crash with -InColor on this host' {
        { Get-DowserTopology -Path $script:WorkDir -InColor -WarningAction SilentlyContinue | Out-Null } |
            Should -Not -Throw
    }
}

Describe '7-Zip default-parameter expression resolves on non-Windows' -Skip:($IsWindows -ne $false) {
    It 'binds the default SevenZipPath to bare 7z on Linux, not a Windows path' {
        # The begin block echoes the resolved $SevenZipPath through verbose
        # ("7-Zip found at: <path>" or "7-Zip not found at <path>"). Capture it
        # and confirm the runtime default is '7z', not Program Files\7-Zip\7z.exe.
        # A no-throw assertion alone would pass even with the old unsafe default.
        $verbose = Test-DowserExtractable -Path $script:SampleFile -Verbose 4>&1 |
            Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } |
            ForEach-Object { $_.Message }
        $sevenZipLine = $verbose | Where-Object { $_ -match '7-?Zip (found at|not found at)' } | Select-Object -First 1
        $sevenZipLine | Should -Not -BeNullOrEmpty
        $sevenZipLine | Should -Match '(:\s*|at\s+)7z(\s|$)'
        $sevenZipLine | Should -Not -Match 'Program Files'
        $sevenZipLine | Should -Not -Match '7z\.exe'
    }
}

Describe 'Log-cleanup function rename' {
    It 'exposes Remove-DowserOldLogFiles after dot-sourcing Write-Log.ps1' {
        Get-Command Remove-DowserOldLogFiles -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'no longer defines the unapproved-verb name Cleanup-LogFiles' {
        Get-Command Cleanup-LogFiles -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }

    It 'Write-Log.ps1 contains no remaining Cleanup-LogFiles references' {
        $src = Get-Content -LiteralPath (Join-Path $script:ModuleRoot 'Private/Write-Log.ps1') -Raw
        $src | Should -Not -Match 'Cleanup-LogFiles'
    }
}

Describe 'Get-ExecutionContextInfo on non-Windows' -Skip:($IsWindows -ne $false) {
    It 'returns the NonWindows session shape' {
        $ctx = Get-ExecutionContextInfo
        $ctx.SessionType | Should -Be 'NonWindows'
        $ctx.IsSystem | Should -BeFalse
    }
}
