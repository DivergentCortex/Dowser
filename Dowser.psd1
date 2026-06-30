@{
    RootModule        = 'Dowser.psm1'
    ModuleVersion     = '0.2.0'
    GUID              = '64c72862-caae-4d55-9a1f-0d5bf94d3695'
    Author            = 'Curt Leggett'
    CompanyName       = 'Divergent Cortex'
    Copyright         = '(c) 2026 Curt Leggett. Licensed under the MIT License.'
    Description       = 'Dowser - filesystem recon and inspection kit. Find what you cannot see. Cross-platform (Windows/Linux/macOS).'
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    FunctionsToExport = @(
        'Compare-DowserReport'
        'ConvertTo-DowserBase64'
        'ConvertTo-DowserExe'
        'ConvertTo-DowserIco'
        'Expand-DowserExe'
        'Find-DowserDependency'
        'Find-DowserDuplicate'
        'Find-DowserFile'
        'Find-DowserModified'
        'Find-DowserOrphan'
        'Find-DowserRecentLog'
        'Find-DowserScript'
        'Find-DowserString'
        'Get-DowserInfo'
        'Get-DowserMap'
        'Get-DowserOwnership'
        'Get-DowserProperty'
        'Get-DowserReport'
        'Get-DowserTemplate'
        'Get-DowserTopology'
        'Invoke-DowserFastSearch'
        'Invoke-DowserNumericSort'
        'Measure-DowserDirectory'
        'Measure-DowserDiskUsage'
        'New-DowserHiddenFolder'
        'Test-DowserExtractable'
        'Test-DowserIntegrity'
    )
    AliasesToExport   = @('*')
    CmdletsToExport   = @()
    VariablesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('filesystem','recon','search','utility','dowser','cross-platform','linux')
            ProjectUri = 'https://github.com/DivergentCortex/Dowser'
        }
    }
}
