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
    FunctionsToExport = @('*')
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
