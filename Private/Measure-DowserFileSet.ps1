function Measure-DowserFileSet {
    <#
    .SYNOPSIS
        Single-pass size, count, extreme-file, and age-bucket statistics for a set of files.
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
        Walks -Files once and returns total bytes, file count, the largest, newest, and
        oldest file, and how many files were modified since -TodayStart, since -RecentCutoff,
        and before -RecentCutoff. Replaces three full Sort-Object passes per folder in
        Measure-DowserDirectory.
    .PARAMETER Files
        FileInfo objects to measure. Directories should already be filtered out.
    .PARAMETER TodayStart
        Midnight of the reference day. Files at or after it count as ModifiedToday.
    .PARAMETER RecentCutoff
        Files at or after it count as ModifiedWithinDays; files before it count as OlderThanDays.
    .OUTPUTS
        PSCustomObject with TotalBytes, FileCount, Largest, Newest, Oldest, ModifiedToday,
        ModifiedWithinDays, OlderThanDays.
    #>
    [CmdletBinding()]
    param (
        [AllowEmptyCollection()]
        [object[]]$Files = @(),

        [Parameter(Mandatory = $true)]
        [datetime]$TodayStart,

        [Parameter(Mandatory = $true)]
        [datetime]$RecentCutoff
    )

    $totalBytes = [int64]0
    $count = 0
    $today = 0
    $recent = 0
    $older = 0
    $largest = $null
    $newest = $null
    $oldest = $null

    foreach ($file in $Files) {
        if ($null -eq $file) {
            continue
        }
        $count++
        $totalBytes += [int64]$file.Length
        $written = $file.LastWriteTime
        if ($written -ge $TodayStart) {
            $today++
        }
        if ($written -ge $RecentCutoff) {
            $recent++
        }
        else {
            $older++
        }
        if ($null -eq $largest -or $file.Length -gt $largest.Length) {
            $largest = $file
        }
        if ($null -eq $newest -or $written -gt $newest.LastWriteTime) {
            $newest = $file
        }
        if ($null -eq $oldest -or $written -lt $oldest.LastWriteTime) {
            $oldest = $file
        }
    }

    return [PSCustomObject]@{
        TotalBytes         = $totalBytes
        FileCount          = $count
        Largest            = $largest
        Newest             = $newest
        Oldest             = $oldest
        ModifiedToday      = $today
        ModifiedWithinDays = $recent
        OlderThanDays      = $older
    }
}
