function Get-DowserActiveProcessPath {
    <#
    .SYNOPSIS
        Collects every path under the given folders that a running process started on or has open, and the running seats with their start times.
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
        On Linux every /proc/<pid> is read through Get-DowserProcessReference for its working
        directory, executable, open descriptors, mapped files, command line and environment. On
        Windows and macOS only the executable path (and, on Windows, the command line) of each
        process is read, which is a reduced check and is reported as Reduced. When the process
        list itself cannot be read the result is Success false, and the caller must treat every
        folder as in use. Processes the user may not inspect are counted in Unreadable and
        reported once.

        A seat is a running process whose program name is one of -SeatName. A seat holds no
        file under the cache open, so the paths cannot show which version it loaded; its start
        time can, and each seat is returned with it. StartKnown is false for a seat whose start
        time could not be read, and the caller must then keep every version.
    .PARAMETER RootPrefix
        Folder paths to look for in each process, in every spelling a process might use.
    .PARAMETER SeatName
        Program names that count as a seat, such as claude.
    .EXAMPLE
        Get-DowserActiveProcessPath -RootPrefix '/home/me/.claude/plugins/cache' -SeatName claude

        Returns the process-held strings under that cache and each running claude with its start time.
    .OUTPUTS
        PSCustomObject with Success, Paths, Seats, ProcessCount, Unreadable, Reduced, Reason,
        ExceptionType, Message, ExitCode.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$RootPrefix,

        [string[]]$SeatName = @()
    )

    $outcome = {
        param($success, $paths, $seats, $count, $unreadable, $reduced, $reason, $exception, $code)
        [pscustomobject]@{
            Success       = $success
            Paths         = @($paths)
            Seats         = @($seats)
            ProcessCount  = $count
            Unreadable    = $unreadable
            Reduced       = $reduced
            Reason        = $reason
            ExceptionType = if ($exception) { $exception.Exception.GetType().Name } else { $null }
            Message       = if ($exception) { $exception.Exception.Message } else { $reason }
            ExitCode      = $code
        }
    }

    $held = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $seats = [System.Collections.Generic.List[object]]::new()
    $unreadable = 0
    $count = 0
    $reduced = $false

    if ($IsWindows -eq $false -and (Test-Path -LiteralPath '/proc' -PathType Container)) {
        $processFolders = @()
        $bootTimeUtc = $null
        try {
            Write-Log "Attempting ProcessScan on /proc for $($RootPrefix.Count) root(s)" -Severity Verbose
            $processFolders = @([System.IO.Directory]::GetDirectories('/proc') | Where-Object { [System.IO.Path]::GetFileName($_) -match '^\d+$' })
        }
        catch {
            Write-Log "ProcessScan failed listing /proc: $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Warning
            return (& $outcome $false @() @() 0 0 $false 'ProcessListUnreadable' $_ (Get-WindowsErrorCode -Exception $_))
        }
        if ($SeatName.Count -gt 0) {
            try {
                Write-Log 'Attempting BootTimeRead on /proc/stat' -Severity Verbose
                $bootLine = [System.IO.File]::ReadLines('/proc/stat') | Where-Object { $_ -like 'btime *' } | Select-Object -First 1
                $bootTimeUtc = [System.DateTimeOffset]::FromUnixTimeSeconds([long]($bootLine.Split(' ')[1])).UtcDateTime
            }
            catch {
                Write-Log "BootTimeRead failed on /proc/stat, so no seat start time can be known: $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Warning
            }
        }
        foreach ($folder in $processFolders) {
            $reference = if ($null -ne $bootTimeUtc) {
                Get-DowserProcessReference -ProcDirectory $folder -RootPrefix $RootPrefix -SeatName $SeatName -BootTimeUtc $bootTimeUtc
            }
            else {
                Get-DowserProcessReference -ProcDirectory $folder -RootPrefix $RootPrefix -SeatName $SeatName
            }
            $count++
            $unreadable += $reference.Unreadable
            foreach ($text in $reference.Paths) {
                [void]$held.Add($text)
            }
            if ($null -ne $reference.SeatName) {
                $seats.Add([pscustomobject]@{
                        ProcessId  = [System.IO.Path]::GetFileName($folder)
                        Name       = $reference.SeatName
                        StartKnown = $reference.SeatStartKnown
                        StartUtc   = $reference.SeatStartUtc
                    })
            }
        }
    }
    else {
        $reduced = $true
        try {
            Write-Log "Attempting ProcessScan through Get-Process for $($RootPrefix.Count) root(s)" -Severity Verbose
            foreach ($process in Get-Process -ErrorAction Stop) {
                $count++
                foreach ($text in @($process.Path)) {
                    if ($text) {
                        foreach ($prefix in $RootPrefix) {
                            if ($text.IndexOf($prefix, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { [void]$held.Add($text) }
                        }
                    }
                }
                if ($SeatName -contains $process.ProcessName) {
                    $started = $null
                    try { $started = $process.StartTime.ToUniversalTime() } catch { $started = $null }
                    $seats.Add([pscustomobject]@{ ProcessId = [string]$process.Id; Name = $process.ProcessName; StartKnown = ($null -ne $started); StartUtc = $started })
                }
            }
            if ($IsWindows -ne $false) {
                foreach ($cim in Get-CimInstance -ClassName Win32_Process -ErrorAction Stop) {
                    foreach ($prefix in $RootPrefix) {
                        if ($cim.CommandLine -and $cim.CommandLine.IndexOf($prefix, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { [void]$held.Add($cim.CommandLine) }
                    }
                }
            }
        }
        catch {
            Write-Log "ProcessScan failed through Get-Process: $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Warning
            return (& $outcome $false @() @() 0 0 $true 'ProcessListUnreadable' $_ (Get-WindowsErrorCode -Exception $_))
        }
    }

    # other users' processes are always unreadable, so only a reduced scan is worth a warning
    $severity = 'Info'
    if ($reduced) { $severity = 'Warning' }
    $unknownStarts = @($seats | Where-Object { -not $_.StartKnown }).Count
    Write-Log "ProcessScan succeeded: $count process(es) read, $($held.Count) held path(s), $($seats.Count) seat(s) ($unknownStarts with an unknown start time), $unreadable unreadable read(s), reduced=$reduced" -Severity $severity
    return (& $outcome $true @($held) $seats.ToArray() $count $unreadable $reduced $null $null 0)
}
