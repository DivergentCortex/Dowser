#Requires -Modules @{ModuleName='Pester';ModuleVersion='5.0'}

Describe 'Measure-DowserDirectory freshness report' {
    BeforeAll {
        $modulePath = Split-Path $PSScriptRoot -Parent
        Remove-Module Dowser -Force -ErrorAction SilentlyContinue
        Import-Module (Join-Path $modulePath 'Dowser.psd1') -Force -ErrorAction Stop

        # Controlled timestamps: 'now' files count as today, a 3-day-old file is inside the
        # default 7-day window but not today, a 30-day-old file is outside it.
        $root = Join-Path ([System.IO.Path]::GetTempPath()) 'DowserMeasureDirRoot'
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        foreach ($rel in @('A/sub', 'B', 'C', '.hidden')) {
            $null = New-Item -ItemType Directory -Path (Join-Path $root $rel) -Force
        }
        # Fixed reference instant (today at noon) passed as -Now, so the buckets cannot flip
        # if the run straddles local midnight (Muninn 1831 finding 5).
        $now = (Get-Date).Date.AddHours(12)
        $files = @(
            @{ Rel = 'loose.txt'; Bytes = 5; When = $now.AddMinutes(-1) }
            @{ Rel = 'A/a1.txt'; Bytes = 100; When = $now.AddMinutes(-1) }
            @{ Rel = 'A/sub/a2.txt'; Bytes = 40; When = $now.AddDays(-3) }
            @{ Rel = 'B/b1.txt'; Bytes = 7; When = $now.AddDays(-30) }
            @{ Rel = '.hidden/h1.txt'; Bytes = 9; When = $now.AddDays(-2) }
        )
        foreach ($f in $files) {
            $full = Join-Path $root $f.Rel
            [System.IO.File]::WriteAllBytes($full, (New-Object byte[] $f.Bytes))
            (Get-Item -LiteralPath $full).LastWriteTime = $f.When
        }
        # A symlink inside A pointing back at the root: following it would loop or double-count.
        $script:canLink = $false
        try {
            $null = New-Item -ItemType SymbolicLink -Path (Join-Path $root 'A/loop') -Target $root -ErrorAction Stop
            $script:canLink = $true
        }
        catch {
            $script:canLink = $false
        }
        $script:root = $root
        $script:now = $now
        $script:rows = @(Measure-DowserDirectory -Path $root -Now $now)
        $script:byName = @{}
        foreach ($r in $script:rows) {
            $script:byName[$r.Folder] = $r
        }
    }

    AfterAll {
        if ($script:root -and (Test-Path -LiteralPath $script:root)) {
            Remove-Item -LiteralPath $script:root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Counts' {
        It 'FileCount is the recursive file count, not the immediate child count' {
            $script:byName['A'].FileCount | Should -Be 2
        }

        It 'ItemCount keeps the immediate children count, folders included' {
            # a1.txt, the sub folder, and (when symlinks work) the loop link
            $expected = if ($script:canLink) { 3 } else { 2 }
            $script:byName['A'].ItemCount | Should -Be $expected
        }

        It 'Does not follow a symlinked directory inside a folder (no loop, no double count)' {
            if (-not $script:canLink) {
                Set-ItResult -Skipped -Because 'symlink creation not available'
                return
            }
            $script:byName['A'].FileCount | Should -Be 2
        }

        It 'Measures hidden, dot-prefixed folders like any other' {
            $h = $script:byName['.hidden']
            $h | Should -Not -BeNullOrEmpty
            $h.FileCount | Should -Be 1
        }

        It 'ModifiedWithinDays plus OlderThanDays equals FileCount' {
            foreach ($r in $script:rows) {
                ($r.ModifiedWithinDays + $r.OlderThanDays) | Should -Be $r.FileCount -Because "folder $($r.Folder)"
            }
        }

        It 'SizeBytes totals the whole subtree' {
            $script:byName['A'].SizeBytes | Should -Be 140
            $script:byName['A'].DataSize | Should -Be '140.0B'
        }
    }

    Context 'Age buckets with the default 7-day window' {
        It 'Splits A into today, within window, and older' {
            $a = $script:byName['A']
            $a.ModifiedToday | Should -Be 1
            $a.ModifiedWithinDays | Should -Be 2
            $a.OlderThanDays | Should -Be 0
            $a.RecentDays | Should -Be 7
        }

        It 'Counts a 30-day-old file as older than the window' {
            $b = $script:byName['B']
            $b.ModifiedToday | Should -Be 0
            $b.ModifiedWithinDays | Should -Be 0
            $b.OlderThanDays | Should -Be 1
            $b.NewestFileAge | Should -Be '30d ago'
        }

        It 'Reports the newest file for the folder' {
            $script:byName['A'].NewestFileName | Should -Be 'a1.txt'
            $script:byName['A'].OldestFileName | Should -Be 'a2.txt'
        }
    }

    Context '-RecentDays' {
        It 'Widening the window moves an old file into ModifiedWithinDays' {
            $wide = @(Measure-DowserDirectory -Path $script:root -RecentDays 60) | Where-Object Folder -eq 'B'
            $wide.ModifiedWithinDays | Should -Be 1
            $wide.OlderThanDays | Should -Be 0
        }

        It 'Accepts the path positionally, as documented (operator run #21255)' {
            $rows = @(Measure-DowserDirectory $script:root -RecentDays 30)
            $rows | Where-Object Folder -eq 'A' | Should -Not -BeNullOrEmpty
        }

        It 'Skips a file passed as -Path instead of reporting it as a "." row' {
            $rows = @(Measure-DowserDirectory -Path (Join-Path $script:root 'loose.txt') -Now $script:now 6>$null)
            $rows.Count | Should -Be 0
        }

        It 'Rejects a window below 1 day' {
            { Measure-DowserDirectory -Path $script:root -RecentDays 0 } | Should -Throw
        }
    }

    Context 'Edge rows' {
        It 'An empty folder reports zero files and blank ages instead of erroring' {
            $c = $script:byName['C']
            $c.FileCount | Should -Be 0
            $c.DataSize | Should -Be '0B'
            $c.NewestFileAge | Should -Be ''
        }

        It 'Loose files directly under the root get a "." row' {
            $dot = $script:byName['.']
            $dot | Should -Not -BeNullOrEmpty
            $dot.FileCount | Should -Be 1
            $dot.ModifiedToday | Should -Be 1
        }

        It 'Emits no "." row when the root has no loose files' {
            $foldersOnlyRoot = Join-Path $script:root 'E'
            $null = New-Item -ItemType Directory -Path (Join-Path $foldersOnlyRoot 'inner') -Force
            [System.IO.File]::WriteAllText((Join-Path $foldersOnlyRoot 'inner/x.txt'), 'x')
            $rows = @(Measure-DowserDirectory -Path $foldersOnlyRoot)
            $rows.Count | Should -Be 1
            $rows[0].Folder | Should -Be 'inner'
        }
    }

    Context 'Default view' {
        It 'Shows the freshness columns by default' {
            $props = $script:rows[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $props | Should -Contain 'ModifiedToday'
            $props | Should -Contain 'OlderThanDays'
            $props | Should -Contain 'NewestFileAge'
        }
    }
}

Describe 'Get-DowserReport depth hint' {
    BeforeAll {
        $modulePath = Split-Path $PSScriptRoot -Parent
        Remove-Module Dowser -Force -ErrorAction SilentlyContinue
        Import-Module (Join-Path $modulePath 'Dowser.psd1') -Force -ErrorAction Stop

        $hintRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'DowserReportHintRoot'
        Remove-Item -LiteralPath $hintRoot -Recurse -Force -ErrorAction SilentlyContinue
        $null = New-Item -ItemType Directory -Path (Join-Path $hintRoot 'only/inner') -Force
        [System.IO.File]::WriteAllText((Join-Path $hintRoot 'only/inner/f.txt'), 'x')
        $script:hintRoot = $hintRoot
    }

    AfterAll {
        if ($script:hintRoot -and (Test-Path -LiteralPath $script:hintRoot)) {
            Remove-Item -LiteralPath $script:hintRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Points at -Depth -1 when a folder of folders yields nothing at the default depth' {
        # Write-Log renders through the information stream (6)
        $log = (Get-DowserReport -Path $script:hintRoot 6>&1) | Out-String
        $log | Should -Match '-Depth -1'
    }

    It 'Does not emit the hint when -Depth already reaches the files' {
        $log = (Get-DowserReport -Path $script:hintRoot -Depth -1 6>&1) | Out-String
        $log | Should -Not -Match 'pass -Depth -1'
    }
}
