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
    - Witness exposes the log-cleanup function as Clear-LogFile, not Cleanup-LogFiles.
    - Witness Get-PlatformContext returns the non-Windows platform shape on Linux.

    The PS 5.1 ($IsWindows = $null) and Windows ($IsWindows = $true) branches
    cannot be executed on this host.

.EXAMPLE
    Invoke-Pester -Path ./Tests/Test-DowserPlatformGuards.Tests.ps1 -Output Detailed
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent $PSScriptRoot
    $script:ManifestPath = Join-Path $script:ModuleRoot 'Dowser.psd1'

    # one Witness instance, shared by the module and these tests, so a test can point every Write-Log at its own file
    Import-Module (Join-Path (Join-Path $script:ModuleRoot 'Modules') 'DivergentCortex.Witness') -ErrorAction Stop
    Remove-Module Dowser -Force -ErrorAction SilentlyContinue
    Import-Module $script:ManifestPath -Force -ErrorAction Stop

    # the ConfuserEx variant is defined but not exported (it lives in a file named after
    # another command), so dot-source the file to reach it
    . (Join-Path $script:ModuleRoot 'Public/ConvertTo-DowserExe.ps1')

    $script:WorkDir = Join-Path ([System.IO.Path]::GetTempPath()) ("dowserguard_" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:WorkDir -Force | Out-Null
    $script:SampleFile = Join-Path $script:WorkDir 'sample.txt'
    'sample content' | Set-Content -LiteralPath $script:SampleFile

    # the tests read this file instead of -WarningVariable because warnings go through Write-Log
    $script:TestLog = Join-Path $script:WorkDir 'guard.log'
    Initialize-Log -LogFilePath $script:TestLog -ScriptName 'Guards'
}

AfterAll {
    if ($script:WorkDir -and (Test-Path $script:WorkDir)) {
        Remove-Item -LiteralPath $script:WorkDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Windows-only public functions on non-Windows' -Skip:($IsWindows -ne $false) {

    BeforeEach {
        # fresh log per test so assertions only see that test's output
        Remove-Item $script:TestLog -ErrorAction SilentlyContinue
        Initialize-Log -LogFilePath $script:TestLog -ScriptName 'Guards'
    }

    It 'ConvertTo-DowserIco warns and returns null' {
        $r = ConvertTo-DowserIco -InputFilePath $script:SampleFile
        $r | Should -BeNullOrEmpty
        (Get-Content -LiteralPath $script:TestLog -Raw) | Should -Match 'requires Windows'
    }

    It 'ConvertTo-DowserExe warns and returns null' {
        $r = ConvertTo-DowserExe -ScriptPath $script:SampleFile
        $r | Should -BeNullOrEmpty
        (Get-Content -LiteralPath $script:TestLog -Raw) | Should -Match 'requires Windows'
    }

    It 'Get-DowserTemplate warns and returns null' {
        $r = Get-DowserTemplate -Path $script:WorkDir
        $r | Should -BeNullOrEmpty
        (Get-Content -LiteralPath $script:TestLog -Raw) | Should -Match 'requires Windows'
    }

    It 'ConvertTo-DowserExeConfuserEx is guarded before the Add-Type compile' {
        # an unguarded Add-Type -OutputType ConsoleApplication throws on pwsh 7, so the
        # platform guard has to return first, with a warning and no exception
        $threw = $false
        $cfx = $null
        try {
            $cfx = ConvertTo-DowserExeConfuserEx -ScriptPath $script:SampleFile -ConfuserExPath $script:WorkDir
        }
        catch {
            $threw = $true
        }
        $threw | Should -BeFalse
        $cfx | Should -BeNullOrEmpty
        (Get-Content -LiteralPath $script:TestLog -Raw) | Should -Match 'requires Windows'
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
        # -Verbose sends Write-Log's verbose lines to the log file ($nativeVerboseActive
        # flips verboseToLogfile). fresh log first, then the 7-Zip line should name the
        # bare '7z', not the Program Files path
        Remove-Item $script:TestLog -ErrorAction SilentlyContinue
        Initialize-Log -LogFilePath $script:TestLog -ScriptName 'Guards'

        Test-DowserExtractable -Path $script:SampleFile -Verbose | Out-Null

        $logText = Get-Content -LiteralPath $script:TestLog -Raw
        $sevenZipLine = ($logText -split "`n") |
            Where-Object { $_ -match '7-?Zip (found at|not found at)' } |
            Select-Object -First 1

        $sevenZipLine | Should -Not -BeNullOrEmpty
        $sevenZipLine | Should -Match '7z'
        $sevenZipLine | Should -Not -Match 'Program Files'
        $sevenZipLine | Should -Not -Match '7z\.exe'
    }
}

Describe 'Witness log-cleanup function name' {
    It 'exposes Clear-LogFile' {
        InModuleScope 'DivergentCortex.Witness' { Get-Command Clear-LogFile -ErrorAction SilentlyContinue } | Should -Not -BeNullOrEmpty
    }

    It 'does not define the unapproved-verb name Cleanup-LogFiles' {
        InModuleScope 'DivergentCortex.Witness' { Get-Command Cleanup-LogFiles -ErrorAction SilentlyContinue } | Should -BeNullOrEmpty
    }
}

Describe 'Witness Get-PlatformContext on non-Windows' -Skip:($IsWindows -ne $false) {
    It 'returns the non-Windows platform shape' {
        $ctx = InModuleScope 'DivergentCortex.Witness' { Get-PlatformContext }
        $ctx.Platform | Should -BeIn @('Linux', 'macOS')
        $ctx.IsSystem | Should -BeFalse
    }
}
