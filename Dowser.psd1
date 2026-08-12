#Requires -Version 5.1
<#
.SYNOPSIS
    Dowser module loader: filesystem reconnaissance, search, sizing, and reporting toolkit.

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
        Loads the Dowser module. Sets PS 5.1 platform-compat variables, establishes a
        default log path under the module root, dot-sources every Public and Private
        function file plus the alias set, reads the module version from the newest
        CHANGELOG slot, initializes the Witness logger with a session-start banner, and
        exports the public command surface.
#>

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
