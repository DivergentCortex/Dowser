function Get-DowserProcessReference {
    <#
    .SYNOPSIS
        Lists the strings one Linux process holds that mention any of the given folders.
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
        Reads, from one /proc/<pid> folder, the working directory, the executable, every open
        file descriptor, the mapped files and the command line arguments, and keeps the ones
        that contain any -RootPrefix text. A process that exits mid-read is not a failure. A
        read the user is not allowed to make counts in Unreadable. Nothing is logged per
        process; the caller reports the totals.
    .PARAMETER ProcDirectory
        The /proc/<pid> folder.
    .PARAMETER RootPrefix
        Folder paths to look for.
    .EXAMPLE
        Get-DowserProcessReference -ProcDirectory /proc/1234 -RootPrefix '/home/me/.claude/plugins/cache'

        Returns the paths process 1234 holds under that cache.
    .OUTPUTS
        PSCustomObject with Paths and Unreadable.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProcDirectory,

        [Parameter(Mandatory = $true)]
        [string[]]$RootPrefix
    )

    $held = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $unreadable = 0
    $keepIfUnderRoot = {
        param($text)
        if ([string]::IsNullOrEmpty($text)) { return }
        foreach ($prefix in $RootPrefix) {
            if ($text.IndexOf($prefix, [System.StringComparison]::Ordinal) -ge 0) {
                [void]$held.Add($text)
                return
            }
        }
    }

    foreach ($linkName in @('cwd', 'exe')) {
        try {
            & $keepIfUnderRoot ([System.IO.FileInfo]::new((Join-Path $ProcDirectory $linkName)).LinkTarget)
        }
        catch {
            if (Test-Path -LiteralPath $ProcDirectory) { $unreadable++ }
        }
    }

    $descriptors = @()
    try {
        $descriptors = [System.IO.Directory]::GetFileSystemEntries((Join-Path $ProcDirectory 'fd'))
    }
    catch {
        if (Test-Path -LiteralPath $ProcDirectory) { $unreadable++ }
    }
    foreach ($descriptor in $descriptors) {
        try {
            & $keepIfUnderRoot ([System.IO.FileInfo]::new($descriptor).LinkTarget)
        }
        catch {
            # a descriptor closes between the listing and the read
            continue
        }
    }

    try {
        foreach ($line in [System.IO.File]::ReadLines((Join-Path $ProcDirectory 'maps'))) {
            $slash = $line.IndexOf('/')
            if ($slash -ge 0) {
                & $keepIfUnderRoot $line.Substring($slash)
            }
        }
    }
    catch {
        if (Test-Path -LiteralPath $ProcDirectory) { $unreadable++ }
    }

    try {
        foreach ($argument in [System.IO.File]::ReadAllText((Join-Path $ProcDirectory 'cmdline')).Split([char]0)) {
            & $keepIfUnderRoot $argument
        }
    }
    catch {
        if (Test-Path -LiteralPath $ProcDirectory) { $unreadable++ }
    }

    # a seat started from a cache version keeps that path in its environment and hands it to its children
    try {
        foreach ($variable in [System.IO.File]::ReadAllText((Join-Path $ProcDirectory 'environ')).Split([char]0)) {
            $equals = $variable.IndexOf('=')
            if ($equals -ge 0) {
                & $keepIfUnderRoot $variable.Substring($equals + 1)
            }
        }
    }
    catch {
        if (Test-Path -LiteralPath $ProcDirectory) { $unreadable++ }
    }

    return [pscustomobject]@{ Paths = @($held); Unreadable = $unreadable }
}
