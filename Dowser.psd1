#Requires -Version 5.1
<#
.SYNOPSIS
    Module manifest for Dowser, a filesystem reconnaissance, search, sizing, and reporting toolkit.

.NOTES
    =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
   
             |                            
         _ ` |   _ \ \ \  \ / (_-<   -_)   _| 
        \__,_| \___/  \_/\_/  ___/ \___| _|  
     
    =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
    =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
    -  Author:        Curtis Leggett                                  -
    =  Copyright:     2026 Divergent Cortex                           =
    -  Organization:  Divergent Cortex                                -
    =  Version:       See docs/CHANGELOG.md                           =
    =-=-                       =-=-=-=-=-=-=-=                     -=-=
    -  it is not water they seek, but the truth beneath the trees     -
    =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

    .DESCRIPTION
        Declares the exported command surface and module metadata. Loading logic
        lives in Dowser.psm1.
#>

@{
    RootModule        = 'Dowser.psm1'
    ModuleVersion     = '2026.11.15.301'
    GUID              = '64c72862-caae-4d55-9a1f-0d5bf94d3695'
    Author            = 'Curtis Leggett'
    CompanyName       = 'Divergent Cortex'
    Copyright         = '(c) 2026 Curt Leggett. Licensed under the MIT License.'
    Description       = 'Dowser - filesystem recon and inspection kit. Find what you cannot see. Cross-platform (Windows/Linux/macOS).'
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    FunctionsToExport = @(
        'Compare-DowserDirectory'
        'Compare-DowserReport'
        'ConvertTo-DowserBase64'
        'ConvertTo-DowserExe'
        'ConvertTo-DowserIco'
        'Enable-DowserAliases'
        'Export-DowserJsonAssessment'
        'Export-DowserJsonCsv'
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
        'Get-DowserJsonKey'
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
        'Remove-DowserTransferSource'
        'Repair-DowserJson'
        'Start-DowserTransfer'
        'Test-DowserExtractable'
        'Test-DowserIntegrity'
        'Test-DowserJson'
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
