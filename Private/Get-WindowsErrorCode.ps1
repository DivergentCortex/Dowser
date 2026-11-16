function Get-WindowsErrorCode {
    <#
    .SYNOPSIS
        Maps a PowerShell exception or HResult to a Windows error code for use as an exit code.

    .NOTES
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
        -  Author:        Curtis Leggett                                  -
        =  Copyright:     2026 Divergent Cortex                           =
        -  Organization:  Divergent Cortex                                -
        =  Version:       See docs/CHANGELOG.md                           =
        =-=-                       =-=-=-=-=-=-=-=                     -=-=
        -  it is not water they seek, but the truth beneath the trees     -
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

        The file-system and exception half of the fleet exit-code mapper, with the
        installer-specific and component-servicing tables left out.

    .DESCRIPTION
        Takes an exception, an error record, or a raw HResult and returns the matching
        Windows error code from WinError.h. Exit codes in Dowser come from this function
        and never from a literal number.

    .PARAMETER Exception
        The error record from a catch block ($_) or its exception.

    .PARAMETER HResult
        An HResult to translate directly, for a condition that has no exception.

    .EXAMPLE
        Get-WindowsErrorCode -HResult 0x80070070

        Returns 112 (ERROR_DISK_FULL).

    .EXAMPLE
        $exitCode = Get-WindowsErrorCode -Exception $_

        Maps the exception caught in a catch block.

    .OUTPUTS
        System.Int32
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $false, Position = 0, ValueFromPipeline = $true)]
        [System.Object]$Exception,

        [Parameter(Mandatory = $false)]
        [int]$HResult
    )

    $ErrorCodes = @{
        FILE_NOT_FOUND    = 2
        PATH_NOT_FOUND    = 3
        ACCESS_DENIED     = 5
        INVALID_HANDLE    = 6
        NOT_ENOUGH_MEMORY = 8
        INVALID_DATA      = 13
        SHARING_VIOLATION = 32
        DISK_FULL         = 112
        INVALID_NAME      = 123
        DIR_NOT_EMPTY     = 145
        BAD_PATHNAME      = 161
        PATH_TOO_LONG     = 162
        ALREADY_EXISTS    = 183
        INVALID_FUNCTION  = 1
    }

    $HResultMap = @{
        0x80070002 = $ErrorCodes.FILE_NOT_FOUND
        0x80070003 = $ErrorCodes.PATH_NOT_FOUND
        0x80070005 = $ErrorCodes.ACCESS_DENIED
        0x80070006 = $ErrorCodes.INVALID_HANDLE
        0x80070008 = $ErrorCodes.NOT_ENOUGH_MEMORY
        0x8007000D = $ErrorCodes.INVALID_DATA
        0x80070020 = $ErrorCodes.SHARING_VIOLATION
        0x80070070 = $ErrorCodes.DISK_FULL
        0x8007007B = $ErrorCodes.INVALID_NAME
        0x80070091 = $ErrorCodes.DIR_NOT_EMPTY
        0x800700A1 = $ErrorCodes.BAD_PATHNAME
        0x800700A2 = $ErrorCodes.PATH_TOO_LONG
        0x800700B7 = $ErrorCodes.ALREADY_EXISTS
    }

    if ($HResult -ne 0) {
        if ($HResultMap.ContainsKey($HResult)) {
            return $HResultMap[$HResult]
        }
        # win32 error rides in the low word, high word is facility and severity
        $lowBits = $HResult -band 0xFFFF
        if ($lowBits -gt 0 -and $lowBits -lt 16000) {
            return $lowBits
        }
    }

    # an error record wraps the exception, unwrap it or we chase the wrong object
    $ex = $null
    if ($Exception -is [System.Management.Automation.ErrorRecord]) {
        $ex = $Exception.Exception
    }
    elseif ($Exception -is [System.Exception]) {
        $ex = $Exception
    }

    if ($null -eq $ex) {
        return $ErrorCodes.INVALID_FUNCTION
    }

    $typeName = $ex.GetType().FullName
    $msg = $ex.Message.ToLower()

    switch -Wildcard ($typeName) {
        'System.IO.FileNotFoundException' { return $ErrorCodes.FILE_NOT_FOUND }
        'System.IO.DirectoryNotFoundException' { return $ErrorCodes.PATH_NOT_FOUND }
        'System.UnauthorizedAccessException' { return $ErrorCodes.ACCESS_DENIED }
        'System.IO.PathTooLongException' { return $ErrorCodes.PATH_TOO_LONG }
        'System.Management.Automation.ItemNotFoundException' {
            # one exception covers a missing file and a missing folder, so the message decides
            if ($msg -notmatch '\.\w{1,5}[''"\s]' -and $msg -notmatch 'file') {
                return $ErrorCodes.PATH_NOT_FOUND
            }
            return $ErrorCodes.FILE_NOT_FOUND
        }
        'System.Security.SecurityException' { return $ErrorCodes.ACCESS_DENIED }
        'System.OutOfMemoryException' { return $ErrorCodes.NOT_ENOUGH_MEMORY }
        'System.ArgumentNullException' { return $ErrorCodes.INVALID_DATA }
        'System.ArgumentException' {
            if ($msg -match 'illegal characters|invalid.*characters') {
                return $ErrorCodes.INVALID_NAME
            }
            if ($msg -match 'access.*denied|permission denied') {
                return $ErrorCodes.ACCESS_DENIED
            }
            return $ErrorCodes.INVALID_DATA
        }
        'System.IO.IOException' {
            if ($msg -match 'used by another process|sharing violation|being used') {
                return $ErrorCodes.SHARING_VIOLATION
            }
            if ($msg -match 'disk.*full|not enough space|no space') {
                return $ErrorCodes.DISK_FULL
            }
            if ($msg -match 'not empty') {
                return $ErrorCodes.DIR_NOT_EMPTY
            }
            if ($msg -match 'already exists') {
                return $ErrorCodes.ALREADY_EXISTS
            }
            if ($ex.HResult) {
                $hr = $ex.HResult
                if ($HResultMap.ContainsKey($hr)) {
                    return $HResultMap[$hr]
                }
                if (($hr -band 0xFFFF0000) -eq 0x80070000) {
                    $winErr = $hr -band 0xFFFF
                    if ($winErr -gt 0 -and $winErr -lt 16000) {
                        return $winErr
                    }
                }
            }
            if ($msg -match 'path|directory|folder') {
                return $ErrorCodes.PATH_NOT_FOUND
            }
            return $ErrorCodes.FILE_NOT_FOUND
        }
    }

    if ($ex.HResult -and $ex.HResult -ne 0) {
        $hr = $ex.HResult
        if ($HResultMap.ContainsKey($hr)) {
            return $HResultMap[$hr]
        }
        if (($hr -band 0xFFFF0000) -eq 0x80070000) {
            $winErr = $hr -band 0xFFFF
            if ($winErr -gt 0 -and $winErr -lt 16000) {
                return $winErr
            }
        }
    }

    # the inner exception often holds the real reason
    if ($ex.InnerException) {
        return Get-WindowsErrorCode -Exception $ex.InnerException
    }

    if ($msg -match 'access.*denied|permission denied|unauthorized') { return $ErrorCodes.ACCESS_DENIED }
    if ($msg -match 'not found|does not exist|cannot find') { return $ErrorCodes.FILE_NOT_FOUND }
    if ($msg -match 'already exists') { return $ErrorCodes.ALREADY_EXISTS }
    if ($msg -match 'path.*long|too long') { return $ErrorCodes.PATH_TOO_LONG }
    if ($msg -match 'illegal characters|invalid.*name') { return $ErrorCodes.INVALID_NAME }

    return $ErrorCodes.INVALID_FUNCTION
}
