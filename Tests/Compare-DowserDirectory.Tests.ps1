#Requires -Modules @{ModuleName='Pester';ModuleVersion='5.0'}

Describe 'Compare-DowserDirectory' {
    BeforeAll {
        $modulePath = Split-Path $PSScriptRoot -Parent
        Remove-Module Dowser -Force -ErrorAction SilentlyContinue
        Import-Module (Join-Path $modulePath 'Dowser.psd1') -Force -ErrorAction Stop

        $base = Join-Path ([System.IO.Path]::GetTempPath()) 'DowserCompareDirRoot'
        Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
        $ref = Join-Path $base 'ref'
        $diff = Join-Path $base 'diff'
        foreach ($rel in @('ref/sub', 'ref/node_modules/pkg', 'ref/logs', 'diff/sub', 'diff/node_modules/pkg', 'diff/logs')) {
            $null = New-Item -ItemType Directory -Path (Join-Path $base $rel) -Force
        }
        function Set-Text([string]$path, [string]$text) {
            [System.IO.File]::WriteAllText($path, $text)
        }
        Set-Text (Join-Path $ref 'same.txt') 'identical'
        Set-Text (Join-Path $diff 'same.txt') 'identical'
        Set-Text (Join-Path $ref 'sub/sized.txt') 'short'
        Set-Text (Join-Path $diff 'sub/sized.txt') 'much longer'
        Set-Text (Join-Path $ref 'content.txt') 'aaaa'
        Set-Text (Join-Path $diff 'content.txt') 'bbbb'
        Set-Text (Join-Path $ref 'only-in-ref.txt') 'x'
        Set-Text (Join-Path $diff 'only-in-diff.txt') 'y'
        # differs only inside default-excluded and pattern-excluded folders
        Set-Text (Join-Path $ref 'node_modules/pkg/index.js') 'one'
        Set-Text (Join-Path $diff 'node_modules/pkg/index.js') 'two'
        Set-Text (Join-Path $ref 'logs/run.log') 'one'
        Set-Text (Join-Path $diff 'logs/run.log') 'two'

        $script:base = $base
        $script:ref = $ref
        $script:diff = $diff
        $script:rows = @(Compare-DowserDirectory -ReferencePath $ref -DifferencePath $diff)
        $script:byPath = @{}
        foreach ($r in $script:rows) {
            $script:byPath[$r.RelativePath] = $r
        }
    }

    AfterAll {
        if ($script:base -and (Test-Path -LiteralPath $script:base)) {
            Remove-Item -LiteralPath $script:base -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Classification' {
        It 'Flags a size difference as Changed (Size)' {
            $script:byPath['sub/sized.txt'].Status | Should -Be 'Changed'
            $script:byPath['sub/sized.txt'].Reason | Should -Be 'Size'
        }

        It 'Flags same-size different content as Changed (Content)' {
            $script:byPath['content.txt'].Status | Should -Be 'Changed'
            $script:byPath['content.txt'].Reason | Should -Be 'Content'
        }

        It 'Reports files only in the reference as MissingFromDifference' {
            $script:byPath['only-in-ref.txt'].Status | Should -Be 'MissingFromDifference'
        }

        It 'Reports files only in the difference as ExtraInDifference' {
            $script:byPath['only-in-diff.txt'].Status | Should -Be 'ExtraInDifference'
        }

        It 'Omits identical files unless -IncludeSame' {
            $script:byPath.ContainsKey('same.txt') | Should -BeFalse
            $all = @(Compare-DowserDirectory $script:ref $script:diff -IncludeSame)
            ($all | Where-Object RelativePath -eq 'same.txt').Status | Should -Be 'Same'
        }
    }

    Context 'Excludes' {
        It 'Prunes node_modules by default' {
            $script:byPath.Keys | Where-Object { $_ -like 'node_modules*' } | Should -BeNullOrEmpty
        }

        It '-NoDefaultExcludes includes node_modules' {
            $rows = @(Compare-DowserDirectory $script:ref $script:diff -NoDefaultExcludes)
            ($rows | Where-Object RelativePath -eq 'node_modules/pkg/index.js').Status | Should -Be 'Changed'
        }

        It '-ExcludePattern prunes a named folder on both sides' {
            $script:byPath.ContainsKey('logs/run.log') | Should -BeTrue
            $rows = @(Compare-DowserDirectory $script:ref $script:diff -ExcludePattern 'logs')
            $rows | Where-Object { $_.RelativePath -like 'logs/*' } | Should -BeNullOrEmpty
        }
    }

    Context 'Summary' {
        It 'Counts every status and reports InSync false when anything differs' {
            $s = Compare-DowserDirectory $script:ref $script:diff -Summary
            $s.Same | Should -Be 1
            $s.Changed | Should -Be 3
            $s.MissingFromDifference | Should -Be 1
            $s.ExtraInDifference | Should -Be 1
            $s.InSync | Should -BeFalse
        }

        It 'Reports InSync true when two trees match' {
            $s = Compare-DowserDirectory (Join-Path $script:ref 'node_modules') (Join-Path $script:ref 'node_modules') -Summary
            $s.InSync | Should -BeTrue
            $s.Same | Should -Be 1
        }
    }

    Context 'Inputs' {
        It 'Compares two files directly' {
            $row = @(Compare-DowserDirectory (Join-Path $script:ref 'content.txt') (Join-Path $script:diff 'content.txt'))
            $row.Count | Should -Be 1
            $row[0].Status | Should -Be 'Changed'
        }

        It 'Refuses to compare a folder with a file' {
            { Compare-DowserDirectory $script:ref (Join-Path $script:diff 'same.txt') } | Should -Throw '*both paths must be folders or both must be files*'
        }

        It 'Throws on a missing path' {
            { Compare-DowserDirectory $script:ref (Join-Path $script:base 'nope') } | Should -Throw '*does not exist*'
        }

        It 'Rejects a stray third positional argument' {
            { Compare-DowserDirectory $script:ref $script:diff extra } | Should -Throw -ErrorId 'PositionalParameterNotFound,Compare-DowserDirectory'
        }

        It 'Never modifies either side' {
            $before = (Get-ChildItem -LiteralPath $script:diff -Recurse -File -Force | Measure-Object Length -Sum).Sum
            $null = Compare-DowserDirectory $script:ref $script:diff -IncludeSame
            (Get-ChildItem -LiteralPath $script:diff -Recurse -File -Force | Measure-Object Length -Sum).Sum | Should -Be $before
        }
    }
}
