function Measure-DowserCacheCandidate {
    <#
    .SYNOPSIS
        Sizes one cache version folder with Measure-DowserDirectory and finds its newest file.
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
        Measure-DowserDirectory returns one row per immediate subfolder of the folder it is
        given plus a '.' row for loose files, so the version folder's total is the sum of those
        rows and its newest file is the latest NewestFileDate. That function skips a subfolder
        it cannot scan and logs the error, so the row count is checked against the real number
        of immediate subfolders; a mismatch returns Success false and the folder is treated as
        unmeasured, never as small.
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

    $expectedFolders = 0
    $rows = @()
    try {
        Write-Log "Attempting CacheCandidateMeasure on '$Path'" -Severity Verbose
        $expectedFolders = @([System.IO.Directory]::GetDirectories($Path)).Count
        $rows = @(Measure-DowserDirectory -Path $Path)
    }
    catch {
        Write-Log "CacheCandidateMeasure failed on '$Path': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Warning
        return (& $outcome $false $null $null $null 'MeasureFailed' $_ (Get-WindowsErrorCode -Exception $_))
    }

    $folderRows = @($rows | Where-Object { $_.Folder -ne '.' })
    if ($folderRows.Count -ne $expectedFolders) {
        Write-Log "CacheCandidateMeasure on '$Path' returned $($folderRows.Count) of $expectedFolders subfolder rows, treating the folder as unmeasured" -Severity Warning
        return (& $outcome $false $null $null $null 'SubfolderRowsMissing' $null (Get-WindowsErrorCode -HResult 0x8007000D))
    }

    $size = [long]0
    $files = 0
    $newest = $null
    foreach ($row in $rows) {
        $size += [long]$row.SizeBytes
        $files += [int]$row.FileCount
        if ($row.FileCount -gt 0 -and ($null -eq $newest -or $row.NewestFileDate -gt $newest)) {
            $newest = $row.NewestFileDate
        }
    }
    Write-Log "CacheCandidateMeasure succeeded on '$Path': $size bytes in $files file(s)" -Severity Verbose
    return (& $outcome $true $size $files $newest $null $null 0)
}
