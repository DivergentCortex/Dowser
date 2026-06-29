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
    - The log-cleanup function is the Witness-aligned name Clear-LogFile
      and the old Cleanup-LogFiles name is gone.
    - Get-PlatformContext returns the non-Windows platform shape on Linux.

    The PS 5.1 ($IsWindows = $null) and Windows ($IsWindows = $true) branches
    cannot be executed on this host; they are covered by reasoning in the
    implementer report and by the canonical guard idiom truth table.

.NOTES
    Run from the module root:
        Invoke-Pester -Path ./Tests/Test-DowserPlatformGuards.Tests.ps1 -Output Detailed
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent $PSScriptRoot
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

    # Write-Log requires a log path. Configure one so the dot-sourced Write-Log
    # (which resets $script:WitnessLogFilePath) has a valid target. Tests read
    # from this file instead of -WarningVariable (warnings now go through Write-Log).
    $script:TestLog = Join-Path $script:WorkDir 'guard.log'
    # Module commands (ConvertTo-DowserIco etc.) use the module's Write-Log, which
    # reads the module's own $script:WitnessLogFilePath. The dot-sourced Initialize-Log
    # only sets the test-scope copy. Invoke Initialize-Log inside the module scope so
    # the module's log path points to our test file.
    # The psm1 sets $LogFilePath at module script scope. Write-Log reads it via
    # $PSCmdlet.SessionState.PSVariable.GetValue('LogFilePath'), which finds the
    # module-scope $LogFilePath BEFORE $script:WitnessLogFilePath. We must
    # update it in the module's script scope so it points to the test log.
    # Set-Variable -Scope Script inside the module's sessionstate sets the correct
    # variable. Then Initialize-Log also sets $script:WitnessLogFilePath.
    # Pass the path as a param; $using: is remoting-only.
    & (Get-Module Dowser) { param($p) Set-Variable -Name LogFilePath -Value $p -Scope Script; Initialize-Log -LogFilePath $p -ScriptName 'Guards' } $script:TestLog
    # Also initialize the dot-sourced (test-scope) copy.
    Initialize-Log -LogFilePath $script:TestLog -ScriptName 'Guards'
}

AfterAll {
    if ($script:WorkDir -and (Test-Path $script:WorkDir)) {
        Remove-Item -LiteralPath $script:WorkDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Windows-only public functions on non-Windows' -Skip:($IsWindows -ne $false) {

    BeforeEach {
        # Reset the log before each test so assertions read only that test's output.
        Remove-Item $script:TestLog -ErrorAction SilentlyContinue
        # Reinitialize both the module-scope and test-scope Write-Log so all
        # Write-Log calls (from module commands and dot-sourced functions alike)
        # land in the fresh test log. Set-Variable -Scope Script inside module
        # scope updates the module's $LogFilePath, preventing it from overriding
        # $script:WitnessLogFilePath in Resolve-WitnessLogPath.
        & (Get-Module Dowser) { param($p) Set-Variable -Name LogFilePath -Value $p -Scope Script; Initialize-Log -LogFilePath $p -ScriptName 'Guards' } $script:TestLog
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
        # On pwsh 7 the unguarded Add-Type -OutputType ConsoleApplication throws;
        # the platform guard must return first with a warning and no exception.
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
        # Write-Log routes verbose through the log file when -Verbose is active
        # ($nativeVerboseActive flips verboseToLogfile). Reset the log before the
        # call so we read only this test's output, then confirm the 7-Zip line
        # names the bare '7z' binary, not the Windows Program Files path.
        Remove-Item $script:TestLog -ErrorAction SilentlyContinue
        & (Get-Module Dowser) { param($p) Set-Variable -Name LogFilePath -Value $p -Scope Script; Initialize-Log -LogFilePath $p -ScriptName 'Guards' } $script:TestLog
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

Describe 'Log-cleanup function rename' {
    It 'exposes Clear-LogFile after dot-sourcing Write-Log.ps1' {
        Get-Command Clear-LogFile -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'no longer defines the unapproved-verb name Cleanup-LogFiles' {
        Get-Command Cleanup-LogFiles -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }

    It 'Write-Log.ps1 contains no remaining Cleanup-LogFiles references' {
        $src = Get-Content -LiteralPath (Join-Path $script:ModuleRoot 'Private/Write-Log.ps1') -Raw
        $src | Should -Not -Match 'Cleanup-LogFiles'
    }
}

Describe 'Get-PlatformContext on non-Windows' -Skip:($IsWindows -ne $false) {
    It 'returns the non-Windows platform shape' {
        $ctx = Get-PlatformContext
        $ctx.Platform | Should -BeIn @('Linux', 'macOS')
        $ctx.IsSystem | Should -BeFalse
    }
}
