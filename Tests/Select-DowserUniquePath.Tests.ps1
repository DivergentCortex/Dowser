#Requires -Modules @{ModuleName='Pester';ModuleVersion='5.0'}

Describe 'Select-DowserUniquePath' {
    BeforeAll {
        . (Join-Path (Split-Path $PSScriptRoot -Parent) 'Private/Select-DowserUniquePath.ps1')
    }

    It 'removes exact duplicates and preserves first-seen order' {
        $result = @(Select-DowserUniquePath -Path @('/b/two.txt', '/a/one.txt', '/b/two.txt', '/c/three.txt'))
        $result | Should -Be @('/b/two.txt', '/a/one.txt', '/c/three.txt')
    }

    It 'treats case-differing paths as distinct, matching Select-Object -Unique' {
        # on Linux /b/File.txt and /b/file.txt are different files; both must survive
        $result = @(Select-DowserUniquePath -Path @('/b/File.txt', '/b/file.txt'))
        $result.Count | Should -Be 2
    }

    It 'returns an empty array for empty input' {
        $result = @(Select-DowserUniquePath -Path @())
        $result.Count | Should -Be 0
    }

    It 'skips null and empty entries' {
        $result = @(Select-DowserUniquePath -Path @('/a.txt', $null, '', '/a.txt', '/b.txt'))
        $result | Should -Be @('/a.txt', '/b.txt')
    }

    It 'deduplicates 50,000 paths in under 5 seconds' {
        # Select-Object -Unique is O(n^2): 40k paths measured at ~37s, 50k extrapolates to ~58s.
        # This is the regression guard for the Find-DowserString stall.
        $paths = 1..50000 | ForEach-Object { "/home/u/projects/deep/path/file$_.ps1" }

        $sw = [Diagnostics.Stopwatch]::StartNew()
        $result = @(Select-DowserUniquePath -Path $paths)
        $sw.Stop()

        $result.Count | Should -Be 50000
        $sw.Elapsed.TotalSeconds | Should -BeLessThan 5
    }
}
