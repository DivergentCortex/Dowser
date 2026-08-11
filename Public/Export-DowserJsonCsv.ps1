#Requires -Version 5.1

function Export-DowserJsonCsv {
    <#
    .SYNOPSIS
        Exports scalar JSON and JSONL values to an Excel-compatible CSV.

    .DESCRIPTION
        Reads JSON tokens from a file without loading the full document. Each scalar value
        becomes a CSV row with its document number and JSON key path. The resulting long-form
        CSV opens directly in Excel and keeps nested objects and arrays unambiguous.

    .PARAMETER Path
        JSON or JSONL file to export. Accepts pipeline input.

    .PARAMETER OutputPath
        Destination CSV path. Existing files are not replaced unless -Force is specified.

    .PARAMETER Force
        Replace an existing destination file.

    .EXAMPLE
        Export-DowserJsonCsv -Path ./events.jsonl -OutputPath ./events.csv

    .OUTPUTS
        PSCustomObject with SourcePath, OutputPath, Documents, and ValuesWritten.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('FullName')]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [switch]$Force
    )

    process {
        try {
            $source = Get-Item -LiteralPath $Path -ErrorAction Stop
        }
        catch {
            Write-Log "Export-DowserJsonCsv could not resolve '$Path': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Error
            return
        }

        if ($source.PSIsContainer -or $source.Extension -notin '.json', '.jsonl') {
            Write-Log "Export-DowserJsonCsv requires a .json or .jsonl file: '$($source.FullName)'" -Severity Error
            return
        }

        if ((Test-Path -LiteralPath $OutputPath) -and -not $Force) {
            Write-Log "Export-DowserJsonCsv will not replace existing file '$OutputPath' without -Force" -Severity Error
            return
        }

        if (-not $PSCmdlet.ShouldProcess($OutputPath, "Export JSON values from '$($source.FullName)'")) {
            return
        }

        $jsonReaderType = [System.Management.Automation.PSTypeName]'Newtonsoft.Json.JsonTextReader'
        if ($null -eq $jsonReaderType.Type) {
            try {
                Add-Type -AssemblyName 'Newtonsoft.Json' -ErrorAction Stop
            }
            catch {
                Write-Log "Export-DowserJsonCsv could not load the JSON reader: $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Error
                return
            }
        }

        $stream = $null
        $reader = $null
        $writer = $null
        $documentCount = 0
        $valueCount = 0

        try {
            $stream = [System.IO.File]::OpenRead($source.FullName)
            $textReader = [System.IO.StreamReader]::new($stream)
            $reader = [Newtonsoft.Json.JsonTextReader]::new($textReader)
            $reader.SupportMultipleContent = $true
            $reader.DateParseHandling = [Newtonsoft.Json.DateParseHandling]::None

            $destinationDirectory = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($OutputPath))
            if ($destinationDirectory -and -not (Test-Path -LiteralPath $destinationDirectory)) {
                New-Item -ItemType Directory -Path $destinationDirectory -Force -ErrorAction Stop | Out-Null
            }

            $writer = [System.IO.StreamWriter]::new($OutputPath, $false, [System.Text.UTF8Encoding]::new($true))
            $writer.WriteLine('"SourceFile","DocumentNumber","KeyPath","Value"')

            while ($reader.Read()) {
                if (($reader.TokenType -eq [Newtonsoft.Json.JsonToken]::StartObject -or
                     $reader.TokenType -eq [Newtonsoft.Json.JsonToken]::StartArray) -and
                    $reader.Depth -eq 0) {
                    $documentCount++
                    continue
                }

                if ($reader.TokenType -notin @(
                    [Newtonsoft.Json.JsonToken]::String,
                    [Newtonsoft.Json.JsonToken]::Integer,
                    [Newtonsoft.Json.JsonToken]::Float,
                    [Newtonsoft.Json.JsonToken]::Boolean,
                    [Newtonsoft.Json.JsonToken]::Null
                )) {
                    continue
                }

                $keyPath = '$.' + ($reader.Path -replace '\[\d+\]', '[]')
                $value = if ($null -eq $reader.Value) {
                    ''
                }
                else {
                    [System.Convert]::ToString($reader.Value, [System.Globalization.CultureInfo]::InvariantCulture)
                }

                $escapedSource = $source.FullName -replace '"', '""'
                $escapedPath = $keyPath -replace '"', '""'
                $escapedValue = $value -replace '"', '""'
                $csvLine = '"{0}","{1}","{2}","{3}"' -f $escapedSource, $documentCount, $escapedPath, $escapedValue
                $writer.WriteLine($csvLine)
                $valueCount++
            }
        }
        catch {
            Write-Log "Export-DowserJsonCsv could not export '$($source.FullName)': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Error
            return
        }
        finally {
            if ($null -ne $writer) { $writer.Dispose() }
            elseif ($null -ne $reader) { $reader.Close() }
            elseif ($null -ne $stream) { $stream.Dispose() }
        }

        Write-Log "Export-DowserJsonCsv wrote $valueCount value(s) from $documentCount document(s) to '$OutputPath'" -Severity Info
        [pscustomobject]@{
            SourcePath    = $source.FullName
            OutputPath    = (Get-Item -LiteralPath $OutputPath).FullName
            Documents     = $documentCount
            ValuesWritten = $valueCount
        }
    }
}
