function Get-DowserInfo {
    <#
    .SYNOPSIS
        Report Dowser module identity: module version (manifest) and latest changelog entry.

    .DESCRIPTION
        Module version is SemVer-style and lives in Dowser.psd1 (ModuleVersion).
        Per-script / per-feature history lives in docs/CHANGELOG.md and uses
        YYYY.MM.DD.XXX entries. Both are surfaced here. They are independent.
    #>
    [CmdletBinding()]
    param()

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
            Write-Log -Severity Warning -Message "Manifest read failed: $($_.Exception.Message)"
        }
    }

    $publicCount = if (Test-Path -LiteralPath $publicPath) {
        (Get-ChildItem -LiteralPath $publicPath -Filter '*.ps1' -File).Count
    }
    else {
        0 
    }

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
