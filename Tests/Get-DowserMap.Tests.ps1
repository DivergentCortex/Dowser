#Requires -Modules @{ModuleName='Pester';ModuleVersion='5.0'}

Describe 'Get-DowserMap symlink rendering' {
    BeforeAll {
        $modulePath = Split-Path $PSScriptRoot -Parent
        Remove-Module Dowser -Force -ErrorAction SilentlyContinue
        Import-Module (Join-Path $modulePath 'Dowser.psd1') -Force -ErrorAction Stop

        # target lives OUTSIDE the mapped root so it is never traversed directly
        $tmpTarget = Join-Path ([System.IO.Path]::GetTempPath()) "DowserSymTarget_$([System.IO.Path]::GetRandomFileName())"
        $tmpRoot   = Join-Path ([System.IO.Path]::GetTempPath()) "DowserSymRoot_$([System.IO.Path]::GetRandomFileName())"
        $null = New-Item -ItemType Directory -Path $tmpTarget -Force
        $null = New-Item -ItemType Directory -Path $tmpRoot   -Force

        # plant a file inside the target so traversal is detectable
        $innerFile = Join-Path $tmpTarget 'inner.txt'
        [System.IO.File]::WriteAllText($innerFile, 'y')

        # symlink inside mapped root -> target outside mapped root
        $linkPath = Join-Path $tmpRoot 'the-link'
        $canSymlink = $false
        try {
            $null = New-Item -ItemType SymbolicLink -Path $linkPath -Target $tmpTarget -ErrorAction Stop
            $canSymlink = (Test-Path -LiteralPath $linkPath)
        } catch { $canSymlink = $false }

        # sibling file after the link so the-link is NOT the last item (sorts before z-*)
        $siblingFile = Join-Path $tmpRoot 'z-sibling.txt'
        [System.IO.File]::WriteAllText($siblingFile, 'x')

        $script:tmpRoot    = $tmpRoot
        $script:tmpTarget  = $tmpTarget
        $script:canSymlink = $canSymlink
    }

    AfterAll {
        foreach ($p in @($script:tmpRoot, $script:tmpTarget)) {
            if ($p -and (Test-Path -LiteralPath $p)) {
                Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Default (no -FollowReparse)' {
        BeforeAll {
            if ($script:canSymlink) {
                $script:out = Get-DowserMap -Path $script:tmpRoot -ShowFullPathTree:$false -NoDefaultExcludes
            }
        }

        It 'Emits arrow line containing link name' -Skip:(-not $script:canSymlink) {
            $linkLine = $script:out | Where-Object { $_ -match [char]0x2192 -and $_ -match 'the-link' }
            $linkLine | Should -Not -BeNullOrEmpty
        }

        It 'Emits target line with resolved path' -Skip:(-not $script:canSymlink) {
            $targetLine = $script:out | Where-Object { $_ -match [char]0x21B3 }
            $targetLine | Should -Not -BeNullOrEmpty
            $targetLine | Should -Match ([regex]::Escape((Split-Path $script:tmpTarget -Leaf)))
        }

        It 'Does not descend into the link (inner.txt must not appear)' -Skip:(-not $script:canSymlink) {
            $script:out | Where-Object { $_ -match 'inner\.txt' } | Should -BeNullOrEmpty
        }

        It 'Target line carries continuation bar for non-last-child symlink' -Skip:(-not $script:canSymlink) {
            # the-link sorts before z-sibling.txt so it is NOT the last child
            $targetLine = $script:out | Where-Object { $_ -match [char]0x21B3 }
            $targetLine | Should -Match ([char]0x2502)
        }
    }

    Context '-FollowReparse still descends' {
        It 'Finds inner.txt when -FollowReparse is set' -Skip:(-not $script:canSymlink) {
            $out = Get-DowserMap -Path $script:tmpRoot -ShowFullPathTree:$false -NoDefaultExcludes -MaxDepth 5 -FollowReparse
            $out | Where-Object { $_ -match 'inner\.txt' } | Should -Not -BeNullOrEmpty
        }
    }

    Context '-AsHtml emits HTML entities' {
        BeforeAll {
            if ($script:canSymlink) {
                $script:htmlOut = Get-DowserMap -Path $script:tmpRoot -ShowFullPathTree:$false -NoDefaultExcludes -AsHtml
            }
        }

        It 'Emits &#x2192; entity on link name line' -Skip:(-not $script:canSymlink) {
            $script:htmlOut | Where-Object { $_ -match '&#x2192;' -and $_ -match 'the-link' } | Should -Not -BeNullOrEmpty
        }

        It 'Emits &#x21B3; entity on target line' -Skip:(-not $script:canSymlink) {
            $script:htmlOut | Where-Object { $_ -match '&#x21B3;' } | Should -Not -BeNullOrEmpty
        }
    }
}
