function Find-DowserModified {
    <#
    .SYNOPSIS
        Find files modified on a specific calendar date.

    .NOTES
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
        -  Author:        Curtis Leggett                                  -
        =  Copyright:     2026 Divergent Cortex                           =
        -  Organization:  Divergent Cortex                                -
        =  Version:       See docs/CHANGELOG.md                           =
        =-=-                       =-=-=-=-=-=-=-=                     -=-=
        -  it is not water they seek, but the truth beneath the trees     -
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
        Alias:  dmod
        Source: Find-FilesModifiedOn.ps1 (hardcoded D:\ path and date default)
        Fixed:  added -Path parameter; default date changed to (Get-Date).Date.

    .DESCRIPTION
        Returns files whose LastWriteTime falls on the specified date (day-level match).
        The default date is today. Use -Date to target a specific day.

        Replaces Find-FilesModifiedOn.ps1, which had a hardcoded D:\ path and a
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

    .OUTPUTS
        PSCustomObject
        Properties: FullName, LastWriteTime, Size.
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
        Write-Log "Starting Find-DowserModified"
        foreach ($rootPath in $Path) {
            if (-not (Test-Path $rootPath)) {
                Write-Log "Find-DowserModified path not found: '$rootPath'" -Severity Warning
                continue
            }

            Write-Log "Searching '$rootPath' for files modified on $($Date.ToString('yyyy-MM-dd'))..."

            try {
                $files = Get-ChildItem -Path $rootPath -Recurse:$Recurse -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.LastWriteTime.Date -eq $Date.Date }

                Write-Log "Found $(@($files).Count) files modified on $($Date.ToString('yyyy-MM-dd'))"

                foreach ($file in $files) {
                    [PSCustomObject]@{
                        FullName      = $file.FullName
                        LastWriteTime = $file.LastWriteTime
                        Size          = $file.Length
                    }
                }
            }
            catch {
                Write-Log "Find-DowserModified failed scanning '$rootPath': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Error
            }
        }
        Write-Log "Ending Find-DowserModified"
    }
}
