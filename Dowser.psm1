#Requires -Version 5.1
## =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
#
#      |                                
#   _` |   _ \ \ \  \ / (_-<   -_)   _| 
# \__,_| \___/  \_/\_/  ___/ \___| _|  
#
# =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
# -  Created on:    04/23/2023                                      -
# =  Author:        Curtis Leggett                                  =
# -  Copyright:     2026 Divergent Cortex                           -
# =  Organization:  Divergent Cortex                                =
# -  Version:       1.0.1                                           -
# =-=-                       =-=-=-=-=-=-=-=                     -=-=
# -     it is not water they seek,                                  -
# =                    the path to truth                            =
# -                            is hidden beneath the trees          -
# =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=



# Platform compat: PS 5.1 lacks $IsWindows/$IsLinux/$IsMacOS automatic variables.
# Set at module scope so dot-sourced functions can read them via scope resolution.
# On pwsh 7+ these are engine automatic variables and this block is skipped.
if (-not (Get-Variable -Name 'IsWindows' -ErrorAction SilentlyContinue)) {
    $IsWindows = $true
    $IsLinux   = $false
    $IsMacOS   = $false
}

$Public  = @(Get-ChildItem -Path (Join-Path (Join-Path $PSScriptRoot 'Public') '*.ps1') -ErrorAction SilentlyContinue)
$Private = @(Get-ChildItem -Path (Join-Path (Join-Path $PSScriptRoot 'Private') '*.ps1') -ErrorAction SilentlyContinue)

foreach ($file in @($Private + $Public)) {
    try { . $file.FullName }
    catch { Write-Error "Failed to import $($file.FullName): $_" }
}

$aliasPath = Join-Path (Join-Path $PSScriptRoot 'Aliases') 'Aliases.ps1'
if (Test-Path $aliasPath) {
    . $aliasPath
}

# Compare-DowserReport is a public function dot-sourced inside Get-DowserReport.ps1,
# so it is not a Public/ basename and must be named explicitly to export it.
Export-ModuleMember -Function ($Public.BaseName + 'Compare-DowserReport') -Alias *
