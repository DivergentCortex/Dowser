#Requires -Version 5.1
<#
.SYNOPSIS
    Pester guard: every exported Dowser function has at least one alias.

.DESCRIPTION
    Imports the module and asserts that Get-Command -Module Dowser -CommandType Function
    returns no function that lacks a corresponding alias. If this test fails, a newly
    exported function was added without a matching entry in Aliases/Aliases.ps1.

    This test exists because three functions shipped without aliases before this guard
    was added (Get-DowserInfo, Compare-DowserReport, New-DowserHiddenFolder).

.NOTES
    Run from the module root:
        Invoke-Pester -Path ./Tests/Test-DowserAliasCoverage.Tests.ps1 -Output Detailed
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent $PSScriptRoot
    $script:ManifestPath = Join-Path $script:ModuleRoot 'Dowser.psd1'

    Remove-Module Dowser -Force -ErrorAction SilentlyContinue
    Import-Module $script:ManifestPath -Force -ErrorAction Stop

    $script:ExportedFunctions = Get-Command -Module Dowser -CommandType Function |
        Select-Object -ExpandProperty Name

    $allAliases = Get-Alias | Where-Object { $script:ExportedFunctions -contains $_.Definition }
    $script:CoveredFunctions = $allAliases | Select-Object -ExpandProperty Definition | Sort-Object -Unique

    $script:Uncovered = $script:ExportedFunctions | Where-Object { $script:CoveredFunctions -notcontains $_ } | Sort-Object
}

Describe 'Dowser alias coverage' {

    It 'every exported function has at least one alias' {
        $script:Uncovered | Should -BeNullOrEmpty -Because (
            'these exported functions have no alias: ' + ($script:Uncovered -join ', ')
        )
    }

    It 'dinfo resolves to Get-DowserInfo' {
        (Get-Alias dinfo).Definition | Should -Be 'Get-DowserInfo'
    }

    It 'dcompare resolves to Compare-DowserReport' {
        (Get-Alias dcompare).Definition | Should -Be 'Compare-DowserReport'
    }

    It 'dhide resolves to New-DowserHiddenFolder' {
        (Get-Alias dhide).Definition | Should -Be 'New-DowserHiddenFolder'
    }
}
