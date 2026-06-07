function Find-DowserModified {
    <#
    .SYNOPSIS
        Find files modified on a specific calendar date.

    .DESCRIPTION
        Returns files whose LastWriteTime falls on the specified date (day-level match).
        The default date is today. Use -Date to target a specific day.

        Replaces Find-FilesModifiedOn.ps1 — that had a hardcoded D:\ path and a
        hardcoded default date of 2025-01-14. Both are gone.

    .PARAMETER Path
        Root directory to search. Accepts pipeline input. Defaults to current directory.

    .PARAMETER Date
        The date to match against LastWriteTime (day-level comparison). Defaults to today.

    .PARAMETER Recurse
        Recurse subdirectories. Default $true. Pass -Recurse:$false to disable.

    .EXAMPLE
        Find-DowserModified -Path D:\ -Date '2026-04-01'

    .EXAMPLE
        Find-DowserModified -Path D:\Repos

    .EXAMPLE
        'D:\Scripts','C:\Tools' | Find-DowserModified -Date (Get-Date).AddDays(-7)

    .NOTES
        Alias: dmod
        Source: Find-FilesModifiedOn.ps1 (General_Scripts — hardcoded D:\ + date default)
        Fixed: added -Path parameter; changed default date from hardcoded to (Get-Date).Date.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('FullName')]
        [string[]]$Path = $PWD,

        [Parameter(Position = 1)]
        [DateTime]$Date = (Get-Date).Date,

        [bool]$Recurse = $true
    )

    process {
        foreach ($rootPath in $Path) {
            if (-not (Test-Path $rootPath)) {
                Write-Warning "Path not found: $rootPath"
                continue
            }

            Write-Verbose "Searching '$rootPath' for files modified on $($Date.ToString('yyyy-MM-dd'))..."

            try {
                $files = Get-ChildItem -Path $rootPath -Recurse:$Recurse -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.LastWriteTime.Date -eq $Date.Date }

                Write-Verbose "Found $(@($files).Count) files modified on $($Date.ToString('yyyy-MM-dd'))"

                foreach ($file in $files) {
                    [PSCustomObject]@{
                        FullName      = $file.FullName
                        LastWriteTime = $file.LastWriteTime
                        Size          = $file.Length
                    }
                }
            }
            catch {
                Write-Warning "Error scanning '$rootPath': $_"
            }
        }
    }
}
