#Requires -Modules @{ModuleName='Pester';ModuleVersion='5.0'}

# probe symlink support up front so the -Skip conditions can see it at discovery time
# $global: because a $script: variable set at file scope is invisible inside BeforeAll
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

        # junk top-level folder (.rustup) full of files that match the pattern by accident,
        # plus one real match elsewhere
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
                # symlinks go one level below the scan root on purpose: a top-level one hits the
                # runspace partitioning instead (next context covers that). this fixture is for
                # the manual stack walk following a link mid-traversal, which Get-ChildItem
                # -Recurse never does
                $script:symRoot = Join-Path ([System.IO.Path]::GetTempPath()) "DowserFindFileSym_$([System.IO.Path]::GetRandomFileName())"
                $normalDir = Join-Path $script:symRoot 'container/normal'
                $null = New-Item -ItemType Directory -Path $normalDir -Force
                'x' | Out-File (Join-Path $normalDir 'file.vbs')
                $elsewhereDir = Join-Path $script:symRoot 'container/elsewhere'
                $null = New-Item -ItemType Directory -Path $elsewhereDir -Force
                $null = New-Item -ItemType SymbolicLink -Path (Join-Path $elsewhereDir 'link_to_normal') -Target $normalDir -Force

                # a symlink that points back at its own folder, also one level down
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
                # a symlink right at the search root used to get its own runspace worker, and
                # Get-ChildItem walks an explicit-root symlink even though it won't follow one
                # it finds mid-recursion. every file under the real target then came back a
                # second time under the symlink path (3 results instead of 2). reparse-point
                # dirs are now dropped from the top-level partition list
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
            # the top-level partition listing is the only place that can find a hidden
            # top-level directory, so it needs -Force or dot-prefixed folders quietly
            # stop being scanned at all
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
            # each top-level subdirectory has its own worker, so the parent worker must not
            # recurse into them too. the duplicates got deduped away afterwards, so the count
            # never showed it. timing is too flaky to assert, so this only checks the nested
            # results stay complete and exact
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
            # several top-level dirs, each with its own match, so an early stop can return
            # before every worker has finished its subtree
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
            # the earlier early-stop tests only check for one non-array result, which passes
            # even if the scan walked the whole tree first. Get-ChildItem -Recurse buffers
            # most of its listing before the loop sees an item, so a plain break never saved
            # any disk work. -StopOnFirstMatch now walks one directory at a time, and this
            # fixture (many separate subdirs) is where that pays off. one huge flat directory
            # still buffers its own full listing, which is a known limit
            # [System.IO.File]::Create instead of New-Item: thousands of files, and New-Item's
            # per-call overhead added about 7 seconds to the suite
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
            # generous multiple instead of a tight percentage so machine load doesn't flake it;
            # without early termination this lands around 1.9x, with it about 1.1x
            $ratio = $swWithSibling.Elapsed.TotalMilliseconds / [Math]::Max(1, $swSmallOnly.Elapsed.TotalMilliseconds)
            $ratio | Should -BeLessThan 3.0
        }
    }

    Context '-ExcludePattern and -StopOnFirstMatch combined' {
        BeforeAll {
            # both flags share one stack walk and one stop signal. the excluded dir holds a
            # match, so a leak would hand back a result from a folder the caller excluded
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
        # cleanup lives in AfterAll because Pester's discovery pass walks the file first (to
        # evaluate the -Skip conditions), and loose code at the end would run then and clear
        # the variable before any BeforeAll could see it
        Remove-Variable DowserFindFileCanSymlink -Scope Global -ErrorAction SilentlyContinue
    }
}
