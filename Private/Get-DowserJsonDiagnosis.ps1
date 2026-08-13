#Requires -Version 5.1

function Get-DowserJsonDiagnosis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    $probeReader = $null
    $stream = $null
    $textReader = $null
    $jsonReader = $null
    $firstLines = [System.Collections.Generic.List[string]]::new()
    $documents = 0
    $comments = 0
    $rootIsArray = $false
    $firstJsonTokenSeen = $false
    $rootDocumentStartLine = $null
    $multilineRootDocuments = 0

    try {
        $probeReader = [System.IO.StreamReader]::new($FilePath)
        while ($firstLines.Count -lt 3 -and -not $probeReader.EndOfStream) {
            $line = $probeReader.ReadLine()
            if (-not [string]::IsNullOrWhiteSpace($line)) {
                $firstLines.Add($line)
            }
        }
    }
    catch {
        return [pscustomobject]@{
            FilePath       = $FilePath
            Classification = 'Unreadable'
            Repairable     = $false
            RepairAction   = 'None'
            Documents      = 0
            ErrorLine      = $null
            ErrorPosition  = $null
            ErrorMessage   = $_.Exception.Message
        }
    }
    finally {
        if ($null -ne $probeReader) {
            $probeReader.Dispose()
        }
    }

    $leadingText = if ($firstLines.Count -gt 0) { $firstLines[0].Trim() } else { '' }

    if ($firstLines.Count -eq 3 -and
        $firstLines[0] -match '^=+$' -and
        $firstLines[1] -match '^RECORD [0-9]+ \(Line [0-9]+\)$' -and
        $firstLines[2] -match '^=+$') {
        return [pscustomobject]@{
            FilePath       = $FilePath
            Classification = 'RecordBannerJson'
            Repairable     = $true
            RepairAction   = 'Remove RECORD banners and write JSONL'
            Documents      = 0
            ErrorLine      = 1
            ErrorPosition  = 1
            ErrorMessage   = 'Valid JSON records are separated by non-JSON RECORD banners.'
        }
    }

    if ($leadingText -in '[USER]', '[ASSISTANT]', '[SYSTEM]') {
        return [pscustomobject]@{
            FilePath       = $FilePath
            Classification = 'TaggedTranscriptText'
            Repairable     = $true
            RepairAction   = 'Convert tagged transcript blocks to structured JSONL'
            Documents      = 0
            ErrorLine      = 1
            ErrorPosition  = 1
            ErrorMessage   = 'Tagged transcript text is not JSON or JSONL, but its USER and ASSISTANT blocks can be preserved as structured JSONL.'
        }
    }

    try {
        $stream = [System.IO.File]::OpenRead($FilePath)
        $textReader = [System.IO.StreamReader]::new($stream)
        $jsonReader = [Newtonsoft.Json.JsonTextReader]::new($textReader)
        $jsonReader.SupportMultipleContent = $true
        $jsonReader.DateParseHandling = [Newtonsoft.Json.DateParseHandling]::None

        while ($jsonReader.Read()) {
            if ($jsonReader.TokenType -eq [Newtonsoft.Json.JsonToken]::Comment) {
                $comments++
                continue
            }

            if (-not $firstJsonTokenSeen) {
                $rootIsArray = $jsonReader.TokenType -eq [Newtonsoft.Json.JsonToken]::StartArray
                $firstJsonTokenSeen = $true
            }

            if (($jsonReader.TokenType -eq [Newtonsoft.Json.JsonToken]::StartObject -or
                 $jsonReader.TokenType -eq [Newtonsoft.Json.JsonToken]::StartArray) -and
                $jsonReader.Depth -eq 0) {
                $documents++
                $rootDocumentStartLine = $jsonReader.LineNumber
                continue
            }

            if (($jsonReader.TokenType -eq [Newtonsoft.Json.JsonToken]::EndObject -or
                 $jsonReader.TokenType -eq [Newtonsoft.Json.JsonToken]::EndArray) -and
                $jsonReader.Depth -eq 0 -and
                $null -ne $rootDocumentStartLine) {
                if ($jsonReader.LineNumber -gt $rootDocumentStartLine) {
                    $multilineRootDocuments++
                }
                $rootDocumentStartLine = $null
            }
        }
    }
    catch {
        $lineNumber = if ($_.Exception.PSObject.Properties.Name -contains 'LineNumber') { $_.Exception.LineNumber } else { $null }
        $linePosition = if ($_.Exception.PSObject.Properties.Name -contains 'LinePosition') { $_.Exception.LinePosition } else { $null }
        $looksLikeJsonValue = $leadingText -match '^(?:[\[{"0-9-]|true(?:\s|$)|false(?:\s|$)|null(?:\s|$))'
        $classification = if ($looksLikeJsonValue) { 'JsonSyntaxError' } else { 'NonJsonText' }
        $message = if ($classification -eq 'NonJsonText') {
            'The file begins with non-JSON text. Its complete original text can be preserved in a structured JSONL fragment record.'
        }
        else {
            $_.Exception.Message
        }
        return [pscustomobject]@{
            FilePath       = $FilePath
            Classification = $classification
            Repairable     = $true
            RepairAction   = 'Preserve complete source text in a structured JSONL fragment record'
            Documents      = $documents
            ErrorLine      = $lineNumber
            ErrorPosition  = $linePosition
            ErrorMessage   = $message
        }
    }
    finally {
        if ($null -ne $jsonReader) { $jsonReader.Close() }
        elseif ($null -ne $textReader) { $textReader.Dispose() }
        elseif ($null -ne $stream) { $stream.Dispose() }
    }

    $classification = if ($rootIsArray) {
        'OuterArrayJson'
    }
    elseif ($comments -gt 0) {
        'JsonWithComments'
    }
    elseif ($documents -gt 1 -and $multilineRootDocuments -gt 0) {
        'JsonSequence'
    }
    elseif ($documents -gt 1) {
        'ValidJsonl'
    }
    else {
        'ValidJson'
    }

    [pscustomobject]@{
        FilePath       = $FilePath
        Classification = $classification
        Repairable     = $classification -in 'OuterArrayJson', 'JsonSequence', 'JsonWithComments'
        RepairAction   = switch ($classification) {
            'OuterArrayJson' { 'Remove only the root array wrapper and write JSONL' }
            'JsonSequence' { 'Write one compact root JSON document per JSONL line' }
            'JsonWithComments' { 'Remove JSON comments and canonicalize JSON' }
            default { 'None' }
        }
        Documents      = $documents
        ErrorLine      = $null
        ErrorPosition  = $null
        ErrorMessage   = $null
    }
}
