#Requires -Modules @{ModuleName='Pester';ModuleVersion='5.0'}

Describe 'Find-DowserDuplicate' {
    BeforeAll {
        $modulePath = Split-Path $PSScriptRoot -Parent
        Remove-Module Dowser -Force -ErrorAction SilentlyContinue
        Import-Module (Join-Path $modulePath 'Dowser.psd1') -Force -ErrorAction Stop

        $script:tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "DowserDuplicates_$([System.IO.Path]::GetRandomFileName())"
        $null = New-Item -ItemType Directory -Path $script:tempRoot -Force
        [System.IO.File]::WriteAllText((Join-Path $script:tempRoot 'first.txt'), 'same content')
        [System.IO.File]::WriteAllText((Join-Path $script:tempRoot 'second.txt'), 'same content')
        [System.IO.File]::WriteAllText((Join-Path $script:tempRoot 'unique.txt'), 'other data')
    }

    AfterAll {
        if ($script:tempRoot -and (Test-Path -LiteralPath $script:tempRoot)) {
            Remove-Item -LiteralPath $script:tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'finds byte-identical files using the Content mode' {
        $null = Find-DowserDuplicate -Path $script:tempRoot -Mode Content
        $contentSet = $global:dupObjects | Where-Object Mode -eq 'Content' | Select-Object -First 1

        $contentSet | Should -Not -BeNullOrEmpty
        $contentSet.Count | Should -Be 2
        $contentSet.Hash | Should -Not -BeNullOrEmpty
        $contentSet.Files.Path | Should -Contain (Join-Path $script:tempRoot 'first.txt')
        $contentSet.Files.Path | Should -Contain (Join-Path $script:tempRoot 'second.txt')
    }

    It 'writes a readable HTML report to a new parent directory' {
        $reportPath = Join-Path $script:tempRoot 'reports/duplicates.html'
        $null = Find-DowserDuplicate -Path $script:tempRoot -Mode Content -ExportHtml $reportPath

        Test-Path -LiteralPath $reportPath | Should -BeTrue
        $html = [System.IO.File]::ReadAllText($reportPath)
        $html | Should -Match 'Exact duplicate files'
        $html | Should -Match '<details class=''duplicate-set''>'
        $html | Should -Match 'Potential space recovery'
        $html | Should -Match 'Proof: full-file SHA256 hash'
        $html | Should -Match 'Hash algorithm: SHA256'
        $html | Should -Match 'first\.txt'
        $html | Should -Match 'second\.txt'
    }

    It 'writes an empty HTML report when filters exclude every file' {
        $reportPath = Join-Path $script:tempRoot 'empty/duplicates.html'
        $null = Find-DowserDuplicate -Path $script:tempRoot -Mode Content -MinSize 1GB -ExportHtml $reportPath

        Test-Path -LiteralPath $reportPath | Should -BeTrue
        [System.IO.File]::ReadAllText($reportPath) | Should -Match 'No byte-identical duplicate files were found'
    }
}
