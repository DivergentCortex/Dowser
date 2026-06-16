@{
    RootModule        = 'Dowser.psm1'
    ModuleVersion     = '0.2.0'
    GUID              = 'b7e1c9a0-0000-0000-0000-000000000001'
    Author            = 'Curt Leggett'
    CompanyName       = 'Divergent Cortex'
    Copyright         = '(c) Curt Leggett. All rights reserved.'
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
            ProjectUri = ''
        }
    }
}
