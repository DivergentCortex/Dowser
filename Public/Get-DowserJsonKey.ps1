#Requires -Version 5.1

function Get-DowserJsonKey {
    <#
    .SYNOPSIS
        Reads JSON and JSONL files as streams and reports their JSON key paths.

    .DESCRIPTION
        Scans one JSON or JSONL file, or every .json and .jsonl file beneath a directory,
        without deserializing whole documents. Default output is one row per file and key
        path. Use -Compare to group files by complete key layout, identify the dominant layout,
        and show representative variants with key differences and sample files. Add
        -ShowKeyComparison when individual key-path comparison rows are needed.

    .NOTES
        -Validation classifies file-level path coverage. It does not load source documents.
        Results from the most recent comparison remain available in
        $global:DowserJsonLastComparison and $global:DowserJsonLastValidation.

    .PARAMETER Path
        JSON or JSONL file, or a directory containing those files. Accepts pipeline input.

    .PARAMETER Recurse
        Scan subdirectories when Path is a directory. Defaults to enabled.

    .PARAMETER Compare
        Assess the complete directory: emits schema profiles and retains full per-key coverage validation.

    .PARAMETER IncludeFiles
        Include full present and missing file lists for detailed key comparison. Implies -ShowKeyComparison.

    .PARAMETER ShowKeyComparison
        Include one detailed row for every discovered key path. The default -Compare report is compact.

    .PARAMETER Validation
        Emit every discovered key with file coverage and an ingestion-suitability classification. The same rows are retained in $global:DowserJsonLastValidation after every comparison.

    .PARAMETER ProfileLimit
        Maximum schema profiles returned by -Compare. Defaults to 10.

    .PARAMETER ThreadCount
        Maximum JSON file readers. Defaults to the lower of 8 or the processor count.

    .EXAMPLE
        Get-DowserJsonKey -Path ./events.jsonl

    .EXAMPLE
        Get-DowserJsonKey -Path ./exports -Compare

    .OUTPUTS
        PSCustomObject. Default: FilePath, Format, Documents, KeyPath, OccurrenceCount.
        Compare emits DirectorySummary and SchemaProfile rows. -Validation emits KeyValidation rows. Detailed key comparison remains available with -ShowKeyComparison.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('FullName')]
        [string[]]$Path,

        [switch]$Recurse = $true,

        [switch]$Compare,

        [switch]$IncludeFiles,

        [switch]$ShowKeyComparison,

        [switch]$Validation,

        [ValidateRange(1, 100)]
        [int]$ProfileLimit = 10,

        [int]$ThreadCount = [Math]::Min(8, [Environment]::ProcessorCount)
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
                $includeTriage = $item.Name -eq 'JSON-Triage'
                $children = Get-ChildItem -LiteralPath $item.FullName -File -Recurse:$Recurse -ErrorAction Stop |
                    Where-Object {
                        $_.Extension -in '.json', '.jsonl' -and
                        ($includeTriage -or $_.FullName -notmatch '[/\\]JSON-Triage([/\\]|$)')
                    }
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

        Write-Log "Get-DowserJsonKey scanning $($files.Count) JSON file(s) with $ThreadCount worker(s)" -Severity Info
        $fileRows = [System.Collections.Generic.List[object]]::new()
        $fileSummaries = [System.Collections.Generic.List[object]]::new()
        $scanResults = @(Invoke-DowserJsonKeyScan -FilePath $files.FullName -ThreadCount $ThreadCount)
        Write-Log "Get-DowserJsonKey scan finished; summarizing $($scanResults.Count) file result(s). Compare/Validation has no progress bar and can sit silent if files have tens of thousands of distinct key paths." -Severity Info

        $parseFailures = [System.Collections.Generic.List[object]]::new()
        foreach ($scanResult in $scanResults) {
            if (-not $scanResult.ReadSucceeded) {
                $parseFailures.Add($scanResult)
                continue
            }

            $keyPaths = @($scanResult.KeyCounts.Keys | Sort-Object)
            if ($keyPaths.Count -ge 5000) {
                Write-Log "Get-DowserJsonKey '$($scanResult.FilePath)' has $($keyPaths.Count) distinct key paths; Compare/Validation will look hung from here." -Severity Warning
            }
            $fileOccurrences = ($scanResult.KeyCounts.Values | Measure-Object -Sum).Sum
            if ($null -eq $fileOccurrences) {
                $fileOccurrences = 0
            }

            $fileSummaries.Add([pscustomobject]@{
                FilePath         = $scanResult.FilePath
                Format           = $scanResult.Format
                Documents        = $scanResult.Documents
                KeyCount         = $keyPaths.Count
                KeyPaths         = $keyPaths
                TotalOccurrences = $fileOccurrences
            })

            if (-not $Compare -or $ShowKeyComparison -or $IncludeFiles) {
                foreach ($keyPath in $keyPaths) {
                    $fileRows.Add([pscustomobject]@{
                        FilePath        = $scanResult.FilePath
                        Format          = $scanResult.Format
                        Documents       = $scanResult.Documents
                        KeyPath         = $keyPath
                        OccurrenceCount = $scanResult.KeyCounts[$keyPath]
                    })
                }
            }
        }

        $global:DowserJsonLastParseFailures = $parseFailures.ToArray()
        if ($parseFailures.Count -gt 0) {
            $sampleFailures = @($parseFailures | Select-Object -First 3 | ForEach-Object { $_.FilePath }) -join '; '
            Write-Log "Get-DowserJsonKey skipped $($parseFailures.Count) non-JSON or invalid JSON file(s). Sample path(s): $sampleFailures. Inspect `$global:DowserJsonLastParseFailures for all paths and parser errors." -Severity Warning
        }
        if ($fileSummaries.Count -eq 0) {
            Write-Log "Get-DowserJsonKey found no parseable JSON files among $($files.Count) candidate(s)" -Severity Warning
            return
        }

        if (-not $Compare) {
            Write-Log "Get-DowserJsonKey emitting $($fileRows.Count) per-key row(s)" -Severity Info
            $fileRows | Sort-Object FilePath, KeyPath
            return
        }

        Write-Log "Get-DowserJsonKey Compare starting on $($fileSummaries.Count) file(s), $((($fileSummaries | Measure-Object KeyCount -Sum).Sum)) total distinct key paths" -Severity Info
        $schemaProfiles = @($fileSummaries | Group-Object { $_.KeyPaths -join [string][char]31 })
        $orderedProfiles = @($schemaProfiles | Sort-Object @{ Expression = 'Count'; Descending = $true }, Name)
        $dominantProfile = $orderedProfiles | Select-Object -First 1
        $dominantKeyPaths = @($dominantProfile.Group[0].KeyPaths)
        $documentsScanned = ($fileSummaries | Measure-Object -Property Documents -Sum).Sum
        $totalOccurrences = ($fileSummaries | Measure-Object -Property TotalOccurrences -Sum).Sum
        $keyFileCounts = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::Ordinal)
        foreach ($fileSummary in $fileSummaries) {
            foreach ($keyPath in $fileSummary.KeyPaths) {
                if ($keyFileCounts.ContainsKey($keyPath)) {
                    $keyFileCounts[$keyPath] = $keyFileCounts[$keyPath] + 1
                }
                else {
                    $keyFileCounts.Add($keyPath, 1)
                }
            }
        }

        $validationRows = [System.Collections.Generic.List[object]]::new()
        foreach ($keyPath in ($keyFileCounts.Keys | Sort-Object)) {
            $fileCount = $keyFileCounts[$keyPath]
            $coveragePercent = [Math]::Round(($fileCount / $fileSummaries.Count) * 100, 2)
            $classification = if ($fileCount -eq $fileSummaries.Count) {
                'AlwaysPresent'
            }
            elseif ($coveragePercent -ge 95) {
                'Common'
            }
            elseif ($coveragePercent -ge 5) {
                'Occasional'
            }
            else {
                'Rare'
            }

            $validationRows.Add([pscustomobject]@{
                ResultType       = 'KeyValidation'
                Classification   = $classification
                KeyPath          = $keyPath
                FileCount        = $fileCount
                MissingFileCount = $fileSummaries.Count - $fileCount
                CoveragePercent  = $coveragePercent
            })
        }
        $global:DowserJsonLastValidation = $validationRows.ToArray()

        $comparisonResults = @(& {
        if ($Validation) {
            $validationRows
        }

        [pscustomobject]@{
            ResultType                 = 'DirectorySummary'
            FilesScanned               = $files.Count
            FilesParsed                = $fileSummaries.Count
            FilesSkippedInvalid        = $parseFailures.Count
            DocumentsScanned           = $documentsScanned
            DistinctSchemas            = $schemaProfiles.Count
            DominantSchemaFileCount    = $dominantProfile.Count
            FilesDifferentFromDominant = $fileSummaries.Count - $dominantProfile.Count
            DominantSchemaKeyCount     = $dominantKeyPaths.Count
            DistinctKeyPaths           = @($fileSummaries.KeyPaths | Sort-Object -Unique).Count
            TotalOccurrences           = $totalOccurrences
        }

        foreach ($profile in ($orderedProfiles | Select-Object -First $ProfileLimit)) {
            $profileKeyPaths = @($profile.Group[0].KeyPaths)
            $missingKeys = @($dominantKeyPaths | Where-Object { $_ -notin $profileKeyPaths })
            $additionalKeys = @($profileKeyPaths | Where-Object { $_ -notin $dominantKeyPaths })
            $sampleFile = ($profile.Group | Sort-Object FilePath | Select-Object -First 1).FilePath

            [pscustomobject]@{
                ResultType           = 'SchemaProfile'
                Role                 = if ($profile.Name -eq $dominantProfile.Name) { 'Dominant' } else { 'Variant' }
                FileCount            = $profile.Count
                KeyCount             = $profileKeyPaths.Count
                MissingKeyCount      = $missingKeys.Count
                AdditionalKeyCount   = $additionalKeys.Count
                MissingKeyPreview    = ($missingKeys | Select-Object -First 5) -join '; '
                AdditionalKeyPreview = ($additionalKeys | Select-Object -First 5) -join '; '
                SampleFile           = $sampleFile
            }
        }

        if ($orderedProfiles.Count -gt $ProfileLimit) {
            [pscustomobject]@{
                ResultType       = 'SchemaProfileRemainder'
                ProfilesOmitted  = $orderedProfiles.Count - $ProfileLimit
                FilesRepresented = @($orderedProfiles | Select-Object -Skip $ProfileLimit | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum
            }
        }

        if ($ShowKeyComparison -or $IncludeFiles) {
            $allFiles = @($fileSummaries.FilePath | Sort-Object)
            $keyGroups = @($fileRows | Group-Object KeyPath)
            foreach ($group in ($keyGroups | Sort-Object Name)) {
                $presentFiles = @($group.Group.FilePath | Sort-Object -Unique)
                $missingFiles = @($allFiles | Where-Object { $_ -notin $presentFiles })
                $occurrenceTotal = ($group.Group | Measure-Object -Property OccurrenceCount -Sum).Sum
                $comparisonRow = [ordered]@{
                    ResultType       = 'KeyComparison'
                    KeyPath          = $group.Name
                    FileCount        = $presentFiles.Count
                    MissingFileCount = $missingFiles.Count
                    TotalOccurrences = $occurrenceTotal
                }
                if ($IncludeFiles) {
                    $comparisonRow.PresentInFiles = $presentFiles -join '; '
                    $comparisonRow.MissingFromFiles = $missingFiles -join '; '
                }
                [pscustomobject]$comparisonRow
            }
        }
        })

        $global:DowserJsonLastComparison = $comparisonResults
        $comparisonResults
    }
}
