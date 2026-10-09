function Format-DowserAge {
    <#
    .SYNOPSIS
        Formats how long ago a timestamp was as a short human-readable string.
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
        Renders the elapsed time between -Timestamp and -Now as minutes under an hour
        ("42m ago"), hours under a day ("5h ago"), or whole days otherwise ("12d ago").
        A $null timestamp returns an empty string so a folder with no files renders a
        blank cell instead of an error. A timestamp in the future (clock skew, copied
        files) renders "in future" rather than a negative age.
    .PARAMETER Timestamp
        The point in time to describe. $null returns an empty string.
    .PARAMETER Now
        The reference time. Defaults to the current time; exposed so callers and tests
        can compute every row against one fixed instant.
    .EXAMPLE
        Format-DowserAge -Timestamp (Get-Date).AddHours(-5)

        Returns "5h ago".
    .INPUTS
        None.
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    param (
        [AllowNull()]
        [Nullable[datetime]]$Timestamp,

        [datetime]$Now = (Get-Date)
    )

    if ($null -eq $Timestamp) {
        return ''
    }
    # PowerShell unwraps a bound [Nullable[datetime]] to a plain DateTime, so .Value is $null.
    $elapsed = $Now - [datetime]$Timestamp
    if ($elapsed.TotalSeconds -lt 0) {
        return 'in future'
    }
    if ($elapsed.TotalHours -lt 1) {
        return ('{0}m ago' -f [int][Math]::Floor($elapsed.TotalMinutes))
    }
    if ($elapsed.TotalDays -lt 1) {
        return ('{0}h ago' -f [int][Math]::Floor($elapsed.TotalHours))
    }
    return ('{0}d ago' -f [int][Math]::Floor($elapsed.TotalDays))
}
