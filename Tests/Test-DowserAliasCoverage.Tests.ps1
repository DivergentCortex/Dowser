#Requires -Version 5.1
<#
.SYNOPSIS
    Pester guard: opt-in normalized aliases cover every exported command and never shadow builtins.

.DESCRIPTION
    Dowser does not register aliases on import. Enable-DowserAliases opts the current session into
    brandless verb-noun aliases (Find-File, Get-Info, Measure-DiskUsage, and the rest). This guard
    asserts that a clean import exposes no Dowser aliases, that Enable-DowserAliases then covers every
    exported function (the enabler itself excepted), that a few known names resolve to their branded
    targets, and that the function refuses to alias over a name already in use unless forced.

    This test exists because three functions shipped without aliases before the original guard was
    added (Get-DowserInfo, Compare-DowserReport, New-DowserHiddenFolder), and because the aliases
    later moved to an opt-in model that must not squat names on import.

.NOTES
    Run from the module root:
        Invoke-Pester -Path ./Tests/Test-DowserAliasCoverage.Tests.ps1 -Output Detailed
#>

BeforeAll {
    $script:ModuleRoot   = Split-Path -Parent $PSScriptRoot
    $script:ManifestPath = Join-Path $script:ModuleRoot 'Dowser.psd1'

    Remove-Module Dowser -Force -ErrorAction SilentlyContinue
    Import-Module $script:ManifestPath -Force -ErrorAction Stop

    $script:ExportedFunctions = Get-Command -Module Dowser -CommandType Function |
        Select-Object -ExpandProperty Name

    # the enabler is the one exported function that carries no alias of its own
    $script:Aliasable = $script:ExportedFunctions | Where-Object { $_ -ne 'Enable-DowserAliases' }
}

Describe 'Dowser alias coverage' {

    It 'a clean import registers no Dowser aliases' {
        $leaked = Get-Alias | Where-Object { $script:ExportedFunctions -contains $_.Definition }
        $leaked | Should -BeNullOrEmpty -Because 'aliases are opt-in and must not load on import'
    }

    Context 'after Enable-DowserAliases' {

        BeforeAll {
            Enable-DowserAliases
            $covered = Get-Alias |
                Where-Object { $script:ExportedFunctions -contains $_.Definition } |
                Select-Object -ExpandProperty Definition | Sort-Object -Unique
            $script:Uncovered = $script:Aliasable | Where-Object { $covered -notcontains $_ } | Sort-Object
        }

        It 'every exported function except the enabler has an alias' {
            $script:Uncovered | Should -BeNullOrEmpty -Because (
                'these exported functions have no alias: ' + ($script:Uncovered -join ', ')
            )
        }

        It 'Get-Info resolves to Get-DowserInfo' {
            (Get-Alias Get-Info).Definition | Should -Be 'Get-DowserInfo'
        }

        It 'Compare-Report resolves to Compare-DowserReport' {
            (Get-Alias Compare-Report).Definition | Should -Be 'Compare-DowserReport'
        }

        It 'New-HiddenFolder resolves to New-DowserHiddenFolder' {
            (Get-Alias New-HiddenFolder).Definition | Should -Be 'New-DowserHiddenFolder'
        }
    }

    Context 'collision safety' {

        It 'does not alias over a name already taken by a function unless forced' {
            function global:Find-File { 'decoy' }
            try {
                Remove-Item Alias:\Find-File -Force -ErrorAction SilentlyContinue
                Enable-DowserAliases
                Get-Alias Find-File -ErrorAction SilentlyContinue |
                    Should -BeNullOrEmpty -Because 'an existing function must not be shadowed without -Force'
            }
            finally {
                Remove-Item Function:\Find-File -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
