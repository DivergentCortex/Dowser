#Requires -Modules @{ModuleName='Pester';ModuleVersion='5.0'}

# Probe symlink capability before Describe so the boolean is available at discovery time.
# $global: is used because $script: set at file scope is not visible inside Pester BeforeAll blocks.
# The probe creates and immediately destroys a throwaway symlink.
$global:DowserTestCanSymlink = $false
$_pt = Join-Path ([System.IO.Path]::GetTempPath()) 'DowserProbeT'
$_pl = Join-Path ([System.IO.Path]::GetTempPath()) 'DowserProbeL'
try {
    $null = New-Item -ItemType Directory -Path $_pt -Force -ErrorAction Stop
    $null = New-Item -ItemType SymbolicLink -Path $_pl -Target $_pt -ErrorAction Stop
    $global:DowserTestCanSymlink = (Test-Path -LiteralPath $_pl)
}
catch {
    $global:DowserTestCanSymlink = $false 
}
finally {
    Remove-Item $_pl -Force -ErrorAction SilentlyContinue
    Remove-Item $_pt -Force -Recurse -ErrorAction SilentlyContinue
}

Describe 'Get-DowserMap symlink rendering' {
    BeforeAll {
        $modulePath = Split-Path $PSScriptRoot -Parent
        Remove-Module Dowser -Force -ErrorAction SilentlyContinue
        Import-Module (Join-Path $modulePath 'Dowser.psd1') -Force -ErrorAction Stop

        # target lives OUTSIDE the mapped root so traversal of the link is the only way inner.txt appears
        $tmpTarget = Join-Path ([System.IO.Path]::GetTempPath()) 'DowserSymTarget'
        $tmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'DowserSymRoot'
        $null = New-Item -ItemType Directory -Path $tmpTarget -Force
        $null = New-Item -ItemType Directory -Path $tmpRoot -Force

        # plant a file inside the target so traversal is detectable
        [System.IO.File]::WriteAllText((Join-Path $tmpTarget 'inner.txt'), 'y')

        # symlink inside mapped root pointing to target outside mapped root
        if ($global:DowserTestCanSymlink) {
            $null = New-Item -ItemType SymbolicLink -Path (Join-Path $tmpRoot 'the-link') -Target $tmpTarget -ErrorAction SilentlyContinue
        }

        # sibling file so the-link is NOT the last child (sorts before z-*)
        [System.IO.File]::WriteAllText((Join-Path $tmpRoot 'z-sibling.txt'), 'x')

        $script:tmpRoot = $tmpRoot
        $script:tmpTarget = $tmpTarget
    }

    AfterAll {
        foreach ($p in @($script:tmpRoot, $script:tmpTarget)) {
            if ($p -and (Test-Path -LiteralPath $p)) {
                Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        Remove-Variable DowserTestCanSymlink -Scope Global -ErrorAction SilentlyContinue
    }

    Context 'Default (no -FollowReparse)' {
        BeforeAll {
            if ($global:DowserTestCanSymlink) {
                $script:out = Get-DowserMap -Path $script:tmpRoot -ShowFullPathTree:$false -NoDefaultExcludes
            }
        }

        It 'Emits arrow line containing link name' -Skip:(-not $global:DowserTestCanSymlink) {
            $script:out | Where-Object { $_ -match [char]0x2192 -and $_ -match 'the-link' } | Should -Not -BeNullOrEmpty
        }

        It 'Emits target line with resolved path' -Skip:(-not $global:DowserTestCanSymlink) {
            $targetLine = $script:out | Where-Object { $_ -match [char]0x21B3 }
            $targetLine | Should -Not -BeNullOrEmpty
            $targetLine | Should -Match ([regex]::Escape((Split-Path $script:tmpTarget -Leaf)))
        }

        It 'Does not descend into the link (inner.txt must not appear)' -Skip:(-not $global:DowserTestCanSymlink) {
            $script:out | Where-Object { $_ -match 'inner\.txt' } | Should -BeNullOrEmpty
        }

        It 'Target line carries continuation bar for non-last-child symlink' -Skip:(-not $global:DowserTestCanSymlink) {
            # the-link sorts before z-sibling.txt so it is NOT the last child
            $script:out | Where-Object { $_ -match [char]0x21B3 } | Should -Match ([char]0x2502)
        }
    }

    Context '-FollowReparse still descends' {
        It 'Finds inner.txt when -FollowReparse is set' -Skip:(-not $global:DowserTestCanSymlink) {
            $out = Get-DowserMap -Path $script:tmpRoot -ShowFullPathTree:$false -NoDefaultExcludes -MaxDepth 5 -FollowReparse
            $out | Where-Object { $_ -match 'inner\.txt' } | Should -Not -BeNullOrEmpty
        }
    }

    Context 'ShowFullPathTree default mode, no -FollowReparse' {
        BeforeAll {
            if ($global:DowserTestCanSymlink) {
                # ShowFullPathTree:$true is the function default; exercises the trunk render path
                $script:sftOut = Get-DowserMap -Path $script:tmpRoot -ShowFullPathTree:$true -NoDefaultExcludes
            }
        }

        It 'Emits arrow line containing link name (ShowFullPathTree path)' -Skip:(-not $global:DowserTestCanSymlink) {
            $script:sftOut | Where-Object { $_ -match [char]0x2192 -and $_ -match 'the-link' } | Should -Not -BeNullOrEmpty
        }

        It 'Emits target line with resolved path (ShowFullPathTree path)' -Skip:(-not $global:DowserTestCanSymlink) {
            $script:sftOut | Where-Object { $_ -match [char]0x21B3 } | Should -Not -BeNullOrEmpty
        }

        It 'Does not descend into link (ShowFullPathTree path)' -Skip:(-not $global:DowserTestCanSymlink) {
            $script:sftOut | Where-Object { $_ -match 'inner\.txt' } | Should -BeNullOrEmpty
        }

        It 'Descends into link when -FollowReparse set (ShowFullPathTree path)' -Skip:(-not $global:DowserTestCanSymlink) {
            $out = Get-DowserMap -Path $script:tmpRoot -ShowFullPathTree:$true -NoDefaultExcludes -MaxDepth 5 -FollowReparse
            $out | Where-Object { $_ -match 'inner\.txt' } | Should -Not -BeNullOrEmpty
        }
    }

    Context '-AsHtml emits HTML entities' {
        BeforeAll {
            if ($global:DowserTestCanSymlink) {
                $script:htmlOut = Get-DowserMap -Path $script:tmpRoot -ShowFullPathTree:$false -NoDefaultExcludes -AsHtml
            }
        }

        It 'Emits &#x2192; entity on link name line' -Skip:(-not $global:DowserTestCanSymlink) {
            $script:htmlOut | Where-Object { $_ -match '&#x2192;' -and $_ -match 'the-link' } | Should -Not -BeNullOrEmpty
        }

        It 'Emits &#x21B3; entity on target line' -Skip:(-not $global:DowserTestCanSymlink) {
            $script:htmlOut | Where-Object { $_ -match '&#x21B3;' } | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Get-DowserMap summary auto-enable and size rollup' {
    BeforeAll {
        $modulePath = Split-Path $PSScriptRoot -Parent
        Remove-Module Dowser -Force -ErrorAction SilentlyContinue
        Import-Module (Join-Path $modulePath 'Dowser.psd1') -Force -ErrorAction Stop

        $tmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'DowserSummaryRoot'
        Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
        $dirA = Join-Path $tmpRoot 'A'
        $dirANested = Join-Path $dirA 'Nested'
        $dirB = Join-Path $tmpRoot 'B'
        $null = New-Item -ItemType Directory -Path $dirA -Force
        $null = New-Item -ItemType Directory -Path $dirANested -Force
        $null = New-Item -ItemType Directory -Path $dirB -Force

        # Known byte counts, real assertions, not a smell test. Shape matters: a file
        # sitting loose at the scan root, a top-level folder with its own file plus a
        # nested subfolder (so its cached size is inclusive of the nested bytes), and a
        # second plain top-level folder. This is the exact shape that surfaced both the
        # total-size undercount (loose root files were never counted) and the Top-N
        # double-count (a nested folder's bytes are already inside its parent's total).
        [System.IO.File]::WriteAllBytes((Join-Path $tmpRoot 'rootloose.txt'), (New-Object byte[] 300))
        [System.IO.File]::WriteAllBytes((Join-Path $dirA 'a1.txt'), (New-Object byte[] 100))
        [System.IO.File]::WriteAllBytes((Join-Path $dirANested 'n1.txt'), (New-Object byte[] 400))
        [System.IO.File]::WriteAllBytes((Join-Path $dirB 'b1.txt'), (New-Object byte[] 50))

        $script:tmpRoot = $tmpRoot

        # Report-file writes below go here, NEVER inside $tmpRoot -- a .md report written into
        # the scanned tree would become a new loose root file for the next test's size totals.
        $outDir = Join-Path ([System.IO.Path]::GetTempPath()) 'DowserSummaryOutputs'
        Remove-Item -LiteralPath $outDir -Recurse -Force -ErrorAction SilentlyContinue
        $null = New-Item -ItemType Directory -Path $outDir -Force
        $script:outDir = $outDir
    }

    AfterAll {
        if ($script:tmpRoot -and (Test-Path -LiteralPath $script:tmpRoot)) {
            Remove-Item -LiteralPath $script:tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        if ($script:outDir -and (Test-Path -LiteralPath $script:outDir)) {
            Remove-Item -LiteralPath $script:outDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Auto-enable rules' {
        It 'Emits no summary when neither markdown output nor -EmitSummary is requested' {
            $out = Get-DowserMap -Path $script:tmpRoot -FoldersOnly -MaxDepth 1
            $out | Where-Object { $_ -eq 'Summary:' } | Should -BeNullOrEmpty
        }

        It 'Auto-enables the summary for -AsMarkdown even with no -OutputFile' {
            $out = Get-DowserMap -Path $script:tmpRoot -FoldersOnly -MaxDepth 1 -AsMarkdown
            $out | Where-Object { $_ -eq 'Summary:' } | Should -Not -BeNullOrEmpty
        }

        It 'Auto-enables the summary for an -OutputFile ending .md' {
            $mdPath = Join-Path $script:outDir 'auto.md'
            $null = Get-DowserMap -Path $script:tmpRoot -FoldersOnly -MaxDepth 1 -AsMarkdown -OutputFile $mdPath
            (Get-Content -LiteralPath $mdPath -Raw) | Should -Match '#### Summary'
        }

        It 'Explicit -EmitSummary:$false wins over markdown auto-enable' {
            $out = Get-DowserMap -Path $script:tmpRoot -FoldersOnly -MaxDepth 1 -AsMarkdown -EmitSummary:$false
            $out | Where-Object { $_ -eq 'Summary:' } | Should -BeNullOrEmpty
        }

        It 'Explicit -EmitSummary still works without markdown output' {
            $out = Get-DowserMap -Path $script:tmpRoot -FoldersOnly -MaxDepth 1 -EmitSummary
            $out | Where-Object { $_ -eq 'Summary:' } | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Scan parameters and size rollup' {
        BeforeAll {
            $script:out = Get-DowserMap -Path $script:tmpRoot -FoldersOnly -IncludeSize -MaxDepth 1 -EmitSummary -NoDefaultExcludes
        }

        It 'Declares MaxDepth, DefaultExcludes, and FoldersOnly' {
            $script:out | Where-Object { $_ -match '^\s*Scan: MaxDepth=1, DefaultExcludes=False, FoldersOnly=True$' } | Should -Not -BeNullOrEmpty
        }

        It 'Reports total size including nested-folder bytes and the loose root file' {
            # A (100) + A/Nested (400) + B (50) + rootloose.txt (300) = 850
            $script:out | Where-Object { $_ -match '^\s*Total size: 850\.0B$' } | Should -Not -BeNullOrEmpty
        }

        It 'Ranks only top-level folders, never double-listing a nested folder inside its parent' {
            # A's cached size (500) is inclusive of A/Nested (400) plus its own a1.txt (100).
            # "Nested" legitimately appears as its own bare tree line -- what must NOT appear
            # is a ranked "A/Nested" row in the summary (the relative-path form only the
            # largest-folders section ever produces).
            $script:out | Where-Object { $_ -match '500\.0B\s+A$' } | Should -Not -BeNullOrEmpty
            $script:out | Where-Object { $_ -match '50\.0B\s+B$' } | Should -Not -BeNullOrEmpty
            $script:out | Where-Object { $_ -match 'A[\\/]Nested' } | Should -BeNullOrEmpty
        }

        It 'Omits the size rollup when -IncludeSize is not set' {
            $noSizeOut = Get-DowserMap -Path $script:tmpRoot -FoldersOnly -MaxDepth 1 -EmitSummary
            $noSizeOut | Where-Object { $_ -match 'Total size:' } | Should -BeNullOrEmpty
        }
    }

    Context 'Default-excluded top-level folders are named, not silently dropped' {
        BeforeAll {
            # 'logs' is one of the built-in default-excluded folder names. Give it more bytes
            # than the folder that IS counted, so a total that silently omitted it would be
            # obviously, provably wrong rather than just slightly off.
            $excludeRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'DowserSummaryExcludeRoot'
            Remove-Item -LiteralPath $excludeRoot -Recurse -Force -ErrorAction SilentlyContinue
            $logsDir = Join-Path $excludeRoot 'logs'
            $normalDir = Join-Path $excludeRoot 'NormalFolder'
            $null = New-Item -ItemType Directory -Path $logsDir -Force
            $null = New-Item -ItemType Directory -Path $normalDir -Force
            [System.IO.File]::WriteAllBytes((Join-Path $logsDir 'big.log'), (New-Object byte[] 9000))
            [System.IO.File]::WriteAllBytes((Join-Path $normalDir 'small.txt'), (New-Object byte[] 100))

            $script:excludeRoot = $excludeRoot
            $script:excludeOut = Get-DowserMap -Path $excludeRoot -FoldersOnly -IncludeSize -MaxDepth 1 -EmitSummary
        }

        AfterAll {
            if ($script:excludeRoot -and (Test-Path -LiteralPath $script:excludeRoot)) {
                Remove-Item -LiteralPath $script:excludeRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Total size reflects only the non-excluded folder, not the excluded one' {
            $script:excludeOut | Where-Object { $_ -match '^\s*Total size: 100\.0B$' } | Should -Not -BeNullOrEmpty
        }

        It 'Names the excluded top-level folder next to the total so the gap is not silent' {
            $script:excludeOut | Where-Object { $_ -match 'Total size excludes filtered top-level folders:.*logs' } | Should -Not -BeNullOrEmpty
        }

        It 'Also names it in -ShowFullPathTree:$false mode (the other twin filter branch)' {
            # Both rendering branches implement top-level filtering separately; a fix applied to
            # only one is a real, previously-uncaught regression risk (review_id 905/906).
            $nonTrunkOut = Get-DowserMap -Path $script:excludeRoot -ShowFullPathTree:$false -FoldersOnly -IncludeSize -MaxDepth 1 -EmitSummary
            $nonTrunkOut | Where-Object { $_ -match '^\s*Total size: 100\.0B$' } | Should -Not -BeNullOrEmpty
            $nonTrunkOut | Where-Object { $_ -match 'Total size excludes filtered top-level folders:.*logs' } | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Path-pattern-excluded top-level folders are also named' {
        BeforeAll {
            # Mirrors the Huginn/Muninn court-review repro exactly: a top-level folder excluded
            # via -ExcludePathPatterns (not a default-excluded name) reproduced the identical
            # silent-undercount failure the 'logs' fix above was meant to close, because only
            # Test-ExcludeFolder rejections were tracked -- Test-ExcludeByPath rejections were not.
            $pathExcludeRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'DowserSummaryPathExcludeRoot'
            Remove-Item -LiteralPath $pathExcludeRoot -Recurse -Force -ErrorAction SilentlyContinue
            $normalDir2 = Join-Path $pathExcludeRoot 'NormalFolder2'
            $secretDir = Join-Path $pathExcludeRoot 'secretstuff'
            $null = New-Item -ItemType Directory -Path $normalDir2 -Force
            $null = New-Item -ItemType Directory -Path $secretDir -Force
            [System.IO.File]::WriteAllBytes((Join-Path $normalDir2 'n2.txt'), (New-Object byte[] 20))
            [System.IO.File]::WriteAllBytes((Join-Path $secretDir 's1.txt'), (New-Object byte[] 5000))

            $script:pathExcludeRoot = $pathExcludeRoot
            $script:pathExcludeOut = Get-DowserMap -Path $pathExcludeRoot -FoldersOnly -IncludeSize -MaxDepth 1 -EmitSummary -ExcludePathPatterns '*secretstuff*'
        }

        AfterAll {
            if ($script:pathExcludeRoot -and (Test-Path -LiteralPath $script:pathExcludeRoot)) {
                Remove-Item -LiteralPath $script:pathExcludeRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Total size reflects only the non-excluded folder, not the path-excluded one' {
            $script:pathExcludeOut | Where-Object { $_ -match '^\s*Total size: 20\.0B$' } | Should -Not -BeNullOrEmpty
        }

        It 'Names the -ExcludePathPatterns-excluded folder next to the total' {
            $script:pathExcludeOut | Where-Object { $_ -match 'Total size excludes filtered top-level folders:.*secretstuff' } | Should -Not -BeNullOrEmpty
        }

        It 'Also names it in -ShowFullPathTree:$false mode (the other twin filter branch)' {
            $nonTrunkOut = Get-DowserMap -Path $script:pathExcludeRoot -ShowFullPathTree:$false -FoldersOnly -IncludeSize -MaxDepth 1 -EmitSummary -ExcludePathPatterns '*secretstuff*'
            $nonTrunkOut | Where-Object { $_ -match '^\s*Total size: 20\.0B$' } | Should -Not -BeNullOrEmpty
            $nonTrunkOut | Where-Object { $_ -match 'Total size excludes filtered top-level folders:.*secretstuff' } | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Excluded root-level files are named, not silently dropped (mirrors the folder case)' {
        BeforeAll {
            # Before this fix, a root-level file rejected by the size-total loop simply
            # vanished with no signal at all -- unlike an excluded top-level FOLDER, which
            # is named via ExcludedTopLevelNames. 'settings.local.json' is one of the
            # built-in default-excluded FILE names; give it more bytes than the counted
            # file so a total that silently included or omitted it would be obviously
            # wrong. Deliberately NOT using '.env' here even though it is also in the
            # default-exclude-files list: a dot-prefixed name is invisible to
            # Get-ChildItem -File without -Force on Linux (the hidden-file convention),
            # so it would never even reach the exclude-rule check this test means to
            # exercise -- confirmed by direct execution before writing this fixture.
            $fileExcludeRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'DowserSummaryFileExcludeRoot'
            Remove-Item -LiteralPath $fileExcludeRoot -Recurse -Force -ErrorAction SilentlyContinue
            $null = New-Item -ItemType Directory -Path $fileExcludeRoot -Force
            [System.IO.File]::WriteAllBytes((Join-Path $fileExcludeRoot 'settings.local.json'), (New-Object byte[] 9000))
            [System.IO.File]::WriteAllBytes((Join-Path $fileExcludeRoot 'normal.txt'), (New-Object byte[] 100))

            $script:fileExcludeRoot = $fileExcludeRoot
            $script:fileExcludeOut = Get-DowserMap -Path $fileExcludeRoot -FoldersOnly -IncludeSize -MaxDepth 1 -EmitSummary
        }

        AfterAll {
            if ($script:fileExcludeRoot -and (Test-Path -LiteralPath $script:fileExcludeRoot)) {
                Remove-Item -LiteralPath $script:fileExcludeRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Total size reflects only the non-excluded file, not the default-excluded one' {
            $script:fileExcludeOut | Where-Object { $_ -match '^\s*Total size: 100\.0B$' } | Should -Not -BeNullOrEmpty
        }

        It 'Names the excluded root-level file next to the total, on its own line from the folder line' {
            $script:fileExcludeOut | Where-Object { $_ -match 'Total size excludes filtered top-level files:.*settings\.local\.json' } | Should -Not -BeNullOrEmpty
        }

        It 'A root-level file excluded by -ExcludePathPatterns is also named' {
            $pathRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'DowserSummaryFilePathExcludeRoot'
            Remove-Item -LiteralPath $pathRoot -Recurse -Force -ErrorAction SilentlyContinue
            $null = New-Item -ItemType Directory -Path $pathRoot -Force
            [System.IO.File]::WriteAllBytes((Join-Path $pathRoot 'secret.dat'), (New-Object byte[] 5000))
            [System.IO.File]::WriteAllBytes((Join-Path $pathRoot 'normal.txt'), (New-Object byte[] 20))
            try {
                $out = Get-DowserMap -Path $pathRoot -FoldersOnly -IncludeSize -MaxDepth 1 -EmitSummary -ExcludePathPatterns '*secret.dat*'
                $out | Where-Object { $_ -match '^\s*Total size: 20\.0B$' } | Should -Not -BeNullOrEmpty
                $out | Where-Object { $_ -match 'Total size excludes filtered top-level files:.*secret\.dat' } | Should -Not -BeNullOrEmpty
            }
            finally {
                Remove-Item -LiteralPath $pathRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'An -IncludeExtensions allowlist mismatch on a root-level file is NOT named (Decision D-1 parity)' {
            # Matches the existing "-IncludeFolders allowlist mismatches are not named"
            # boundary: declared scope narrowing via an allowlist is not a surprise the
            # summary needs to flag the way an actual exclude rule is.
            $allowlistRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'DowserSummaryFileAllowlistRoot'
            Remove-Item -LiteralPath $allowlistRoot -Recurse -Force -ErrorAction SilentlyContinue
            $null = New-Item -ItemType Directory -Path $allowlistRoot -Force
            [System.IO.File]::WriteAllBytes((Join-Path $allowlistRoot 'keep.txt'), (New-Object byte[] 20))
            [System.IO.File]::WriteAllBytes((Join-Path $allowlistRoot 'ignore.log'), (New-Object byte[] 9000))
            try {
                $out = Get-DowserMap -Path $allowlistRoot -FoldersOnly -IncludeSize -MaxDepth 1 -EmitSummary -NoDefaultExcludes -IncludeExtensions '.txt'
                $out | Where-Object { $_ -match '^\s*Total size: 20\.0B$' } | Should -Not -BeNullOrEmpty
                $out | Where-Object { $_ -match 'Total size excludes filtered top-level files:' } | Should -BeNullOrEmpty
            }
            finally {
                Remove-Item -LiteralPath $allowlistRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Emits no new line when no root-level file is excluded (backward compatible default)' {
            $plainRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'DowserSummaryFilePlainRoot'
            Remove-Item -LiteralPath $plainRoot -Recurse -Force -ErrorAction SilentlyContinue
            $null = New-Item -ItemType Directory -Path $plainRoot -Force
            [System.IO.File]::WriteAllBytes((Join-Path $plainRoot 'ok.txt'), (New-Object byte[] 10))
            try {
                $out = Get-DowserMap -Path $plainRoot -FoldersOnly -IncludeSize -MaxDepth 1 -EmitSummary
                $out | Where-Object { $_ -match 'Total size excludes filtered top-level files:' } | Should -BeNullOrEmpty
            }
            finally {
                Remove-Item -LiteralPath $plainRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Single-surviving-line output is never fused into one string' {
        It 'Keeps the tree line and the summary as separate array elements when exactly one item survives' {
            # Regression for review_id 906 (Huginn): Where-Object unwraps a single surviving
            # result to a bare string, so "$filteredLines + $summaryLines" silently became
            # string concatenation instead of array concatenation, fusing the tree line and
            # every summary line into one corrupted string. Only reachable via
            # -ShowFullPathTree:$false, which nothing else in this file exercises.
            $singleRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'DowserSummarySingleRoot'
            Remove-Item -LiteralPath $singleRoot -Recurse -Force -ErrorAction SilentlyContinue
            $onlyDir = Join-Path $singleRoot 'OnlyFolder'
            $null = New-Item -ItemType Directory -Path $onlyDir -Force
            try {
                $out = Get-DowserMap -Path $singleRoot -ShowFullPathTree:$false -FoldersOnly -EmitSummary
                $out | Where-Object { $_ -eq 'Summary:' } | Should -Not -BeNullOrEmpty
                $out | Where-Object { $_ -match 'OnlyFolder' } | Should -Not -BeNullOrEmpty
            }
            finally {
                Remove-Item -LiteralPath $singleRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Decision D-1: -IncludeFolders allowlist mismatches are not named' {
        It 'Does not treat an -IncludeFolders allowlist as an exclusion worth naming' {
            # Deliberate scope boundary (Synapse decision_id 175): -IncludeFolders is an opt-in
            # allowlist, so everything outside it is expected, declared absence, not a surprise
            # the summary needs to flag the way a default-exclude or -ExcludeFolders carve-out is.
            $allowlistOut = Get-DowserMap -Path $script:tmpRoot -FoldersOnly -IncludeSize -MaxDepth 1 -EmitSummary -IncludeFolders 'A'
            $allowlistOut | Where-Object { $_ -match 'Total size excludes filtered top-level folders:' } | Should -BeNullOrEmpty
        }
    }

    Context 'Markdown summary placement' {
        It 'Places Summary before the fenced tree block and renders the size table' {
            $mdPath = Join-Path $script:outDir 'placement.md'
            $null = Get-DowserMap -Path $script:tmpRoot -FoldersOnly -IncludeSize -MaxDepth 1 -AsMarkdown -MarkdownFile $mdPath
            $content = Get-Content -LiteralPath $mdPath

            $summaryIndex = [array]::IndexOf($content, '#### Summary')
            $fenceIndex = [array]::IndexOf($content, '```text')
            $summaryIndex | Should -BeGreaterThan -1
            $fenceIndex | Should -BeGreaterThan $summaryIndex

            $raw = $content -join "`n"
            $raw | Should -Match '\| Size \| Folder \|'
            $raw | Should -Match '\| 500\.0B \| `A` \|'
            $raw | Should -Match '\| 50\.0B \| `B` \|'
        }
    }
}

Describe 'Get-DowserMap archive-mode summary, output-file, and markdown-file support' {
    BeforeAll {
        $modulePath = Split-Path $PSScriptRoot -Parent
        Remove-Module Dowser -Force -ErrorAction SilentlyContinue
        Import-Module (Join-Path $modulePath 'Dowser.psd1') -Force -ErrorAction Stop

        # Prior to the fix, the -Path-is-an-archive branch returned its tree lines directly,
        # bypassing Complete-DirectoryMapOutput entirely -- -EmitSummary, -OutputFile, and
        # -MarkdownFile were all silent no-ops for a .zip/.7z/.rar/.tar/.gz input. Fixed
        # 2026-09-15 via Complete-DowserArchiveMapOutput, a self-contained archive-mode
        # counterpart (Complete-DirectoryMapOutput itself is defined ~900 lines later in the
        # file and is not yet callable at the point the archive-mode check runs -- PowerShell
        # does not hoist function definitions ahead of sequential execution, confirmed by
        # direct execution before this fix was written).
        $arcWork = Join-Path ([System.IO.Path]::GetTempPath()) 'DowserArchiveSummaryWork'
        Remove-Item -LiteralPath $arcWork -Recurse -Force -ErrorAction SilentlyContinue
        $srcDir = Join-Path $arcWork 'src'
        $folderA = Join-Path $srcDir 'folderA'
        $folderB = Join-Path $srcDir 'folderB'
        $null = New-Item -ItemType Directory -Path $folderA -Force
        $null = New-Item -ItemType Directory -Path $folderB -Force
        [System.IO.File]::WriteAllBytes((Join-Path $folderA 'big.bin'), (New-Object byte[] 500))
        [System.IO.File]::WriteAllBytes((Join-Path $folderB 'small.bin'), (New-Object byte[] 100))
        [System.IO.File]::WriteAllBytes((Join-Path $srcDir 'rootloose.bin'), (New-Object byte[] 50))

        $zipPath = Join-Path $arcWork 'archive.zip'
        Compress-Archive -Path (Join-Path $srcDir '*') -DestinationPath $zipPath

        $corruptZipPath = Join-Path $arcWork 'corrupt.zip'
        'not a real zip' | Out-File -LiteralPath $corruptZipPath -Encoding ascii

        $script:zipPath = $zipPath
        $script:corruptZipPath = $corruptZipPath
        $script:arcOutDir = Join-Path $arcWork 'outputs'
        $null = New-Item -ItemType Directory -Path $script:arcOutDir -Force
    }

    AfterAll {
        $arcWork = Split-Path $script:zipPath -Parent
        if ($arcWork -and (Test-Path -LiteralPath $arcWork)) {
            Remove-Item -LiteralPath $arcWork -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context '-EmitSummary against an archive is no longer a no-op' {
        It 'Emits a Summary block with correct Folders/Files counts' {
            $out = Get-DowserMap -Path $script:zipPath -EmitSummary
            $out | Where-Object { $_ -eq 'Summary:' } | Should -Not -BeNullOrEmpty
            $out | Where-Object { $_ -match '^\s*Folders: 2$' } | Should -Not -BeNullOrEmpty
            $out | Where-Object { $_ -match '^\s*Files: 3$' } | Should -Not -BeNullOrEmpty
        }

        It 'Reports total size and per-top-level-folder size with -IncludeSize' {
            $out = Get-DowserMap -Path $script:zipPath -EmitSummary -IncludeSize
            # folderA (500) + folderB (100) + rootloose.bin (50) = 650
            $out | Where-Object { $_ -match '^\s*Total size: 650\.0B$' } | Should -Not -BeNullOrEmpty
            $out | Where-Object { $_ -match '500\.0B\s+folderA$' } | Should -Not -BeNullOrEmpty
            $out | Where-Object { $_ -match '100\.0B\s+folderB$' } | Should -Not -BeNullOrEmpty
        }

        It 'Emits no summary when -EmitSummary is not requested (backward compatible default)' {
            $out = Get-DowserMap -Path $script:zipPath
            $out | Where-Object { $_ -eq 'Summary:' } | Should -BeNullOrEmpty
        }
    }

    Context '-OutputFile against an archive is no longer a no-op' {
        It 'Actually writes the rendered tree plus summary to disk' {
            $outFile = Join-Path $script:arcOutDir 'archive-map.txt'
            Remove-Item -LiteralPath $outFile -ErrorAction SilentlyContinue
            $null = Get-DowserMap -Path $script:zipPath -EmitSummary -OutputFile $outFile
            Test-Path -LiteralPath $outFile | Should -Be $true
            $content = Get-Content -LiteralPath $outFile -Raw
            $content | Should -Match 'Summary:'
            $content | Should -Match 'folderA'
        }
    }

    Context '-MarkdownFile against an archive is no longer a no-op' {
        It 'Writes a markdown file with title, summary section, and fenced tree' {
            $mdFile = Join-Path $script:arcOutDir 'archive-map.md'
            Remove-Item -LiteralPath $mdFile -ErrorAction SilentlyContinue
            $null = Get-DowserMap -Path $script:zipPath -EmitSummary -MarkdownFile $mdFile
            Test-Path -LiteralPath $mdFile | Should -Be $true
            $content = Get-Content -LiteralPath $mdFile
            $content | Should -Contain '# Directory Map'
            $content | Should -Contain '#### Summary'
            $content | Should -Contain '```text'
            ($content -join "`n") | Should -Match 'folderA'
        }
    }

    Context 'Archive read failure still surfaces its error line through the new return shape' {
        It 'Returns the ARCHIVE UNREADABLE line instead of losing it to a shape mismatch' {
            # The error path inside Get-DowserArchiveTreeLines used to return a bare
            # [string[]], while the success path now returns a richer [PSCustomObject].
            # If the error path had not been updated to match, Complete-DowserArchiveMapOutput
            # reading .Lines off a bare string array would have silently resolved to $null,
            # losing the error message entirely instead of surfacing it.
            $out = Get-DowserMap -Path $script:corruptZipPath
            $out | Where-Object { $_ -match 'ARCHIVE UNREADABLE' } | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Excluded root-level files inside an archive are also named (parity with the filesystem path)' {
        BeforeAll {
            # Found by Huginn/Muninn review of the filesystem-mode fix (entry 2026.09.15.255):
            # the archive path's own top-level total-size loop had the identical blind spot
            # Test-FileExcludedByRule closed on the filesystem side -- a root-level archive
            # entry rejected by an actual exclude rule vanished from TotalBytes with zero
            # signal. Fixed 2026-09-15 via Test-ArcFileExcludedByRule.
            $arcFileExcludeWork = Join-Path ([System.IO.Path]::GetTempPath()) 'DowserArchiveFileExcludeWork'
            Remove-Item -LiteralPath $arcFileExcludeWork -Recurse -Force -ErrorAction SilentlyContinue
            $srcDir2 = Join-Path $arcFileExcludeWork 'src'
            $null = New-Item -ItemType Directory -Path $srcDir2 -Force
            [System.IO.File]::WriteAllBytes((Join-Path $srcDir2 'settings.local.json'), (New-Object byte[] 9000))
            [System.IO.File]::WriteAllBytes((Join-Path $srcDir2 'normal.txt'), (New-Object byte[] 100))
            $script:arcFileExcludeZip = Join-Path $arcFileExcludeWork 'archive.zip'
            Compress-Archive -Path (Join-Path $srcDir2 '*') -DestinationPath $script:arcFileExcludeZip
        }

        AfterAll {
            $w = Split-Path $script:arcFileExcludeZip -Parent
            if ($w -and (Test-Path -LiteralPath $w)) {
                Remove-Item -LiteralPath $w -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Total size reflects only the non-excluded archive entry' {
            $out = Get-DowserMap -Path $script:arcFileExcludeZip -EmitSummary -IncludeSize
            $out | Where-Object { $_ -match '^\s*Total size: 100\.0B$' } | Should -Not -BeNullOrEmpty
        }

        It 'Names the excluded root-level archive entry, on the file-specific summary line' {
            $out = Get-DowserMap -Path $script:arcFileExcludeZip -EmitSummary -IncludeSize
            $out | Where-Object { $_ -match 'Total size excludes filtered top-level files:.*settings\.local\.json' } | Should -Not -BeNullOrEmpty
        }
    }

    Context '-LinuxPaths markdown Root header matches the filesystem path''s own behavior' {
        It 'Applies the same WSL-path conversion rule as Complete-DirectoryMapOutput for an already-Unix-style path' {
            # Found by Huginn/Muninn review: Complete-DowserArchiveMapOutput's markdown Root
            # header ignored -LinuxPaths entirely, always rendering the raw archive path even
            # when the filesystem path would run it through ConvertTo-WslPath. Fixed
            # 2026-09-15 by wiring -LinuxPaths through to Complete-DowserArchiveMapOutput and
            # calling the (now shared, relocated) ConvertTo-WslPath. On this platform, an
            # already-Unix-style path is a correct no-op for ConvertTo-WslPath (it only
            # transforms Windows drive-letter/UNC paths), so this test asserts TRUE PARITY --
            # archive-mode and filesystem-mode produce the identical Root line for the same
            # already-Unix-style path and the same -LinuxPaths flag -- rather than asserting
            # a specific /mnt/-style string that would be platform-dependent.
            $work = Join-Path ([System.IO.Path]::GetTempPath()) 'DowserLinuxPathsParityWork'
            Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
            $null = New-Item -ItemType Directory -Path $work -Force
            'x' | Out-File (Join-Path $work 'file.txt')
            $zipSrc = Join-Path $work 'zipsrc'
            $null = New-Item -ItemType Directory -Path $zipSrc -Force
            'x' | Out-File (Join-Path $zipSrc 'file.txt')
            $zipPath = Join-Path $work 'archive.zip'
            Compress-Archive -Path (Join-Path $zipSrc '*') -DestinationPath $zipPath

            try {
                $mdFs = Join-Path $work 'fs.md'
                $null = Get-DowserMap -Path $work -LinuxPaths -MarkdownFile $mdFs -MaxDepth 1
                $fsRootLine = Get-Content -LiteralPath $mdFs | Where-Object { $_ -match '\*\*Root:\*\*' }

                $mdArc = Join-Path $work 'arc.md'
                $null = Get-DowserMap -Path $zipPath -LinuxPaths -MarkdownFile $mdArc
                $arcRootLine = Get-Content -LiteralPath $mdArc | Where-Object { $_ -match '\*\*Root:\*\*' }

                $fsRootLine | Should -Match ([regex]::Escape($work))
                $arcRootLine | Should -Match ([regex]::Escape($zipPath))
            }
            finally {
                Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Get-DowserMap -IncludeFolders scoping, -MaxDepth, and parameter binding' {
    BeforeAll {
        $modulePath = Split-Path $PSScriptRoot -Parent
        Remove-Module Dowser -Force -ErrorAction SilentlyContinue
        Import-Module (Join-Path $modulePath 'Dowser.psd1') -Force -ErrorAction Stop

        # Mirrors the operator's ~/projects/modules layout that exposed the defects:
        # -IncludeFolders py, ts stopped at py/ and ts/ because the filter was re-applied at
        # every depth, so 'pyconfig' was tested against 'py' and dropped.
        $root = Join-Path ([System.IO.Path]::GetTempPath()) 'DowserIncludeScopeRoot'
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        foreach ($rel in @('py/pyconfig/docs', 'py/pyconfig/tests', 'py/pydates/docs', 'ts/tsconfig/tests', 'js/jsdates/docs')) {
            $null = New-Item -ItemType Directory -Path (Join-Path $root $rel) -Force
        }
        [System.IO.File]::WriteAllText((Join-Path $root 'LICENSE'), 'x')
        [System.IO.File]::WriteAllText((Join-Path $root 'py/INDEX.md'), 'x')
        [System.IO.File]::WriteAllText((Join-Path $root 'py/pyconfig/config.py'), 'x')

        $script:canLink = $false
        try {
            $null = New-Item -ItemType SymbolicLink -Path (Join-Path $root 'py/pyconfig/DOCTRINE.md') -Target (Join-Path $root 'LICENSE') -ErrorAction Stop
            $script:canLink = $true
        }
        catch {
            $script:canLink = $false
        }
        $script:incRoot = $root
    }

    AfterAll {
        if ($script:incRoot -and (Test-Path -LiteralPath $script:incRoot)) {
            Remove-Item -LiteralPath $script:incRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Name entries render the matched folder''s subtree' {
        It 'Shows subfolders of each included folder instead of stopping at it' {
            $out = Get-DowserMap -Path $script:incRoot -IncludeFolders py, ts -FoldersOnly -MaxDepth 1
            $out | Where-Object { $_ -match 'pyconfig[\\/]' } | Should -Not -BeNullOrEmpty
            $out | Where-Object { $_ -match 'pydates[\\/]' } | Should -Not -BeNullOrEmpty
            $out | Where-Object { $_ -match 'tsconfig[\\/]' } | Should -Not -BeNullOrEmpty
        }

        It 'Excludes folders that are not included' {
            $out = Get-DowserMap -Path $script:incRoot -IncludeFolders py, ts -FoldersOnly -MaxDepth 3
            $out | Where-Object { $_ -match '\bjs' } | Should -BeNullOrEmpty
        }

        It '-MaxDepth takes effect inside an included folder' {
            $shallow = Get-DowserMap -Path $script:incRoot -IncludeFolders py -FoldersOnly -MaxDepth 1
            $deep = Get-DowserMap -Path $script:incRoot -IncludeFolders py -FoldersOnly -MaxDepth 2
            $shallow | Where-Object { $_ -match 'docs[\\/]' } | Should -BeNullOrEmpty
            $deep | Where-Object { $_ -match 'docs[\\/]' } | Should -Not -BeNullOrEmpty
        }

        It 'Hides loose files at the root but keeps files inside the included folder' {
            $out = Get-DowserMap -Path $script:incRoot -IncludeFolders py -MaxDepth 2
            # Anchored to a file line: the DOCTRINE.md symlink's target line also ends in LICENSE.
            $out | Where-Object { $_ -match ([char]0x00B7 + ' LICENSE$') } | Should -BeNullOrEmpty
            $out | Where-Object { $_ -match 'INDEX\.md' } | Should -Not -BeNullOrEmpty
            $out | Where-Object { $_ -match 'config\.py' } | Should -Not -BeNullOrEmpty
        }

        It 'Behaves the same in -ShowFullPathTree:$false mode (the twin render branch)' {
            $out = Get-DowserMap -Path $script:incRoot -ShowFullPathTree:$false -IncludeFolders py, ts -FoldersOnly -MaxDepth 1
            $out | Where-Object { $_ -match 'pyconfig[\\/]' } | Should -Not -BeNullOrEmpty
            $out | Where-Object { $_ -match 'tsconfig[\\/]' } | Should -Not -BeNullOrEmpty
            $out | Where-Object { $_ -match ([char]0x00B7 + ' LICENSE$') } | Should -BeNullOrEmpty
        }
    }

    Context 'Path entries are relative to -Path' {
        It 'py/pyconfig selects exactly that folder and the route to it' {
            $out = Get-DowserMap -Path $script:incRoot -IncludeFolders 'py/pyconfig' -FoldersOnly -MaxDepth 3
            $out | Where-Object { $_ -match 'pyconfig[\\/]' } | Should -Not -BeNullOrEmpty
            $out | Where-Object { $_ -match 'tests[\\/]' } | Should -Not -BeNullOrEmpty
            $out | Where-Object { $_ -match 'pydates' } | Should -BeNullOrEmpty
            $out | Where-Object { $_ -match 'tsconfig' } | Should -BeNullOrEmpty
        }

        It '-ExcludePathPatterns relative paths resolve against the scan root below depth 0' {
            $out = Get-DowserMap -Path $script:incRoot -FoldersOnly -MaxDepth 3 -ExcludePathPatterns 'py/pyconfig'
            $out | Where-Object { $_ -match 'pyconfig' } | Should -BeNullOrEmpty
            $out | Where-Object { $_ -match 'pydates[\\/]' } | Should -Not -BeNullOrEmpty
        }
    }

    Context '-FoldersOnly and file symlinks' {
        It 'Does not list file symlinks below the root under -FoldersOnly' {
            if (-not $script:canLink) {
                Set-ItResult -Skipped -Because 'symlink creation not available'
                return
            }
            $out = Get-DowserMap -Path $script:incRoot -FoldersOnly -MaxDepth 3
            $out | Where-Object { $_ -match 'DOCTRINE\.md' } | Should -BeNullOrEmpty
            $out | Where-Object { $_ -match 'pyconfig[\\/]' } | Should -Not -BeNullOrEmpty
        }

        It '-ExcludePathPatterns hides file and folder symlinks in both render branches (Huginn review 1454)' {
            if (-not $script:canLink) {
                Set-ItResult -Skipped -Because 'symlink creation not available'
                return
            }
            $linkDir = Join-Path $script:incRoot 'ts/linkeddir'
            if (-not (Test-Path -LiteralPath $linkDir)) {
                $null = New-Item -ItemType SymbolicLink -Path $linkDir -Target (Join-Path $script:incRoot 'js') -ErrorAction Stop
            }
            foreach ($trunk in @($true, $false)) {
                $out = Get-DowserMap -Path $script:incRoot -ShowFullPathTree:$trunk -MaxDepth 3 -ExcludePathPatterns '*DOCTRINE*', '*linkeddir*'
                $out | Where-Object { $_ -match 'DOCTRINE\.md' } | Should -BeNullOrEmpty -Because "ShowFullPathTree=$trunk"
                $out | Where-Object { $_ -match 'linkeddir' } | Should -BeNullOrEmpty -Because "ShowFullPathTree=$trunk"
            }
            $control = Get-DowserMap -Path $script:incRoot -ShowFullPathTree:$false -MaxDepth 3
            $control | Where-Object { $_ -match 'linkeddir' } | Should -Not -BeNullOrEmpty
        }

        It 'Still lists file symlinks when -FoldersOnly is off' {
            if (-not $script:canLink) {
                Set-ItResult -Skipped -Because 'symlink creation not available'
                return
            }
            $out = Get-DowserMap -Path $script:incRoot -MaxDepth 3
            $out | Where-Object { $_ -match 'DOCTRINE\.md' } | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Size and count accounting stays inside the -IncludeFolders scope (Muninn review 1452)' {
        BeforeAll {
            $sizeRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'DowserIncludeSizeRoot'
            Remove-Item -LiteralPath $sizeRoot -Recurse -Force -ErrorAction SilentlyContinue
            foreach ($rel in @('selected', 'outer/inner', 'outer/other', 'logs/target')) {
                $null = New-Item -ItemType Directory -Path (Join-Path $sizeRoot $rel) -Force
            }
            [System.IO.File]::WriteAllBytes((Join-Path $sizeRoot 'loose.txt'), (New-Object byte[] 20))
            [System.IO.File]::WriteAllBytes((Join-Path $sizeRoot 'selected/scoped.txt'), (New-Object byte[] 10))
            [System.IO.File]::WriteAllBytes((Join-Path $sizeRoot 'outer/outerloose.txt'), (New-Object byte[] 300))
            [System.IO.File]::WriteAllBytes((Join-Path $sizeRoot 'outer/inner/in.txt'), (New-Object byte[] 40))
            [System.IO.File]::WriteAllBytes((Join-Path $sizeRoot 'outer/other/o.txt'), (New-Object byte[] 500))
            [System.IO.File]::WriteAllBytes((Join-Path $sizeRoot 'logs/target/inside.txt'), (New-Object byte[] 7))
            $script:sizeRoot = $sizeRoot
        }

        AfterAll {
            if ($script:sizeRoot -and (Test-Path -LiteralPath $script:sizeRoot)) {
                Remove-Item -LiteralPath $script:sizeRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Total size does not count loose root files hidden by -IncludeFolders' {
            $out = Get-DowserMap -Path $script:sizeRoot -IncludeFolders selected -IncludeSize -EmitSummary -FoldersOnly
            $out | Where-Object { $_ -match '^\s*Total size: 10\.0B$' } | Should -Not -BeNullOrEmpty
        }

        It 'A route folder annotates and totals only its in-scope descendants' {
            # outer/ is only the route to outer/inner: its own 300B file and outer/other (500B)
            # are out of scope. Only inner's 40B counts, on the outer/ line and in the total.
            $out = Get-DowserMap -Path $script:sizeRoot -IncludeFolders 'outer/inner' -IncludeSize -IncludeFileCount -EmitSummary -FoldersOnly
            $out | Where-Object { $_ -match 'outer[\\/] \[40\.0B\] \[1 files\]' } | Should -Not -BeNullOrEmpty
            $out | Where-Object { $_ -match '^\s*Total size: 40\.0B$' } | Should -Not -BeNullOrEmpty
        }

        It 'A path include below default-excluded ancestors reaches the target' {
            # both 'logs' and 'target' are default-excluded folder names
            $out = Get-DowserMap -Path $script:sizeRoot -IncludeFolders 'logs/target' -MaxDepth 3
            $out | Where-Object { $_ -match 'target[\\/]' } | Should -Not -BeNullOrEmpty
            $out | Where-Object { $_ -match 'inside\.txt' } | Should -Not -BeNullOrEmpty
        }

        It 'Default excludes still apply inside an included folder' {
            $null = New-Item -ItemType Directory -Path (Join-Path $script:sizeRoot 'selected/node_modules') -Force
            [System.IO.File]::WriteAllBytes((Join-Path $script:sizeRoot 'selected/node_modules/dep.js'), (New-Object byte[] 999))
            $out = Get-DowserMap -Path $script:sizeRoot -IncludeFolders selected -IncludeSize -EmitSummary -MaxDepth 3
            $out | Where-Object { $_ -match 'node_modules' } | Should -BeNullOrEmpty
            $out | Where-Object { $_ -match '^\s*Total size: 10\.0B$' } | Should -Not -BeNullOrEmpty
        }
    }

    Context '-Ascii glyphs' {
        It 'Uses a single backslash for the last-child connector' {
            $out = Get-DowserMap -Path $script:incRoot -FoldersOnly -MaxDepth 0 -Ascii
            $out | Where-Object { $_ -match '\\\\-' } | Should -BeNullOrEmpty
            $out | Where-Object { $_ -match '^\s*\\- \+ ' } | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Parameter binding' {
        It 'Rejects stray positional arguments instead of silently binding them to filters' {
            # 'max 1' without a dash used to bind to -IncludeFilePatterns/-IncludeExtensions
            # and return an empty tree with no error.
            { Get-DowserMap $script:incRoot -FoldersOnly max 1 } | Should -Throw -ErrorId 'PositionalParameterNotFound,Get-DowserMap'
        }

        It 'Still accepts -Path positionally' {
            $out = Get-DowserMap $script:incRoot -FoldersOnly -MaxDepth 0
            $out | Where-Object { $_ -match ' py[\\/]$' } | Should -Not -BeNullOrEmpty
        }
    }
}
