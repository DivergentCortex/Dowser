
function Get-DowserSeatVersionHold {
    <#
    .SYNOPSIS
        Decides which versions of one plugin the running seats must have loaded, from their start times.
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
        A seat reads its plugin files into memory when it starts and keeps none of them open, so
        the only proof of what it loaded is when it started. For each seat the version it loaded
        is the newest one the cache already held at that moment: the newest rankable version
        whose folder was created at or before the seat's start. That version is held, and so is
        the next older one, because a folder that was still being copied in at the start would
        have left the seat on the older one. When no folder is old enough, the cache has since
        lost the version the seat loaded, and the oldest remaining version is held as the
        closest one. Nothing is held for a plugin when no seat is running.

        When any seat has no known start time, or any rankable folder has no usable creation
        time, nothing can be attributed and every version is held (AllHeld). The start and
        creation times are plain inputs, so a test can drive every case without touching real
        file times or processes.
    .PARAMETER Version
        One object per version folder with Version, VersionKey (null when the name has no
        dotted-number order) and BirthUtc (when the folder was created).
    .PARAMETER Seat
        One object per running seat with StartKnown and StartUtc.
    .EXAMPLE
        Get-DowserSeatVersionHold -Version $rows -Seat $seats

        Returns the version names the seats loaded, or AllHeld when that cannot be told.
    .OUTPUTS
        PSCustomObject with HeldVersions, AllHeld and Reason.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [AllowEmptyCollection()]
        [object[]]$Version = @(),

        [AllowEmptyCollection()]
        [object[]]$Seat = @()
    )

    $earliestUsableBirth = [datetime]::new(1971, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc)
    # boot time has whole-second resolution, so a start time can read up to a second early
    $startSkewSeconds = 2
    $held = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $result = {
        param($all, $reason)
        [pscustomobject]@{ HeldVersions = @($held); AllHeld = $all; Reason = $reason }
    }

    if ($Seat.Count -eq 0) {
        return (& $result $false $null)
    }
    if (@($Seat | Where-Object { -not $_.StartKnown -or $null -eq $_.StartUtc }).Count -gt 0) {
        return (& $result $true 'SeatStartUnknown')
    }

    $rankable = @($Version | Where-Object { $null -ne $_.VersionKey } | Sort-Object VersionKey -Descending)
    if (@($rankable | Where-Object { $null -eq $_.BirthUtc -or $_.BirthUtc -lt $earliestUsableBirth }).Count -gt 0) {
        return (& $result $true 'BirthTimeUnknown')
    }

    foreach ($running in $Seat) {
        $loaded = -1
        $startLimit = $running.StartUtc.AddSeconds($startSkewSeconds)
        for ($index = 0; $index -lt $rankable.Count; $index++) {
            if ($rankable[$index].BirthUtc -le $startLimit) { $loaded = $index; break }
        }
        if ($loaded -ge 0) {
            [void]$held.Add([string]$rankable[$loaded].Version)
            if ($loaded + 1 -lt $rankable.Count) { [void]$held.Add([string]$rankable[$loaded + 1].Version) }
        }
        elseif ($rankable.Count -gt 0) {
            [void]$held.Add([string]$rankable[$rankable.Count - 1].Version)
        }
    }
    return (& $result $false $null)
}
