#Requires -Modules @{ModuleName='Pester';ModuleVersion='5.0'}

# Probe symlink capability before Describe so the boolean is available at discovery time,
# matching the pattern already established in Get-DowserMap.Tests.ps1. $global: is used
# because $script: set at file scope is not visible inside Pester BeforeAll blocks.
$global:DowserFindFileCanSymlink = $false
$_pt = Join-Path ([System.IO.Path]::GetTempPath()) 'DowserFindFileProbeT'
$_pl = Join-Path ([System.IO.Path]::GetTempPath()) 'DowserFindFileProbeL'
try {
    $null = New-Item -ItemType Directory -Path $_pt -Force -ErrorAction Stop
    $null = New-Item -ItemType SymbolicLink -Path $_pl -Target $_pt -ErrorAction Stop
    $global:DowserFindFileCanSymlink = (Test-Path -LiteralPath $_pl)
}
catch {
    $global:DowserFindFileCanSymlink = $false
}
finally {
    Remove-Item $_pl -Force -ErrorAction SilentlyContinue
    Remove-Item $_pt -Force -Recurse -ErrorAction SilentlyContinue
}

Describe 'Find-DowserFile -ExcludePattern' {
    BeforeAll {
        $modulePath = Split-Path $PSScriptRoot -Parent
        Remove-Module Dowser -Force -ErrorAction SilentlyContinue
        Import-Module (Join-Path $modulePath 'Dowser.psd1') -Force -ErrorAction Stop

        # Shape matches the reported incident: a junk top-level folder (".rustup") sitting
        # directly under the search root, containing a file whose name is a false-positive
        # substring match for the include pattern, plus a real match outside it.
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) "DowserFindFile_$([System.IO.Path]::GetRandomFileName())"
        $junkDir = Join-Path $script:root '.rustup'
        $junkNested = Join-Path $junkDir 'nested/deep'
        $null = New-Item -ItemType Directory -Path $junkNested -Force
        'junk' | Out-File (Join-Path $junkDir 'fn.vbsl_s32.html')
        'junk-deep' | Out-File (Join-Path $junkNested 'also.vbsl.html')

        $realDir = Join-Path $script:root 'scripts'
        $null = New-Item -ItemType Directory -Path $realDir -Force
        'real' | Out-File (Join-Path $realDir 'run.vbs')
    }

    AfterAll {
        if ($script:root -and (Test-Path -LiteralPath $script:root)) {
            Remove-Item -LiteralPath $script:root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Backward compatibility' {
        It 'Returns every substring match when -ExcludePattern is omitted (reproduces the reported bug)' {
            $out = Find-DowserFile -Path $script:root -Pattern .vbs -UseRunspaces:$false
            @($out).Count | Should -Be 3
        }
    }

    Context 'Exclusion by path fragment, runspaces (default)' {
        It 'Drops every match under the excluded folder, keeps the real match' {
            $out = @(Find-DowserFile -Path $script:root -Pattern .vbs -ExcludePattern '*.rustup*')
            $out.Count | Should -Be 1
            $out[0].FullName | Should -Match 'run\.vbs$'
        }
    }

    Context 'Exclusion by path fragment, serial (-UseRunspaces:$false)' {
        It 'Drops every match under the excluded folder, keeps the real match' {
            $out = @(Find-DowserFile -Path $script:root -Pattern .vbs -ExcludePattern '*.rustup*' -UseRunspaces:$false)
            $out.Count | Should -Be 1
            $out[0].FullName | Should -Match 'run\.vbs$'
        }
    }

    Context 'Auto-wrap' {
        It 'Treats a bare exclude string the same as a wrapped wildcard' {
            $out = @(Find-DowserFile -Path $script:root -Pattern .vbs -ExcludePattern 'rustup' -UseRunspaces:$false)
            $out.Count | Should -Be 1
        }
    }

    Context 'Recurse:$false interaction' {
        It 'Still applies the exclude test at the single level being scanned' {
            $out = @(Find-DowserFile -Path (Join-Path $script:root '.rustup') -Pattern '*' -ExcludePattern '*fn.vbsl*' -Recurse:$false -UseRunspaces:$false)
            $out.FullName | Should -Not -Match 'fn\.vbsl_s32\.html$'
        }
    }

    Context 'True traversal pruning, not post-hoc filtering' -Skip:(-not $IsLinux) {
        BeforeAll {
            $script:pruneRoot = Join-Path ([System.IO.Path]::GetTempPath()) "DowserFindFilePrune_$([System.IO.Path]::GetRandomFileName())"
            $script:lockedDir = Join-Path $script:pruneRoot 'locked'
            $null = New-Item -ItemType Directory -Path $script:lockedDir -Force
            'secret' | Out-File (Join-Path $script:lockedDir 'inside.vbs')
            $openDir = Join-Path $script:pruneRoot 'open'
            $null = New-Item -ItemType Directory -Path $openDir -Force
            'real' | Out-File (Join-Path $openDir 'run.vbs')
            & chmod 000 $script:lockedDir
        }

        AfterAll {
            if ($script:lockedDir -and (Test-Path -LiteralPath $script:lockedDir)) {
                & chmod 755 $script:lockedDir
            }
            if ($script:pruneRoot -and (Test-Path -LiteralPath $script:pruneRoot)) {
                Remove-Item -LiteralPath $script:pruneRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Records an access-denied error when the locked folder is NOT excluded (proves the walk enters it)' {
            $Error.Clear()
            $null = Find-DowserFile -Path $script:pruneRoot -Pattern .vbs -UseRunspaces:$false 4>$null
            $Error.Count | Should -BeGreaterThan 0
        }

        It 'Records zero errors when the locked folder IS excluded (proves the walk never enters it)' {
            $Error.Clear()
            $out = @(Find-DowserFile -Path $script:pruneRoot -Pattern .vbs -ExcludePattern '*locked*' -UseRunspaces:$false 4>$null)
            $Error.Count | Should -Be 0
            $out.Count | Should -Be 1
            $out[0].FullName | Should -Match 'run\.vbs$'
        }
    }

    Context 'Symlinked directories are never followed by the -ExcludePattern stack walk' {
        BeforeAll {
            if ($global:DowserFindFileCanSymlink) {
                # Symlink placed one level BELOW the scan root, not as an immediate child of it.
                # A symlink sitting directly at the top level exercises the runspace path's
                # top-level-directory partitioning instead (its own dedicated context below,
                # "Top-level symlinked directory", covers that case, fixed 2026-09-15). This
                # fixture isolates the regression this diff actually introduced: the new manual
                # stack walk following a symlink DURING a deep traversal, which Get-ChildItem
                # -Recurse never did.
                $script:symRoot = Join-Path ([System.IO.Path]::GetTempPath()) "DowserFindFileSym_$([System.IO.Path]::GetRandomFileName())"
                $normalDir = Join-Path $script:symRoot 'container/normal'
                $null = New-Item -ItemType Directory -Path $normalDir -Force
                'x' | Out-File (Join-Path $normalDir 'file.vbs')
                $elsewhereDir = Join-Path $script:symRoot 'container/elsewhere'
                $null = New-Item -ItemType Directory -Path $elsewhereDir -Force
                $null = New-Item -ItemType SymbolicLink -Path (Join-Path $elsewhereDir 'link_to_normal') -Target $normalDir -Force

                # Self-referencing cycle, also one level below the root.
                $cycleDir = Join-Path $script:symRoot 'container/cycle'
                $null = New-Item -ItemType Directory -Path $cycleDir -Force
                'y' | Out-File (Join-Path $cycleDir 'target.vbs')
                $null = New-Item -ItemType SymbolicLink -Path (Join-Path $cycleDir 'loop') -Target $cycleDir -Force
            }
        }

        AfterAll {
            if ($script:symRoot -and (Test-Path -LiteralPath $script:symRoot)) {
                Remove-Item -LiteralPath $script:symRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Does not return the same file twice via a plain symlink, serial path' -Skip:(-not $global:DowserFindFileCanSymlink) {
            $out = @(Find-DowserFile -Path $script:symRoot -Pattern .vbs -ExcludePattern '*nomatch*' -UseRunspaces:$false)
            $out.Count | Should -Be 2
        }

        It 'Does not return the same file twice via a plain symlink, default runspace path' -Skip:(-not $global:DowserFindFileCanSymlink) {
            $out = @(Find-DowserFile -Path $script:symRoot -Pattern .vbs -ExcludePattern '*nomatch*')
            $out.Count | Should -Be 2
        }

        It 'Does not loop forever on a self-referencing symlink, serial path' -Skip:(-not $global:DowserFindFileCanSymlink) {
            $cycleDir = Join-Path $script:symRoot 'container/cycle'
            $out = @(Find-DowserFile -Path $cycleDir -Pattern .vbs -ExcludePattern '*nomatch*' -UseRunspaces:$false)
            $out.Count | Should -Be 1
        }
    }

    Context 'Top-level symlinked directory (default runspace, no -ExcludePattern)' {
        BeforeAll {
            if ($global:DowserFindFileCanSymlink) {
                # Real fix target: a symlink sitting directly at the search root used to get
                # its own dedicated runspace worker (the top-level partitioning step handed it
                # the symlink's own path as an explicit scan root), and Get-ChildItem happily
                # walks through an explicit-root symlink even though it never follows one it
                # only ENCOUNTERS mid-recursion. That returned every file under the real target
                # a second time, reported under the symlink's own path. Fixed 2026-09-15 by
                # dropping reparse-point directories from the top-level partition list
                # unconditionally. Confirmed by direct execution before the fix: this exact
                # shape returned 3 results instead of 2.
                $script:topSymRoot = Join-Path ([System.IO.Path]::GetTempPath()) "DowserFindFileTopSym_$([System.IO.Path]::GetRandomFileName())"
                $realTarget = Join-Path $script:topSymRoot 'realtarget'
                New-Item -ItemType Directory -Path $realTarget -Force | Out-Null
                'x' | Out-File (Join-Path $realTarget 'inside.vbs')
                $normalDir = Join-Path $script:topSymRoot 'normal'
                New-Item -ItemType Directory -Path $normalDir -Force | Out-Null
                'y' | Out-File (Join-Path $normalDir 'plain.vbs')
                New-Item -ItemType SymbolicLink -Path (Join-Path $script:topSymRoot 'linkdir') -Target $realTarget -Force | Out-Null
            }
        }

        AfterAll {
            if ($script:topSymRoot -and (Test-Path -LiteralPath $script:topSymRoot)) {
                Remove-Item -LiteralPath $script:topSymRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Returns each real file once, not a second time through the symlink path' -Skip:(-not $global:DowserFindFileCanSymlink) {
            $out = @(Find-DowserFile -Path $script:topSymRoot -Pattern .vbs)
            $out.Count | Should -Be 2
            $out.FullName | Should -Not -Match 'linkdir'
        }

        It 'Matches the serial path result count exactly (parity, not just a fixed number)' -Skip:(-not $global:DowserFindFileCanSymlink) {
            $runspaceOut = @(Find-DowserFile -Path $script:topSymRoot -Pattern .vbs)
            $serialOut = @(Find-DowserFile -Path $script:topSymRoot -Pattern .vbs -UseRunspaces:$false)
            $runspaceOut.Count | Should -Be $serialOut.Count
        }
    }

    Context 'Hidden top-level directory is still scanned after the double-scan fix' {
        BeforeAll {
            # The double-scan fix stops $p's own worker from recursing through every
            # subdirectory (that work now belongs solely to each subdirectory's own
            # dedicated worker), so the top-level partitioning enumeration is the ONLY
            # remaining place that can find a hidden top-level directory. It must use
            # -Force, or a dot-prefixed directory here would silently stop being scanned
            # entirely instead of merely being scanned twice. Confirmed by direct
            # execution before and after the fix: count stayed at 1 in both cases.
            $script:hiddenRoot = Join-Path ([System.IO.Path]::GetTempPath()) "DowserFindFileHidden_$([System.IO.Path]::GetRandomFileName())"
            $hiddenDir = Join-Path $script:hiddenRoot '.hidden'
            New-Item -ItemType Directory -Path $hiddenDir -Force | Out-Null
            'x' | Out-File (Join-Path $hiddenDir 'inside.vbs')
        }

        AfterAll {
            if ($script:hiddenRoot -and (Test-Path -LiteralPath $script:hiddenRoot)) {
                Remove-Item -LiteralPath $script:hiddenRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Finds a file inside a dot-prefixed top-level directory, default runspace path' {
            $out = @(Find-DowserFile -Path $script:hiddenRoot -Pattern .vbs)
            $out.Count | Should -Be 1
        }
    }

    Context 'No redundant double-scan of subdirectories already covered by their own worker' {
        BeforeAll {
            # Before the fix, $p's own worker recursed through the entire tree AND every
            # top-level subdirectory got its own separately recursive worker, so each file
            # nested under a top-level subdirectory was enumerated twice (deduped back down
            # to the correct count by Select-DowserUniquePath, so this was invisible in the
            # result count and only showed up as wasted scan work). This does not re-measure
            # timing (too fixture-size-sensitive to assert reliably); it locks in the
            # correctness invariant instead: nested results stay complete and exact after
            # the redundant pass was removed.
            $script:noDupeRoot = Join-Path ([System.IO.Path]::GetTempPath()) "DowserFindFileNoDupe_$([System.IO.Path]::GetRandomFileName())"
            for ($d = 1; $d -le 3; $d++) {
                $nested = Join-Path $script:noDupeRoot "dir$d/deep"
                New-Item -ItemType Directory -Path $nested -Force | Out-Null
                'x' | Out-File (Join-Path $nested "file$d.vbs")
            }
        }

        AfterAll {
            if ($script:noDupeRoot -and (Test-Path -LiteralPath $script:noDupeRoot)) {
                Remove-Item -LiteralPath $script:noDupeRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Returns exactly one result per nested file, no duplicates' {
            $out = @(Find-DowserFile -Path $script:noDupeRoot -Pattern .vbs)
            $out.Count | Should -Be 3
            (@($out.FullName) | Select-Object -Unique).Count | Should -Be 3
        }
    }

    Context 'StopOnFirstMatch stops early instead of scanning the whole tree' {
        BeforeAll {
            # Multiple top-level directories, each with its own matching file, so a
            # correct fix should return before every worker finishes its own subtree.
            # A prior gap here: the runspace scriptblock never received -StopOnFirstMatch
            # at all, so every target was scanned to completion before the flag was
            # checked, post-hoc, against the fully aggregated result list. Fixed
            # 2026-09-15 with a synchronized stop signal shared across every worker.
            $script:stopRoot = Join-Path ([System.IO.Path]::GetTempPath()) "DowserFindFileStop_$([System.IO.Path]::GetRandomFileName())"
            for ($d = 1; $d -le 4; $d++) {
                $dir = Join-Path $script:stopRoot "dir$d"
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
                'x' | Out-File (Join-Path $dir "match$d.vbs")
            }
        }

        AfterAll {
            if ($script:stopRoot -and (Test-Path -LiteralPath $script:stopRoot)) {
                Remove-Item -LiteralPath $script:stopRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Returns exactly one result, default runspace path' {
            $out = Find-DowserFile -Path $script:stopRoot -Pattern .vbs -StopOnFirstMatch
            $out | Should -Not -BeNullOrEmpty
            $out -is [array] | Should -Be $false
        }

        It 'Returns exactly one result, serial path' {
            $out = Find-DowserFile -Path $script:stopRoot -Pattern .vbs -StopOnFirstMatch -UseRunspaces:$false
            $out | Should -Not -BeNullOrEmpty
            $out -is [array] | Should -Be $false
        }
    }

    Context 'StopOnFirstMatch genuinely bounds work to one directory at a time, not the whole tree' {
        BeforeAll {
            # Regression coverage for a real gap the earlier "StopOnFirstMatch stops early"
            # tests could not catch: those tests only assert correctness (a single non-array
            # result), which passes identically whether the underlying scan stopped early or
            # walked the entire tree first and picked one result afterward -- exactly what
            # the pre-fix code already did. Confirmed by direct execution that
            # Get-ChildItem -Recurse largely BUFFERS its entire recursive listing before a
            # consuming foreach loop can begin iterating (breaking after the first of 50,000
            # recursively-enumerated items still cost 77% of the time to enumerate all
            # 50,000), so converting "return" to "break" alone only skipped per-item
            # processing, never the disk work. Fixed 2026-09-15 by routing -StopOnFirstMatch
            # through the same manual, per-directory stack walk -ExcludePattern already used,
            # which bounds buffered work to one directory's children at a time instead of an
            # entire recursive subtree. This fixture (many separate subdirectories) is the
            # shape that fix actually helps: a single huge FLAT directory with no
            # subdirectories at all does not benefit the same way (Get-ChildItem still
            # buffers that one directory's own full listing before any item is examined),
            # but that shape was never faster before this fix either, so it is a documented
            # boundary, not a regression.
            # [System.IO.File]::Create, not New-Item: this fixture needs thousands of files
            # and New-Item's per-call cmdlet overhead made this single Context add roughly
            # 7 seconds to the suite on its own -- the direct .NET call is materially faster
            # for bulk fixture creation and the content of these files is never read.
            $script:perfRoot = Join-Path ([System.IO.Path]::GetTempPath()) "DowserFindFilePerf_$([System.IO.Path]::GetRandomFileName())"
            $bigDir = Join-Path $script:perfRoot 'big'
            for ($d = 0; $d -lt 10; $d++) {
                $sub = Join-Path $bigDir "s$d"
                [System.IO.Directory]::CreateDirectory($sub) | Out-Null
                for ($f = 0; $f -lt 500; $f++) {
                    [System.IO.File]::Create((Join-Path $sub "f$f.dat")).Dispose()
                }
            }
            $script:smallDir = Join-Path $script:perfRoot 'small'
            [System.IO.Directory]::CreateDirectory($script:smallDir) | Out-Null
            [System.IO.File]::Create((Join-Path $script:smallDir 'match.vbs')).Dispose()
        }

        AfterAll {
            if ($script:perfRoot -and (Test-Path -LiteralPath $script:perfRoot)) {
                Remove-Item -LiteralPath $script:perfRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Default runspace path: a match in a small directory is not delayed by a large non-matching sibling' {
            $swSmallOnly = [Diagnostics.Stopwatch]::StartNew()
            $null = Find-DowserFile -Path $script:smallDir -Pattern .vbs -StopOnFirstMatch 6>$null
            $swSmallOnly.Stop()

            $swWithSibling = [Diagnostics.Stopwatch]::StartNew()
            $result = Find-DowserFile -Path $script:perfRoot -Pattern .vbs -StopOnFirstMatch 6>$null
            $swWithSibling.Stop()

            $result.FullName | Should -Match 'match\.vbs$'
            # Generous multiple (not a tight percentage) to stay reliable under normal
            # machine-load variance while still failing hard if early termination regresses:
            # the pre-fix code measured roughly 1.9x here; the fix measured roughly 1.1x.
            $ratio = $swWithSibling.Elapsed.TotalMilliseconds / [Math]::Max(1, $swSmallOnly.Elapsed.TotalMilliseconds)
            $ratio | Should -BeLessThan 3.0
        }
    }

    Context '-ExcludePattern and -StopOnFirstMatch combined' {
        BeforeAll {
            # Both flags share the same manual stack walk and the same stop signal; this
            # combination had zero permanent test coverage before (flagged independently by
            # both Huginn and Muninn during review). The excluded directory would contain a
            # match if not pruned, so a leak here would be a real, user-visible defect: the
            # caller asked to exclude that directory and would get a match from inside it
            # anyway.
            $script:comboRoot = Join-Path ([System.IO.Path]::GetTempPath()) "DowserFindFileCombo_$([System.IO.Path]::GetRandomFileName())"
            $excludedDir = Join-Path $script:comboRoot 'excluded'
            New-Item -ItemType Directory -Path $excludedDir -Force | Out-Null
            'x' | Out-File (Join-Path $excludedDir 'wouldmatch.vbs')
            $realDir = Join-Path $script:comboRoot 'real'
            New-Item -ItemType Directory -Path $realDir -Force | Out-Null
            'y' | Out-File (Join-Path $realDir 'real.vbs')
        }

        AfterAll {
            if ($script:comboRoot -and (Test-Path -LiteralPath $script:comboRoot)) {
                Remove-Item -LiteralPath $script:comboRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Never returns a match from the excluded directory, default runspace path' {
            $result = Find-DowserFile -Path $script:comboRoot -Pattern .vbs -ExcludePattern '*excluded*' -StopOnFirstMatch
            $result.FullName | Should -Match 'real\.vbs$'
            $result.FullName | Should -Not -Match 'excluded'
        }

        It 'Never returns a match from the excluded directory, serial path' {
            $result = Find-DowserFile -Path $script:comboRoot -Pattern .vbs -ExcludePattern '*excluded*' -StopOnFirstMatch -UseRunspaces:$false
            $result.FullName | Should -Match 'real\.vbs$'
            $result.FullName | Should -Not -Match 'excluded'
        }
    }

    Context 'A blank -ExcludePattern element is dropped, not treated as match-everything' {
        It 'Ignores an empty string element instead of excluding the whole tree' {
            $out = @(Find-DowserFile -Path $script:root -Pattern .vbs -ExcludePattern '', '*.rustup*' -UseRunspaces:$false)
            $out.Count | Should -Be 1
            $out[0].FullName | Should -Match 'run\.vbs$'
        }
    }

    AfterAll {
        # Deferred cleanup, not loose top-level code: Pester's discovery pass walks the whole
        # file once (to evaluate every -Skip:(-not $global:DowserFindFileCanSymlink) condition
        # correctly), and loose top-level code at file end would execute during THAT walk,
        # clearing the variable before the run phase's BeforeAll bodies ever see it. An AfterAll
        # is deferred until the run phase actually finishes this Describe's tests, matching the
        # proven-working pattern in Get-DowserMap.Tests.ps1.
        Remove-Variable DowserFindFileCanSymlink -Scope Global -ErrorAction SilentlyContinue
    }
}
