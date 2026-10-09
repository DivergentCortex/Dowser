#Requires -Version 5.1
function Measure-DowserDirectory {
    <#
    .SYNOPSIS
        Measures size, file count, and key file timestamps for each subdirectory under a root path.

    .NOTES
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
        -  Author:        Curtis Leggett                                  -
        =  Copyright:     2026 Divergent Cortex                           =
        -  Organization:  Divergent Cortex                                -
        =  Version:       See docs/CHANGELOG.md                           =
        =-=-                       =-=-=-=-=-=-=-=                     -=-=
        -  it is not water they seek, but the truth beneath the trees     -
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

        Alias: Measure-Directory (opt-in via Enable-DowserAliases)
        Source: Get-DirectorySizeCounts.ps1 (standalone scripts)
        Ported: removed legacy write-alias dot-source and replaced custom write-alias calls with Write-Log.
        Output improved: NewestFile/OldestFile split into separate Name/Date properties instead
        of a single concatenated string.
        Related: Get-DowserTree (tree traversal), Get-DowserReport (per-file metrics)

    .DESCRIPTION
        For each immediate subdirectory under -Path, Measure-DowserDirectory returns a
        freshness and size row: recursive file count, how many files were modified today,
        within the last -RecentDays days, and before that, how long ago the newest file was
        written, the newest and oldest file, total data size (human-readable via
        Format-DowserSize, raw bytes in SizeBytes), and the largest file.

        The age columns are not three exclusive tiers: ModifiedWithinDays + OlderThanDays =
        FileCount, and ModifiedToday is the subset of ModifiedWithinDays written since local
        midnight. Do not sum all three.

        Loose files directly under -Path get their own row with Folder '.' when any exist.
        Hidden and dot-prefixed folders (.git, .claude) are measured like any other folder.
        Symlinked directories inside a folder are not followed, so a link loop cannot hang the
        scan. Files are measured in a single pass per folder. Unreadable subfolders are
        skipped and logged instead of dropping the whole row. A -Path that is a file, not a
        folder, is skipped with a warning.

        The -RecentDays cutoff is -Now minus N days in local clock time, so a window that spans
        a daylight-saving change is up to one hour off from N x 24 elapsed hours.

        The default table view shows Folder, FileCount, ModifiedToday, ModifiedWithinDays,
        OlderThanDays, NewestFileAge, NewestFileName, and DataSize; every other property is on
        the object (Format-List * or Select-Object) for scripting.

        Replaces Get-DirectorySizeCounts. Verb changed from Get to Measure because this is
        a sizing/counting operation, not a retrieval. Inline ConvertFrom-Bytes removed;
        all byte formatting now routes through Format-DowserSize (Private\).

    .PARAMETER Path
        Root directory to measure. Defaults to current directory.
        Accepts pipeline input by value and by FullName property.

    .PARAMETER RecentDays
        Window for the ModifiedWithinDays and OlderThanDays counts, in days (1 to 36500).
        Default: 7. ModifiedToday always means since local midnight.

    .PARAMETER Now
        Reference instant for every bucket and age in the run. Defaults to the current time;
        pass a fixed value to make results reproducible (tests, comparisons across runs).

    .EXAMPLE
        Measure-DowserDirectory -Path ~/.claude/plugins/cache/divergentcortex

        One row per plugin folder: how many files changed today and this week, how many are
        older than a week, and how long ago the newest file was written.

    .EXAMPLE
        Measure-DowserDirectory -Path D:\Projects -RecentDays 30 | Where-Object ModifiedWithinDays -eq 0

        Folders with no file modified in the last 30 days.

    .EXAMPLE
        Measure-DowserDirectory -Path D:\Projects

    .EXAMPLE
        Measure-DowserDirectory

    .EXAMPLE
        Get-Item C:\Data | Measure-DowserDirectory

    .EXAMPLE
        'C:\Repos','C:\Work' | Measure-DowserDirectory -Verbose

    .OUTPUTS
        PSCustomObject per subdirectory (plus an optional '.' root row): Folder, Directory,
        FileCount (recursive files), ItemCount (immediate children, folders included; this was
        the value previously reported as FileCount), ModifiedToday, ModifiedWithinDays,
        OlderThanDays, RecentDays, NewestFileAge, NewestFileName, NewestFileDate,
        OldestFileName, OldestFileDate, DataSize, SizeBytes, LargestFile, LargestFileName.
    #>
    [CmdletBinding()]
    param (
        [Parameter(
            ParameterSetName = "Path",
            Position = 0,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true
        )]
        [ValidateNotNullOrEmpty()]
        [Alias("FullName")]
        [string[]]$Path = ".",

        [ValidateRange(1, 36500)]
        [int]$RecentDays = 7,

        [datetime]$Now = (Get-Date)
    )

    begin {
        Write-Log "Starting Measure-DowserDirectory"
        # One reference instant for every row, so buckets and ages are consistent across folders.
        # -Now makes it injectable; tests pass their fixture instant instead of racing midnight.
        $runNow = $Now
        $todayStart = $runNow.Date
        $recentCutoff = $runNow.AddDays(-$RecentDays)
        $defaultView = [System.Management.Automation.PSPropertySet]::new('DefaultDisplayPropertySet', [string[]]@(
                'Folder', 'FileCount', 'ModifiedToday', 'ModifiedWithinDays', 'OlderThanDays', 'NewestFileAge', 'NewestFileName', 'DataSize'))
        $standardMembers = [System.Management.Automation.PSMemberInfo[]]@($defaultView)

        function New-DowserDirectoryRow {
            param([string]$DirectoryPath, [string]$FolderName, [int]$ItemCount, [object[]]$Files)
            $stats = Measure-DowserFileSet -Files $Files -TodayStart $todayStart -RecentCutoff $recentCutoff
            if ($stats.Newest -and $stats.Newest.LastWriteTime -gt $runNow) {
                # Clock skew or backdated copies: leave a trace beyond the 'in future' table cell.
                Write-Log "Measure-DowserDirectory: newest file under '$DirectoryPath' is dated in the future ($($stats.Newest.Name), $($stats.Newest.LastWriteTime))" -Severity Verbose
            }
            $row = [PSCustomObject][Ordered]@{
                Folder             = $FolderName
                Directory          = $DirectoryPath
                FileCount          = $stats.FileCount
                ItemCount          = $ItemCount
                ModifiedToday      = $stats.ModifiedToday
                ModifiedWithinDays = $stats.ModifiedWithinDays
                OlderThanDays      = $stats.OlderThanDays
                RecentDays         = $RecentDays
                NewestFileAge      = Format-DowserAge -Timestamp $stats.Newest.LastWriteTime -Now $runNow
                NewestFileName     = $stats.Newest.Name
                NewestFileDate     = $stats.Newest.LastWriteTime
                OldestFileName     = $stats.Oldest.Name
                OldestFileDate     = $stats.Oldest.LastWriteTime
                DataSize           = Format-DowserSize -DataValue $stats.TotalBytes
                SizeBytes          = $stats.TotalBytes
                LargestFile        = if ($stats.Largest) { Format-DowserSize -DataValue $stats.Largest.Length } else { '0B' }
                LargestFileName    = $stats.Largest.Name
            }
            $row | Add-Member -MemberType MemberSet -Name PSStandardMembers -Value $standardMembers -Force
            return $row
        }
    }

    process {
        foreach ($rootPath in $Path) {
            Write-Log "Measure-DowserDirectory scanning subdirectories under '$rootPath'" -Severity Verbose

            # A file passed as -Path used to produce a '.' row describing that single file.
            if (-not (Test-Path -LiteralPath $rootPath -PathType Container)) {
                Write-Log "Measure-DowserDirectory: '$rootPath' is not a folder; pass a directory to measure its subfolders" -Severity Warning
                continue
            }

            $directoryItems = $null
            try {
                # -Force so hidden and dot-prefixed folders (.git, .claude) get a row like any
                # other; without it they were silently absent from the whole report.
                $directoryItems = @(Get-ChildItem -LiteralPath $rootPath -Directory -Force -ErrorAction Stop |
                    Sort-Object Name)
            }
            catch {
                Write-Log "Measure-DowserDirectory failed enumerating '$rootPath': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Error
                continue
            }

            # Loose files directly under the root were never reported before; they get a '.'
            # row, emitted only when there are any.
            $rootFiles = @()
            try {
                $rootFiles = @(Get-ChildItem -LiteralPath $rootPath -File -Force -ErrorAction Stop)
            }
            catch {
                Write-Log "Measure-DowserDirectory failed listing root files in '$rootPath': $($_.Exception.Message)" -Severity Warning
            }
            if ($rootFiles.Count -gt 0) {
                $resolvedRoot = (Resolve-Path -LiteralPath $rootPath).ProviderPath
                New-DowserDirectoryRow -DirectoryPath $resolvedRoot -FolderName '.' -ItemCount $rootFiles.Count -Files $rootFiles
            }

            foreach ($dir in $directoryItems) {
                Write-Log "Searching $($dir.FullName)" -Severity Verbose

                $subFolderItems = $null
                try {
                    # ItemCount keeps the old 'FileCount' meaning (immediate children, folders
                    # included), now with -Force so it counts the same hidden items FileCount does.
                    $itemCount = @(Get-ChildItem -LiteralPath $dir.FullName -Force -ErrorAction Stop).Count
                    if ($PSVersionTable.PSVersion.Major -ge 6) {
                        # PowerShell 6+: Get-ChildItem -Recurse does not follow symlinked
                        # directories (verified by execution in both task 1831 reviews), and it is
                        # about 15x faster than the script-level walker on large trees (25.7s vs
                        # 388.7s on 955k files).
                        $scanErrors = $null
                        $subFolderItems = @(Get-ChildItem -LiteralPath $dir.FullName -Recurse -File -Force -ErrorAction SilentlyContinue -ErrorVariable scanErrors)
                        $skipped = @($scanErrors).Count
                    }
                    else {
                        # Windows PowerShell 5.1: -Recurse follows directory symlinks and junctions,
                        # so a link loop could hang the scan. Use the pruning walker, which never
                        # follows symlinked directories.
                        $scan = Get-DowserRelativeFileMap -Root $dir.FullName
                        $subFolderItems = @($scan.Map.Values)
                        $skipped = $scan.Errors
                    }
                    if ($skipped -gt 0) {
                        Write-Log "Measure-DowserDirectory skipped $skipped unreadable path(s) under '$($dir.FullName)'" -Severity Warning
                    }
                }
                catch {
                    Write-Log "Measure-DowserDirectory failed scanning '$($dir.FullName)': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Error
                    continue
                }

                New-DowserDirectoryRow -DirectoryPath $dir.FullName -FolderName $dir.Name -ItemCount $itemCount -Files $subFolderItems

                Write-Log "Complete $($dir.FullName)" -Severity Verbose
            }
        }
    }

    end {
        Write-Log "Ending Measure-DowserDirectory"
    }
}
