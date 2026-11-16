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
        file descriptor, the mapped files, the command line arguments and the environment, and
        keeps the ones that contain any -RootPrefix text. A process that exits mid-read is not a
        failure. A read the user is not allowed to make counts in Unreadable. Nothing is logged
        per process; the caller reports the totals.

        A process is also reported as a seat when its program name, taken from the last part of
        argv[0] or of the executable link, is one of -SeatName. A seat keeps no path under the
        cache open, because its plugin files are read into memory when it starts, so the paths
        above cannot show which version it loaded. Its start time can: the version it loaded is
        the one the cache held when it started. SeatStartKnown is false when the start time
        could not be read.
    .PARAMETER ProcDirectory
        The /proc/<pid> folder.
    .PARAMETER RootPrefix
        Folder paths to look for, in every spelling a process might use.
    .PARAMETER SeatName
        Program names that count as a seat, such as claude.
    .PARAMETER BootTimeUtc
        When the machine booted; needed to turn a start tick count into a time.
    .EXAMPLE
        Get-DowserProcessReference -ProcDirectory /proc/1234 -RootPrefix '/home/me/.claude/plugins/cache'

        Returns the paths process 1234 holds under that cache.
    .OUTPUTS
        PSCustomObject with Paths, Unreadable, SeatName, SeatStartKnown and SeatStartUtc.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProcDirectory,

        [Parameter(Mandatory = $true)]
        [string[]]$RootPrefix,

        [string[]]$SeatName = @(),

        [datetime]$BootTimeUtc
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

    $exeTarget = $null
    $argumentList = @()
    foreach ($linkName in @('cwd', 'exe')) {
        try {
            $target = [System.IO.FileInfo]::new((Join-Path $ProcDirectory $linkName)).LinkTarget
            if ($linkName -eq 'exe') { $exeTarget = $target }
            & $keepIfUnderRoot $target
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
        $argumentList = @([System.IO.File]::ReadAllText((Join-Path $ProcDirectory 'cmdline')).Split([char]0))
        foreach ($argument in $argumentList) {
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

    $seat = $null
    $startKnown = $false
    $startUtc = $null
    if ($SeatName.Count -gt 0) {
        # a deleted executable reads as 'name (deleted)', and a launcher may add .exe or .js
        $programName = {
            param($path)
            if ([string]::IsNullOrEmpty($path)) { return '' }
            $live = $path -replace ' \(deleted\)$', ''
            $leaf = [System.IO.Path]::GetFileName($live)
            return ($leaf -replace '\.(exe|js)$', '')
        }
        $names = @((& $programName ($argumentList | Select-Object -First 1)), (& $programName $exeTarget))
        foreach ($candidate in $SeatName) {
            if ($names -contains $candidate) { $seat = $candidate; break }
        }
        if ($null -ne $seat -and $PSBoundParameters.ContainsKey('BootTimeUtc')) {
            $start = Get-DowserProcessStartTime -ProcDirectory $ProcDirectory -BootTimeUtc $BootTimeUtc
            $startKnown = $start.Success
            $startUtc = $start.StartUtc
        }
    }

    return [pscustomobject]@{
        Paths          = @($held)
        Unreadable     = $unreadable
        SeatName       = $seat
        SeatStartKnown = $startKnown
        SeatStartUtc   = $startUtc
    }
}
