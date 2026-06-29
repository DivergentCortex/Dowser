function Find-DowserDuplicate {
    <#
    .SYNOPSIS
        Finds duplicate files in a directory using multiple detection strategies.

    .NOTES
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
        -  Author:        Curtis Leggett                                  -
        =  Copyright:     2026 Divergent Cortex                           =
        -  Organization:  Divergent Cortex                                -
        =  Version:       See docs/CHANGELOG.md                           =
        =-=-                       =-=-=-=-=-=-=-=                     -=-=
        -  it is not water they seek, but the truth beneath the trees     -
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
        Date Created:   2026-02-28

    .DESCRIPTION
        Scans a directory recursively and detects duplicate files using one or more
        modes: Name (exact filename), PartialName (normalized stem matching),
        NameSize (name + size combo), Content (full file hash), Chunk (block-level hash).

        Default output is a compact summary table showing filename and duplicate count.
        Full detail is always stored in $global:dupObjects for drill-down.

    .PARAMETER Path
        Root directory to scan for duplicates.

    .PARAMETER Exclude
        Wildcard patterns to exclude from scanning.

    .PARAMETER MinSize
        Minimum file size in bytes to include. Default 0.

    .PARAMETER Mode
        Detection strategy. One or more of: Name, PartialName, NameSize, Content, Chunk, All.
        Default is 'All' which runs every mode.

    .PARAMETER HashAlgorithm
        Hash algorithm for Content and Chunk modes. Default SHA256.

    .PARAMETER ChunkSize
        Block size for Chunk mode. Default 1MB.

    .PARAMETER ChunkOverlap
        Overlap between chunks in bytes. Default 0.

    .PARAMETER ReportPath
        Export full results to CSV at this path.

    .PARAMETER AutoRemove
        Automatically delete duplicates (keeps first file in each set).

    .PARAMETER ReviewBeforeDelete
        Prompt before deleting each duplicate.

    .PARAMETER ChunkSequenceLength
        Number of sequential chunks to match. Default 3.

    .EXAMPLE
        Find-DowserDuplicate -Path "D:\Documents"

        Scans D:\Documents with all modes. Shows compact summary, details in $global:dupObjects.

    .EXAMPLE
        Find-DowserDuplicate -Path "D:\Scripts" -Mode Name,PartialName

        Finds files with identical or similar names.

    .EXAMPLE
        Find-DowserDuplicate -Path "D:\Backup" -Mode Content -MinSize 1MB
        $global:dupObjects | Where-Object Count -gt 3

        Finds content-identical files over 1MB, then filters the stored results.

    .OUTPUTS
        PSCustomObject summary table to console. Full details in $global:dupObjects.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('FullName')]
        [string]$Path,

        [string[]]$Exclude,

        [long]$MinSize = 0,

        [ValidateSet('Name', 'PartialName', 'NameSize', 'Content', 'Chunk', 'All')]
        [string[]]$Mode = @('All'),

        [ValidateSet('SHA256', 'SHA1', 'MD5')]
        [string]$HashAlgorithm = 'SHA256',

        [long]$ChunkSize = 1MB,

        [long]$ChunkOverlap = 0,

        [string]$ReportPath,

        [Switch]$AutoRemove,

        [Switch]$ReviewBeforeDelete,

        [ValidateRange(1, 32)]
        [int]$ChunkSequenceLength = 3
    )

    if (-not (Test-Path -Path $Path)) {
        throw "Path '$Path' not found."
    }

    Write-Verbose "Scanning '$Path'..."

    $files = Get-ChildItem -Path $Path -File -Recurse |
        Where-Object {
            if ($_.Length -lt $MinSize) {
                return $false 
            }
            if ($Exclude) {
                foreach ($pattern in $Exclude) {
                    if ($_.FullName -like $pattern) {
                        return $false 
                    }
                }
            }
            return $true
        }

    if (-not $files) {
        Write-Verbose "No files matched the filters."
        return
    }

    Write-Verbose "Found $(@($files).Count) files. Analyzing..."

    function Get-NormalizedStem {
        param([string]$FileName)
        $stem = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
        # strip copy backup and version suffixes
        $stem = $stem -replace '\s*[-_]?\s*(?:copy|backup|old|new|original|bak)\s*\d*$', ''
        $stem = $stem -replace '\s*\(\d+\)$', ''
        $stem = $stem -replace '\s*[-_]\s*v?\d+$', ''
        return $stem.ToLower().Trim()
    }

    function Get-ChunkHashes {
        param(
            [System.IO.FileInfo]$File,
            [long]$Size,
            [long]$Overlap,
            [string]$Algorithm
        )

        $results = [System.Collections.Generic.List[object]]::new()
        $buffer = New-Object byte[] $Size
        $fs = $File.OpenRead()
        try {
            $position = 0
            $chunkIndex = 0
            while ($position -lt $fs.Length) {
                $remaining = [Math]::Min($Size, $fs.Length - $position)
                $fs.Position = $position
                $read = $fs.Read($buffer, 0, [int]$remaining)
                $hash = (Get-FileHash -Algorithm $Algorithm -InputStream ([System.IO.MemoryStream]::new($buffer, 0, $read))).Hash
                $results.Add([PSCustomObject]@{
                        Hash       = $hash
                        File       = $File.FullName
                        Offset     = $position
                        Length     = $read
                        ChunkIndex = $chunkIndex
                    })
                $chunkIndex++
                if ($Overlap -ge $Size) {
                    break 
                }
                $position += $Size - $Overlap
            }
        }
        finally {
            $fs.Close()
        }

        return $results
    }

    $runName = $Mode -contains 'All' -or $Mode -contains 'Name'
    $runPartial = $Mode -contains 'All' -or $Mode -contains 'PartialName'
    $runNameSize = $Mode -contains 'All' -or $Mode -contains 'NameSize'
    $runContent = $Mode -contains 'All' -or $Mode -contains 'Content'
    $runChunk = $Mode -contains 'All' -or $Mode -contains 'Chunk'

    $dupSets = [System.Collections.Generic.List[object]]::new()

    if ($runName) {
        $groups = $files |
            Group-Object -Property Name |
            Where-Object { $_.Count -gt 1 }

        foreach ($group in $groups) {
            $dupSets.Add([PSCustomObject]@{
                    Mode     = 'Name'
                    MatchKey = $group.Group[0].Name
                    Count    = $group.Count
                    Hash     = $null
                    Files    = @($group.Group | Sort-Object FullName | ForEach-Object {
                            [PSCustomObject]@{ Path = $_.FullName; Size = $_.Length; Offset = $null; Length = $_.Length }
                        })
                })
        }
    }

    if ($runPartial) {
        $groups = $files |
            Group-Object -Property { Get-NormalizedStem $_.Name } |
            Where-Object { $_.Count -gt 1 }

        foreach ($group in $groups) {
            # name mode already caught exact dupes
            $uniqueNames = $group.Group | Select-Object -ExpandProperty Name -Unique
            if (@($uniqueNames).Count -le 1 -and $runName) {
                continue 
            }

            $stem = Get-NormalizedStem $group.Group[0].Name
            $dupSets.Add([PSCustomObject]@{
                    Mode     = 'PartialName'
                    MatchKey = "~$stem ($(@($uniqueNames) -join ', '))"
                    Count    = $group.Count
                    Hash     = $null
                    Files    = @($group.Group | Sort-Object FullName | ForEach-Object {
                            [PSCustomObject]@{ Path = $_.FullName; Size = $_.Length; Offset = $null; Length = $_.Length }
                        })
                })
        }
    }

    if ($runNameSize) {
        $groups = $files |
            Group-Object -Property { "$($_.Name)|$($_.Length)" } |
            Where-Object { $_.Count -gt 1 }

        foreach ($group in $groups) {
            $dupSets.Add([PSCustomObject]@{
                    Mode     = 'NameSize'
                    MatchKey = "$($group.Group[0].Name) [$($group.Group[0].Length) B]"
                    Count    = $group.Count
                    Hash     = $null
                    Files    = @($group.Group | Sort-Object FullName | ForEach-Object {
                            [PSCustomObject]@{ Path = $_.FullName; Size = $_.Length; Offset = $null; Length = $_.Length }
                        })
                })
        }
    }

    if ($runContent) {
        $hashGroups = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[object]]]::new()
        foreach ($file in $files) {
            if (-not (Test-Path -LiteralPath $file.FullName)) {
                continue 
            }
            try {
                $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm $HashAlgorithm -ErrorAction Stop).Hash
            }
            catch {
                Write-Verbose "Skipping unreadable file: $($file.FullName)"
                continue
            }
            if (-not $hash) {
                continue 
            }
            if (-not $hashGroups.ContainsKey($hash)) {
                $hashGroups[$hash] = [System.Collections.Generic.List[object]]::new()
            }
            $hashGroups[$hash].Add([PSCustomObject]@{ Path = $file.FullName; Size = $file.Length })
        }

        foreach ($hash in $hashGroups.Keys) {
            if ($hashGroups[$hash].Count -gt 1) {
                $firstName = Split-Path $hashGroups[$hash][0].Path -Leaf
                $dupSets.Add([PSCustomObject]@{
                        Mode     = 'Content'
                        MatchKey = $firstName
                        Count    = $hashGroups[$hash].Count
                        Hash     = $hash
                        Files    = @($hashGroups[$hash] | Sort-Object Path | ForEach-Object {
                                [PSCustomObject]@{ Path = $_.Path; Size = $_.Size; Offset = $null; Length = $_.Size }
                            })
                    })
            }
        }
    }

    if ($runChunk) {
        $chunkGroups = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[object]]]::new()
        foreach ($file in $files) {
            if (-not (Test-Path -LiteralPath $file.FullName)) {
                continue 
            }
            try {
                $chunks = Get-ChunkHashes -File $file -Size $ChunkSize -Overlap $ChunkOverlap -Algorithm $HashAlgorithm
            }
            catch {
                Write-Verbose "Skipping unreadable file: $($file.FullName)"
                continue
            }
            foreach ($entry in $chunks) {
                if (-not $entry.Hash) {
                    continue 
                }
                if (-not $chunkGroups.ContainsKey($entry.Hash)) {
                    $chunkGroups[$entry.Hash] = [System.Collections.Generic.List[object]]::new()
                }
                $chunkGroups[$entry.Hash].Add([PSCustomObject]@{
                        Path   = $entry.File
                        Size   = $entry.Length
                        Offset = $entry.Offset
                        Length = $entry.Length
                    })
            }
        }

        foreach ($hash in $chunkGroups.Keys) {
            if ($chunkGroups[$hash].Count -gt 1) {
                $firstName = Split-Path $chunkGroups[$hash][0].Path -Leaf
                $dupSets.Add([PSCustomObject]@{
                        Mode     = 'Chunk'
                        MatchKey = $firstName
                        Count    = $chunkGroups[$hash].Count
                        Hash     = $hash
                        Files    = @($chunkGroups[$hash] | Sort-Object Path | ForEach-Object {
                                [PSCustomObject]@{ Path = $_.Path; Size = $_.Size; Offset = $_.Offset; Length = $_.Length }
                            })
                    })
            }
        }
    }

    if ($AutoRemove -or $ReviewBeforeDelete) {
        foreach ($set in $dupSets) {
            $fileList = $set.Files
            if ($fileList.Count -le 1) {
                continue 
            }
            $keep = $fileList[0]
            $toDelete = $fileList | Select-Object -Skip 1

            if ($ReviewBeforeDelete) {
                Write-Verbose ""
                Write-Verbose "Duplicate set [$($set.Mode)]: $($set.MatchKey)"
                Write-Verbose "Keeping: $($keep.Path)"
                foreach ($file in $toDelete) {
                    $response = Read-Host "  Delete $($file.Path)? (y/N)"
                    if ($response -match '^[yY]$') {
                        Remove-Item -Path $file.Path -Force
                        Write-Verbose "  Deleted $($file.Path)"
                    }
                }
            }
            elseif ($AutoRemove) {
                foreach ($file in $toDelete) {
                    Remove-Item -Path $file.Path -Force
                    Write-Verbose "Deleted $($file.Path)"
                }
            }
        }
    }

    $global:dupObjects = $dupSets

    if ($ReportPath) {
        $exportRows = foreach ($set in $dupSets) {
            foreach ($f in $set.Files) {
                [PSCustomObject]@{
                    Mode     = $set.Mode
                    MatchKey = $set.MatchKey
                    Hash     = $set.Hash
                    FilePath = $f.Path
                    FileSize = $f.Size
                    Offset   = $f.Offset
                }
            }
        }
        $exportRows | Export-Csv -Path $ReportPath -NoTypeInformation
        Write-Verbose "Report saved to $ReportPath"
    }

    if ($dupSets.Count -eq 0) {
        Write-Verbose "No duplicates found."
        return
    }

    $modeSummary = $dupSets | Group-Object Mode | ForEach-Object {
        $totalDupes = ($_.Group | Measure-Object -Property Count -Sum).Sum
        [PSCustomObject]@{
            OutputType = 'ModeSummary'
            Mode       = $_.Name
            Sets       = $_.Count
            TotalFiles = $totalDupes
        }
    } | Sort-Object Mode

    Write-Verbose ""
    $modeSummary | Format-Table -AutoSize | Out-String | Write-Verbose
    # emit to pipeline so callers can capture
    Write-Output $modeSummary

    $topSets = $dupSets | Sort-Object Count -Descending | Select-Object -First 15 | ForEach-Object {
        [PSCustomObject]@{
            OutputType = 'TopSets'
            Mode       = $_.Mode
            FileName   = if ($_.MatchKey.Length -gt 60) {
                $_.MatchKey.Substring(0, 57) + '...' 
            }
            else {
                $_.MatchKey 
            }
            Duplicates = $_.Count
        }
    }

    Write-Verbose "Top duplicate sets (by count):"
    $topSets | Format-Table -AutoSize | Out-String | Write-Verbose
    Write-Output $topSets

    Write-Verbose "--- $($dupSets.Count) duplicate set(s) found across $(@($files).Count) files scanned ---"
    Write-Verbose 'Full details: $global:dupObjects'
    Write-Verbose 'Drill-down:   $global:dupObjects | Where-Object Mode -eq "Name" | Select-Object -ExpandProperty Files'
}

