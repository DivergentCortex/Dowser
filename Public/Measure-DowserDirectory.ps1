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

        Alias: dsize
        Source: Get-DirectorySizeCounts.ps1 (standalone scripts)
        Ported: removed legacy write-alias dot-source and replaced custom write-alias calls with Write-Verbose.
        Output improved: NewestFile/OldestFile split into separate Name/Date properties instead
        of a single concatenated string.
        Related: Get-DowserTree (tree traversal), Get-DowserReport (per-file metrics)

    .DESCRIPTION
        For each immediate subdirectory under -Path, Measure-DowserDirectory returns:
        total data size (human-readable via Format-DowserSize), file count, largest file
        name and size, newest file, and oldest file, emitted as PSCustomObjects to the pipeline.

        Replaces Get-DirectorySizeCounts. Verb changed from Get to Measure because this is
        a sizing/counting operation, not a retrieval. Inline ConvertFrom-Bytes removed;
        all byte formatting now routes through Format-DowserSize (Private\).

        Note: scans immediate subdirectories only. Files directly under the -Path root are not
        reported as their own row; they count toward the parent's fcount via Get-ChildItem.

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

    .OUTPUTS
        PSCustomObject per subdirectory with size, file count, and largest/newest/oldest file details.
    #>
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

    begin {
        Write-Log "Starting Measure-DowserDirectory"
    }

    process {
        foreach ($rootPath in $Path) {
            Write-Log "Measure-DowserDirectory scanning subdirectories under '$rootPath'"

            $directoryItems = $null
            try {
                $directoryItems = @(Get-ChildItem $rootPath -ErrorAction Stop |
                    Where-Object { $_.PSIsContainer } |
                    Sort-Object)
            }
            catch {
                Write-Log "Measure-DowserDirectory failed enumerating '$rootPath': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Error
                continue
            }

            foreach ($dir in $directoryItems) {
                Write-Verbose "Searching $($dir.FullName)"

                $subFolderItems = $null
                try {
                    # immediate children only, matches original fcount
                    $fcount = (Get-ChildItem (Join-Path $rootPath $dir.Name) -ErrorAction Stop | Measure-Object).Count
                    $subFolderItems = @(Get-ChildItem $dir.FullName -Recurse -Force -ErrorAction Stop |
                        Where-Object { -not $_.PSIsContainer })
                }
                catch {
                    Write-Log "Measure-DowserDirectory failed scanning '$($dir.FullName)': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Error
                    continue
                }

                $totalSize = ($subFolderItems | Measure-Object -Property Length -Sum).Sum
                $largestItem = $subFolderItems | Sort-Object Length | Select-Object -Last 1
                $largestSize = if ($largestItem) {
                    ($largestItem.Length | ForEach-Object { Format-DowserSize -DataValue $_ })
                }
                else {
                    '0B' 
                }
                $newestFile = $subFolderItems | Sort-Object LastWriteTime | Select-Object -Last 1
                $oldestFile = $subFolderItems | Sort-Object LastWriteTime | Select-Object -First 1

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
            }
        }
    }

    end {
        Write-Log "Ending Measure-DowserDirectory"
    }
}
