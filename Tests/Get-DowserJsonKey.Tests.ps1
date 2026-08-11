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
        $rows = @(Get-DowserJsonKey -Path $script:WorkDir -Compare)
        $name = $rows | Where-Object { $_.KeyPath -eq '$.name' }
        $extra = $rows | Where-Object { $_.KeyPath -eq '$.extra' }

        $name.FileCount | Should -Be 2
        $extra.FileCount | Should -Be 1
        $extra.MissingFromFiles | Should -Match 'records\.json'
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
