#Requires -Version 5.1
# Dowser root module - dot-sources Public/Private/Aliases

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

Export-ModuleMember -Function $Public.BaseName -Alias *
