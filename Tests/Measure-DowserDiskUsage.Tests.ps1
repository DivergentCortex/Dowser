#Requires -Modules @{ModuleName='Pester';ModuleVersion='5.0'}

Describe 'Measure-DowserDiskUsage' {
    BeforeAll {
        $modulePath = Split-Path $PSScriptRoot -Parent
        Remove-Module Dowser -Force -ErrorAction SilentlyContinue
        Import-Module (Join-Path $modulePath 'Dowser.psd1') -Force -ErrorAction Stop

        # Build a temp tree with known file sizes.
        # All paths use nested Join-Path calls for cross-platform correctness.
        #
        #   $tmpRoot/
        #     BigDir/
        #       huge.bin        1,000,000 bytes
        #       medium.bin        500,000 bytes
        #     SmallDir/
        #       small.txt           1,000 bytes
        #       tiny.dat              100 bytes
        #     root.ps1             10,000 bytes
        #     noext                   500 bytes   (extensionless -- tests '<none>' bucket)
        #
        # Total bytes: 1,000,000 + 500,000 + 1,000 + 100 + 10,000 + 500 = 1,511,600
        # BigDir rollup  : 1,500,000
        # SmallDir rollup:     1,100
        # Root-level files (treemap remainder): 10,000 + 500 = 10,500
        $tmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) "DduTest_$([System.IO.Path]::GetRandomFileName())"
        $null = New-Item -ItemType Directory -Path $tmpRoot -Force
        $null = New-Item -ItemType Directory -Path (Join-Path $tmpRoot 'BigDir') -Force
        $null = New-Item -ItemType Directory -Path (Join-Path $tmpRoot 'SmallDir') -Force

        [System.IO.File]::WriteAllBytes((Join-Path (Join-Path $tmpRoot 'BigDir') 'huge.bin'), ([byte[]]::new(1000000)))
        [System.IO.File]::WriteAllBytes((Join-Path (Join-Path $tmpRoot 'BigDir') 'medium.bin'), ([byte[]]::new(500000)))
        [System.IO.File]::WriteAllBytes((Join-Path (Join-Path $tmpRoot 'SmallDir') 'small.txt'), ([byte[]]::new(1000)))
        [System.IO.File]::WriteAllBytes((Join-Path (Join-Path $tmpRoot 'SmallDir') 'tiny.dat'), ([byte[]]::new(100)))
        [System.IO.File]::WriteAllBytes((Join-Path $tmpRoot 'root.ps1'), ([byte[]]::new(10000)))
        [System.IO.File]::WriteAllBytes((Join-Path $tmpRoot 'noext'), ([byte[]]::new(500)))

        $expectedTotal = 1511600
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
            $summary.TotalFiles | Should -Be 6
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
            $names = @($script:dirRows | Select-Object -ExpandProperty RelPath)
            $bigIdx = [array]::IndexOf($names, ($names | Where-Object { $_ -match 'BigDir' }   | Select-Object -First 1))
            $smallIdx = [array]::IndexOf($names, ($names | Where-Object { $_ -match 'SmallDir' } | Select-Object -First 1))
            $bigIdx | Should -BeLessThan $smallIdx
        }

        It 'Each row has a non-empty Size string' {
            $script:dirRows | ForEach-Object { $_.Size | Should -Not -BeNullOrEmpty }
        }

        It 'PctOfTotal for BigDir is approximately 99.2%' {
            $bigDir = $script:dirRows | Where-Object { $_.RelPath -match 'BigDir' }
            $bigDir.PctOfTotal | Should -BeGreaterThan 98
        }
    }

    Context 'Biggest Files - ranking and values' {
        BeforeAll {
            $script:fileRows = $script:results | Where-Object { $_.Section -eq 'BiggestFiles' }
        }

        It 'Returns at least 5 file rows' {
            $script:fileRows.Count | Should -BeGreaterOrEqual 5
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

        It '<none> extension aggregates the extensionless file noext (500 bytes)' {
            $none = $script:extRows | Where-Object { $_.Extension -eq '<none>' }
            $none | Should -Not -BeNullOrEmpty
            $none.SizeBytes | Should -Be 500
        }

        It '<none> FileCount is 1' {
            $none = $script:extRows | Where-Object { $_.Extension -eq '<none>' }
            $none.FileCount | Should -Be 1
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
            $script:htmlContent = [System.IO.File]::ReadAllText($script:htmlPath)
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
            $script:htmlContent | Should -Match 'id=.ddu-treemap'
        }

        It 'Contains treemap block elements (ddu-block class)' {
            $script:htmlContent | Should -Match "class='ddu-block"
        }

        It 'Contains the dark background palette color #1e1e1e' {
            $script:htmlContent | Should -Match '#1e1e1e'
        }

        It 'Contains accent blue #569cd6' {
            $script:htmlContent | Should -Match '#569cd6'
        }

        It 'Contains teal accent #4ec9b0' {
            $script:htmlContent | Should -Match '#4ec9b0'
        }

        It 'Contains the ranked tables sections' {
            $script:htmlContent | Should -Match 'Biggest Directories'
            $script:htmlContent | Should -Match 'Biggest Files'
            $script:htmlContent | Should -Match 'By Extension'
        }

        It 'Treemap block widths sum to approximately 100% of total (proportionality check)' {
            # Extract width:NN.NN% values from all ddu-block style attributes (immediate-child
            # blocks + remainder block). Their widths must be proportional to TotalBytes and
            # must together sum close to 100 (all bytes accounted for).
            $allWidths = [System.Collections.Generic.List[double]]::new()
            $rx = [System.Text.RegularExpressions.Regex]::new(
                "class='ddu-block[^']*'[^>]*style='[^']*width:([\d.]+)%")
            $rxMatches = $rx.Matches($script:htmlContent)
            foreach ($m in $rxMatches) {
                $allWidths.Add([double]$m.Groups[1].Value)
            }
            $allWidths.Count | Should -BeGreaterThan 0
            $totalWidth = 0.0
            foreach ($w in $allWidths) {
                $totalWidth += $w 
            }
            # All blocks (immediate children + remainder) must together represent the full
            # tree -- sum should be within 1% of 100 to account for rounding.
            $totalWidth | Should -BeGreaterThan 99
            $totalWidth | Should -BeLessOrEqual 101
        }

        It 'Largest treemap block width is proportional to BigDir fraction of total' {
            # BigDir = 1500000 / 1511600 = ~99.2% of total.
            # The largest ddu-block width must be >= 98 (immediate-child block for BigDir).
            $rx = [System.Text.RegularExpressions.Regex]::new(
                "class='ddu-block[^']*'[^>]*style='[^']*width:([\d.]+)%")
            $widths = $rx.Matches($script:htmlContent) | ForEach-Object { [double]$_.Groups[1].Value }
            ($widths | Measure-Object -Maximum).Maximum | Should -BeGreaterThan 98
        }

        It 'Remainder block for root-level files is present in treemap' {
            # root.ps1 (10000) + noext (500) = 10500 bytes live directly in root,
            # not under any immediate subdir -- must appear as a remainder block.
            $script:htmlContent | Should -Match 'ddu-remainder'
        }
    }

    Context '-ExcludePath' {
        It 'Skips excluded directory and its files' {
            $excl = Measure-DowserDiskUsage -Path $script:tmpRoot -TopN 15 -ExcludePath 'BigDir'
            $summary = $excl | Where-Object { $_.Section -eq 'Summary' }
            # BigDir had 1500000 bytes; total should be 1511600 - 1500000 = 11600
            $summary.TotalBytes | Should -Be 11600
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

    Context 'Cross-platform path handling' {
        It 'RelPath uses the platform separator (no wrong-platform slashes)' {
            $dirRows = $script:results | Where-Object { $_.Section -eq 'BiggestDirectories' }
            $dirRows | Should -Not -BeNullOrEmpty
            if ($IsLinux -or $IsMacOS) {
                $dirRows | ForEach-Object {
                    $_.RelPath | Should -Not -Match '\\'
                }
            }
            else {
                $dirRows | ForEach-Object {
                    $_.RelPath | Should -Not -Match '^/'
                }
            }
        }

        It 'Accepts path via pipeline (FullName alias)' {
            $item = Get-Item $script:tmpRoot
            $r = $item | Measure-DowserDiskUsage -TopN 5
            $summary = $r | Where-Object { $_.Section -eq 'Summary' }
            $summary | Should -Not -BeNullOrEmpty
            $summary.TotalBytes | Should -Be $script:expectedTotal
        }

        It 'Handles a path with trailing separator' {
            $trailingPath = $script:tmpRoot + [System.IO.Path]::DirectorySeparatorChar
            $r = Measure-DowserDiskUsage -Path $trailingPath -TopN 5
            $summary = $r | Where-Object { $_.Section -eq 'Summary' }
            $summary | Should -Not -BeNullOrEmpty
            $summary.TotalBytes | Should -Be $script:expectedTotal
        }

        It 'Scans a symlinked root directory correctly (non-Windows only)' -Skip:($IsWindows -ne $false) {
            # Symlink pointing at the temp tree; function must scan it without skipping
            # (FIX #2: root reparse point is allowed even though it is a symlink).
            $symlinkPath = Join-Path ([System.IO.Path]::GetTempPath()) "DduSymlink_$([System.IO.Path]::GetRandomFileName())"
            $created = $false
            try {
                $null = New-Item -ItemType SymbolicLink -Path $symlinkPath -Target $script:tmpRoot -ErrorAction Stop
                $created = $true
            }
            catch {
                Set-ItResult -Skipped -Because "symlink creation not permitted: $($_.Exception.Message)"
                return
            }
            try {
                $r = Measure-DowserDiskUsage -Path $symlinkPath -TopN 5
                $summary = $r | Where-Object { $_.Section -eq 'Summary' }
                $summary | Should -Not -BeNullOrEmpty
                $summary.TotalBytes | Should -Be $script:expectedTotal
            }
            finally {
                if ($created -and (Test-Path $symlinkPath)) {
                    Remove-Item -LiteralPath $symlinkPath -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
}
