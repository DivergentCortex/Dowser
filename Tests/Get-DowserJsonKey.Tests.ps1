#Requires -Modules @{ModuleName='Pester';ModuleVersion='5.0'}

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent $PSScriptRoot
    $script:ManifestPath = Join-Path $script:ModuleRoot 'Dowser.psd1'
    $script:WorkDir = Join-Path ([System.IO.Path]::GetTempPath()) ("DowserJson_" + [guid]::NewGuid().Guid)

    Import-Module $script:ManifestPath -Force -ErrorAction Stop
    New-Item -ItemType Directory -Path $script:WorkDir -Force | Out-Null

    $script:JsonPath = Join-Path $script:WorkDir 'records.json'
    $script:JsonlPath = Join-Path $script:WorkDir 'events.jsonl'
    $script:CsvPath = Join-Path $script:WorkDir 'events.csv'
    $script:RecordBannerPath = Join-Path $script:WorkDir 'formatted.json'
    $script:TaggedTranscriptPath = Join-Path $script:WorkDir 'transcript.jsonl'
    $script:CommentJsonPath = Join-Path $script:WorkDir 'commented.json'
    $script:OuterArrayPath = Join-Path $script:WorkDir 'array-export.json'
    $script:JsonSequencePath = Join-Path $script:WorkDir 'pretty-sequence.jsonl'
    $script:TextFragmentPath = Join-Path $script:WorkDir 'fragment.jsonl'

    [System.IO.File]::WriteAllText(
        $script:JsonPath,
        '{"name":"one","items":[{"id":1},{"id":2}]}',
        [System.Text.UTF8Encoding]::new($false)
    )
    [System.IO.File]::WriteAllText(
        $script:JsonlPath,
        '{"name":"two","flag":true}' + [System.Environment]::NewLine + '{"name":"three","extra":null}',
        [System.Text.UTF8Encoding]::new($false)
    )
    [System.IO.File]::WriteAllText(
        $script:RecordBannerPath,
        "`n====`nRECORD 1 (Line 1)`n====`n{`"name`":`"one`"}`n====`nRECORD 2 (Line 2)`n====`n{`"name`":`"two`"}",
        [System.Text.UTF8Encoding]::new($false)
    )
    [System.IO.File]::WriteAllText(
        $script:TaggedTranscriptPath,
        "[USER]`nHello`n[ASSISTANT]`nWorld",
        [System.Text.UTF8Encoding]::new($false)
    )
    [System.IO.File]::WriteAllText(
        $script:CommentJsonPath,
        "{ // operator note`n  `"name`": `"one`"`n}",
        [System.Text.UTF8Encoding]::new($false)
    )
    [System.IO.File]::WriteAllText(
        $script:OuterArrayPath,
        '[{"id":1,"interactions":[{"speaker":"human"}]},{"id":2,"contextFiles":[{"path":"/tmp/example"}]}]',
        [System.Text.UTF8Encoding]::new($false)
    )
    [System.IO.File]::WriteAllText(
        $script:JsonSequencePath,
        "{`n  `"id`": 1,`n  `"content`": `"first`"`n}`n{`n  `"id`": 2,`n  `"content`": `"second`"`n}",
        [System.Text.UTF8Encoding]::new($false)
    )
    [System.IO.File]::WriteAllText(
        $script:TextFragmentPath,
        'middle of an exported assistant response' + [System.Environment]::NewLine + 'with its exact text preserved',
        [System.Text.UTF8Encoding]::new($false)
    )
}

AfterAll {
    if (Test-Path -LiteralPath $script:WorkDir) {
        Remove-Item -LiteralPath $script:WorkDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Get-DowserJsonKey' {
    It 'is exported from the module' {
        Get-Command Get-DowserJsonKey -Module Dowser | Should -Not -BeNullOrEmpty
    }

    It 'counts nested keys without deserializing the JSON document' {
        $rows = @(Get-DowserJsonKey -Path $script:JsonPath)
        $nested = $rows | Where-Object { $_.KeyPath -eq '$.items[].id' }

        $nested | Should -Not -BeNullOrEmpty
        $nested.OccurrenceCount | Should -Be 2
        $nested.Documents | Should -Be 1
    }

    It 'compares keys across JSON and JSONL files' {
        $rows = @(Get-DowserJsonKey -Path $script:JsonPath, $script:JsonlPath -Compare -ShowKeyComparison -IncludeFiles)
        $name = $rows | Where-Object { $_.KeyPath -eq '$.name' }
        $extra = $rows | Where-Object { $_.KeyPath -eq '$.extra' }

        $name.FileCount | Should -Be 2
        $extra.FileCount | Should -Be 1
        $extra.MissingFromFiles | Should -Match 'records\.json'
    }

    It 'reports file schemas and their differences from the dominant schema' {
        $rows = @(Get-DowserJsonKey -Path $script:JsonPath, $script:JsonlPath -Compare -Validation)
        $global:DowserJsonLastComparison.Count | Should -Be $rows.Count
        $global:DowserJsonLastValidation.Count | Should -Be 5
        ($global:DowserJsonLastValidation | Where-Object { $_.KeyPath -eq '$.name' }).Classification | Should -Be 'AlwaysPresent'
        $summary = $rows | Where-Object { $_.ResultType -eq 'DirectorySummary' }
        $dominant = $rows | Where-Object { $_.ResultType -eq 'SchemaProfile' -and $_.Role -eq 'Dominant' }
        $variant = $rows | Where-Object { $_.ResultType -eq 'SchemaProfile' -and $_.Role -eq 'Variant' }

        $summary.FilesScanned | Should -Be 2
        $summary.DistinctSchemas | Should -Be 2
        $summary.FilesDifferentFromDominant | Should -Be 1
        $summary.DistinctKeyPaths | Should -Be 5
        $dominant.FileCount | Should -Be 1
        $variant.FileCount | Should -Be 1
        ($rows | Where-Object { $_.ResultType -eq 'KeyComparison' }) | Should -BeNullOrEmpty
    }

    It 'uses one bounded JSON worker when requested' {
        $rows = @(Get-DowserJsonKey -Path $script:JsonPath, $script:JsonlPath -Compare -ThreadCount 1)
        $summary = $rows | Where-Object { $_.ResultType -eq 'DirectorySummary' }

        $summary.FilesScanned | Should -Be 2
        $summary.DistinctKeyPaths | Should -Be 5
    }
}

Describe 'Export-DowserJsonAssessment' {
    It 'writes an assessment report with all key validation rows' {
        $reportDirectory = Join-Path $script:WorkDir 'assessment'
        $result = Export-DowserJsonAssessment -Path $script:WorkDir -OutputDirectory $reportDirectory

        Test-Path -LiteralPath $result.SummaryPath | Should -BeTrue
        Test-Path -LiteralPath $result.SchemaProfilesPath | Should -BeTrue
        (Import-Csv -LiteralPath $result.KeyValidationPath).Count | Should -Be 12
    }
}

Describe 'Export-DowserJsonCsv' {
    It 'is exported from the module' {
        Get-Command Export-DowserJsonCsv -Module Dowser | Should -Not -BeNullOrEmpty
    }

    It 'writes scalar JSONL values to an Excel-compatible CSV' {
        $result = Export-DowserJsonCsv -Path $script:JsonlPath -OutputPath $script:CsvPath
        $rows = @(Import-Csv -LiteralPath $script:CsvPath)

        $result.Documents | Should -Be 2
        $result.ValuesWritten | Should -Be 4
        $rows.Count | Should -Be 4
        ($rows | Where-Object { $_.KeyPath -eq '$.extra' }).Value | Should -Be ''
    }
}

Describe 'Test-DowserJson and Repair-DowserJson' {
    It 'distinguishes repairable RECORD banners from tagged transcript text' {
        $rows = @(Test-DowserJson -Path $script:RecordBannerPath, $script:TaggedTranscriptPath)
        ($rows | Where-Object { $_.FilePath -eq $script:RecordBannerPath }).Classification | Should -Be 'RecordBannerJson'
        ($rows | Where-Object { $_.FilePath -eq $script:RecordBannerPath }).Repairable | Should -BeTrue
        ($rows | Where-Object { $_.FilePath -eq $script:TaggedTranscriptPath }).Classification | Should -Be 'TaggedTranscriptText'
        ($rows | Where-Object { $_.FilePath -eq $script:TaggedTranscriptPath }).Repairable | Should -BeTrue
    }

    It 'repairs independent files through bounded workers' {
        $results = @(Repair-DowserJson -Path $script:RecordBannerPath, $script:TaggedTranscriptPath, $script:OuterArrayPath -ThreadCount 3 -Force)

        $results.Count | Should -Be 3
        ($results | Where-Object { $_.Result -eq 'Repaired' }).Count | Should -Be 3
        ($results | Where-Object { -not (Test-Path -LiteralPath $_.OutputPath) }).Count | Should -Be 0
        ($results | Where-Object { -not $_.SourceMoved }).Count | Should -Be 0
        ($results | Where-Object { -not (Test-Path -LiteralPath $_.TriagePath) }).Count | Should -Be 0

        foreach ($result in $results) {
            Move-Item -LiteralPath $result.TriagePath -Destination $result.FilePath -ErrorAction Stop
        }
        $results.OutputPath | Remove-Item -Force
    }

    It 'converts tagged transcript blocks to structured JSONL without losing content' {
        $result = Repair-DowserJson -Path $script:TaggedTranscriptPath
        $expectedPath = Join-Path $script:WorkDir 'JSON-Repaired/transcript.repaired.jsonl'
        $rows = @(Get-Content -LiteralPath $expectedPath | ConvertFrom-Json)

        $result.Result | Should -Be 'Repaired'
        $rows.Count | Should -Be 2
        $rows[0].role | Should -Be 'user'
        $rows[0].content | Should -Be 'Hello'
        $rows[1].role | Should -Be 'assistant'
        $rows[1].content | Should -Be 'World'
        $rows[0].source_format | Should -Be 'tagged_transcript_text'
        (Test-DowserJson -Path $expectedPath).Classification | Should -Be 'ValidJsonl'
    }

    It 'preserves bracket-led source text instead of treating it as a transcript tag' {
        $bracketedPath = Join-Path $script:WorkDir 'bracketed-code.jsonl'
        $bracketedText = "[area]['dist_patches'].append(mod)" + [System.Environment]::NewLine + 'report.append(value)'
        [System.IO.File]::WriteAllText($bracketedPath, $bracketedText, [System.Text.UTF8Encoding]::new($false))
        (Test-DowserJson -Path $bracketedPath).Classification | Should -Be 'JsonSyntaxError'
        $result = Repair-DowserJson -Path $bracketedPath
        $row = Get-Content -LiteralPath (Join-Path $script:WorkDir 'JSON-Repaired/bracketed-code.repaired.jsonl') | ConvertFrom-Json

        $result.Result | Should -Be 'Repaired'
        $row.source_format | Should -Be 'unstructured_text_fragment'
        $row.content | Should -Be $bracketedText
    }

    It 'preserves an untagged fragment as one structured JSONL record' {
        (Test-DowserJson -Path $script:TextFragmentPath).Classification | Should -Be 'NonJsonText'
        $result = Repair-DowserJson -Path $script:TextFragmentPath
        $expectedPath = Join-Path $script:WorkDir 'JSON-Repaired/fragment.repaired.jsonl'
        $row = Get-Content -LiteralPath $expectedPath | ConvertFrom-Json

        $result.Result | Should -Be 'Repaired'
        $row.source_format | Should -Be 'unstructured_text_fragment'
        $row.content | Should -Be "middle of an exported assistant response$([System.Environment]::NewLine)with its exact text preserved"
        (Test-DowserJson -Path $expectedPath).Classification | Should -Be 'ValidJson'
    }

    It 'writes a repaired RECORD banner copy beside its source' {
        $result = Repair-DowserJson -Path $script:RecordBannerPath
        $expectedPath = Join-Path $script:WorkDir 'JSON-Repaired/formatted.repaired.jsonl'

        $result.Result | Should -Be 'Repaired'
        $result.OutputPath | Should -Be $expectedPath
        (Get-Content -LiteralPath $expectedPath).Count | Should -Be 2
        (Test-DowserJson -Path $expectedPath).Classification | Should -Be 'ValidJsonl'
    }

    It 'removes only a root array wrapper when converting to JSONL' {
        (Test-DowserJson -Path $script:OuterArrayPath).Classification | Should -Be 'OuterArrayJson'
        $result = Repair-DowserJson -Path $script:OuterArrayPath
        $expectedPath = Join-Path $script:WorkDir 'JSON-Repaired/array-export.repaired.jsonl'
        $rows = @(Get-Content -LiteralPath $expectedPath | ConvertFrom-Json)

        $result.Result | Should -Be 'Repaired'
        $rows.Count | Should -Be 2
        $rows[0].interactions[0].speaker | Should -Be 'human'
        $rows[1].contextFiles[0].path | Should -Be '/tmp/example'
        (Test-DowserJson -Path $expectedPath).Classification | Should -Be 'ValidJsonl'
    }

    It 'triages a lingering source when its repaired copy already exists' {
        $pendingPath = Join-Path $script:WorkDir 'pending-triage.json'
        $pendingText = "{ // pending triage" + [Environment]::NewLine + '  "id": 7' + [Environment]::NewLine + "}"
        [System.IO.File]::WriteAllText($pendingPath, $pendingText, [System.Text.UTF8Encoding]::new($false))

        $initial = Repair-DowserJson -Path $pendingPath
        Move-Item -LiteralPath $initial.TriagePath -Destination $pendingPath -ErrorAction Stop
        $result = Repair-DowserJson -Path $pendingPath

        $result.Result | Should -Be 'TriagedExistingRepair'
        $result.SourceMoved | Should -BeTrue
        Test-Path -LiteralPath $result.OutputPath | Should -BeTrue
        Test-Path -LiteralPath $result.TriagePath | Should -BeTrue
        Test-Path -LiteralPath $pendingPath | Should -BeFalse
    }

    It 'normalizes a pretty-printed JSON sequence into physical JSONL records' {
        (Test-DowserJson -Path $script:JsonSequencePath).Classification | Should -Be 'JsonSequence'
        $result = Repair-DowserJson -Path $script:JsonSequencePath
        $expectedPath = Join-Path $script:WorkDir 'JSON-Repaired/pretty-sequence.repaired.jsonl'
        $lines = @(Get-Content -LiteralPath $expectedPath)

        $result.Result | Should -Be 'Repaired'
        $lines.Count | Should -Be 2
        ($lines | ForEach-Object { $_ | ConvertFrom-Json }).content | Should -Be @('first', 'second')
        (Test-DowserJson -Path $expectedPath).Classification | Should -Be 'ValidJsonl'
    }
}
