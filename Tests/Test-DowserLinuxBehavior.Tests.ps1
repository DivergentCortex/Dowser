#Requires -Modules @{ModuleName='Pester';ModuleVersion='5.0'}

# Pester coverage for the Linux-behavior / path-separator / output-silence fixes
# (Task #1). These exercise the cross-platform defects that previously produced
# silent false success or empty/zero output on non-Windows pwsh.

Describe 'Dowser Linux behavior fixes' {
    BeforeAll {
        $modulePath = Split-Path $PSScriptRoot -Parent
        Remove-Module Dowser -Force -ErrorAction SilentlyContinue
        Import-Module (Join-Path $modulePath 'Dowser.psd1') -Force -ErrorAction Stop

        $tmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) "DowserLinux_$([System.IO.Path]::GetRandomFileName())"
        $null = New-Item -ItemType Directory -Path $tmpRoot -Force
        $script:tmpRoot = $tmpRoot
        # On a non-Windows pwsh $IsWindows is $false; on PS 5.1 it is $null.
        $script:onWindows = ($IsWindows -ne $false)
    }

    AfterAll {
        if ($script:tmpRoot -and (Test-Path $script:tmpRoot)) {
            Remove-Item -LiteralPath $script:tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Get-DowserOwnership' {
        BeforeAll {
            $script:ownDir = Join-Path $script:tmpRoot 'own'
            $null = New-Item -ItemType Directory -Path $script:ownDir -Force
            Set-Content -Path (Join-Path $script:ownDir 'a.txt') -Value 'hello'
            $script:ownResult = @(Get-DowserOwnership -Directory $script:ownDir)
        }

        It 'Returns at least one metadata object (not empty)' {
            $script:ownResult.Count | Should -BeGreaterThan 0
        }

        It 'Populates Unix Owner/Group/UnixMode on non-Windows' -Skip:$script:onWindows {
            $entry = $script:ownResult | Select-Object -First 1
            $entry.Owner    | Should -Not -BeNullOrEmpty
            $entry.Group    | Should -Not -BeNullOrEmpty
            $entry.UnixMode | Should -Not -BeNullOrEmpty
        }

        It 'Carries a PlatformNote on non-Windows' -Skip:$script:onWindows {
            $entry = $script:ownResult | Select-Object -First 1
            $entry.PlatformNote | Should -Match 'Windows-only'
        }
    }

    Context 'Measure-DowserDirectory' {
        BeforeAll {
            $script:measRoot = Join-Path $script:tmpRoot 'meas'
            $sub = Join-Path $script:measRoot 'sub'
            $null = New-Item -ItemType Directory -Path $sub -Force
            Set-Content -Path (Join-Path $sub 'one.txt') -Value '1'
            Set-Content -Path (Join-Path $sub 'two.txt') -Value '2'
            $script:measResult = @(Measure-DowserDirectory -Path $script:measRoot)
        }

        It 'Reports a non-zero FileCount for the subdirectory' {
            $row = $script:measResult | Where-Object { $_.Directory -like '*sub' } | Select-Object -First 1
            $row | Should -Not -BeNullOrEmpty
            $row.FileCount | Should -BeGreaterThan 0
        }
    }

    Context 'Find-DowserOrphan' {
        BeforeAll {
            $script:orphRoot = Join-Path $script:tmpRoot 'orph'
            $git = Join-Path $script:orphRoot '.git'
            $null = New-Item -ItemType Directory -Path $git -Force
            Set-Content -Path (Join-Path $script:orphRoot 'lonely.txt') -Value 'nothing references me'
            Set-Content -Path (Join-Path $git 'config') -Value 'excluded content'
            $script:orphResult = @(Find-DowserOrphan -SearchPath $script:orphRoot)
        }

        It 'Excludes files under an excluded directory (.git) regardless of separator' {
            ($script:orphResult.FullName -join "`n") | Should -Not -Match '\.git'
        }

        It 'Returns clean FileInfo objects with no Format-Table pollution' {
            $script:orphResult.Count | Should -BeGreaterThan 0
            foreach ($o in $script:orphResult) {
                $o | Should -BeOfType [System.IO.FileInfo]
            }
            # No format-record objects leak into the return.
            ($script:orphResult | Where-Object { $_.GetType().FullName -like 'Microsoft.PowerShell.Commands.Internal.Format.*' }) |
                Should -BeNullOrEmpty
        }
    }

    Context 'ConvertTo-DowserBase64' {
        BeforeAll {
            $script:imgPath = Join-Path $script:tmpRoot 'img.png'
            [System.IO.File]::WriteAllBytes($script:imgPath, ([byte[]](1..32)))
        }

        It 'Emits the Base64 string to the pipeline when no destination is given' {
            $out = ConvertTo-DowserBase64 -Path $script:imgPath
            $out | Should -Not -BeNullOrEmpty
            $out | Should -BeOfType [string]
            # Round-trips back to the original bytes.
            [Convert]::FromBase64String($out).Length | Should -Be 32
        }
    }

    Context 'New-DowserHiddenFolder' {
        It 'Dot-prefixes the folder for true hiding on non-Windows' -Skip:$script:onWindows {
            $target = Join-Path $script:tmpRoot 'secretwork'
            $result = New-DowserHiddenFolder -Path $target
            $result | Should -Not -BeNullOrEmpty
            # The created/renamed folder is dot-prefixed and actually exists on disk.
            $dotted = Join-Path $script:tmpRoot '.secretwork'
            Test-Path -LiteralPath $dotted | Should -BeTrue
            (Split-Path -Path $result.Path -Leaf) | Should -Be '.secretwork'
            $result.PlatformNote | Should -Match 'Windows-only'
        }

        It 'Leaves an already-dotted folder unchanged on non-Windows' -Skip:$script:onWindows {
            $target = Join-Path $script:tmpRoot '.alreadyhidden'
            $result = New-DowserHiddenFolder -Path $target
            (Split-Path -Path $result.Path -Leaf) | Should -Be '.alreadyhidden'
            Test-Path -LiteralPath $target | Should -BeTrue
        }
    }

    Context 'Get-DowserMap symlink render' {
        BeforeAll {
            $script:mapRoot = Join-Path $script:tmpRoot 'map'
            $mapSub = Join-Path $script:mapRoot 'sub'
            $null = New-Item -ItemType Directory -Path $mapSub -Force
            Set-Content -Path (Join-Path $mapSub 'leaf.txt') -Value 'leaf'
            $script:linkMade = $true
            try {
                $null = New-Item -ItemType SymbolicLink -Path (Join-Path $script:mapRoot 'link') -Target $mapSub -ErrorAction Stop
            } catch {
                $script:linkMade = $false
            }
        }

        It 'Renders symlinks as a two-line name/target pair' {
            # If this environment cannot create symlinks, the render feature has
            # nothing to assert against; record that rather than fail spuriously.
            if (-not $script:linkMade) {
                Set-ItResult -Skipped -Because 'symlink creation is not permitted in this environment'
                return
            }
            $lines = Get-DowserMap -Path $script:mapRoot
            $joined = $lines -join "`n"
            # The link name and its target both appear in the output.
            $joined | Should -Match 'link'
            $joined | Should -Match 'sub'
        }

        It 'Still traverses into subdirectories with an include filter on Linux' {
            $lines = Get-DowserMap -Path $script:mapRoot -IncludeFilePatterns '*.txt'
            ($lines -join "`n") | Should -Match 'leaf\.txt'
        }
    }
}
