#Requires -Version 5.1

function Repair-DowserJson {
    <#
    .SYNOPSIS
        Diagnoses JSON first, then writes only safe repaired copies.

    .DESCRIPTION
        Each file is classified before any write occurs. The command repairs only
        deterministic cases: root JSON arrays, pretty-printed JSON document sequences,
        Dowser RECORD banner exports, JSON comments accepted by the parser, tagged
        transcript blocks, and unstructured fragments. Tagged blocks become role-aware
        records. Unstructured fragments become one provenance-bearing JSONL record with
        their complete original text; no missing structure is guessed.

        By default each repaired copy is written as <name>.repaired.jsonl in a
        JSON-Repaired directory beside its source. After that copy is verified as
        parseable, the malformed source moves into JSON-Triage beside its source so
        the working corpus contains only valid originals and repaired copies. Use
        OutputDirectory to select a different repaired-copy destination.

    .PARAMETER Path
        JSON or JSONL file, or a directory containing them. Accepts pipeline input.

    .PARAMETER Recurse
        Repair JSON and JSONL files below a directory. Defaults to enabled.

    .PARAMETER OutputDirectory
        Optional common directory for repaired copies. The default is JSON-Repaired
        beside each source file.

    .PARAMETER Force
        Replace an existing repaired copy.

    .PARAMETER ThreadCount
        Maximum concurrent JSON repair workers. Defaults to the lower of 8 or the processor count.

    .EXAMPLE
        Repair-DowserJson -Path /data/transcripts

    .EXAMPLE
        Repair-DowserJson -Path ./formatted-export.json -OutputDirectory ./json-triage

    .OUTPUTS
        PSCustomObject with the diagnosis plus Result and OutputPath.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('FullName')]
        [string[]]$Path,

        [switch]$Recurse = $true,

        [string]$OutputDirectory,

        [switch]$Force,

        [ValidateRange(1, 100)]
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
                Write-Log 'Repair-DowserJson loading Newtonsoft.Json' -Severity Verbose
                Add-Type -AssemblyName 'Newtonsoft.Json' -ErrorAction Stop
                Write-Log 'Repair-DowserJson loaded Newtonsoft.Json' -Severity Verbose
            }
            catch {
                Write-Log "Repair-DowserJson could not load the JSON reader: $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Error
                return
            }
        }

        $files = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
        $seenFiles = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($requestedPath in $requestedPaths) {
            try {
                Write-Log "Repair-DowserJson resolving '$requestedPath'" -Severity Verbose
                $item = Get-Item -LiteralPath $requestedPath -ErrorAction Stop
                Write-Log "Repair-DowserJson resolved '$($item.FullName)'" -Severity Verbose
            }
            catch {
                Write-Log "Repair-DowserJson could not resolve '$requestedPath': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Warning
                continue
            }

            if (-not $item.PSIsContainer) {
                if ($item.Extension -in '.json', '.jsonl' -and $seenFiles.Add($item.FullName)) {
                    $files.Add($item)
                }
                continue
            }

            try {
                Write-Log "Repair-DowserJson enumerating '$($item.FullName)'" -Severity Verbose
                $children = Get-ChildItem -LiteralPath $item.FullName -File -Recurse:$Recurse -ErrorAction Stop |
                    Where-Object {
                        $_.Extension -in '.json', '.jsonl' -and
                        $_.Directory.Name -notin 'JSON-Repaired', 'JSON-Triage'
                    }
                Write-Log "Repair-DowserJson enumerated '$($item.FullName)'" -Severity Verbose
            }
            catch {
                Write-Log "Repair-DowserJson could not enumerate '$($item.FullName)': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Warning
                continue
            }

            foreach ($child in $children) {
                if ($seenFiles.Add($child.FullName)) {
                    $files.Add($child)
                }
            }
        }

        if ($files.Count -eq 0) {
            Write-Log 'Repair-DowserJson found no .json or .jsonl files' -Severity Warning
            return
        }

        $writeEnabled = $PSCmdlet.ShouldProcess(
            "$($files.Count) .json/.jsonl file(s)",
            'Diagnose and create separate repaired JSONL copies'
        )
        $tasks = [System.Collections.Generic.List[object]]::new()
        foreach ($file in $files) {
            $destinationDirectory = if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
                Join-Path (Split-Path -Parent $file.FullName) 'JSON-Repaired'
            }
            else {
                [System.IO.Path]::GetFullPath($OutputDirectory)
            }

            $tasks.Add([pscustomobject]@{
                FilePath     = $file.FullName
                OutputPath   = Join-Path $destinationDirectory ([System.IO.Path]::GetFileNameWithoutExtension($file.Name) + '.repaired.jsonl')
                TriagePath   = Join-Path (Join-Path (Split-Path -Parent $file.FullName) 'JSON-Triage') $file.Name
                Force        = [bool]$Force
                WriteEnabled = $writeEnabled
            })
        }

        Invoke-DowserJsonRepairScan -Task $tasks.ToArray() -ThreadCount $ThreadCount |
            Sort-Object FilePath
    }
}
