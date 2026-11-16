#Requires -Version 5.1
<#
.SYNOPSIS
    Scheduled entry point for Invoke-DowserCacheRetention: one run, one log file, one exit code.

.DESCRIPTION
    Imports Witness and the Dowser module, points the log at
    logs/dowser.cache.retention_YYYYMMDD.log, runs Invoke-DowserCacheRetention without
    prompting, and exits with the command's ExitCode (0, the mapped code of the worst failure,
    or 112 when a free-space threshold is breached). Without -Remove it only reports.
    The systemd units in deploy/systemd run it with -Remove.

.PARAMETER Remove
    Delete the stale cache versions. Without it the run is a preview.

.PARAMETER ConfigPath
    Rule file to apply. Defaults to Config/CacheRetentionRules.psd1 in this folder.

.EXAMPLE
    pwsh -NoProfile -File ./Invoke-DowserScheduledRetention.ps1

    Previews what a removal run would do and exits 0 when nothing is wrong.

.EXAMPLE
    pwsh -NoProfile -File ./Invoke-DowserScheduledRetention.ps1 -Remove

    Removes the stale cache versions and exits with the run's code.
#>
[CmdletBinding()]
param(
    [switch]$Remove,

    [string]$ConfigPath
)

Import-Module (Join-Path $PSScriptRoot '_modules/ps/DivergentCortex.Witness')
. (Join-Path (Join-Path $PSScriptRoot 'Private') 'Get-WindowsErrorCode.ps1')

$script:ExitCode = 0
$retentionLog = Join-Path (Join-Path $PSScriptRoot 'logs') "dowser.cache.retention_$(Get-Date -Format 'yyyyMMdd').log"
Initialize-Log -LogFilePath $retentionLog -ScriptName 'Invoke-DowserScheduledRetention'

$moduleLoaded = $false
try {
    Write-Log "Attempting ModuleImport on '$(Join-Path $PSScriptRoot 'Dowser.psd1')'" -Severity Info
    Import-Module (Join-Path $PSScriptRoot 'Dowser.psd1') -Force -ErrorAction Stop
    $moduleLoaded = $true
    Write-Log 'ModuleImport succeeded for Dowser' -Severity Success
}
catch {
    Write-Log "ModuleImport failed for Dowser: $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Error
    $code = Get-WindowsErrorCode -Exception $_
    if ($code -gt $script:ExitCode) { $script:ExitCode = $code }
}

if ($moduleLoaded) {
    # importing the module points Witness at the module log, so the run log is set again
    Initialize-Log -LogFilePath $retentionLog -ScriptName 'Invoke-DowserScheduledRetention' -Version (Get-Module Dowser).Version.ToString()
    $retentionParameters = @{ Confirm = $false }
    if ($Remove) { $retentionParameters.Remove = $true }
    if ($ConfigPath) { $retentionParameters.ConfigPath = $ConfigPath }
    $result = Invoke-DowserCacheRetention @retentionParameters
    if ([int]$result.ExitCode -gt $script:ExitCode) { $script:ExitCode = [int]$result.ExitCode }
}

Write-LogFinal -Message "Invoke-DowserScheduledRetention finished. Exit code: $script:ExitCode" -Severity Info
exit $script:ExitCode
