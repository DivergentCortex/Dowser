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
        # linux paths are case-sensitive, so both must survive
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
        # Select-Object -Unique is quadratic: at this size it takes about a minute
        # and looks exactly like a hang, so keep the time limit honest
        $paths = 1..50000 | ForEach-Object { "/home/u/projects/deep/path/file$_.ps1" }

        $sw = [Diagnostics.Stopwatch]::StartNew()
        $result = @(Select-DowserUniquePath -Path $paths)
        $sw.Stop()

        $result.Count | Should -Be 50000
        $sw.Elapsed.TotalSeconds | Should -BeLessThan 5
    }
}
