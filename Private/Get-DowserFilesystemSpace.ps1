function Get-DowserFilesystemSpace {
    <#
    .SYNOPSIS
        Reports free and total bytes on the filesystem that holds a path.
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
        On Linux and macOS the owning filesystem is the mount with the longest root that
        prefixes the path, so a folder on a separate mount reports that mount and not the
        root filesystem. On Windows it is the drive of the path root. Free space is the
        space available to the calling user. Failures return a structured result with the
        mapped exit code; nothing is thrown.
    .PARAMETER Path
        Any path on the filesystem to measure. It does not have to exist.
    .EXAMPLE
        Get-DowserFilesystemSpace -Path '/home/user/.claude'

        Returns the mount, free bytes and total bytes of the filesystem holding that folder.
    .OUTPUTS
        PSCustomObject with Success, Path, Mount, FreeBytes, TotalBytes, Reason, ExceptionType,
        Message, ExitCode.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    $failure = {
        param($reason, $exception, $code)
        [pscustomobject]@{
            Success       = $false
            Path          = $Path
            Mount         = $null
            FreeBytes     = $null
            TotalBytes    = $null
            Reason        = $reason
            ExceptionType = if ($exception) { $exception.Exception.GetType().Name } else { $null }
            Message       = if ($exception) { $exception.Exception.Message } else { $reason }
            ExitCode      = $code
        }
    }

    $fullPath = $null
    try {
        Write-Log "Attempting FilesystemSpaceResolve on '$Path'" -Severity Verbose
        $fullPath = [System.IO.Path]::GetFullPath($Path)
    }
    catch {
        Write-Log "FilesystemSpaceResolve failed on '$Path': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Warning
        return (& $failure 'PathResolveFailed' $_ (Get-WindowsErrorCode -Exception $_))
    }

    $drive = $null
    try {
        Write-Log "Attempting FilesystemSpaceRead on '$fullPath'" -Severity Verbose
        if ($IsWindows -eq $false) {
            $drive = [System.IO.DriveInfo]::GetDrives() | Where-Object {
                $mountRoot = $_.RootDirectory.FullName.TrimEnd('/')
                $fullPath -eq $mountRoot -or $fullPath.StartsWith("$mountRoot/", [System.StringComparison]::Ordinal)
            } | Sort-Object { $_.RootDirectory.FullName.Length } -Descending | Select-Object -First 1
        }
        else {
            $drive = [System.IO.DriveInfo]::new([System.IO.Path]::GetPathRoot($fullPath))
        }
        if ($null -eq $drive) {
            Write-Log "FilesystemSpaceRead found no mount holding '$fullPath'" -Severity Warning
            return (& $failure 'NoMatchingMount' $null (Get-WindowsErrorCode -HResult 0x80070003))
        }
        $result = [pscustomobject]@{
            Success       = $true
            Path          = $fullPath
            Mount         = $drive.RootDirectory.FullName
            FreeBytes     = [long]$drive.AvailableFreeSpace
            TotalBytes    = [long]$drive.TotalSize
            Reason        = $null
            ExceptionType = $null
            Message       = $null
            ExitCode      = 0
        }
        Write-Log "FilesystemSpaceRead succeeded on '$fullPath': mount '$($result.Mount)', free $($result.FreeBytes) of $($result.TotalBytes) bytes" -Severity Verbose
        return $result
    }
    catch {
        Write-Log "FilesystemSpaceRead failed on '$fullPath': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Warning
        return (& $failure 'DriveReadFailed' $_ (Get-WindowsErrorCode -Exception $_))
    }
}
