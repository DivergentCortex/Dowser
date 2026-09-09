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
        $dirB = Join-Path $tmpRoot 'B'
        $null = New-Item -ItemType Directory -Path $dirA -Force
        $null = New-Item -ItemType Directory -Path $dirB -Force

        # known byte counts so the size math below is a real assertion, not a smell test
        [System.IO.File]::WriteAllBytes((Join-Path $dirA 'a1.txt'), [byte[]](1..100))
        [System.IO.File]::WriteAllBytes((Join-Path $dirB 'b1.txt'), [byte[]](1..50))

        $script:tmpRoot = $tmpRoot
    }

    AfterAll {
        if ($script:tmpRoot -and (Test-Path -LiteralPath $script:tmpRoot)) {
            Remove-Item -LiteralPath $script:tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
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
            $mdPath = Join-Path $script:tmpRoot 'auto.md'
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

        It 'Reports total size as the sum of top-level folder sizes' {
            $script:out | Where-Object { $_ -match '^\s*Total size: 150\.0B$' } | Should -Not -BeNullOrEmpty
        }

        It 'Lists both known folders at their correct sizes in the largest-folders section' {
            $joined = $script:out -join "`n"
            $joined | Should -Match '100\.0B\s+A'
            $joined | Should -Match '50\.0B\s+B'
        }

        It 'Omits the size rollup when -IncludeSize is not set' {
            $noSizeOut = Get-DowserMap -Path $script:tmpRoot -FoldersOnly -MaxDepth 1 -EmitSummary
            $noSizeOut | Where-Object { $_ -match 'Total size:' } | Should -BeNullOrEmpty
        }
    }

    Context 'Markdown summary placement' {
        It 'Places Summary before the fenced tree block and renders the size table' {
            $mdPath = Join-Path $script:tmpRoot 'placement.md'
            $null = Get-DowserMap -Path $script:tmpRoot -FoldersOnly -IncludeSize -MaxDepth 1 -AsMarkdown -MarkdownFile $mdPath
            $content = Get-Content -LiteralPath $mdPath

            $summaryIndex = [array]::IndexOf($content, '#### Summary')
            $fenceIndex = [array]::IndexOf($content, '```text')
            $summaryIndex | Should -BeGreaterThan -1
            $fenceIndex | Should -BeGreaterThan $summaryIndex

            $raw = $content -join "`n"
            $raw | Should -Match '\| Size \| Folder \|'
            $raw | Should -Match '\| 100\.0B \| `A` \|'
            $raw | Should -Match '\| 50\.0B \| `B` \|'
        }
    }
}
