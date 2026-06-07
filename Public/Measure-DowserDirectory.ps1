#Requires -Version 5.1
<#
.SYNOPSIS
    Measures size, file count, and key file timestamps for each subdirectory under a root path.

.DESCRIPTION
    For each immediate subdirectory under -Path, Measure-DowserDirectory returns:
    total data size (human-readable via Format-DowserSize), file count, largest file
    name and size, newest file, and oldest file — emitted as PSCustomObjects to the pipeline.

    Replaces Get-DirectorySizeCounts. Verb changed from Get to Measure because this is
    a sizing/counting operation, not a retrieval. Inline ConvertFrom-Bytes removed;
    all byte formatting now routes through Format-DowserSize (Private\).

    Note: scans immediate subdirectories only. Files directly under -Path root are not
    reported as their own row — they count toward the parent's fcount via Get-ChildItem.

.PARAMETER Path
    Root directory to measure. Defaults to current directory.
    Accepts pipeline input by value and by FullName property.

.EXAMPLE
    Measure-DowserDirectory -Path D:\Projects

.EXAMPLE
    Measure-DowserDirectory

.EXAMPLE
    Get-Item C:\Data | Measure-DowserDirectory

.EXAMPLE
    'C:\Repos','C:\Work' | Measure-DowserDirectory -Verbose

.NOTES
    Alias: dsize
    Source: Get-DirectorySizeCounts.ps1 (General_Scripts — Curtis Leggett)
    Blocker resolved: removed dot-source of E:\_Local-H\...\Set-WriteAlias.ps1 (line 2 of source).
    Blocker resolved: replaced WHY/WHM/WHG/WHB/WH write-alias calls with Write-Verbose.
    Output improved: NewestFile/OldestFile split into separate Name/Date properties instead
    of a single concatenated string ("filename -=- date").
    Related: Get-DowserTree (tree traversal), Get-DowserReport (per-file metrics)
#>
function Measure-DowserDirectory {
    [CmdletBinding()]
    param (
        [Parameter(
            ParameterSetName = "Path",
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true
        )]
        [ValidateNotNullOrEmpty()]
        [Alias("FullName")]
        [string[]]$Path = "."
    )

    process {
        foreach ($rootPath in $Path) {
            Write-Verbose "Scanning subdirectories under: $rootPath"

            $directoryItems = Get-ChildItem $rootPath -ErrorAction SilentlyContinue |
                Where-Object { $_.PSIsContainer } |
                Sort-Object

            foreach ($dir in $directoryItems) {
                Write-Verbose "|-=-=-=-=-=-=-|-=-=-=-=-=-=-|"
                Write-Verbose "Searching $($dir.FullName)"

                # immediate child count (dirs + files) — mirrors original fcount behavior
                $fcount = (Get-ChildItem "$rootPath\$($dir.Name)" -ErrorAction SilentlyContinue | Measure-Object).Count

                $subFolderItems = Get-ChildItem $dir.FullName -Recurse -Force -ErrorAction SilentlyContinue |
                    Where-Object { -not $_.PSIsContainer }

                $totalSize   = ($subFolderItems | Measure-Object -Property Length -Sum).Sum
                $largestItem = $subFolderItems | Sort-Object Length | Select-Object -Last 1
                $largestSize = if ($largestItem) {
                    ($largestItem.Length | ForEach-Object { Format-DowserSize -DataValue $_ })
                } else { '0B' }
                $newestFile  = $subFolderItems | Sort-Object LastWriteTime | Select-Object -Last 1
                $oldestFile  = $subFolderItems | Sort-Object LastWriteTime | Select-Object -First 1

                [PSCustomObject][Ordered]@{
                    Directory       = $dir.FullName
                    DataSize        = Format-DowserSize -DataValue $totalSize
                    FileCount       = $fcount
                    LargestFile     = $largestSize
                    LargestFileName = $largestItem.Name
                    NewestFileName  = $newestFile.Name
                    NewestFileDate  = $newestFile.LastWriteTime
                    OldestFileName  = $oldestFile.Name
                    OldestFileDate  = $oldestFile.LastWriteTime
                }

                Write-Verbose "Complete $($dir.FullName)"
                Write-Verbose "|-=-=-=-=-=-=-|-=-=-=-=-=-=-|"
            }
        }
    }
}
