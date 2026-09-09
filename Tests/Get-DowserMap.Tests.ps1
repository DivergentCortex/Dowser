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
