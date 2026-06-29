#Requires -Version 5.1
<#
.SYNOPSIS
    Pester coverage for the Write-Log / Initialize-Log logging contract.

.NOTES
    Author:       Curtis Leggett
    Organization: Divergent Cortex
    Version:      See docs/CHANGELOG.md

.DESCRIPTION
    Proves the logging contract for Private/Write-Log.ps1:
    - Initialize-Log creates the file and writes the session-start banner.
    - Bare Write-Log (Info severity) always lands in the log file.
    - Write-Log -Severity Verbose is suppressed by default and appears when
      $Global:VerboseLogfile = $true is set.
    - Write-Log -Severity Warning always lands in the log file.
    - Every entry uses the CMTrace wire format (<![LOG[...]LOG]!>).

    Run from the module root:
        Invoke-Pester -Path ./Tests/Test-DowserLogging.Tests.ps1 -Output Detailed
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent $PSScriptRoot

    # Dot-source Write-Log.ps1 directly so these tests own the Write-Log
    # definitions. No module import; we are testing the helper in isolation.
    . (Join-Path $script:ModuleRoot 'Private/Write-Log.ps1')

    $script:TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("dowserlogltest_" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:TempDir -Force | Out-Null
    $script:TempLog = Join-Path $script:TempDir 'contract.log'
}

AfterAll {
    Remove-Variable -Name VerboseLogfile -Scope Global -ErrorAction SilentlyContinue

    if ($script:TempDir -and (Test-Path $script:TempDir)) {
        Remove-Item -LiteralPath $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Initialize-Log contract' {

    BeforeEach {
        Remove-Item $script:TempLog -ErrorAction SilentlyContinue
        Initialize-Log -LogFilePath $script:TempLog -ScriptName 'LoggingTest'
    }

    It 'creates the log file on disk' {
        Test-Path $script:TempLog | Should -BeTrue
    }

    It 'writes the SCRIPT START banner to the file' {
        $content = Get-Content -LiteralPath $script:TempLog -Raw
        $content | Should -Match 'SCRIPT START'
    }

    It 'uses CMTrace LOG markers in the banner' {
        $content = Get-Content -LiteralPath $script:TempLog -Raw
        $content | Should -Match '<!\[LOG\['
    }
}

Describe 'Write-Log Info severity (always-on)' {

    BeforeEach {
        Remove-Item $script:TempLog -ErrorAction SilentlyContinue
        Initialize-Log -LogFilePath $script:TempLog -ScriptName 'LoggingTest'
    }

    It 'lands a bare Write-Log message in the file' {
        Write-Log 'hello-info'
        $content = Get-Content -LiteralPath $script:TempLog -Raw
        $content | Should -Match 'hello-info'
    }

    It 'wraps the message in CMTrace LOG markers' {
        Write-Log 'info-marker-check'
        $content = Get-Content -LiteralPath $script:TempLog -Raw
        $content | Should -Match '<!\[LOG\[info-marker-check\]LOG\]!>'
    }

    It 'sets CMTrace type code 1 for Info' {
        Write-Log 'info-type-code'
        $content = Get-Content -LiteralPath $script:TempLog -Raw
        $infoLine = ($content -split [System.Environment]::NewLine) |
            Where-Object { $_ -match 'info-type-code' } |
            Select-Object -First 1
        $infoLine | Should -Match 'type="1"'
    }
}

Describe 'Write-Log Verbose severity gating' {

    BeforeEach {
        Remove-Variable -Name VerboseLogfile -Scope Global -ErrorAction SilentlyContinue
        Remove-Item $script:TempLog -ErrorAction SilentlyContinue
        Initialize-Log -LogFilePath $script:TempLog -ScriptName 'LoggingTest'
    }

    AfterEach {
        Remove-Variable -Name VerboseLogfile -Scope Global -ErrorAction SilentlyContinue
    }

    It 'does NOT write to the log by default' {
        Write-Log 'trace-line' -Severity Verbose
        $content = Get-Content -LiteralPath $script:TempLog -Raw
        $content | Should -Not -Match 'trace-line'
    }

    It 'writes to the log when $Global:VerboseLogfile is $true' {
        $Global:VerboseLogfile = $true
        Write-Log 'trace-line-verbose-on' -Severity Verbose
        $content = Get-Content -LiteralPath $script:TempLog -Raw
        $content | Should -Match 'trace-line-verbose-on'
    }

    It 'sets CMTrace type code 4 for Verbose entries' {
        $Global:VerboseLogfile = $true
        Write-Log 'verbose-type-code' -Severity Verbose
        $content = Get-Content -LiteralPath $script:TempLog -Raw
        $verboseLine = ($content -split [System.Environment]::NewLine) |
            Where-Object { $_ -match 'verbose-type-code' } |
            Select-Object -First 1
        $verboseLine | Should -Match 'type="4"'
    }
}

Describe 'Write-Log Warning severity (always-on)' {

    BeforeEach {
        Remove-Item $script:TempLog -ErrorAction SilentlyContinue
        Initialize-Log -LogFilePath $script:TempLog -ScriptName 'LoggingTest'
    }

    It 'lands a Warning message in the file' {
        Write-Log 'warn-line' -Severity Warning
        $content = Get-Content -LiteralPath $script:TempLog -Raw
        $content | Should -Match 'warn-line'
    }

    It 'sets CMTrace type code 2 for Warning' {
        Write-Log 'warn-type-code' -Severity Warning
        $content = Get-Content -LiteralPath $script:TempLog -Raw
        $warnLine = ($content -split [System.Environment]::NewLine) |
            Where-Object { $_ -match 'warn-type-code' } |
            Select-Object -First 1
        $warnLine | Should -Match 'type="2"'
    }
}

Describe 'CMTrace wire format' {

    BeforeEach {
        Remove-Item $script:TempLog -ErrorAction SilentlyContinue
        Initialize-Log -LogFilePath $script:TempLog -ScriptName 'LoggingTest'
    }

    It 'every log entry contains the opening LOG marker' {
        Write-Log 'format-check'
        $lines = Get-Content -LiteralPath $script:TempLog |
            Where-Object { $_ -match '\S' }
        $lines | ForEach-Object {
            $_ | Should -Match '<!\[LOG\['
        }
    }

    It 'every log entry contains date and time fields' {
        Write-Log 'timestamp-check'
        $lines = Get-Content -LiteralPath $script:TempLog |
            Where-Object { $_ -match '\S' }
        $lines | ForEach-Object {
            $_ | Should -Match 'time="'
            $_ | Should -Match 'date="'
        }
    }
}

Describe 'Write-Log throws when no log path configured' {

    It 'throws FATAL when called with no path set and no Initialize-Log' {
        # Temporarily clear the script-scope path to exercise the throw branch.
        $saved = $script:WitnessLogFilePath
        $script:WitnessLogFilePath = $null
        $savedGlobal = if (Test-Path Variable:Global:LogFilePath) { $Global:LogFilePath } else { $null }
        Remove-Variable -Name LogFilePath -Scope Global -ErrorAction SilentlyContinue

        $threw = $false
        try {
            Write-Log 'should-not-land'
        }
        catch {
            $threw = ($_.Exception.Message -match 'FATAL')
        }
        finally {
            $script:WitnessLogFilePath = $saved
            if ($null -ne $savedGlobal) { $Global:LogFilePath = $savedGlobal }
        }

        $threw | Should -BeTrue
    }
}
