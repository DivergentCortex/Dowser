function Get-DowserActiveProcessPath {
    <#
    .SYNOPSIS
        Collects every path under the given folders that a running process started on or has open.
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
        directory, executable, open descriptors, mapped files and command line. On Windows and
        macOS only the executable path (and, on Windows, the command line) of each process is
        read, which is a reduced check and is reported as Reduced. When the process list itself
        cannot be read the result is Success false, and the caller must treat every folder as
        in use. Processes the user may not inspect are counted in Unreadable and reported once.
    .PARAMETER RootPrefix
        Folder paths to look for in each process.
    .EXAMPLE
        Get-DowserActiveProcessPath -RootPrefix '/home/me/.claude/plugins/cache'

        Returns the process-held strings under that cache.
    .OUTPUTS
        PSCustomObject with Success, Paths, ProcessCount, Unreadable, Reduced, Reason,
        ExceptionType, Message, ExitCode.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$RootPrefix
    )

    $outcome = {
        param($success, $paths, $count, $unreadable, $reduced, $reason, $exception, $code)
        [pscustomobject]@{
            Success       = $success
            Paths         = @($paths)
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
    $unreadable = 0
    $count = 0
    $reduced = $false

    if ($IsWindows -eq $false -and (Test-Path -LiteralPath '/proc' -PathType Container)) {
        $processFolders = @()
        try {
            Write-Log "Attempting ProcessScan on /proc for $($RootPrefix.Count) root(s)" -Severity Verbose
            $processFolders = @([System.IO.Directory]::GetDirectories('/proc') | Where-Object { [System.IO.Path]::GetFileName($_) -match '^\d+$' })
        }
        catch {
            Write-Log "ProcessScan failed listing /proc: $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Warning
            return (& $outcome $false @() 0 0 $false 'ProcessListUnreadable' $_ (Get-WindowsErrorCode -Exception $_))
        }
        foreach ($folder in $processFolders) {
            $reference = Get-DowserProcessReference -ProcDirectory $folder -RootPrefix $RootPrefix
            $count++
            $unreadable += $reference.Unreadable
            foreach ($text in $reference.Paths) {
                [void]$held.Add($text)
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
            return (& $outcome $false @() 0 0 $true 'ProcessListUnreadable' $_ (Get-WindowsErrorCode -Exception $_))
        }
    }

    # other users' processes are always unreadable, so only a reduced scan is worth a warning
    $severity = 'Info'
    if ($reduced) { $severity = 'Warning' }
    Write-Log "ProcessScan succeeded: $count process(es) read, $($held.Count) held path(s), $unreadable unreadable read(s), reduced=$reduced" -Severity $severity
    return (& $outcome $true @($held) $count $unreadable $reduced $null $null 0)
}
