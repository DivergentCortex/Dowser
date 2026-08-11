#Requires -Version 5.1

function Get-DowserJsonKey {
    <#
    .SYNOPSIS
        Reads JSON and JSONL files as streams and reports their JSON key paths.

    .DESCRIPTION
        Scans one JSON or JSONL file, or every .json and .jsonl file beneath a directory,
        without deserializing whole documents. Default output is one row per file and key
        path. Use -Compare to aggregate paths across the scanned files and identify the
        files that omit each path.

    .PARAMETER Path
        JSON or JSONL file, or a directory containing those files. Accepts pipeline input.

    .PARAMETER Recurse
        Scan subdirectories when Path is a directory. Defaults to enabled.

    .PARAMETER Compare
        Emit one aggregate row per key path instead of per-file rows.

    .EXAMPLE
        Get-DowserJsonKey -Path ./events.jsonl

    .EXAMPLE
        Get-DowserJsonKey -Path ./exports -Compare

    .OUTPUTS
        PSCustomObject. Default: FilePath, Format, Documents, KeyPath, OccurrenceCount.
        Compare: KeyPath, FileCount, TotalOccurrences, PresentInFiles, MissingFromFiles.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('FullName')]
        [string[]]$Path,

        [switch]$Recurse = $true,

        [switch]$Compare
    )

    begin {
        $requestedPaths = [System.Collections.Generic.List[string]]::new()
    }

    process {
        foreach ($inputPath in $Path) {
            $requestedPaths.Add($inputPath)
        }
    }

    end {
        $jsonReaderType = [System.Management.Automation.PSTypeName]'Newtonsoft.Json.JsonTextReader'
        if ($null -eq $jsonReaderType.Type) {
            try {
                Add-Type -AssemblyName 'Newtonsoft.Json' -ErrorAction Stop
            }
            catch {
                Write-Log "Get-DowserJsonKey could not load the JSON reader: $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Error
                return
            }
        }

        $files = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
        $seenFiles = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

        foreach ($requestedPath in $requestedPaths) {
            try {
                $item = Get-Item -LiteralPath $requestedPath -ErrorAction Stop
            }
            catch {
                Write-Log "Get-DowserJsonKey could not resolve '$requestedPath': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Warning
                continue
            }

            if (-not $item.PSIsContainer) {
                if ($item.Extension -notin '.json', '.jsonl') {
                    Write-Log "Get-DowserJsonKey skipped non-JSON file '$($item.FullName)'" -Severity Warning
                    continue
                }
                if ($seenFiles.Add($item.FullName)) {
                    $files.Add($item)
                }
                continue
            }

            try {
                $children = Get-ChildItem -LiteralPath $item.FullName -File -Recurse:$Recurse -ErrorAction Stop |
                    Where-Object { $_.Extension -in '.json', '.jsonl' }
            }
            catch {
                Write-Log "Get-DowserJsonKey could not enumerate '$($item.FullName)': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Warning
                continue
            }

            foreach ($child in $children) {
                if ($seenFiles.Add($child.FullName)) {
                    $files.Add($child)
                }
            }
        }

        if ($files.Count -eq 0) {
            Write-Log 'Get-DowserJsonKey found no .json or .jsonl files' -Severity Warning
            return
        }

        Write-Log "Get-DowserJsonKey scanning $($files.Count) JSON file(s)" -Severity Info
        $fileRows = [System.Collections.Generic.List[object]]::new()

        foreach ($file in $files) {
            $keyCounts = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::Ordinal)
            $documentCount = 0
            $stream = $null
            $reader = $null

            try {
                $stream = [System.IO.File]::OpenRead($file.FullName)
                $textReader = [System.IO.StreamReader]::new($stream)
                $reader = [Newtonsoft.Json.JsonTextReader]::new($textReader)
                $reader.SupportMultipleContent = $true
            }
            catch {
                Write-Log "Get-DowserJsonKey could not open '$($file.FullName)': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Warning
                if ($null -ne $reader) { $reader.Close() }
                elseif ($null -ne $stream) { $stream.Dispose() }
                continue
            }

            try {
                while ($reader.Read()) {
                    if (($reader.TokenType -eq [Newtonsoft.Json.JsonToken]::StartObject -or
                         $reader.TokenType -eq [Newtonsoft.Json.JsonToken]::StartArray) -and
                        $reader.Depth -eq 0) {
                        $documentCount++
                    }

                    if ($reader.TokenType -ne [Newtonsoft.Json.JsonToken]::PropertyName) {
                        continue
                    }

                    $keyPath = '$.' + ($reader.Path -replace '\[\d+\]', '[]')
                    if ($keyCounts.ContainsKey($keyPath)) {
                        $keyCounts[$keyPath] = $keyCounts[$keyPath] + 1
                    }
                    else {
                        $keyCounts.Add($keyPath, 1)
                    }
                }
            }
            catch {
                Write-Log "Get-DowserJsonKey could not parse '$($file.FullName)': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Warning
            }
            finally {
                $reader.Close()
            }

            foreach ($keyPath in ($keyCounts.Keys | Sort-Object)) {
                $fileRows.Add([pscustomobject]@{
                    FilePath        = $file.FullName
                    Format          = $file.Extension.TrimStart('.').ToUpperInvariant()
                    Documents       = $documentCount
                    KeyPath         = $keyPath
                    OccurrenceCount = $keyCounts[$keyPath]
                })
            }
        }

        if (-not $Compare) {
            $fileRows | Sort-Object FilePath, KeyPath
            return
        }

        $allFiles = @($files.FullName | Sort-Object)
        $keyGroups = $fileRows | Group-Object KeyPath
        foreach ($group in ($keyGroups | Sort-Object Name)) {
            $presentFiles = @($group.Group.FilePath | Sort-Object -Unique)
            $missingFiles = @($allFiles | Where-Object { $_ -notin $presentFiles })
            $occurrenceTotal = ($group.Group | Measure-Object -Property OccurrenceCount -Sum).Sum

            [pscustomobject]@{
                KeyPath         = $group.Name
                FileCount       = $presentFiles.Count
                TotalOccurrences = $occurrenceTotal
                PresentInFiles  = $presentFiles -join '; '
                MissingFromFiles = $missingFiles -join '; '
            }
        }
    }
}
