#Requires -Version 5.1

function Test-DowserJson {
    <#
    .SYNOPSIS
        Diagnoses JSON and JSONL files before repair or assessment.

    .DESCRIPTION
        Streams each selected file and reports whether it is valid JSON, valid JSONL,
        comment-bearing JSON, a RECORD banner export, tagged transcript text, or a parser
        syntax failure. Syntax failures include the parser message and the reported line
        and position. No files are changed.

    .PARAMETER Path
        JSON or JSONL file, or a directory to inspect. Accepts pipeline input.

    .PARAMETER Recurse
        Inspect JSON and JSONL files below a directory. Defaults to enabled.

    .EXAMPLE
        Test-DowserJson -Path /data/transcripts

    .EXAMPLE
        Test-DowserJson -Path ./export.json | Where-Object Repairable

    .OUTPUTS
        PSCustomObject with FilePath, Classification, Repairable, RepairAction, Documents,
        ErrorLine, ErrorPosition, and ErrorMessage.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('FullName')]
        [string[]]$Path,

        [switch]$Recurse = $true
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
                Write-Log 'Test-DowserJson loading Newtonsoft.Json' -Severity Verbose
                Add-Type -AssemblyName 'Newtonsoft.Json' -ErrorAction Stop
                Write-Log 'Test-DowserJson loaded Newtonsoft.Json' -Severity Verbose
            }
            catch {
                Write-Log "Test-DowserJson could not load the JSON reader: $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Error
                return
            }
        }

        $files = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
        $seenFiles = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($requestedPath in $requestedPaths) {
            try {
                Write-Log "Test-DowserJson resolving '$requestedPath'" -Severity Verbose
                $item = Get-Item -LiteralPath $requestedPath -ErrorAction Stop
                Write-Log "Test-DowserJson resolved '$($item.FullName)'" -Severity Verbose
            }
            catch {
                Write-Log "Test-DowserJson could not resolve '$requestedPath': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Warning
                continue
            }

            if (-not $item.PSIsContainer) {
                if ($item.Extension -in '.json', '.jsonl' -and $seenFiles.Add($item.FullName)) {
                    $files.Add($item)
                }
                continue
            }

            try {
                Write-Log "Test-DowserJson enumerating '$($item.FullName)'" -Severity Verbose
                $children = Get-ChildItem -LiteralPath $item.FullName -File -Recurse:$Recurse -ErrorAction Stop |
                    Where-Object { $_.Extension -in '.json', '.jsonl' }
                Write-Log "Test-DowserJson enumerated '$($item.FullName)'" -Severity Verbose
            }
            catch {
                Write-Log "Test-DowserJson could not enumerate '$($item.FullName)': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Warning
                continue
            }

            foreach ($child in $children) {
                if ($seenFiles.Add($child.FullName)) {
                    $files.Add($child)
                }
            }
        }

        $completed = 0
        $classificationCounts = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::Ordinal)
        foreach ($file in $files) {
            $completed++
            $percent = [Math]::Round(($completed / $files.Count) * 100)
            Write-Progress -Activity 'Test-DowserJson' -Status "Diagnosing $completed of $($files.Count)" -PercentComplete $percent
            $result = Get-DowserJsonDiagnosis -FilePath $file.FullName
            if ($classificationCounts.ContainsKey($result.Classification)) {
                $classificationCounts[$result.Classification] = $classificationCounts[$result.Classification] + 1
            }
            else {
                $classificationCounts.Add($result.Classification, 1)
            }
            $result
        }

        Write-Progress -Activity 'Test-DowserJson' -Completed
        $classificationSummary = @($classificationCounts.Keys | Sort-Object | ForEach-Object {
            "$_=$($classificationCounts[$_])"
        }) -join '; '
        Write-Log "Test-DowserJson diagnosed $($files.Count) JSON file(s): $classificationSummary" -Severity Info
    }
}
