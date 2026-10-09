function Get-DowserRelativeFileMap {
    <#
    .SYNOPSIS
        Maps every file under a root to its forward-slash relative path, pruning excluded folders.
    .NOTES
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
        -  Author:        Curtis Leggett                                  -
        =  Copyright:     2026 Divergent Cortex                           =
        -  Organization:  Divergent Cortex                                -
        =  Version:       See docs/CHANGELOG.md                           =
        =-=-                       =-=-=-=-=-=-=-=                     -=-=
        -  it is not water they seek, but the truth beneath the trees     -
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
    .DESCRIPTION
        Walks -Root with an explicit directory stack so excluded folders are never entered
        (Get-ChildItem -Recurse -Exclude only hides matches from output and still descends).
        A folder is pruned when its name is in -ExcludeNames or its name or relative path
        matches any -ExcludePatterns wildcard; files are dropped on the same pattern test.
        Symlinked directories are listed nowhere and never followed, so a link loop or a link
        out to a large tree cannot inflate the map. Hidden items are included.

        Keys are relative paths with forward slashes. The map compares keys case-sensitively
        on Linux/macOS and case-insensitively on Windows, matching each filesystem.
    .PARAMETER Root
        Resolved directory to walk.
    .PARAMETER ExcludeNames
        Exact folder names to prune (for example .git, node_modules).
    .PARAMETER ExcludePatterns
        Wildcards tested against each item's name and its relative path.
    .OUTPUTS
        PSCustomObject with Map (Dictionary[string, FileInfo]) and Errors (count of paths that
        could not be listed).
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [string[]]$ExcludeNames = @(),

        [string[]]$ExcludePatterns = @()
    )

    $comparer = if ($IsWindows -or $PSVersionTable.PSVersion.Major -lt 6) {
        [System.StringComparer]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparer]::Ordinal
    }
    $map = New-Object 'System.Collections.Generic.Dictionary[string,System.IO.FileInfo]' ($comparer)
    $errors = 0
    $rootFull = $Root.TrimEnd('/', '\')

    function Test-Excluded([string]$name, [string]$rel) {
        foreach ($pattern in $ExcludePatterns) {
            if ($name -like $pattern -or $rel -like $pattern) {
                return $true
            }
        }
        return $false
    }

    $stack = New-Object 'System.Collections.Generic.Stack[string]'
    $stack.Push($rootFull)
    while ($stack.Count -gt 0) {
        $dir = $stack.Pop()
        $children = $null
        try {
            $children = @(Get-ChildItem -LiteralPath $dir -Force -ErrorAction Stop)
        }
        catch {
            $errors++
            Write-Log "Get-DowserRelativeFileMap could not list '$dir': $($_.Exception.Message)" -Severity Verbose
            continue
        }
        foreach ($child in $children) {
            $rel = $child.FullName.Substring($rootFull.Length).TrimStart('/', '\') -replace '\\', '/'
            if ($child.PSIsContainer) {
                $isLink = ($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
                if ($isLink -or ($ExcludeNames -contains $child.Name) -or (Test-Excluded $child.Name $rel)) {
                    continue
                }
                $stack.Push($child.FullName)
            }
            elseif (-not (Test-Excluded $child.Name $rel)) {
                $map[$rel] = $child
            }
        }
    }

    return [PSCustomObject]@{ Map = $map; Errors = $errors }
}
