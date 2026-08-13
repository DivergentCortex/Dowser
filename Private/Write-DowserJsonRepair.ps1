#Requires -Version 5.1

function Write-DowserJsonRepair {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Diagnosis,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [hashtable]$Sync
    )

    $writeLog = {
        param(
            [string]$Message,
            [string]$Severity
        )

        if ($null -ne $Sync) {
            $Sync.LogQueue.Enqueue([pscustomobject]@{
                Message  = $Message
                Severity = $Severity
            })
            return
        }

        Write-Log $Message -Severity $Severity
    }

    $outputDirectory = [System.IO.Path]::GetDirectoryName($OutputPath)
    $temporaryPath = Join-Path $outputDirectory ('.' + [System.IO.Path]::GetFileName($OutputPath) + '.' + [guid]::NewGuid().Guid + '.partial')
    $textReader = $null
    $sourceStream = $null
    $jsonReader = $null
    $textWriter = $null
    $jsonWriter = $null
    $documentsWritten = 0

    try {
        & $writeLog "Repair-DowserJson creating output directory '$outputDirectory' when needed" 'Verbose'
        if (-not (Test-Path -LiteralPath $outputDirectory)) {
            New-Item -ItemType Directory -Path $outputDirectory -Force -ErrorAction Stop | Out-Null
        }
        Write-Log "Repair-DowserJson output directory is ready '$outputDirectory'" -Severity Verbose
    }
    catch {
        Write-Log "Repair-DowserJson could not create output directory '$outputDirectory': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Error
        return [pscustomobject]@{ Success = $false; DocumentsWritten = 0; ErrorMessage = $_.Exception.Message }
    }

    try {
        Write-Log "Repair-DowserJson writing '$OutputPath'" -Severity Info
        $textWriter = [System.IO.StreamWriter]::new($temporaryPath, $false, [System.Text.UTF8Encoding]::new($false))

        if ($Diagnosis.Classification -eq 'RecordBannerJson') {
            $textReader = [System.IO.StreamReader]::new($Diagnosis.FilePath)
            $recordText = [System.Text.StringBuilder]::new()
            $insideRecord = $false

            while (-not $textReader.EndOfStream) {
                $line = $textReader.ReadLine()
                if ($line -match '^=+$') {
                    $header = $textReader.ReadLine()
                    $followingLine = $textReader.ReadLine()
                    if ($header -match '^RECORD [0-9]+ \(Line [0-9]+\)$' -and $followingLine -match '^=+$') {
                        if ($recordText.ToString().Trim().Length -gt 0) {
                            $token = [Newtonsoft.Json.Linq.JToken]::Parse($recordText.ToString())
                            $textWriter.WriteLine($token.ToString([Newtonsoft.Json.Formatting]::None))
                            $recordText.Clear() | Out-Null
                            $documentsWritten++
                        }
                        $insideRecord = $true
                        continue
                    }

                    if ($insideRecord) {
                        $recordText.AppendLine($line) | Out-Null
                        $recordText.AppendLine($header) | Out-Null
                        $recordText.AppendLine($followingLine) | Out-Null
                    }
                    continue
                }

                if ($insideRecord) {
                    $recordText.AppendLine($line) | Out-Null
                }
            }

            if ($recordText.Length -gt 0) {
                $token = [Newtonsoft.Json.Linq.JToken]::Parse($recordText.ToString())
                $textWriter.WriteLine($token.ToString([Newtonsoft.Json.Formatting]::None))
                $documentsWritten++
            }
        }
        elseif ($Diagnosis.Classification -in 'NonJsonText', 'JsonSyntaxError') {
            $sourceText = [System.IO.File]::ReadAllText($Diagnosis.FilePath)
            $record = [Newtonsoft.Json.Linq.JObject]::new()
            $record.Add('source_file', [Newtonsoft.Json.Linq.JValue]::new($Diagnosis.FilePath))
            $record.Add('source_format', [Newtonsoft.Json.Linq.JValue]::new('unstructured_text_fragment'))
            $record.Add('classification', [Newtonsoft.Json.Linq.JValue]::new($Diagnosis.Classification))
            $record.Add('content', [Newtonsoft.Json.Linq.JValue]::new($sourceText))
            $textWriter.WriteLine($record.ToString([Newtonsoft.Json.Formatting]::None))
            $documentsWritten++
        }
        elseif ($Diagnosis.Classification -eq 'TaggedTranscriptText') {
            $textReader = [System.IO.StreamReader]::new($Diagnosis.FilePath)
            $currentRole = $null
            $contentLines = [System.Collections.Generic.List[string]]::new()
            $writeTranscriptRecord = {
                param(
                    [string]$Role,
                    [System.Collections.Generic.List[string]]$Lines,
                    [int]$Sequence
                )

                if ([string]::IsNullOrWhiteSpace($Role)) {
                    return $false
                }

                $record = [Newtonsoft.Json.Linq.JObject]::new()
                $record.Add('source_file', [Newtonsoft.Json.Linq.JValue]::new($Diagnosis.FilePath))
                $record.Add('source_format', [Newtonsoft.Json.Linq.JValue]::new('tagged_transcript_text'))
                $record.Add('sequence', [Newtonsoft.Json.Linq.JValue]::new($Sequence))
                $record.Add('role', [Newtonsoft.Json.Linq.JValue]::new($Role.ToLowerInvariant()))
                $record.Add('content', [Newtonsoft.Json.Linq.JValue]::new([string]::Join([Environment]::NewLine, $Lines)))
                $textWriter.WriteLine($record.ToString([Newtonsoft.Json.Formatting]::None))
                return $true
            }

            while (-not $textReader.EndOfStream) {
                $line = $textReader.ReadLine()
                if ($line -match '^\[(USER|ASSISTANT|SYSTEM)\]\s*$') {
                    if (& $writeTranscriptRecord $currentRole $contentLines ($documentsWritten + 1)) {
                        $documentsWritten++
                    }
                    $currentRole = $matches[1]
                    $contentLines = [System.Collections.Generic.List[string]]::new()
                    continue
                }
                $contentLines.Add($line)
            }

            if (& $writeTranscriptRecord $currentRole $contentLines ($documentsWritten + 1)) {
                $documentsWritten++
            }
        }
        elseif ($Diagnosis.Classification -eq 'OuterArrayJson') {
            $sourceStream = [System.IO.File]::OpenRead($Diagnosis.FilePath)
            $textReader = [System.IO.StreamReader]::new($sourceStream)
            $jsonReader = [Newtonsoft.Json.JsonTextReader]::new($textReader)
            $jsonReader.DateParseHandling = [Newtonsoft.Json.DateParseHandling]::None

            if (-not $jsonReader.Read() -or
                $jsonReader.TokenType -ne [Newtonsoft.Json.JsonToken]::StartArray -or
                $jsonReader.Depth -ne 0) {
                throw [System.IO.InvalidDataException]::new('Expected one root JSON array.')
            }

            while ($jsonReader.Read()) {
                if ($jsonReader.TokenType -eq [Newtonsoft.Json.JsonToken]::Comment) {
                    continue
                }

                if ($jsonReader.TokenType -eq [Newtonsoft.Json.JsonToken]::EndArray -and $jsonReader.Depth -eq 0) {
                    break
                }

                $item = [Newtonsoft.Json.Linq.JToken]::ReadFrom($jsonReader)
                $textWriter.WriteLine($item.ToString([Newtonsoft.Json.Formatting]::None))
                $documentsWritten++
            }
        }
        elseif ($Diagnosis.Classification -in 'JsonWithComments', 'JsonSequence') {
            $sourceStream = [System.IO.File]::OpenRead($Diagnosis.FilePath)
            $textReader = [System.IO.StreamReader]::new($sourceStream)
            $jsonReader = [Newtonsoft.Json.JsonTextReader]::new($textReader)
            $jsonReader.SupportMultipleContent = $true
            $jsonReader.DateParseHandling = [Newtonsoft.Json.DateParseHandling]::None
            $jsonWriter = [Newtonsoft.Json.JsonTextWriter]::new($textWriter)
            $jsonWriter.Formatting = [Newtonsoft.Json.Formatting]::None
            $jsonWriter.CloseOutput = $false

            while ($jsonReader.Read()) {
                if ($jsonReader.TokenType -eq [Newtonsoft.Json.JsonToken]::Comment) {
                    continue
                }

                $jsonWriter.WriteToken($jsonReader, $false)
                if (($jsonReader.TokenType -in [Newtonsoft.Json.JsonToken]::EndObject, [Newtonsoft.Json.JsonToken]::EndArray) -and $jsonReader.Depth -eq 0) {
                    $jsonWriter.WriteRaw([Environment]::NewLine)
                    $documentsWritten++
                }
            }

            $jsonWriter.Flush()
        }

        if ($documentsWritten -eq 0) {
            throw [System.IO.InvalidDataException]::new('The repair produced no complete JSON documents.')
        }

        $textWriter.Flush()
    }
    catch {
        Write-Log "Repair-DowserJson could not repair '$($Diagnosis.FilePath)': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Error
        return [pscustomobject]@{ Success = $false; DocumentsWritten = 0; ErrorMessage = $_.Exception.Message }
    }
    finally {
        if ($null -ne $jsonWriter) { $jsonWriter.Close() }
        if ($null -ne $textWriter) { $textWriter.Dispose() }
        if ($null -ne $jsonReader) { $jsonReader.Close() }
        elseif ($null -ne $textReader) { $textReader.Dispose() }
        elseif ($null -ne $sourceStream) { $sourceStream.Dispose() }

        if ((Test-Path -LiteralPath $temporaryPath) -and $documentsWritten -eq 0) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
    }

    try {
        Write-Log "Repair-DowserJson publishing '$OutputPath'" -Severity Verbose
        Move-Item -LiteralPath $temporaryPath -Destination $OutputPath -Force -ErrorAction Stop
        Write-Log "Repair-DowserJson published '$OutputPath'" -Severity Verbose
    }
    catch {
        Write-Log "Repair-DowserJson could not publish '$OutputPath': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Error
        return [pscustomobject]@{ Success = $false; DocumentsWritten = 0; ErrorMessage = $_.Exception.Message }
    }

    [pscustomobject]@{ Success = $true; DocumentsWritten = $documentsWritten; ErrorMessage = $null }
}
