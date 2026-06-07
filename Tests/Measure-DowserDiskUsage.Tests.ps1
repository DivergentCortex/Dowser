#Requires -Modules @{ModuleName='Pester';ModuleVersion='5.0'}

Describe 'Measure-DowserDiskUsage' {
    BeforeAll {
        $modulePath = Split-Path $PSScriptRoot -Parent
        Remove-Module Dowser -Force -ErrorAction SilentlyContinue
        Import-Module (Join-Path $modulePath 'Dowser.psd1') -Force -ErrorAction Stop

        # Build a temp tree with known file sizes:
        #   $tmpRoot/
        #     BigDir/
        #       huge.bin      1,000,000 bytes
        #       medium.bin      500,000 bytes
        #     SmallDir/
        #       small.txt         1,000 bytes
        #       tiny.dat            100 bytes
        #     root.ps1            10,000 bytes
        #
        # Total bytes: 1,000,000 + 500,000 + 1,000 + 100 + 10,000 = 1,511,100
        # BigDir rollup  : 1,500,000
        # SmallDir rollup:     1,100
        $tmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) "DduTest_$([System.IO.Path]::GetRandomFileName())"
        $null = New-Item -ItemType Directory -Path $tmpRoot -Force
        $null = New-Item -ItemType Directory -Path (Join-Path $tmpRoot 'BigDir')   -Force
        $null = New-Item -ItemType Directory -Path (Join-Path $tmpRoot 'SmallDir') -Force

        # Write files with exact byte counts using byte arrays
        [System.IO.File]::WriteAllBytes((Join-Path $tmpRoot 'BigDir\huge.bin'),   ([byte[]]::new(1000000)))
        [System.IO.File]::WriteAllBytes((Join-Path $tmpRoot 'BigDir\medium.bin'), ([byte[]]::new(500000)))
        [System.IO.File]::WriteAllBytes((Join-Path $tmpRoot 'SmallDir\small.txt'),([byte[]]::new(1000)))
        [System.IO.File]::WriteAllBytes((Join-Path $tmpRoot 'SmallDir\tiny.dat'), ([byte[]]::new(100)))
        [System.IO.File]::WriteAllBytes((Join-Path $tmpRoot 'root.ps1'),          ([byte[]]::new(10000)))

        $expectedTotal = 1511100
        $script:tmpRoot = $tmpRoot
        $script:expectedTotal = $expectedTotal
    }

    AfterAll {
        if ($script:tmpRoot -and (Test-Path $script:tmpRoot)) {
            Remove-Item -LiteralPath $script:tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Basic scan - summary' {
        BeforeAll {
            $script:results = Measure-DowserDiskUsage -Path $script:tmpRoot -TopN 15
        }

        It 'Returns a Summary object' {
            $summary = $script:results | Where-Object { $_.Section -eq 'Summary' }
            $summary | Should -Not -BeNullOrEmpty
        }

        It 'Reports correct total bytes' {
            $summary = $script:results | Where-Object { $_.Section -eq 'Summary' }
            $summary.TotalBytes | Should -Be $script:expectedTotal
        }

        It 'Reports correct total file count' {
            $summary = $script:results | Where-Object { $_.Section -eq 'Summary' }
            $summary.TotalFiles | Should -Be 5
        }

        It 'Summary TotalSize is a non-empty string' {
            $summary = $script:results | Where-Object { $_.Section -eq 'Summary' }
            $summary.TotalSize | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Biggest Directories - ranking and values' {
        BeforeAll {
            $script:dirRows = $script:results | Where-Object { $_.Section -eq 'BiggestDirectories' }
        }

        It 'Returns at least two directory rows' {
            $script:dirRows.Count | Should -BeGreaterOrEqual 2
        }

        It 'BigDir is ranked first' {
            $first = $script:dirRows | Select-Object -First 1
            $first.RelPath | Should -Match 'BigDir'
        }

        It 'BigDir rollup size is correct (1500000 bytes)' {
            $bigDir = $script:dirRows | Where-Object { $_.RelPath -match 'BigDir' }
            $bigDir.SizeBytes | Should -Be 1500000
        }

        It 'SmallDir rollup size is correct (1100 bytes)' {
            $smallDir = $script:dirRows | Where-Object { $_.RelPath -match 'SmallDir' }
            $smallDir.SizeBytes | Should -Be 1100
        }

        It 'BigDir is ranked before SmallDir' {
            $names = $script:dirRows | Select-Object -ExpandProperty RelPath
            $bigIdx   = [array]::IndexOf($names, ($names | Where-Object { $_ -match 'BigDir' }))
            $smallIdx = [array]::IndexOf($names, ($names | Where-Object { $_ -match 'SmallDir' }))
            $bigIdx | Should -BeLessThan $smallIdx
        }

        It 'Each row has a non-empty Size string' {
            $script:dirRows | ForEach-Object { $_.Size | Should -Not -BeNullOrEmpty }
        }

        It 'PctOfTotal for BigDir is approximately 99.3%' {
            $bigDir = $script:dirRows | Where-Object { $_.RelPath -match 'BigDir' }
            $bigDir.PctOfTotal | Should -BeGreaterThan 98
        }
    }

    Context 'Biggest Files - ranking and values' {
        BeforeAll {
            $script:fileRows = $script:results | Where-Object { $_.Section -eq 'BiggestFiles' }
        }

        It 'Returns at least 4 file rows' {
            $script:fileRows.Count | Should -BeGreaterOrEqual 4
        }

        It 'huge.bin is ranked first' {
            $first = $script:fileRows | Select-Object -First 1
            $first.RelPath | Should -Match 'huge\.bin'
        }

        It 'huge.bin size is correct (1000000 bytes)' {
            $f = $script:fileRows | Where-Object { $_.RelPath -match 'huge\.bin' }
            $f.SizeBytes | Should -Be 1000000
        }

        It 'medium.bin is ranked second' {
            $second = $script:fileRows | Select-Object -Skip 1 -First 1
            $second.RelPath | Should -Match 'medium\.bin'
        }

        It 'Files are ordered descending by size' {
            $sizes = $script:fileRows | Select-Object -ExpandProperty SizeBytes
            for ($i = 0; $i -lt ($sizes.Count - 1); $i++) {
                $sizes[$i] | Should -BeGreaterOrEqual $sizes[$i + 1]
            }
        }
    }

    Context '-MinSize filtering' {
        It 'Excludes files below MinSize from file ranking' {
            $filtered = Measure-DowserDiskUsage -Path $script:tmpRoot -TopN 15 -MinSize '100KB'
            $fileRows = $filtered | Where-Object { $_.Section -eq 'BiggestFiles' }
            # Only huge.bin (1MB) and medium.bin (500KB) exceed 100KB
            $fileRows.Count | Should -Be 2
            $fileRows | ForEach-Object { $_.SizeBytes | Should -BeGreaterOrEqual (100 * 1KB) }
        }

        It 'Total bytes is unaffected by -MinSize' {
            $filtered = Measure-DowserDiskUsage -Path $script:tmpRoot -TopN 15 -MinSize '100KB'
            $summary = $filtered | Where-Object { $_.Section -eq 'Summary' }
            $summary.TotalBytes | Should -Be $script:expectedTotal
        }
    }

    Context 'By Extension aggregation' {
        BeforeAll {
            $script:extRows = $script:results | Where-Object { $_.Section -eq 'ByExtension' }
        }

        It 'Returns extension rows' {
            $script:extRows | Should -Not -BeNullOrEmpty
        }

        It '.bin extension aggregates huge.bin + medium.bin (1500000 bytes)' {
            $bin = $script:extRows | Where-Object { $_.Extension -eq '.bin' }
            $bin | Should -Not -BeNullOrEmpty
            $bin.SizeBytes | Should -Be 1500000
        }

        It '.bin FileCount is 2' {
            $bin = $script:extRows | Where-Object { $_.Extension -eq '.bin' }
            $bin.FileCount | Should -Be 2
        }

        It '.txt extension aggregates small.txt (1000 bytes)' {
            $txt = $script:extRows | Where-Object { $_.Extension -eq '.txt' }
            $txt | Should -Not -BeNullOrEmpty
            $txt.SizeBytes | Should -Be 1000
        }

        It '.ps1 extension aggregates root.ps1 (10000 bytes)' {
            $ps1 = $script:extRows | Where-Object { $_.Extension -eq '.ps1' }
            $ps1 | Should -Not -BeNullOrEmpty
            $ps1.SizeBytes | Should -Be 10000
        }

        It 'Extension rows are ordered descending by size' {
            $sizes = $script:extRows | Select-Object -ExpandProperty SizeBytes
            for ($i = 0; $i -lt ($sizes.Count - 1); $i++) {
                $sizes[$i] | Should -BeGreaterOrEqual $sizes[$i + 1]
            }
        }
    }

    Context '-ExportHtml' {
        BeforeAll {
            $script:htmlPath = Join-Path ([System.IO.Path]::GetTempPath()) "DduTest_$([System.IO.Path]::GetRandomFileName()).html"
            $null = Measure-DowserDiskUsage -Path $script:tmpRoot -TopN 15 -ExportHtml $script:htmlPath
        }

        AfterAll {
            if ($script:htmlPath -and (Test-Path $script:htmlPath)) {
                Remove-Item -LiteralPath $script:htmlPath -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Writes the HTML file' {
            Test-Path $script:htmlPath | Should -Be $true
        }

        It 'HTML file is non-empty' {
            (Get-Item $script:htmlPath).Length | Should -BeGreaterThan 0
        }

        It 'Contains treemap markup (ddu-treemap id)' {
            $content = [System.IO.File]::ReadAllText($script:htmlPath)
            $content | Should -Match 'id=.ddu-treemap'
        }

        It 'Contains treemap block elements (ddu-block class)' {
            $content = [System.IO.File]::ReadAllText($script:htmlPath)
            $content | Should -Match "class='ddu-block'"
        }

        It 'Contains the dark background palette color #1e1e1e' {
            $content = [System.IO.File]::ReadAllText($script:htmlPath)
            $content | Should -Match '#1e1e1e'
        }

        It 'Contains accent blue #569cd6' {
            $content = [System.IO.File]::ReadAllText($script:htmlPath)
            $content | Should -Match '#569cd6'
        }

        It 'Contains teal accent #4ec9b0' {
            $content = [System.IO.File]::ReadAllText($script:htmlPath)
            $content | Should -Match '#4ec9b0'
        }

        It 'Contains the ranked tables sections' {
            $content = [System.IO.File]::ReadAllText($script:htmlPath)
            $content | Should -Match 'Biggest Directories'
            $content | Should -Match 'Biggest Files'
            $content | Should -Match 'By Extension'
        }
    }

    Context '-ExcludePath' {
        It 'Skips excluded directory and its files' {
            $excl = Measure-DowserDiskUsage -Path $script:tmpRoot -TopN 15 -ExcludePath 'BigDir'
            $summary = $excl | Where-Object { $_.Section -eq 'Summary' }
            # BigDir had 1500000 bytes; total should be 1511100 - 1500000 = 11100
            $summary.TotalBytes | Should -Be 11100
        }
    }

    Context 'Alias' {
        It 'ddu alias resolves to Measure-DowserDiskUsage' {
            $alias = Get-Alias ddu -ErrorAction SilentlyContinue
            $alias | Should -Not -BeNullOrEmpty
            $alias.Definition | Should -Be 'Measure-DowserDiskUsage'
        }
    }

    Context 'Help' {
        It 'Get-Help returns a help object with SYNOPSIS' {
            $help = Get-Help Measure-DowserDiskUsage -ErrorAction SilentlyContinue
            $help | Should -Not -BeNullOrEmpty
            $help.Synopsis | Should -Not -BeNullOrEmpty
        }
    }
}
