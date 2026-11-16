#Requires -Version 5.1
function Invoke-DowserCacheRetention {
    <#
    .SYNOPSIS
        Prunes stale plugin cache versions by rule and reports low free disk space.

    .NOTES
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
        -  Author:        Curtis Leggett                                  -
        =  Copyright:     2026 Divergent Cortex                           =
        -  Organization:  Divergent Cortex                                -
        =  Version:       See docs/CHANGELOG.md                           =
        =-=-                       =-=-=-=-=-=-=-=                     -=-=
        -  it is not water they seek, but the truth beneath the trees     -
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

        Alias: Invoke-CacheRetention (opt-in via Enable-DowserAliases)
        Related: Measure-DowserDirectory (per-folder freshness and size rows), Measure-DowserDiskUsage
        (what is eating the space under a folder)

    .DESCRIPTION
        Reads the rule file (Config/CacheRetentionRules.psd1 by default) and applies each rule.

        A VersionedCache rule covers <Root>/<marketplace>/<plugin>/<version> folders. A version
        is kept when it is the installPath named in the rule's installed_plugins.json, when a
        running process has it as its working directory, executable, open file, mapped file,
        command line argument or environment value (InUse), when a running seat started on it
        (InUseByStart), when it is one of the newest KeepNewest versions by dotted number, when
        it is a symlink or sits under a symlinked marketplace or plugin folder (a link is never
        followed or removed), when its version is not a dotted number, or when a file in it was
        written inside the rule's QuietMinutes. When the installed manifest or the process scan
        cannot be read, nothing is removed for that run, because nothing can be shown to be
        unused. A folder whose size cannot be measured is also kept.

        A seat is a running process named in the rule's SeatProcessNames, such as claude. It
        reads its plugin files into memory when it starts and keeps none open, so only its start
        time shows what it loaded: the newest version the cache held at that moment and the next
        older one are kept. A seat whose start time cannot be read keeps every version of that
        plugin.

        A DiskThreshold rule reports when free space on the filesystem holding its Path is below
        MinFree. It never removes anything itself; it reads the space after any removal in the
        same run.

        Preview is the default: no folder is touched and the result lists each folder, its
        decision, its size and the total that removal would free. -Remove deletes the folders
        marked Remove, each behind ShouldProcess, so -WhatIf and -Confirm work. Immediately
        before deleting, the process scan is repeated and a folder a process now holds is kept.

        Only the folders marked Remove are sized, with the same file statistics Measure-DowserDirectory
        uses. Every decision and removal is logged through
        Write-Log, and the result carries an ExitCode built from the mapped Windows error codes:
        0 when nothing failed and no threshold was breached, otherwise the highest code among
        the failures (112, disk full, for a breached threshold).

        Reduced on Windows and macOS: the process check reads only the executable path of each
        process, and on Windows its command line.

    .PARAMETER ConfigPath
        Rule file to apply. Defaults to Config/CacheRetentionRules.psd1 in the module folder.

    .PARAMETER RuleName
        Apply only the rules with these names.

    .PARAMETER Remove
        Delete the folders marked Remove. Without it the run only reports.

    .PARAMETER Now
        Reference time for the quiet-window check. Defaults to the current time.

    .EXAMPLE
        Invoke-DowserCacheRetention

        Previews every rule: lists each cache version folder, whether it is kept and why, and
        how much removal would free. Nothing is deleted.

    .EXAMPLE
        Invoke-DowserCacheRetention -Remove -WhatIf

        Shows each deletion that -Remove would perform without performing it.

    .EXAMPLE
        $run = Invoke-DowserCacheRetention -RuleName ClaudePluginCache -Remove -Confirm:$false
        $run.Folders | Where-Object Removed | Format-Table Plugin, Version, Size

        Removes the stale Claude plugin cache versions without prompting and lists what went.

    .OUTPUTS
        PSCustomObject with Mode, ConfigPath, Success, ExitCode, RulesEvaluated, FolderCount,
        CandidateCount, CandidateBytes, CandidateSize, RemovedCount, FreedBytes, FreedSize,
        SkippedCount, FailedCount, Folders, DiskChecks, DiskBreachCount, Errors, Seconds.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$ConfigPath = (Join-Path (Join-Path $script:DowserRoot 'Config') 'CacheRetentionRules.psd1'),

        [string[]]$RuleName,

        [switch]$Remove,

        [datetime]$Now = (Get-Date)
    )

    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $mode = if ($Remove) { 'Remove' } else { 'Preview' }
    $state = @{ ExitCode = 0 }
    $errors = [System.Collections.Generic.List[object]]::new()
    $folders = [System.Collections.Generic.List[object]]::new()
    $diskChecks = [System.Collections.Generic.List[object]]::new()
    $counts = @{ Rules = 0; Removed = 0; Skipped = 0; Failed = 0; FreedBytes = [long]0 }

    $note = {
        param($operation, $target, $exceptionType, $message, $code)
        $errors.Add([pscustomobject]@{ Operation = $operation; Target = $target; ExceptionType = $exceptionType; Message = $message; ExitCode = $code })
        if ($code -gt $state.ExitCode) { $state.ExitCode = $code }
    }
    $finish = {
        $candidates = @($folders | Where-Object { $_.Decision -eq 'Remove' -or $_.Removed })
        $candidateBytes = [long]0
        foreach ($row in $candidates) { $candidateBytes += [long]$row.SizeBytes }
        $breaches = @($diskChecks | Where-Object { $_.Breached }).Count
        if ($breaches -gt 0) {
            $breachCode = Get-WindowsErrorCode -HResult 0x80070070
            if ($breachCode -gt $state.ExitCode) { $state.ExitCode = $breachCode }
        }
        $clock.Stop()
        $summary = "mode=$mode, rules=$($counts.Rules), folders=$($folders.Count), candidates=$($candidates.Count) ($(Format-DowserSize -DataValue $candidateBytes)), removed=$($counts.Removed) ($(Format-DowserSize -DataValue $counts.FreedBytes) freed), skipped=$($counts.Skipped), failures=$($errors.Count), disk_breaches=$breaches, exit=$($state.ExitCode), seconds=$([int]$clock.Elapsed.TotalSeconds)"
        # the component is named because a scriptblock caller would otherwise log as <ScriptBlock>
        if ($errors.Count -eq 0 -and $breaches -eq 0) {
            Write-Log "Invoke-DowserCacheRetention completed: $summary" -Severity Success -Component 'Invoke-DowserCacheRetention'
        }
        else {
            Write-Log "Invoke-DowserCacheRetention finished with failures or a breach: $summary" -Severity Warning -Component 'Invoke-DowserCacheRetention'
        }
        [pscustomobject]@{
            Mode            = $mode
            ConfigPath      = $ConfigPath
            Success         = ($errors.Count -eq 0)
            ExitCode        = $state.ExitCode
            RulesEvaluated  = $counts.Rules
            FolderCount     = $folders.Count
            CandidateCount  = $candidates.Count
            CandidateBytes  = $candidateBytes
            CandidateSize   = Format-DowserSize -DataValue $candidateBytes
            RemovedCount    = $counts.Removed
            FreedBytes      = $counts.FreedBytes
            FreedSize       = Format-DowserSize -DataValue $counts.FreedBytes
            SkippedCount    = $counts.Skipped
            FailedCount     = $errors.Count
            Folders         = $folders.ToArray()
            DiskChecks      = $diskChecks.ToArray()
            DiskBreachCount = $breaches
            Errors          = $errors.ToArray()
            Seconds         = [Math]::Round($clock.Elapsed.TotalSeconds, 1)
        }
    }
    $progress = {
        param($activity, $done, $total, $watch)
        $eta = -1
        if ($done -gt 0) { $eta = [int](($watch.Elapsed.TotalSeconds / $done) * ($total - $done)) }
        Write-Progress -Activity $activity -Status "$done of $total processed" -PercentComplete ([int](($done / [Math]::Max(1, $total)) * 100)) -SecondsRemaining $eta
    }

    Write-Log "Starting Invoke-DowserCacheRetention (mode=$mode, config='$ConfigPath')" -Severity Info

    $loaded = Get-DowserRetentionRule -ConfigPath $ConfigPath
    if (-not $loaded.Success) {
        & $note 'RuleLoad' $ConfigPath $loaded.ExceptionType "$($loaded.Reason): $($loaded.Message)" $loaded.ExitCode
    }
    $rules = @($loaded.Rules | Where-Object { -not $RuleName -or $RuleName -contains $_.Name })
    foreach ($wanted in @($RuleName | Where-Object { $_ -and ($loaded.Rules.Name -notcontains $_) })) {
        Write-Log "Invoke-DowserCacheRetention has no rule named '$wanted' in '$ConfigPath'" -Severity Warning
        & $note 'RuleName' $wanted $null 'no rule has this name' (Get-WindowsErrorCode -HResult 0x8007000D)
    }
    $counts.Rules = $rules.Count
    if ($rules.Count -eq 0) {
        return (& $finish)
    }

    $rulesByName = @{}
    foreach ($rule in $rules) { $rulesByName[$rule.Name] = $rule }
    $versioned = @($rules | Where-Object { $_.Type -eq 'VersionedCache' })
    $roots = @($versioned | ForEach-Object { $_.Root } | Select-Object -Unique)
    $prefixes = @($versioned | ForEach-Object { $_.Root; $_.RootAliases } | Where-Object { $_ } | Select-Object -Unique)
    $seatNames = @($versioned | ForEach-Object { $_.SeatProcessNames } | Where-Object { $_ } | Select-Object -Unique)
    $installedByRule = @{}

    $planRule = {
        param($rule, $scan)
        if (-not $installedByRule.ContainsKey($rule.Name)) {
            $manifest = [pscustomobject]@{ Success = $true; Paths = @() }
            if ($rule.InstalledManifest) {
                $manifest = Get-DowserInstalledPluginPath -ManifestPath $rule.InstalledManifest
                if (-not $manifest.Success) {
                    & $note 'InstalledManifest' $rule.InstalledManifest $manifest.ExceptionType "$($manifest.Reason): $($manifest.Message)" $manifest.ExitCode
                }
            }
            $installedByRule[$rule.Name] = $manifest
        }
        $manifest = $installedByRule[$rule.Name]
        Get-DowserCacheVersionPlan -Rule $rule -InstalledPath $manifest.Paths -InstalledKnown $manifest.Success -ProcessPath $scan.Paths -ProcessKnown $scan.Success -Seat $scan.Seats
    }

    if ($versioned.Count -gt 0) {
        $scan = Get-DowserActiveProcessPath -RootPrefix $prefixes -SeatName $seatNames
        if (-not $scan.Success) {
            & $note 'ProcessScan' ($roots -join ';') $scan.ExceptionType "$($scan.Reason): $($scan.Message)" $scan.ExitCode
        }
        foreach ($rule in $versioned) {
            $plan = & $planRule $rule $scan
            if (-not $plan.Success) {
                & $note 'CacheVersionList' $rule.Root $plan.ExceptionType "$($plan.Reason): $($plan.Message)" $plan.ExitCode
            }
            foreach ($row in $plan.Rows) { $folders.Add($row) }
        }

        $candidates = @($folders | Where-Object { $_.Decision -eq 'Remove' })
        $measureClock = [System.Diagnostics.Stopwatch]::StartNew()
        $measured = 0
        foreach ($row in $candidates) {
            $size = Measure-DowserCacheCandidate -Path $row.Path
            $measured++
            & $progress 'Invoke-DowserCacheRetention measuring candidates' $measured $candidates.Count $measureClock
            if (-not $size.Success) {
                $row.Decision = 'Keep'
                $row.Reasons.Add('Unmeasured')
                & $note 'CacheCandidateMeasure' $row.Path $size.ExceptionType "$($size.Reason): $($size.Message)" $size.ExitCode
                continue
            }
            $row.SizeBytes = $size.SizeBytes
            $row.Size = Format-DowserSize -DataValue $size.SizeBytes
            $row.FileCount = $size.FileCount
            $row.NewestFileDate = $size.NewestFileDate
            $quietMinutes = $rulesByName[$row.Rule].QuietMinutes
            if ($null -ne $size.NewestFileDate -and $size.NewestFileDate -gt $Now.AddMinutes(-$quietMinutes)) {
                $row.Decision = 'Keep'
                $row.Reasons.Add('RecentlyWritten')
            }
        }
        if ($candidates.Count -gt 0) {
            Write-Progress -Activity 'Invoke-DowserCacheRetention measuring candidates' -Completed
            $sizedBytes = [long]0
            foreach ($row in @($candidates | Where-Object { $null -ne $_.SizeBytes })) { $sizedBytes += [long]$row.SizeBytes }
            Write-Log "CacheCandidateMeasure sized $($measured) candidate folder(s), $(Format-DowserSize -DataValue $sizedBytes) in total, in $([int]$measureClock.Elapsed.TotalSeconds) second(s)" -Severity Info
        }

        foreach ($group in @($folders | Group-Object -Property Rule, Marketplace, Plugin)) {
            $kept = @($group.Group | Where-Object { $_.Decision -eq 'Keep' } | Sort-Object Version -Descending | ForEach-Object { "$($_.Version) [$($_.Reasons -join ',')]" })
            $dropped = @($group.Group | Where-Object { $_.Decision -eq 'Remove' } | Sort-Object Version -Descending | ForEach-Object { "$($_.Version) ($($_.Size))" })
            Write-Log "CacheRetention rule '$($group.Group[0].Rule)' plugin '$($group.Group[0].Marketplace)/$($group.Group[0].Plugin)': $($group.Count) version(s), keep $($kept.Count) ($($kept -join '; ')), remove $($dropped.Count) ($($dropped -join ', '))" -Severity Info
        }

        if ($Remove -and @($folders | Where-Object { $_.Decision -eq 'Remove' }).Count -gt 0) {
            $fresh = Get-DowserActiveProcessPath -RootPrefix $prefixes -SeatName $seatNames
            if (-not $fresh.Success) {
                & $note 'ProcessScan' ($roots -join ';') $fresh.ExceptionType "$($fresh.Reason): $($fresh.Message)" $fresh.ExitCode
            }
            $latest = @{}
            foreach ($rule in $versioned) {
                foreach ($row in (& $planRule $rule $fresh).Rows) { $latest[$row.Path] = $row }
            }
            foreach ($row in @($folders | Where-Object { $_.Decision -eq 'Remove' })) {
                if (-not $latest.ContainsKey($row.Path) -or $latest[$row.Path].Decision -ne 'Remove') {
                    $row.Decision = 'Keep'
                    $reasons = if ($latest.ContainsKey($row.Path)) { $latest[$row.Path].Reasons } else { @('Vanished') }
                    foreach ($reason in $reasons) { $row.Reasons.Add($reason) }
                }
            }

            $removeList = @($folders | Where-Object { $_.Decision -eq 'Remove' })
            $removeClock = [System.Diagnostics.Stopwatch]::StartNew()
            $handled = 0
            foreach ($row in $removeList) {
                $handled++
                & $progress 'Invoke-DowserCacheRetention removing versions' $handled $removeList.Count $removeClock
                if (-not $PSCmdlet.ShouldProcess($row.Path, "Remove cache version folder ($($row.Size), $($row.FileCount) files)")) {
                    $counts.Skipped++
                    Write-Log "CacheVersionRemove skipped '$($row.Path)' by confirmation or -WhatIf" -Severity Info
                    continue
                }
                $removal = Remove-DowserCacheVersion -Path $row.Path -Root $rulesByName[$row.Rule].Root
                if ($removal.Success -and $removal.Removed) {
                    $row.Removed = $true
                    $counts.Removed++
                    $counts.FreedBytes += [long]$row.SizeBytes
                }
                elseif (-not $removal.Success) {
                    $row.Failure = $removal.Reason
                    & $note 'CacheVersionRemove' $row.Path $removal.ExceptionType "$($removal.Reason): $($removal.Message)" $removal.ExitCode
                }
            }
            Write-Progress -Activity 'Invoke-DowserCacheRetention removing versions' -Completed
        }
    }

    foreach ($rule in @($rules | Where-Object { $_.Type -eq 'DiskThreshold' })) {
        $check = Test-DowserDiskThreshold -Rule $rule
        $diskChecks.Add($check)
        if (-not $check.Success) {
            & $note 'DiskThreshold' $rule.Path $null "$($check.Reason)" $check.ExitCode
        }
    }

    return (& $finish)
}
