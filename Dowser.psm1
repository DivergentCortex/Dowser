#Requires -Version 5.1
# =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
#
#      |                                
#   _` |   _ \ \ \  \ / (_-<   -_)   _| 
# \__,_| \___/  \_/\_/  ___/ \___| _|  
#
# =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
#   Author:  Curtis Leggett / Divergent Cortex
#
#   Every folder is a grave pretending to be a drawer.
#
# =-=-                       =-=-=-=-=-=-=-=                     -=-=
#   it is not water they seek, it is truth, the path hidden in the trees
#   the rods tremble as they near the truth buried beneath the tree
# =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=



# Platform compat: PS 5.1 lacks $IsWindows/$IsLinux/$IsMacOS automatic variables.
# Set at module scope so dot-sourced functions can read them via scope resolution.
# On pwsh 7+ these are engine automatic variables and this block is skipped.
if (-not (Get-Variable -Name 'IsWindows' -ErrorAction SilentlyContinue)) {
    $IsWindows = $true
    $IsLinux   = $false
    $IsMacOS   = $false
}

# Write-Log FATAL-throws when $LogFilePath is empty. Set a module-root default
# here so every dot-sourced function logs with no per-function setup. A caller
# can still override by setting $LogFilePath before import or passing -Logfile.
$script:DowserRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($LogFilePath)) {
    $LogDir = Join-Path $PSScriptRoot 'logs'
    if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
    $LogFilePath = Join-Path $LogDir ("Dowser_{0}.log" -f (Get-Date -Format 'yyyyMMdd'))
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

# version is the latest changelog slot, read at load so nothing hardcodes it
$script:DowserVersion = 'unknown'
$changelogPath = Join-Path (Join-Path $PSScriptRoot 'docs') 'CHANGELOG.md'
if (Test-Path -LiteralPath $changelogPath) {
    $head = Get-Content -LiteralPath $changelogPath |
        Where-Object { $_ -match '^##\s*\[[^\]]+\]' } | Select-Object -First 1
    if ($head -match '^##\s*\[(?<ver>[^\]]+)\]') { $script:DowserVersion = $Matches['ver'] }
}

# open every session with the identity and context header
Initialize-Log -ScriptName 'Dowser' -Version $script:DowserVersion

# Compare-DowserReport is a public function dot-sourced inside Get-DowserReport.ps1,
# so it is not a Public/ basename and must be named explicitly to export it.
Export-ModuleMember -Function ($Public.BaseName + 'Compare-DowserReport') -Alias *
