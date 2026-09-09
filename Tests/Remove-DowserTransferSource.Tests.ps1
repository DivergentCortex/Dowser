#Requires -Modules @{ModuleName='Pester';ModuleVersion='5.0'}

Describe 'Remove-DowserTransferSource' {
    BeforeAll {
        $modulePath = Split-Path $PSScriptRoot -Parent
        Remove-Module Dowser -Force -ErrorAction SilentlyContinue
        Import-Module (Join-Path $modulePath 'Dowser.psd1') -Force -ErrorAction Stop

        $script:tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "DowserRemoveSource_$([System.IO.Path]::GetRandomFileName())"
        $null = New-Item -ItemType Directory -Path $script:tempRoot -Force
    }

    AfterAll {
        if ($script:tempRoot -and (Test-Path -LiteralPath $script:tempRoot)) {
            Remove-Item -LiteralPath $script:tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'is exported from the module' {
        Get-Command Remove-DowserTransferSource -Module Dowser | Should -Not -BeNullOrEmpty
    }

    It 'deletes only verified entries, skips unverified ones, and re-verifies both source and destination hashes so a tampered entry is skipped while its untampered sibling is still deleted' {
        $utf8 = [System.Text.UTF8Encoding]::new($false)

        $sourceVerified = Join-Path $script:tempRoot 'verified-source.txt'
        $destVerified = Join-Path $script:tempRoot 'verified-dest.txt'
        [System.IO.File]::WriteAllText($sourceVerified, 'content that was copied and verified', $utf8)
        [System.IO.File]::WriteAllText($destVerified, 'content that was copied and verified', $utf8)
        $hashVerified = (Get-FileHash -LiteralPath $destVerified -Algorithm SHA256).Hash

        $sourceUnverified = Join-Path $script:tempRoot 'unverified-source.txt'
        $destUnverified = Join-Path $script:tempRoot 'unverified-dest.txt'
        [System.IO.File]::WriteAllText($sourceUnverified, 'content whose copy failed verification', $utf8)
        [System.IO.File]::WriteAllText($destUnverified, 'different content, never verified', $utf8)

        $sourceTampered = Join-Path $script:tempRoot 'tampered-source.txt'
        $destTampered = Join-Path $script:tempRoot 'tampered-dest.txt'
        [System.IO.File]::WriteAllText($sourceTampered, 'content that was verified but then drifted', $utf8)
        [System.IO.File]::WriteAllText($destTampered, 'content that was verified but then drifted', $utf8)
        $hashAtVerifyTime = (Get-FileHash -LiteralPath $destTampered -Algorithm SHA256).Hash
        [System.IO.File]::WriteAllText($destTampered, 'tampered after verification, before deletion pass', $utf8)

        $sourceDrifted = Join-Path $script:tempRoot 'drifted-source.txt'
        $destDrifted = Join-Path $script:tempRoot 'drifted-dest.txt'
        [System.IO.File]::WriteAllText($sourceDrifted, 'content that was verified but source then drifted', $utf8)
        [System.IO.File]::WriteAllText($destDrifted, 'content that was verified but source then drifted', $utf8)
        $hashAtSourceVerifyTime = (Get-FileHash -LiteralPath $sourceDrifted -Algorithm SHA256).Hash
        [System.IO.File]::WriteAllText($sourceDrifted, 'source modified after successful transfer, before deletion pass', $utf8)

        $manifest = [pscustomobject]@{
            GeneratedAt = (Get-Date).ToString('o')
            Destination = $script:tempRoot
            Items       = @(
                [pscustomobject]@{ Success = $true;  SourcePath = $sourceVerified;   DestinationPath = $destVerified;   SourceHash = $hashVerified;           DestHash = $hashVerified;           BytesCopied = 0; Error = $null }
                [pscustomobject]@{ Success = $false; SourcePath = $sourceUnverified; DestinationPath = $destUnverified; SourceHash = 'AAAA';                  DestHash = 'BBBB';                  BytesCopied = 0; Error = 'Hash mismatch (simulated)' }
                [pscustomobject]@{ Success = $true;  SourcePath = $sourceTampered;   DestinationPath = $destTampered;   SourceHash = $hashAtVerifyTime;       DestHash = $hashAtVerifyTime;       BytesCopied = 0; Error = $null }
                [pscustomobject]@{ Success = $true;  SourcePath = $sourceDrifted;    DestinationPath = $destDrifted;    SourceHash = $hashAtSourceVerifyTime; DestHash = $hashAtSourceVerifyTime; BytesCopied = 0; Error = $null }
            )
        }
        $manifestPath = Join-Path $script:tempRoot 'manifest.json'
        [System.IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 6), $utf8)

        $result = Remove-DowserTransferSource -ManifestPath $manifestPath -Confirm:$false

        $result.TotalEntries | Should -Be 4
        $result.DeletedCount | Should -Be 1
        $result.SkippedCount | Should -Be 1
        $result.ReVerifyFailedCount | Should -Be 2
        $result.DeleteFailedCount | Should -Be 0
        $result.Success | Should -BeFalse

        Test-Path -LiteralPath $sourceVerified | Should -BeFalse
        Test-Path -LiteralPath $sourceUnverified | Should -BeTrue
        Test-Path -LiteralPath $sourceTampered | Should -BeTrue
        Test-Path -LiteralPath $sourceDrifted | Should -BeTrue
        [System.IO.File]::ReadAllText($destTampered) | Should -Be 'tampered after verification, before deletion pass'
        [System.IO.File]::ReadAllText($sourceDrifted) | Should -Be 'source modified after successful transfer, before deletion pass'
    }
}
