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

# 5.1 doesn't know what linux is, bless it, so we hand it $IsWindows/$IsLinux/$IsMacOS
# on pwsh 6+ those are read-only automatics, hence the version gate and Set-Variable
if ($PSVersionTable.PSVersion.Major -lt 6) {
    Set-Variable -Name 'IsWindows' -Value $true  -Scope Script
    Set-Variable -Name 'IsLinux'   -Value $false -Scope Script
    Set-Variable -Name 'IsMacOS'   -Value $false -Scope Script
}

# Write-Log throws on an empty $LogFilePath, so give it one before anything logs
$script:DowserRoot = $PSScriptRoot

$ScriptName = $MyInvocation.MyCommand.Name -replace '\.ps1$'
$logName = "$($ScriptName)_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$LogDir = Join-Path $PSScriptRoot "logs"
$LogFilePath = Join-Path $LogDir $logName

if ([string]::IsNullOrWhiteSpace($LogFilePath)) {
    $LogDir = Join-Path $PSScriptRoot 'logs'
    if (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null 
    }
    $LogFilePath = Join-Path $LogDir ("Dowser_{0}.log" -f (Get-Date -Format 'yyyyMMdd'))
}

$Public = @(Get-ChildItem -Path (Join-Path (Join-Path $PSScriptRoot 'Public') '*.ps1') -ErrorAction SilentlyContinue)
$Private = @(Get-ChildItem -Path (Join-Path (Join-Path $PSScriptRoot 'Private') '*.ps1') -ErrorAction SilentlyContinue)

# Write-Log goes first so anything that logs at dot-source time can find it
$Private = @($Private | Sort-Object { $_.Name -ne 'Write-Log.ps1' })

foreach ($file in @($Private + $Public)) {
    try {
        . $file.FullName 
    }
    catch {
        Write-Error "Failed to import $($file.FullName): $_" 
    }
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
    if ($head -match '^##\s*\[(?<ver>[^\]]+)\]') {
        $script:DowserVersion = $Matches['ver'] 
    }
}

Initialize-Log -ScriptName 'Dowser' -Version $script:DowserVersion

# one shared state bag for every pooled worker, exported so you can poke at it after a run
$script:SyncHash = [hashtable]::Synchronized(@{
        LogQueue = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
    })

# Compare-DowserReport lives inside Get-DowserReport.ps1, so it isn't a Public/ basename and gets exported by name
Export-ModuleMember -Function ($Public.BaseName + 'Compare-DowserReport' + 'Enable-DowserAliases') -Alias * -Variable SyncHash
