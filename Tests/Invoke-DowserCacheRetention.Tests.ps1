#Requires -Modules @{ModuleName='Pester';ModuleVersion='5.0'}
<#
.SYNOPSIS
    Pester coverage for Invoke-DowserCacheRetention and the private helpers it is built from.

.DESCRIPTION
    Every test runs against a fixture cache tree under the temp folder; nothing real is read for
    removal or deleted. The fixture holds one plugin with versions chosen so each keep reason and
    the two removable folders are known:

        1.0.1  removable, 1010 bytes
        1.0.2  named by installPath in the fixture manifest
        1.0.3  a running process has it as its working directory
        1.0.4  removable, 2010 bytes, holds a link out to a folder with a canary file
        1.0.5  a file in it was written just now
        1.0.6  newest but one
        1.0.7  newest
        local  no numeric order
        0.9.0  a symlink to the canary folder

.EXAMPLE
    Invoke-Pester -Path ./Tests/Invoke-DowserCacheRetention.Tests.ps1 -Output Detailed
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $script:ModuleRoot '_modules/ps/DivergentCortex.Witness') -ErrorAction Stop
    Remove-Module Dowser -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $script:ModuleRoot 'Dowser.psd1') -Force -ErrorAction Stop

    $script:OnLinux = ($IsWindows -eq $false) -and ($IsMacOS -ne $true)
    $script:Work = Join-Path ([System.IO.Path]::GetTempPath()) ("dowserretention_" + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $script:Work -Force
    $script:Holders = [System.Collections.Generic.List[object]]::new()

    # builds a fresh cache tree, manifest, rule file and running holder, and returns their paths
    $script:NewFixture = {
        param([string]$Name)
        $base = Join-Path $script:Work $Name
        $root = Join-Path $base 'cache'
        $outside = Join-Path $base 'outside'
        $plugin = Join-Path (Join-Path $root 'mk') 'plugA'
        $null = New-Item -ItemType Directory -Path $outside, $plugin -Force
        [System.IO.File]::WriteAllBytes((Join-Path $outside 'canary.txt'), [byte[]]::new(7))
        $old = (Get-Date).AddDays(-3)
        $sizes = [ordered]@{ '1.0.1' = 1000; '1.0.2' = 1500; '1.0.3' = 1500; '1.0.4' = 2000; '1.0.5' = 1500; '1.0.6' = 1500; '1.0.7' = 1500; 'local' = 1500 }
        foreach ($version in $sizes.Keys) {
            $bin = Join-Path (Join-Path $plugin $version) 'bin'
            $null = New-Item -ItemType Directory -Path $bin -Force
            [System.IO.File]::WriteAllBytes((Join-Path $bin 'a.bin'), [byte[]]::new($sizes[$version]))
            [System.IO.File]::WriteAllBytes((Join-Path (Join-Path $plugin $version) 'readme.txt'), [byte[]]::new(10))
            if ($version -ne '1.0.5') {
                foreach ($file in Get-ChildItem -LiteralPath (Join-Path $plugin $version) -Recurse -File) { $file.LastWriteTime = $old }
            }
        }
        $null = New-Item -ItemType SymbolicLink -Path (Join-Path $plugin '0.9.0') -Target $outside
        $null = New-Item -ItemType SymbolicLink -Path (Join-Path (Join-Path (Join-Path $plugin '1.0.4') 'bin') 'linkout') -Target $outside

        $manifest = Join-Path $base 'installed_plugins.json'
        $installJson = @{ version = 2; plugins = @{ 'plugA@mk' = @(@{ installPath = (Join-Path $plugin '1.0.2') }) } } | ConvertTo-Json -Depth 5
        [System.IO.File]::WriteAllText($manifest, $installJson)

        $config = Join-Path $base 'rules.psd1'
        [System.IO.File]::WriteAllText($config, "@{ Rules = @(@{ Name = 'Fixture'; Type = 'VersionedCache'; Root = '$root'; Marketplaces = @('mk'); Plugins = @('plugA'); KeepNewest = 2; InstalledManifest = '$manifest'; QuietMinutes = 60 }) }")

        if ($script:OnLinux) {
            $holder = Start-Process -FilePath 'sleep' -ArgumentList '600' -WorkingDirectory (Join-Path $plugin '1.0.3') -PassThru
            $script:Holders.Add($holder)
        }
        [pscustomobject]@{ Base = $base; Root = $root; Plugin = $plugin; Outside = $outside; Manifest = $manifest; Config = $config }
    }

    # a seat as it really is: started once, holds nothing under the cache afterwards, so only its start time places it.
    # versions 1.0.1 to 1.0.3 exist before the seat starts, 1.0.4 to 1.0.6 after
    $script:NewSeatFixture = {
        param([string]$Name, [bool]$WithSeatNames)
        $base = Join-Path $script:Work $Name
        $root = Join-Path $base 'cache'
        $plugin = Join-Path (Join-Path $root 'mk') 'plugS'
        $null = New-Item -ItemType Directory -Path $plugin -Force
        $old = (Get-Date).AddDays(-3)
        $addVersion = {
            param($version)
            $folder = Join-Path $plugin $version
            $null = New-Item -ItemType Directory -Path $folder -Force
            $file = Join-Path $folder 'a.bin'
            [System.IO.File]::WriteAllBytes($file, [byte[]]::new(100))
            (Get-Item -LiteralPath $file).LastWriteTime = $old
        }
        foreach ($version in '1.0.1', '1.0.2', '1.0.3') { & $addVersion $version }
        $seatName = 'dowserseat' + [guid]::NewGuid().ToString('N').Substring(0, 8)
        $seatProgram = Join-Path $base $seatName
        $null = New-Item -ItemType SymbolicLink -Path $seatProgram -Target (Get-Command sleep -CommandType Application | Select-Object -First 1).Source
        $holder = Start-Process -FilePath $seatProgram -ArgumentList '600' -WorkingDirectory $script:Work -PassThru
        $script:Holders.Add($holder)
        Start-Sleep -Milliseconds 3500
        foreach ($version in '1.0.4', '1.0.5', '1.0.6') { & $addVersion $version }
        $seatLine = if ($WithSeatNames) { "SeatProcessNames = @('$seatName'); " } else { '' }
        $config = Join-Path $base 'rules.psd1'
        [System.IO.File]::WriteAllText($config, "@{ Rules = @(@{ Name = 'Seat'; Type = 'VersionedCache'; Root = '$root'; ${seatLine}Marketplaces = @('mk'); Plugins = @('plugS'); KeepNewest = 2; QuietMinutes = 0 }) }")
        [pscustomobject]@{ Base = $base; Root = $root; Plugin = $plugin; Config = $config; SeatName = $seatName; Holder = $holder }
    }
}

AfterAll {
    foreach ($holder in $script:Holders) {
        Stop-Process -Id $holder.Id -Force -ErrorAction SilentlyContinue
    }
    if ($script:Work -and (Test-Path -LiteralPath $script:Work)) {
        Remove-Item -LiteralPath $script:Work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Invoke-DowserCacheRetention preview' -Skip:(-not ($IsWindows -eq $false -and $IsMacOS -ne $true)) {
    BeforeAll {
        $script:Fx = & $script:NewFixture 'preview'
        $script:Run = Invoke-DowserCacheRetention -ConfigPath $script:Fx.Config
        $script:ByVersion = @{}
        foreach ($row in $script:Run.Folders) { $script:ByVersion[$row.Version] = $row }
    }

    It 'reports a successful preview with exit code 0' {
        $script:Run.Mode | Should -Be 'Preview'
        $script:Run.Success | Should -BeTrue
        $script:Run.ExitCode | Should -Be 0
    }

    It 'marks exactly the two stale versions for removal' {
        @($script:Run.Folders | Where-Object { $_.Decision -eq 'Remove' } | ForEach-Object { $_.Version } | Sort-Object) | Should -Be @('1.0.1', '1.0.4')
        $script:Run.CandidateCount | Should -Be 2
    }

    It 'sizes the candidates' {
        $script:ByVersion['1.0.1'].SizeBytes | Should -Be 1010
        $script:ByVersion['1.0.4'].SizeBytes | Should -Be 2010
        $script:Run.CandidateBytes | Should -Be 3020
    }

    It 'keeps each protected version for the right reason' {
        $script:ByVersion['1.0.2'].Reasons | Should -Contain 'Installed'
        $script:ByVersion['1.0.3'].Reasons | Should -Contain 'InUse'
        $script:ByVersion['1.0.5'].Reasons | Should -Contain 'RecentlyWritten'
        $script:ByVersion['1.0.6'].Reasons | Should -Contain 'Newest'
        $script:ByVersion['1.0.7'].Reasons | Should -Contain 'Newest'
        $script:ByVersion['local'].Reasons | Should -Contain 'UnrankableVersion'
        $script:ByVersion['0.9.0'].Reasons | Should -Contain 'Symlink'
    }

    It 'deletes nothing in preview' {
        foreach ($version in '1.0.1', '1.0.4') {
            Test-Path -LiteralPath (Join-Path $script:Fx.Plugin $version) | Should -BeTrue
        }
        $script:Run.RemovedCount | Should -Be 0
    }
}

Describe 'Invoke-DowserCacheRetention -Remove' -Skip:(-not ($IsWindows -eq $false -and $IsMacOS -ne $true)) {
    It 'with -WhatIf removes nothing and counts each folder as skipped' {
        $fx = & $script:NewFixture 'whatif'
        $run = Invoke-DowserCacheRetention -ConfigPath $fx.Config -Remove -WhatIf
        $run.RemovedCount | Should -Be 0
        $run.SkippedCount | Should -Be 2
        Test-Path -LiteralPath (Join-Path $fx.Plugin '1.0.1') | Should -BeTrue
    }

    It 'removes only the stale versions and never follows a link' {
        $fx = & $script:NewFixture 'remove'
        $run = Invoke-DowserCacheRetention -ConfigPath $fx.Config -Remove -Confirm:$false
        $run.RemovedCount | Should -Be 2
        $run.FreedBytes | Should -Be 3020
        $run.ExitCode | Should -Be 0
        Test-Path -LiteralPath (Join-Path $fx.Plugin '1.0.1') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $fx.Plugin '1.0.4') | Should -BeFalse
        foreach ($kept in '1.0.2', '1.0.3', '1.0.5', '1.0.6', '1.0.7', 'local', '0.9.0') {
            Test-Path -LiteralPath (Join-Path $fx.Plugin $kept) | Should -BeTrue -Because "$kept must survive"
        }
        Test-Path -LiteralPath (Join-Path $fx.Outside 'canary.txt') | Should -BeTrue -Because 'a link inside a removed folder is never followed'
    }

    It 'removes nothing and reports a failure when the installed manifest cannot be read' {
        $fx = & $script:NewFixture 'nomanifest'
        Remove-Item -LiteralPath $fx.Manifest -Force
        $run = Invoke-DowserCacheRetention -ConfigPath $fx.Config -Remove -Confirm:$false
        $run.RemovedCount | Should -Be 0
        $run.Success | Should -BeFalse
        $run.ExitCode | Should -BeGreaterThan 0
        Test-Path -LiteralPath (Join-Path $fx.Plugin '1.0.1') | Should -BeTrue
    }
}

Describe 'Invoke-DowserCacheRetention disk threshold and input handling' {
    It 'reports a breach with exit code 112 when free space is below the minimum' {
        $config = Join-Path $script:Work 'disk-breach.psd1'
        [System.IO.File]::WriteAllText($config, "@{ Rules = @(@{ Name = 'Disk'; Type = 'DiskThreshold'; Path = '$($script:Work)'; MinFree = '9PB' }) }")
        $run = Invoke-DowserCacheRetention -ConfigPath $config
        $run.DiskBreachCount | Should -Be 1
        $run.DiskChecks[0].Breached | Should -BeTrue
        $run.ExitCode | Should -Be 112
    }

    It 'reports no breach and exit code 0 when free space is above the minimum' {
        $config = Join-Path $script:Work 'disk-ok.psd1'
        [System.IO.File]::WriteAllText($config, "@{ Rules = @(@{ Name = 'Disk'; Type = 'DiskThreshold'; Path = '$($script:Work)'; MinFree = '1' }) }")
        $run = Invoke-DowserCacheRetention -ConfigPath $config
        $run.DiskBreachCount | Should -Be 0
        $run.DiskChecks[0].FreeBytes | Should -BeGreaterThan 0
        $run.ExitCode | Should -Be 0
    }

    It 'returns a failed result and a nonzero exit code for a missing rule file, without throwing' {
        { $script:Missing = Invoke-DowserCacheRetention -ConfigPath (Join-Path $script:Work 'no-such.psd1') } | Should -Not -Throw
        $script:Missing.Success | Should -BeFalse
        $script:Missing.ExitCode | Should -BeGreaterThan 0
    }

    It 'reports an unknown -RuleName as a failure' {
        $config = Join-Path $script:Work 'disk-ok.psd1'
        $run = Invoke-DowserCacheRetention -ConfigPath $config -RuleName 'NoSuchRule'
        $run.Success | Should -BeFalse
        $run.ExitCode | Should -Be 13
    }

    It 'rejects an empty -ConfigPath at parameter binding' {
        { Invoke-DowserCacheRetention -ConfigPath '' } | Should -Throw
    }

    It 'loads the shipped rule file with no rejected rule' {
        $loaded = InModuleScope 'Dowser' { Get-DowserRetentionRule -ConfigPath (Join-Path $script:DowserRoot 'Config/CacheRetentionRules.psd1') }
        $loaded.Success | Should -BeTrue
        @($loaded.Rules).Count | Should -Be 3
    }
}

Describe 'Cache retention helpers' {
    It 'orders dotted versions numerically and gives other text no key' {
        InModuleScope 'Dowser' {
            (Get-DowserVersionKey -Version '2026.11.16.8572') | Should -BeGreaterThan (Get-DowserVersionKey -Version '2026.11.16.858')
            (Get-DowserVersionKey -Version '1.10') | Should -BeGreaterThan (Get-DowserVersionKey -Version '1.9')
            Get-DowserVersionKey -Version 'e3ce52391a03' | Should -BeNullOrEmpty
            Get-DowserVersionKey -Version 'local' | Should -BeNullOrEmpty
        }
    }

    It 'rejects a rule whose plugin name steps out of its root' {
        $config = Join-Path $script:Work 'traversal.psd1'
        [System.IO.File]::WriteAllText($config, "@{ Rules = @(@{ Name = 'Bad'; Type = 'VersionedCache'; Root = '$($script:Work)'; Marketplaces = @('mk'); Plugins = @('..'); KeepNewest = 2 }, @{ Name = 'Bad2'; Type = 'VersionedCache'; Root = '$($script:Work)'; Marketplaces = @('mk'); Plugins = @('a/b'); KeepNewest = 2 }) }")
        $loaded = InModuleScope 'Dowser' -Parameters @{ Config = $config } -ScriptBlock { param($Config) Get-DowserRetentionRule -ConfigPath $Config }
        $loaded.Success | Should -BeFalse
        @($loaded.Rules).Count | Should -Be 0
        @($loaded.Rejected) | Should -Be @('Bad', 'Bad2')
    }

    It 'finds the path a running process holds as its working directory' -Skip:(-not ($IsWindows -eq $false -and $IsMacOS -ne $true)) {
        $fx = & $script:NewFixture 'procscan'
        $scan = InModuleScope 'Dowser' -Parameters @{ Root = $fx.Root } -ScriptBlock { param($Root) Get-DowserActiveProcessPath -RootPrefix $Root }
        $scan.Success | Should -BeTrue
        @($scan.Paths | Where-Object { $_ -like "*/1.0.3" }).Count | Should -BeGreaterThan 0
    }

    It 'reports the filesystem holding a path' {
        $space = InModuleScope 'Dowser' -Parameters @{ Path = $script:Work } -ScriptBlock { param($Path) Get-DowserFilesystemSpace -Path $Path }
        $space.Success | Should -BeTrue
        $space.FreeBytes | Should -BeGreaterThan 0
        $space.TotalBytes | Should -BeGreaterOrEqual $space.FreeBytes
    }

    It 'refuses to delete a folder that is not three levels under the root' {
        $target = Join-Path $script:Work 'guarded'
        $null = New-Item -ItemType Directory -Path $target -Force
        $result = InModuleScope 'Dowser' -Parameters @{ Path = $target; Root = $script:Work } -ScriptBlock { param($Path, $Root) Remove-DowserCacheVersion -Path $Path -Root $Root }
        $result.Success | Should -BeFalse
        $result.Reason | Should -Be 'OutsideRuleRoot'
        Test-Path -LiteralPath $target | Should -BeTrue
    }

    It 'refuses to delete a symlink at the version level' -Skip:(-not ($IsWindows -eq $false -and $IsMacOS -ne $true)) {
        $fx = & $script:NewFixture 'linkguard'
        $link = Join-Path $fx.Plugin '0.9.0'
        $result = InModuleScope 'Dowser' -Parameters @{ Path = $link; Root = $fx.Root } -ScriptBlock { param($Path, $Root) Remove-DowserCacheVersion -Path $Path -Root $Root }
        $result.Success | Should -BeFalse
        $result.Reason | Should -Be 'IsSymlink'
        Test-Path -LiteralPath (Join-Path $fx.Outside 'canary.txt') | Should -BeTrue
    }

    It 'maps a breached threshold to ERROR_DISK_FULL through the exit-code mapper' {
        InModuleScope 'Dowser' { Get-WindowsErrorCode -HResult 0x80070070 | Should -Be 112 }
    }

    It 'ships the claude rule with the ravens link as a root spelling and the seat program names' {
        $loaded = InModuleScope 'Dowser' { Get-DowserRetentionRule -ConfigPath (Join-Path $script:DowserRoot 'Config/CacheRetentionRules.psd1') }
        $claude = $loaded.Rules | Where-Object { $_.Name -eq 'ClaudePluginCache' }
        $codex = $loaded.Rules | Where-Object { $_.Name -eq 'CodexPluginCache' }
        $claude.SeatProcessNames | Should -Contain 'claude'
        $claude.RootAliases | Should -Contain (Join-Path $HOME '.claude/ravens/plugins/cache')
        $codex.SeatProcessNames | Should -Contain 'codex'
    }
}

Describe 'Seat version attribution' {
    BeforeAll {
        $script:Hold = InModuleScope 'Dowser' {
            $day0 = [datetime]::new(2026, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc)
            $versions = 1..6 | ForEach-Object { [pscustomobject]@{ Version = "1.0.$_"; VersionKey = Get-DowserVersionKey -Version "1.0.$_"; BirthUtc = $day0.AddDays($_) } }
            $seatAt = { param($days) [pscustomobject]@{ StartKnown = $true; StartUtc = $day0.AddDays($days) } }
            $unknownBirth = @($versions | ForEach-Object { [pscustomobject]@{ Version = $_.Version; VersionKey = $_.VersionKey; BirthUtc = [datetime]::new(1601, 1, 1) } })
            @{
                Middle       = Get-DowserSeatVersionHold -Version $versions -Seat @(& $seatAt 3.5)
                BeforeAll    = Get-DowserSeatVersionHold -Version $versions -Seat @(& $seatAt 0.5)
                AfterAll     = Get-DowserSeatVersionHold -Version $versions -Seat @(& $seatAt 30)
                Two          = Get-DowserSeatVersionHold -Version $versions -Seat @((& $seatAt 1.5), (& $seatAt 4.5))
                NoSeat       = Get-DowserSeatVersionHold -Version $versions -Seat @()
                StartUnknown = Get-DowserSeatVersionHold -Version $versions -Seat @((& $seatAt 3.5), [pscustomobject]@{ StartKnown = $false; StartUtc = $null })
                BirthUnknown = Get-DowserSeatVersionHold -Version $unknownBirth -Seat @(& $seatAt 3.5)
            }
        }
    }

    It 'holds the newest version the cache had at the seat start and the next older one' {
        $script:Hold.Middle.AllHeld | Should -BeFalse
        @($script:Hold.Middle.HeldVersions | Sort-Object) | Should -Be @('1.0.2', '1.0.3')
    }

    It 'holds the oldest version when the seat started before every remaining version' {
        @($script:Hold.BeforeAll.HeldVersions) | Should -Be @('1.0.1')
    }

    It 'holds the newest two when the seat started after every version' {
        @($script:Hold.AfterAll.HeldVersions | Sort-Object) | Should -Be @('1.0.5', '1.0.6')
    }

    It 'unions the versions of several seats' {
        @($script:Hold.Two.HeldVersions | Sort-Object) | Should -Be @('1.0.1', '1.0.3', '1.0.4')
    }

    It 'holds nothing when no seat runs' {
        $script:Hold.NoSeat.AllHeld | Should -BeFalse
        @($script:Hold.NoSeat.HeldVersions).Count | Should -Be 0
    }

    It 'holds every version when a seat start time is unreadable' {
        $script:Hold.StartUnknown.AllHeld | Should -BeTrue
        $script:Hold.StartUnknown.Reason | Should -Be 'SeatStartUnknown'
    }

    It 'holds every version when a folder has no usable creation time' {
        $script:Hold.BirthUnknown.AllHeld | Should -BeTrue
        $script:Hold.BirthUnknown.Reason | Should -Be 'BirthTimeUnknown'
    }
}

Describe 'Invoke-DowserCacheRetention running seats' -Skip:(-not ($IsWindows -eq $false -and $IsMacOS -ne $true)) {
    It 'keeps the version a seat started on and the one before it, although both are older than the newest two' {
        $fx = & $script:NewSeatFixture 'seat' $true
        $run = Invoke-DowserCacheRetention -ConfigPath $fx.Config
        $byVersion = @{}
        foreach ($row in $run.Folders) { $byVersion[$row.Version] = $row }
        @($run.Folders | Where-Object { $_.Decision -eq 'Remove' } | ForEach-Object { $_.Version } | Sort-Object) | Should -Be @('1.0.1', '1.0.4')
        $byVersion['1.0.3'].Reasons | Should -Contain 'InUseByStart'
        $byVersion['1.0.2'].Reasons | Should -Contain 'InUseByStart'
        $byVersion['1.0.5'].Reasons | Should -Contain 'Newest'
    }

    It 'marks the seat versions for removal when the rule names no seat' {
        $fx = & $script:NewSeatFixture 'noseat' $false
        $run = Invoke-DowserCacheRetention -ConfigPath $fx.Config
        @($run.Folders | Where-Object { $_.Decision -eq 'Remove' } | ForEach-Object { $_.Version } | Sort-Object) | Should -Be @('1.0.1', '1.0.2', '1.0.3', '1.0.4')
    }

    It 'deletes only the versions no seat started on in a real removal' {
        $fx = & $script:NewSeatFixture 'seatremove' $true
        $run = Invoke-DowserCacheRetention -ConfigPath $fx.Config -Remove -Confirm:$false
        $run.RemovedCount | Should -Be 2
        foreach ($gone in '1.0.1', '1.0.4') { Test-Path -LiteralPath (Join-Path $fx.Plugin $gone) | Should -BeFalse }
        foreach ($kept in '1.0.2', '1.0.3', '1.0.5', '1.0.6') { Test-Path -LiteralPath (Join-Path $fx.Plugin $kept) | Should -BeTrue -Because "$kept must survive" }
    }

    It 'reports a running seat from the process scan with its start time' {
        $fx = & $script:NewSeatFixture 'seatscan' $true
        $scan = InModuleScope 'Dowser' -Parameters @{ Root = $fx.Root; Name = $fx.SeatName } -ScriptBlock { param($Root, $Name) Get-DowserActiveProcessPath -RootPrefix $Root -SeatName $Name }
        @($scan.Seats).Count | Should -Be 1
        $scan.Seats[0].StartKnown | Should -BeTrue
        $scan.Seats[0].StartUtc | Should -BeLessThan ([datetime]::UtcNow)
        $scan.Seats[0].StartUtc | Should -BeGreaterThan ([datetime]::UtcNow.AddMinutes(-5))
    }

    It 'keeps every version, reports the failure and exits non-zero when no birth time can be read' {
        Mock -ModuleName 'Dowser' Get-DowserFolderBirthTime {
            [pscustomobject]@{ Success = $false; Births = @{}; Reason = 'BirthTimeMissing'; ExceptionType = $null; Message = 'BirthTimeMissing'; ExitCode = 13 }
        }
        $fx = & $script:NewSeatFixture 'nobirth' $true
        $run = Invoke-DowserCacheRetention -ConfigPath $fx.Config -Remove -Confirm:$false
        $run.Success | Should -BeFalse
        $run.ExitCode | Should -Be 13
        @($run.Errors | Where-Object { $_.Operation -eq 'FolderBirthRead' }).Count | Should -Be 1
        $run.CandidateCount | Should -Be 0
        $run.RemovedCount | Should -Be 0
        foreach ($row in $run.Folders) { $row.Reasons | Should -Contain 'BirthTimeUnknown' }
        foreach ($version in '1.0.1', '1.0.2', '1.0.3', '1.0.4', '1.0.5', '1.0.6') { Test-Path -LiteralPath (Join-Path $fx.Plugin $version) | Should -BeTrue }
    }

    It 'matches a process that names a version through a link to the cache root' {
        $fx = & $script:NewFixture 'alias'
        $alias = Join-Path $fx.Base 'viaalias'
        $null = New-Item -ItemType SymbolicLink -Path $alias -Target $fx.Root
        $viaLink = Join-Path (Join-Path (Join-Path $alias 'mk') 'plugA') '1.0.1'
        $start = [System.Diagnostics.ProcessStartInfo]::new('sh')
        foreach ($argument in @('-c', 'while :; do sleep 1; done', 'dowserholder', $viaLink)) { $start.ArgumentList.Add($argument) }
        $script:Holders.Add([System.Diagnostics.Process]::Start($start))
        $withAlias = Join-Path $fx.Base 'alias-rules.psd1'
        [System.IO.File]::WriteAllText($withAlias, "@{ Rules = @(@{ Name = 'Alias'; Type = 'VersionedCache'; Root = '$($fx.Root)'; RootAliases = @('$alias'); Marketplaces = @('mk'); Plugins = @('plugA'); KeepNewest = 2; InstalledManifest = '$($fx.Manifest)'; QuietMinutes = 60 }) }")
        $matched = Invoke-DowserCacheRetention -ConfigPath $withAlias
        $without = Invoke-DowserCacheRetention -ConfigPath $fx.Config
        ($matched.Folders | Where-Object { $_.Version -eq '1.0.1' }).Reasons | Should -Contain 'InUse'
        ($without.Folders | Where-Object { $_.Version -eq '1.0.1' }).Decision | Should -Be 'Remove'
    }

    It 'reads the birth time of a folder whose modification time was set back' {
        $folder = Join-Path $script:Work 'birthcheck'
        $null = New-Item -ItemType Directory -Path $folder -Force
        (Get-Item -LiteralPath $folder).LastWriteTime = [datetime]::new(2001, 1, 1)
        [System.IO.DirectoryInfo]::new($folder).CreationTimeUtc | Should -BeLessThan ([datetime]::UtcNow.AddYears(-10)) -Because '.NET reports the earlier of birth and write time'
        $result = InModuleScope 'Dowser' -Parameters @{ Folder = $folder } -ScriptBlock { param($Folder) Get-DowserFolderBirthTime -Path $Folder }
        $result.Success | Should -BeTrue
        $result.Births[$folder] | Should -BeGreaterThan ([datetime]::UtcNow.AddMinutes(-5))
    }
}

Describe 'Invoke-DowserCacheRetention symlinked parent folders' -Skip:(-not ($IsWindows -eq $false -and $IsMacOS -ne $true)) {
    BeforeAll {
        $base = Join-Path $script:Work 'parentlink'
        $script:Target = Join-Path (Join-Path $base 'real') 'mk'
        $script:LinkedRoot = Join-Path $base 'cache'
        $old = (Get-Date).AddDays(-3)
        foreach ($version in '1.0.1', '1.0.2', '1.0.3') {
            $folder = Join-Path (Join-Path $script:Target 'plugA') $version
            $null = New-Item -ItemType Directory -Path $folder -Force
            $file = Join-Path $folder 'a.bin'
            [System.IO.File]::WriteAllBytes($file, [byte[]]::new(100))
            (Get-Item -LiteralPath $file).LastWriteTime = $old
        }
        $null = New-Item -ItemType Directory -Path $script:LinkedRoot -Force
        $null = New-Item -ItemType SymbolicLink -Path (Join-Path $script:LinkedRoot 'mk') -Target $script:Target
        $script:LinkedConfig = Join-Path $base 'rules.psd1'
        [System.IO.File]::WriteAllText($script:LinkedConfig, "@{ Rules = @(@{ Name = 'Linked'; Type = 'VersionedCache'; Root = '$($script:LinkedRoot)'; Marketplaces = @('mk'); Plugins = @('plugA'); KeepNewest = 1; QuietMinutes = 0 }) }")
    }

    It 'keeps every version under a symlinked marketplace folder and removes nothing' {
        $run = Invoke-DowserCacheRetention -ConfigPath $script:LinkedConfig -Remove -Confirm:$false
        $run.CandidateCount | Should -Be 0
        $run.RemovedCount | Should -Be 0
        foreach ($row in $run.Folders) { $row.Reasons | Should -Contain 'ParentSymlink' }
        foreach ($version in '1.0.1', '1.0.2', '1.0.3') { Test-Path -LiteralPath (Join-Path (Join-Path $script:Target 'plugA') $version) | Should -BeTrue }
    }

    It 'refuses to delete beneath a symlinked parent when called directly' {
        $path = Join-Path (Join-Path (Join-Path $script:LinkedRoot 'mk') 'plugA') '1.0.1'
        $result = InModuleScope 'Dowser' -Parameters @{ Path = $path; Root = $script:LinkedRoot } -ScriptBlock { param($Path, $Root) Remove-DowserCacheVersion -Path $Path -Root $Root }
        $result.Success | Should -BeFalse
        $result.Reason | Should -Be 'ParentSymlink'
        Test-Path -LiteralPath (Join-Path (Join-Path $script:Target 'plugA') '1.0.1') | Should -BeTrue
    }
}
