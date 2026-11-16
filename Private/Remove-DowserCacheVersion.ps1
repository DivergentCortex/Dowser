function Remove-DowserCacheVersion {
    <#
    .SYNOPSIS
        Deletes one cache version folder after re-checking that it is a real folder at the expected depth.
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
        Refuses a path that is not exactly <Root>/<marketplace>/<plugin>/<version>, a path that
        is a symlink, and a path that no longer exists. The delete is
        [System.IO.Directory]::Delete with recursion, which removes a link inside the folder
        without following it, so nothing outside the folder is touched. The folder is checked
        gone afterwards. The caller owns the confirmation prompt.
    .PARAMETER Path
        The version folder to delete.
    .PARAMETER Root
        The rule root the folder must sit three levels under.
    .EXAMPLE
        Remove-DowserCacheVersion -Path $row.Path -Root $rule.Root

        Deletes the folder and returns whether it is gone.
    .OUTPUTS
        PSCustomObject with Success, Removed, Path, Reason, ExceptionType, Message, ExitCode.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Root
    )

    $outcome = {
        param($success, $removed, $reason, $exception, $code)
        [pscustomobject]@{
            Success       = $success
            Removed       = $removed
            Path          = $Path
            Reason        = $reason
            ExceptionType = if ($exception) { $exception.Exception.GetType().Name } else { $null }
            Message       = if ($exception) { $exception.Exception.Message } else { $reason }
            ExitCode      = $code
        }
    }

    $rootMark = $Root.TrimEnd('/', '\') + [System.IO.Path]::DirectorySeparatorChar
    $depthOk = $false
    if ($Path.StartsWith($rootMark, [System.StringComparison]::Ordinal)) {
        $depthOk = @($Path.Substring($rootMark.Length) -split '[/\\]' | Where-Object { $_ }).Count -eq 3
    }
    if (-not $depthOk) {
        Write-Log "CacheVersionRemove refused '$Path': not three levels under '$Root'" -Severity Error
        return (& $outcome $false $false 'OutsideRuleRoot' $null (Get-WindowsErrorCode -HResult 0x8007007B))
    }

    $info = $null
    try {
        $info = [System.IO.DirectoryInfo]::new($Path)
    }
    catch {
        Write-Log "CacheVersionRemove failed reading '$Path': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Warning
        return (& $outcome $false $false 'FolderUnreadable' $_ (Get-WindowsErrorCode -Exception $_))
    }
    if (-not $info.Exists) {
        Write-Log "CacheVersionRemove found '$Path' already gone" -Severity Info
        return (& $outcome $true $false 'AlreadyGone' $null 0)
    }
    if ($info.Attributes -band [System.IO.FileAttributes]::ReparsePoint -or $null -ne $info.LinkTarget) {
        Write-Log "CacheVersionRemove refused '$Path': it is a symlink" -Severity Warning
        return (& $outcome $false $false 'IsSymlink' $null (Get-WindowsErrorCode -HResult 0x80070005))
    }

    try {
        Write-Log "Attempting CacheVersionRemove on '$Path'" -Severity Info
        [System.IO.Directory]::Delete($Path, $true)
        if ([System.IO.Directory]::Exists($Path)) {
            Write-Log "CacheVersionRemove on '$Path' returned but the folder is still there" -Severity Warning
            return (& $outcome $false $false 'StillPresent' $null (Get-WindowsErrorCode -HResult 0x80070091))
        }
        Write-Log "CacheVersionRemove succeeded on '$Path'" -Severity Success
        return (& $outcome $true $true $null $null 0)
    }
    catch {
        Write-Log "CacheVersionRemove failed on '$Path': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Error
        return (& $outcome $false $false 'DeleteFailed' $_ (Get-WindowsErrorCode -Exception $_))
    }
}
