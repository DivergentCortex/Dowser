#Requires -Version 5.1
<#
.SYNOPSIS
    Pester smoke tests for Test-DowserIntegrity.

.DESCRIPTION
    Covers the basic contract:
    - Cmdlet is exported from the module.
    - Summary mode emits a single summary object and populates $global:DowserIntegrityDetails.
    - Detailed mode streams per-file objects.
    - Zero-byte files get Status = Warning.
    - Corrupt PE is detected (bogus bytes labelled .exe).
    - Residue filename patterns (Thumbs.db, ~$lockfile.docx) flip Status to Residue.
    - IncludeClean surfaces OK files in the detailed stream.
    - BaselineCsv drift detection flags hash mismatches.

    These are smoke tests. They do not validate every code path; they validate that
    the cmdlet's public contract holds for the common scenarios.

.NOTES
    Run from the module root:
        Invoke-Pester -Path .\Tests\Test-DowserIntegrity.Tests.ps1 -Output Detailed
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent $PSScriptRoot
    $script:ManifestPath = Join-Path $script:ModuleRoot 'Dowser.psd1'

    Import-Module $script:ManifestPath -Force -ErrorAction Stop

    # Scratch directory
    $script:WorkDir = Join-Path ([System.IO.Path]::GetTempPath()) ("DowserIntegrity_" + [guid]::NewGuid().Guid.Substring(0, 8))
    New-Item -ItemType Directory -Path $script:WorkDir -Force | Out-Null

    # Fixtures
    $script:EmptyFile   = Join-Path $script:WorkDir 'empty.bin'
    $script:CleanText   = Join-Path $script:WorkDir 'clean.txt'
    $script:CorruptExe  = Join-Path $script:WorkDir 'broken.exe'
    $script:ThumbsDb    = Join-Path $script:WorkDir 'Thumbs.db'
    $script:OfficeLock  = Join-Path $script:WorkDir '~$document.docx'

    # Create them
    New-Item -ItemType File -Path $script:EmptyFile -Force | Out-Null

    'This is a clean text file for baseline + read-access tests.' |
        Set-Content -LiteralPath $script:CleanText -Encoding ASCII

    # Corrupt "EXE": bytes that are not MZ-prefixed
    [byte[]](0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07) |
        Set-Content -LiteralPath $script:CorruptExe -Encoding Byte

    'junk' | Set-Content -LiteralPath $script:ThumbsDb -Encoding ASCII
    'junk' | Set-Content -LiteralPath $script:OfficeLock -Encoding ASCII
}

AfterAll {
    if (Test-Path -LiteralPath $script:WorkDir) {
        Remove-Item -LiteralPath $script:WorkDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Variable -Name DowserIntegrityDetails -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Test-DowserIntegrity - contract' {

    It 'is exported from the module' {
        Get-Command Test-DowserIntegrity -Module Dowser | Should -Not -BeNullOrEmpty
    }

    It 'has the expected aliases' {
        (Get-Alias dintegrity -ErrorAction SilentlyContinue).Definition | Should -Be 'Test-DowserIntegrity'
        (Get-Alias dinteg     -ErrorAction SilentlyContinue).Definition | Should -Be 'Test-DowserIntegrity'
    }

    It 'summary mode emits exactly one summary object' {
        $summary = Test-DowserIntegrity -Path $script:WorkDir
        @($summary).Count | Should -Be 1
        $summary.PSObject.Properties.Name | Should -Contain 'TotalFiles'
        $summary.PSObject.Properties.Name | Should -Contain 'ProblemCount'
        $summary.PSObject.Properties.Name | Should -Contain 'DetailsGlobal'
    }

    It 'summary mode populates $global:DowserIntegrityDetails' {
        Test-DowserIntegrity -Path $script:WorkDir | Out-Null
        $global:DowserIntegrityDetails | Should -Not -BeNullOrEmpty
        @($global:DowserIntegrityDetails).Count | Should -BeGreaterThan 0
    }

    It 'detailed mode streams per-file objects' {
        $files = Test-DowserIntegrity -Path $script:WorkDir -Detailed -IncludeClean
        @($files).Count | Should -BeGreaterThan 1
        $files[0].PSObject.Properties.Name | Should -Contain 'Status'
        $files[0].PSObject.Properties.Name | Should -Contain 'RelativePath'
    }
}

Describe 'Test-DowserIntegrity - detection' {

    It 'flags zero-byte files with Status = Warning' {
        $r = Test-DowserIntegrity -Path $script:EmptyFile -Detailed -IncludeClean
        @($r).Count           | Should -Be 1
        @($r)[0].Status       | Should -Be 'Warning'
        @($r)[0].SizeBytes    | Should -Be 0
    }

    It 'flags corrupt PE with Status = Corrupt and Category = PE' {
        $r = Test-DowserIntegrity -Path $script:CorruptExe -Detailed
        @($r).Count        | Should -Be 1
        @($r)[0].Status    | Should -Be 'Corrupt'
        @($r)[0].Category  | Should -Be 'PE'
        @($r)[0].Method    | Should -Be 'PE-Structural'
    }

    It 'flags Thumbs.db as Residue via filename pattern' {
        $r = Test-DowserIntegrity -Path $script:ThumbsDb -Detailed
        @($r).Count        | Should -Be 1
        @($r)[0].Status    | Should -Be 'Residue'
        (@($r)[0].Issues -join ' ') | Should -Match 'Residue name pattern'
    }

    It 'flags Office lock file (~$*) as Residue' {
        $r = Test-DowserIntegrity -Path $script:OfficeLock -Detailed
        @($r)[0].Status | Should -Be 'Residue'
    }

    It 'passes clean text file when IncludeClean is set' {
        $r = Test-DowserIntegrity -Path $script:CleanText -Detailed -IncludeClean
        @($r).Count     | Should -Be 1
        @($r)[0].Status | Should -BeIn @('OK', 'Unverified')
    }
}

Describe 'Test-DowserIntegrity - baseline' {

    It 'flags hash mismatch when baseline differs' {
        $baselineCsv = Join-Path $script:WorkDir 'baseline.csv'

        # Capture the real hash but record a fake one in the baseline
        $realHash = (Get-FileHash -LiteralPath $script:CleanText -Algorithm SHA256).Hash
        $fakeHash = ('0' * 64)

        [PSCustomObject]@{
            RelativePath = 'clean.txt'
            Length       = (Get-Item -LiteralPath $script:CleanText).Length
            SHA256       = $fakeHash
        } | Export-Csv -LiteralPath $baselineCsv -NoTypeInformation

        $r = Test-DowserIntegrity -Path $script:WorkDir -BaselineCsv $baselineCsv -Detailed -IncludeClean
        $cleanEntry = @($r) | Where-Object { $_.Name -eq 'clean.txt' }
        $cleanEntry               | Should -Not -BeNullOrEmpty
        $cleanEntry.Status        | Should -Be 'Suspicious'
        $cleanEntry.BaselineMatch | Should -Be $false
        ($cleanEntry.Issues -join ' ') | Should -Match 'Hash mismatch'
        $realHash | Should -Not -BeNullOrEmpty  # sanity: we did compute a hash
    }
}
