
function Get-DowserProcessStartTime {
    <#
    .SYNOPSIS
        Reads when a Linux process started from its /proc stat file.
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
        Field 22 of /proc/<pid>/stat is the start time in clock ticks since boot. The command
        name in field 2 sits in parentheses and may hold spaces, so the fields are counted from
        the last closing parenthesis. User space always sees 100 ticks per second on Linux.
        The result is Success false, never an exception, when the file cannot be read or parsed,
        and the caller must then treat the process as started at an unknown time.
    .PARAMETER ProcDirectory
        The /proc/<pid> folder.
    .PARAMETER BootTimeUtc
        When the machine booted, from the btime line of /proc/stat.
    .EXAMPLE
        Get-DowserProcessStartTime -ProcDirectory /proc/1234 -BootTimeUtc $boot

        Returns the UTC start time of process 1234.
    .OUTPUTS
        PSCustomObject with Success, StartUtc, Reason, ExceptionType, Message, ExitCode.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ProcDirectory,

        [Parameter(Mandatory = $true)]
        [datetime]$BootTimeUtc
    )

    $ticksPerSecond = 100
    $startTicksField = 19
    $outcome = {
        param($success, $start, $reason, $exception, $code)
        [pscustomobject]@{
            Success       = $success
            StartUtc      = $start
            Reason        = $reason
            ExceptionType = if ($exception) { $exception.Exception.GetType().Name } else { $null }
            Message       = if ($exception) { $exception.Exception.Message } else { $reason }
            ExitCode      = $code
        }
    }

    try {
        Write-Log "Attempting ProcessStartRead on '$ProcDirectory'" -Severity Verbose
        $stat = [System.IO.File]::ReadAllText((Join-Path $ProcDirectory 'stat'))
        $closing = $stat.LastIndexOf(')')
        if ($closing -lt 0) {
            Write-Log "ProcessStartRead on '$ProcDirectory' found no command name in the stat file" -Severity Warning
            return (& $outcome $false $null 'StatUnparseable' $null (Get-WindowsErrorCode -HResult 0x8007000D))
        }
        $fields = $stat.Substring($closing + 2).Split(' ')
        $ticks = [long]$fields[$startTicksField]
        return (& $outcome $true $BootTimeUtc.AddSeconds($ticks / $ticksPerSecond) $null $null 0)
    }
    catch {
        Write-Log "ProcessStartRead failed on '$ProcDirectory': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Warning
        return (& $outcome $false $null 'StatUnreadable' $_ (Get-WindowsErrorCode -Exception $_))
    }
}
