function Get-DowserInfo {
    <#
    .SYNOPSIS
        Report Dowser module identity: module version (manifest) and latest changelog entry.
    .NOTES
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
        -  Author:        Curtis Leggett                                  -
        =  Copyright:     2026 Divergent Cortex                           =
        -  Organization:  Divergent Cortex                                -
        =  Version:       See docs/CHANGELOG.md                           =
        =-=-                       =-=-=-=-=-=-=-=                     -=-=
        -  it is not water they seek, but the truth beneath the trees     -
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
    .DESCRIPTION
        Module version is SemVer-style and lives in Dowser.psd1 (ModuleVersion).
        Per-script / per-feature history lives in docs/CHANGELOG.md and uses
        YYYY.MM.DD.XXX entries. Both are surfaced here. They are independent.
    .EXAMPLE
        Get-DowserInfo

        Returns a single object carrying the manifest ModuleVersion alongside the
        latest changelog version, date, and title, plus module root and public
        function count.
    .OUTPUTS
        PSCustomObject
        Properties: Module, ModuleVersion, LatestChangelogVersion,
        LatestChangelogDate, LatestChangelogTitle, ModuleRoot, PublicFunctions,
        ChangelogPath.
    #>
    [CmdletBinding()]
    param()

    Write-Log "Starting Get-DowserInfo"

    $moduleRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
    $manifestPath = Join-Path $moduleRoot 'Dowser.psd1'
    $changelogPath = Join-Path (Join-Path $moduleRoot 'docs') 'CHANGELOG.md'
    $publicPath = Join-Path $moduleRoot 'Public'

    $changelogVersion = $null
    $changelogDate = $null
    $changelogTitle = $null

    if (Test-Path -LiteralPath $changelogPath) {
        $headerLine = Get-Content -LiteralPath $changelogPath |
            Where-Object { $_ -match '^##\s*\[[^\]]+\]' } |
            Select-Object -First 1

        if ($headerLine -match '^##\s*\[(?<ver>[^\]]+)\]\s*-\s*(?:(?<date>\d{4}-\d{2}-\d{2})\s*-?\s*)?(?<title>.*)$') {
            $changelogVersion = $Matches['ver']
            $changelogDate = $Matches['date']
            $changelogTitle = $Matches['title'].Trim()
        }
    }

    $manifestVersion = $null
    if (Test-Path -LiteralPath $manifestPath) {
        try {
            $manifest = Import-PowerShellDataFile -LiteralPath $manifestPath
            $manifestVersion = $manifest.ModuleVersion
        }
        catch {
            Write-Log "Get-DowserInfo failed reading manifest '$manifestPath': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Warning
        }
    }

    $publicCount = if (Test-Path -LiteralPath $publicPath) {
        (Get-ChildItem -LiteralPath $publicPath -Filter '*.ps1' -File).Count
    }
    else {
        0 
    }

    Write-Log "Ending Get-DowserInfo"
    [pscustomobject]@{
        Module                 = 'Dowser'
        ModuleVersion          = $manifestVersion
        LatestChangelogVersion = $changelogVersion
        LatestChangelogDate    = $changelogDate
        LatestChangelogTitle   = $changelogTitle
        ModuleRoot             = $moduleRoot
        PublicFunctions        = $publicCount
        ChangelogPath          = $changelogPath
    }
}
