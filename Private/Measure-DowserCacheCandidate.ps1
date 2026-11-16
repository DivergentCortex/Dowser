function Measure-DowserCacheCandidate {
    <#
    .SYNOPSIS
        Sizes one cache version folder and finds its newest file, logging at Verbose only.
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
        Lists every file under the folder once, without following symlinked folders, and totals
        them with Measure-DowserFileSet, the same single-pass statistics Measure-DowserDirectory
        uses. The public command is not called here because it logs an Info start and end pair
        per call, and a run sizes many folders. A path that cannot be listed returns Success
        false and the folder is treated as unmeasured, never as small.
    .PARAMETER Path
        The version folder to measure.
    .EXAMPLE
        Measure-DowserCacheCandidate -Path ~/.claude/plugins/cache/divergentcortex/myelindrite/2026.11.13.8256

        Returns the folder's byte total, file count and newest file time.
    .OUTPUTS
        PSCustomObject with Success, SizeBytes, FileCount, NewestFileDate, Reason, ExceptionType,
        Message, ExitCode.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    $outcome = {
        param($success, $size, $files, $newest, $reason, $exception, $code)
        [pscustomobject]@{
            Success        = $success
            SizeBytes      = $size
            FileCount      = $files
            NewestFileDate = $newest
            Reason         = $reason
            ExceptionType  = if ($exception) { $exception.Exception.GetType().Name } else { $null }
            Message        = if ($exception) { $exception.Exception.Message } else { $reason }
            ExitCode       = $code
        }
    }

    $files = @()
    $skipped = 0
    try {
        Write-Log "Attempting CacheCandidateMeasure on '$Path'" -Severity Verbose
        if ($PSVersionTable.PSVersion.Major -ge 6) {
            $scanErrors = $null
            $files = @(Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue -ErrorVariable scanErrors)
            $skipped = @($scanErrors).Count
        }
        else {
            # 5.1 -Recurse follows links, so the pruning walker lists the files
            $scan = Get-DowserRelativeFileMap -Root $Path
            $files = @($scan.Map.Values)
            $skipped = $scan.Errors
        }
    }
    catch {
        Write-Log "CacheCandidateMeasure failed on '$Path': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Warning
        return (& $outcome $false $null $null $null 'MeasureFailed' $_ (Get-WindowsErrorCode -Exception $_))
    }
    if ($skipped -gt 0) {
        Write-Log "CacheCandidateMeasure on '$Path' could not read $skipped path(s), treating the folder as unmeasured" -Severity Warning
        return (& $outcome $false $null $null $null 'UnreadablePaths' $null (Get-WindowsErrorCode -HResult 0x8007000D))
    }

    $reference = Get-Date
    $stats = Measure-DowserFileSet -Files $files -TodayStart $reference.Date -RecentCutoff $reference
    $newest = if ($stats.Newest) { $stats.Newest.LastWriteTime } else { $null }
    Write-Log "CacheCandidateMeasure succeeded on '$Path': $($stats.TotalBytes) bytes in $($stats.FileCount) file(s)" -Severity Verbose
    return (& $outcome $true $stats.TotalBytes $stats.FileCount $newest $null $null 0)
}
