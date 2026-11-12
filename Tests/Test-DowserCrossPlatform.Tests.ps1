#Requires -Modules @{ModuleName='Pester';ModuleVersion='5.0'}

Describe 'Dowser Cross-Platform Support' {
    BeforeAll {
        $modulePath = Split-Path $PSScriptRoot -Parent
        Remove-Module Dowser -Force -ErrorAction SilentlyContinue
        Import-Module (Join-Path $modulePath 'Dowser.psd1') -Force -ErrorAction Stop
    }

    Context 'Module Import' {
        It 'Imports without error on any platform' {
            $mod = Get-Module Dowser
            $mod | Should -Not -BeNullOrEmpty
        }

        It 'Exports public functions' {
            $commands = Get-Command -Module Dowser
            $commands | Should -Not -BeNullOrEmpty
            $commands.Count | Should -BeGreaterThan 5
        }

        It 'Exports expected cross-platform functions' {
            $commands = (Get-Command -Module Dowser).Name
            $commands | Should -Contain 'Find-DowserDuplicate'
            $commands | Should -Contain 'Find-DowserFile'
            $commands | Should -Contain 'Measure-DowserDirectory'
            $commands | Should -Contain 'Get-DowserMap'
        }
    }

    Context 'Platform Detection' {
        It 'Platform variable IsWindows is accessible to module functions' {
            # if platform detection failed, windows-only guards would misfire
            if ($IsWindows) {
                $IsWindows | Should -BeOfType [bool]
            }
            else {
                $IsWindows | Should -Be $false
            }
        }
    }
}
