#Requires -Modules @{ModuleName='Pester';ModuleVersion='5.0'}

# Probe symlink capability before Describe so the boolean is available at discovery time
# (mirrors Get-DowserMap.Tests.ps1's convention). $global: is used because $script: set at
# file scope is not visible inside Pester BeforeAll blocks. The probe creates and immediately
# destroys a throwaway symlink; if the sandbox can't create one (e.g. Windows without Developer
# Mode / elevation), the one symlink-skip assertion below is skipped rather than faked.
$global:DowserTransferCanSymlink = $false
$_dtProbeTarget = Join-Path ([System.IO.Path]::GetTempPath()) 'DowserTransferProbeTarget'
$_dtProbeLink = Join-Path ([System.IO.Path]::GetTempPath()) 'DowserTransferProbeLink'
try {
    $null = New-Item -ItemType Directory -Path $_dtProbeTarget -Force -ErrorAction Stop
    $null = New-Item -ItemType SymbolicLink -Path $_dtProbeLink -Target $_dtProbeTarget -ErrorAction Stop
    $global:DowserTransferCanSymlink = (Test-Path -LiteralPath $_dtProbeLink)
}
catch {
    $global:DowserTransferCanSymlink = $false
}
finally {
    Remove-Item $_dtProbeLink -Force -ErrorAction SilentlyContinue
    Remove-Item $_dtProbeTarget -Force -Recurse -ErrorAction SilentlyContinue
}

Describe 'Start-DowserTransfer' {
    BeforeAll {
        $modulePath = Split-Path $PSScriptRoot -Parent
        Remove-Module Dowser -Force -ErrorAction SilentlyContinue
        Import-Module (Join-Path $modulePath 'Dowser.psd1') -Force -ErrorAction Stop

        $script:tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "DowserTransfer_$([System.IO.Path]::GetRandomFileName())"
        $script:sourceDir = Join-Path $script:tempRoot 'Source'
        $null = New-Item -ItemType Directory -Path $script:sourceDir -Force
        $utf8 = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText((Join-Path $script:sourceDir 'alpha.txt'), 'Alpha content for Dowser transfer testing', $utf8)
        [System.IO.File]::WriteAllText((Join-Path $script:sourceDir 'beta.txt'), 'Beta content differs from alpha entirely', $utf8)
    }

    AfterAll {
        if ($script:tempRoot -and (Test-Path -LiteralPath $script:tempRoot)) {
            Remove-Item -LiteralPath $script:tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        Remove-Variable DowserTransferCanSymlink -Scope Global -ErrorAction SilentlyContinue
    }

    It 'is exported from the module' {
        Get-Command Start-DowserTransfer -Module Dowser | Should -Not -BeNullOrEmpty
    }

    It 'performs a dry run that touches nothing on disk' {
        $destDir = Join-Path $script:tempRoot 'DryRunDest'
        $result = Start-DowserTransfer -Source $script:sourceDir -Destination $destDir -WhatIf

        $result.DryRun | Should -BeTrue
        $result.Success | Should -BeTrue
        $result.FileCount | Should -Be 2
        $result.ManifestPath | Should -BeNullOrEmpty
        Test-Path -LiteralPath $destDir | Should -BeFalse
    }

    It 'copies and verifies matching files, writing a manifest with correct hash data' {
        $destDir = Join-Path $script:tempRoot 'RealDest'
        $result = Start-DowserTransfer -Source $script:sourceDir -Destination $destDir

        $result.Success | Should -BeTrue
        $result.FailureCount | Should -Be 0
        $result.FileCount | Should -Be 2
        Test-Path -LiteralPath $result.ManifestPath | Should -BeTrue

        $manifest = Get-Content -LiteralPath $result.ManifestPath -Raw | ConvertFrom-Json
        $manifest.Items.Count | Should -Be 2

        foreach ($item in $manifest.Items) {
            $item.Success | Should -BeTrue
            Test-Path -LiteralPath $item.DestinationPath | Should -BeTrue
            (Get-FileHash -LiteralPath $item.SourcePath -Algorithm SHA256).Hash | Should -Be $item.SourceHash
            (Get-FileHash -LiteralPath $item.DestinationPath -Algorithm SHA256).Hash | Should -Be $item.DestHash
            $item.SourceHash | Should -Be $item.DestHash
        }

        [System.IO.File]::ReadAllText((Join-Path $destDir 'Source/alpha.txt')) | Should -Be 'Alpha content for Dowser transfer testing'
        [System.IO.File]::ReadAllText((Join-Path $destDir 'Source/beta.txt')) | Should -Be 'Beta content differs from alpha entirely'
    }

    It 'treats an induced destination-write race as a hard failure that is never marked verified' {
        # Start-DowserTransfer's safety contract is hash-source -> copy -> hash-dest -> compare,
        # verified only on a match. To exercise that TOCTOU defense for real (no mocking, no
        # calling the private worker directly), a background runspace continuously overwrites
        # the destination file for the whole transfer, racing the worker's own copy/verify
        # steps. That lands as either a genuine hash mismatch or a copy denied mid-write -
        # both are real induced failures, and both must never be marked verified.
        $raceRoot = Join-Path $script:tempRoot 'Race'
        $raceSourceDir = Join-Path $raceRoot 'Source'
        $null = New-Item -ItemType Directory -Path $raceSourceDir -Force
        $raceSourceFile = Join-Path $raceSourceDir 'race.bin'
        $originalBytes = New-Object byte[] (2097152)
        (New-Object Random).NextBytes($originalBytes)
        [System.IO.File]::WriteAllBytes($raceSourceFile, $originalBytes)
        $originalHash = (Get-FileHash -LiteralPath $raceSourceFile -Algorithm SHA256).Hash

        $corruptBytes = New-Object byte[] (2097152)
        (New-Object Random).NextBytes($corruptBytes)

        $destDir = Join-Path $raceRoot 'Dest'
        $destFile = Join-Path $destDir 'Source/race.bin'

        $stopFlag = [ref]$false
        $corrupter = [powershell]::Create()
        $null = $corrupter.AddScript({
            param($TargetPath, $CorruptBytes, $StopFlag)
            while (-not $StopFlag.Value) {
                try {
                    [System.IO.File]::WriteAllBytes($TargetPath, $CorruptBytes)
                } catch { }
                Start-Sleep -Milliseconds 1
            }
        }).AddArgument($destFile).AddArgument($corruptBytes).AddArgument($stopFlag)
        $handle = $corrupter.BeginInvoke()

        try {
            $result = Start-DowserTransfer -Source $raceSourceDir -Destination $destDir -ThreadCount 1
        }
        finally {
            $stopFlag.Value = $true
            try { $corrupter.EndInvoke($handle) | Out-Null } catch { }
            $corrupter.Dispose()
        }

        $result.Success | Should -BeFalse
        $result.FailureCount | Should -Be 1

        $manifest = Get-Content -LiteralPath $result.ManifestPath -Raw | ConvertFrom-Json
        $manifest.Items.Count | Should -Be 1
        $manifest.Items[0].Success | Should -BeFalse
        $manifest.Items[0].Error | Should -Not -BeNullOrEmpty

        (Get-FileHash -LiteralPath $raceSourceFile -Algorithm SHA256).Hash | Should -Be $originalHash
    }

    It 'fails loudly on insufficient destination free space before touching the destination' {
        # This exercises the shared "not enough room" failure path, not the non-Windows
        # mount-matching fix itself (DriveInfo.GetDrives() boundary-prefix match against the
        # actual filesystem backing -Destination, vs. GetPathRoot's collapsed "/"). Reproducing
        # THAT specific fix would need a second real mount point distinct from the one backing
        # this temp dir, which this sandbox does not have -- an untestable-in-this-environment
        # gap, noted here rather than silently skipped.
        $spaceRoot = Join-Path $script:tempRoot 'Space'
        $spaceSourceDir = Join-Path $spaceRoot 'Source'
        $null = New-Item -ItemType Directory -Path $spaceSourceDir -Force
        $hugeFile = Join-Path $spaceSourceDir 'huge.bin'
        $stream = [System.IO.File]::Open($hugeFile, [System.IO.FileMode]::Create)
        $stream.SetLength(10TB)
        $stream.Close()

        $destDir = Join-Path $spaceRoot 'Dest'
        $result = Start-DowserTransfer -Source $spaceSourceDir -Destination $destDir

        $result.Success | Should -BeFalse
        $result.ManifestPath | Should -BeNullOrEmpty
        Test-Path -LiteralPath $destDir | Should -BeFalse
    }

    It 'returns Success=$false when the transfer pool fails to start, instead of a false-positive empty success' {
        $destDir = Join-Path $script:tempRoot 'PoolFailDest'
        InModuleScope Dowser -Parameters @{ SourceDir = $script:sourceDir; DestDir = $destDir } {
            Mock Invoke-DowserTransferPool { [pscustomobject]@{ PoolStarted = $false; Results = @() } }

            $result = Start-DowserTransfer -Source $SourceDir -Destination $DestDir

            $result.Success | Should -BeFalse
            $result.FileCount | Should -Be 2
            $result.ManifestPath | Should -BeNullOrEmpty
        }
    }

    It 'never deletes source files after a successful real run' {
        $destDir = Join-Path $script:tempRoot 'NeverDeleteDest'
        $null = Start-DowserTransfer -Source $script:sourceDir -Destination $destDir

        Test-Path -LiteralPath (Join-Path $script:sourceDir 'alpha.txt') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:sourceDir 'beta.txt') | Should -BeTrue
    }

    It 'accepts a single bare file as -Source, exercising the non-container code path' {
        $bareFile = Join-Path $script:tempRoot 'BareFile.txt'
        [System.IO.File]::WriteAllText($bareFile, 'standalone file content', [System.Text.UTF8Encoding]::new($false))
        $destDir = Join-Path $script:tempRoot 'BareFileDest'

        $result = Start-DowserTransfer -Source $bareFile -Destination $destDir

        $result.Success | Should -BeTrue
        $result.FileCount | Should -Be 1
        $copiedPath = Join-Path $destDir 'BareFile.txt'
        Test-Path -LiteralPath $copiedPath | Should -BeTrue
        [System.IO.File]::ReadAllText($copiedPath) | Should -Be 'standalone file content'
    }

    It 'accepts multiple items piped into -Source, matching the piped .EXAMPLE usage' {
        $pipeDir = Join-Path $script:tempRoot 'PipeSource'
        $null = New-Item -ItemType Directory -Path $pipeDir -Force
        [System.IO.File]::WriteAllText((Join-Path $pipeDir 'one.txt'), 'pipe one', [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::WriteAllText((Join-Path $pipeDir 'two.txt'), 'pipe two', [System.Text.UTF8Encoding]::new($false))
        $destDir = Join-Path $script:tempRoot 'PipeDest'

        $result = Get-ChildItem -LiteralPath $pipeDir -File | Start-DowserTransfer -Destination $destDir

        $result.Success | Should -BeTrue
        $result.FileCount | Should -Be 2
        [System.IO.File]::ReadAllText((Join-Path $destDir 'one.txt')) | Should -Be 'pipe one'
        [System.IO.File]::ReadAllText((Join-Path $destDir 'two.txt')) | Should -Be 'pipe two'
    }

    It 'fails loudly pre-flight and copies nothing when two sources collide on the same destination path' {
        $collideDirA = Join-Path $script:tempRoot 'CollideA/Shared'
        $collideDirB = Join-Path $script:tempRoot 'CollideB/Shared'
        $null = New-Item -ItemType Directory -Path $collideDirA -Force
        $null = New-Item -ItemType Directory -Path $collideDirB -Force
        [System.IO.File]::WriteAllText((Join-Path $collideDirA 'same.txt'), 'from A', [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::WriteAllText((Join-Path $collideDirB 'same.txt'), 'from B', [System.Text.UTF8Encoding]::new($false))
        $destDir = Join-Path $script:tempRoot 'CollideDest'

        $result = Start-DowserTransfer -Source $collideDirA, $collideDirB -Destination $destDir

        $result.Success | Should -BeFalse
        $result.ManifestPath | Should -BeNullOrEmpty
        $result.BytesCopied | Should -Be 0
        Test-Path -LiteralPath $destDir | Should -BeFalse
    }

    It 'skips a symlink inside a source directory during recursive enumeration instead of following it' -Skip:(-not $global:DowserTransferCanSymlink) {
        $symlinkRoot = Join-Path $script:tempRoot 'SymlinkSource'
        $symlinkTarget = Join-Path $script:tempRoot 'SymlinkTarget'
        $null = New-Item -ItemType Directory -Path $symlinkRoot -Force
        $null = New-Item -ItemType Directory -Path $symlinkTarget -Force
        [System.IO.File]::WriteAllText((Join-Path $symlinkTarget 'linked.txt'), 'should never be copied', [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::WriteAllText((Join-Path $symlinkRoot 'real.txt'), 'should be copied', [System.Text.UTF8Encoding]::new($false))
        $null = New-Item -ItemType SymbolicLink -Path (Join-Path $symlinkRoot 'the-link') -Target $symlinkTarget -ErrorAction Stop

        $destDir = Join-Path $script:tempRoot 'SymlinkDest'
        $result = Start-DowserTransfer -Source $symlinkRoot -Destination $destDir

        $result.Success | Should -BeTrue
        $result.FileCount | Should -Be 1
        Test-Path -LiteralPath (Join-Path $destDir 'SymlinkSource/real.txt') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $destDir 'SymlinkSource/the-link') | Should -BeFalse
    }
}
