
function Get-DowserFolderBirthTime {
    <#
    .SYNOPSIS
        Reads when each folder was created, as the filesystem recorded it.
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
        On Linux, .NET reports a folder's creation time as the earlier of its birth time and its
        last write time, so a folder whose write time was set back (an extracted archive, a copy
        that keeps times) looks older than it is. The real birth time is read with one stat call
        for all the folders (the %W field, whole seconds since the epoch). A folder the
        filesystem records no birth time for, or that stat could not read, is left out of Births,
        and the caller must then treat its age as unknown. Elsewhere the .NET creation time is
        used as it is.
    .PARAMETER Path
        Folders to read.
    .EXAMPLE
        Get-DowserFolderBirthTime -Path $versionFolders.FullName

        Returns Births, a hashtable from each readable folder path to its UTC creation time.
    .OUTPUTS
        PSCustomObject with Success, Births, Reason, ExceptionType, Message, ExitCode.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [AllowEmptyCollection()]
        [string[]]$Path = @()
    )

    $births = @{}
    $outcome = {
        param($success, $reason, $exception, $code)
        [pscustomobject]@{
            Success       = $success
            Births        = $births
            Reason        = $reason
            ExceptionType = if ($exception) { $exception.Exception.GetType().Name } else { $null }
            Message       = if ($exception) { $exception.Exception.Message } else { $reason }
            ExitCode      = $code
        }
    }
    if ($Path.Count -eq 0) {
        return (& $outcome $true $null $null 0)
    }

    if ($IsWindows -ne $false -or $IsMacOS -eq $true) {
        try {
            Write-Log "Attempting FolderBirthRead through .NET on $($Path.Count) folder(s)" -Severity Verbose
            foreach ($folder in $Path) {
                $births[$folder] = [System.IO.DirectoryInfo]::new($folder).CreationTimeUtc
            }
            return (& $outcome $true $null $null 0)
        }
        catch {
            Write-Log "FolderBirthRead failed through .NET: $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Warning
            return (& $outcome $false 'CreationTimeUnreadable' $_ (Get-WindowsErrorCode -Exception $_))
        }
    }

    $lines = @()
    $statExit = 0
    try {
        Write-Log "Attempting FolderBirthRead through stat on $($Path.Count) folder(s)" -Severity Verbose
        $lines = @(& stat -c '%W|%n' $Path 2>&1)
        $statExit = $LASTEXITCODE
    }
    catch {
        Write-Log "FolderBirthRead failed running stat: $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Warning
        return (& $outcome $false 'StatUnavailable' $_ (Get-WindowsErrorCode -Exception $_))
    }

    $problems = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $lines) {
        $text = [string]$line
        $bar = $text.IndexOf('|')
        $seconds = 0L
        if ($bar -gt 0 -and [long]::TryParse($text.Substring(0, $bar), [ref]$seconds) -and $seconds -gt 0) {
            $births[$text.Substring($bar + 1)] = [System.DateTimeOffset]::FromUnixTimeSeconds($seconds).UtcDateTime
        }
        else {
            $problems.Add($text)
        }
    }

    if ($statExit -ne 0 -or $problems.Count -gt 0) {
        Write-Log "FolderBirthRead got a birth time for $($births.Count) of $($Path.Count) folder(s); stat exit $statExit, first problem '$($problems | Select-Object -First 1)'" -Severity Warning
        return (& $outcome $false 'BirthTimeMissing' $null (Get-WindowsErrorCode -HResult 0x8007000D))
    }
    return (& $outcome $true $null $null 0)
}
