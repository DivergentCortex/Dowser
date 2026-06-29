function Find-DowserRecentLog {
    <#
    .SYNOPSIS
        Find the most recently modified copy of a named file across one or more search paths.

    .DESCRIPTION
        Useful for locating the canonical / newest copy of a shared helper (e.g. Write-Log.ps1)
        when multiple copies exist across a drive. Returns the newest match by default; use -All
        to get all copies ranked by LastWriteTime descending.

        Replaces Find-MostRecentLog.ps1 — that was a bare script hardcoded to hunt for
        Write-Log_Ps20.ps1 on D:. This version is fully parameterized.

    .PARAMETER FileName
        The file name (or wildcard pattern) to search for. Example: 'Write-Log.ps1', '*.config'.

    .PARAMETER Path
        Root path(s) to search. Defaults to current directory.

    .PARAMETER All
        Return all found copies ranked by LastWriteTime descending, not just the newest.

    .PARAMETER Recurse
        Recurse subdirectories. Default $true. Pass -Recurse:$false to disable.

    .EXAMPLE
        Find-DowserRecentLog -FileName 'Write-Log.ps1' -Path D:\

    .EXAMPLE
        Find-DowserRecentLog -FileName '*.config' -All -Verbose

    .EXAMPLE
        'D:\Repos','C:\Scripts' | Find-DowserRecentLog -FileName 'Write-Log.ps1'

    .NOTES
        Alias: dlog
        Source: Find-MostRecentLog.ps1 (standalone scripts) — bare script, no params, hardcoded.
        Full function rewrite. Logic preserved: find, sort newest-first, emit PSCustomObject.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$FileName,

        [Parameter(Position = 1, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('FullName')]
        [string[]]$Path = $PWD,

        [switch]$All,

        [bool]$Recurse = $true
    )

    process {
        foreach ($rootPath in $Path) {
            if (-not (Test-Path $rootPath)) {
                Write-Warning "Path not found: $rootPath"
                continue
            }

            Write-Verbose "Searching '$rootPath' for '$FileName'..."

            try {
                $searchParams = @{
                    Path        = $rootPath
                    Filter      = $FileName
                    Recurse     = [bool]$Recurse
                    File        = $true
                    ErrorAction = 'SilentlyContinue'
                }

                $found = @(Get-ChildItem @searchParams | Sort-Object LastWriteTime -Descending)

                Write-Verbose "Found $($found.Count) copy/copies of '$FileName' in '$rootPath'"

                if ($found.Count -eq 0) {
                    Write-Verbose "No copies of '$FileName' found under '$rootPath'."
                    return
                }

                if ($All) {
                    foreach ($f in $found) {
                        [PSCustomObject]@{
                            FullName      = $f.FullName
                            LastWriteTime = $f.LastWriteTime
                            Length        = $f.Length
                        }
                    }
                }
                else {
                    $newest = $found | Select-Object -First 1
                    Write-Verbose "Most recent: $($newest.FullName) @ $($newest.LastWriteTime)"
                    [PSCustomObject]@{
                        FullName      = $newest.FullName
                        LastWriteTime = $newest.LastWriteTime
                        Length        = $newest.Length
                    }
                }
            }
            catch {
                Write-Warning "Error searching '$rootPath': $_"
            }
        }
    }
}
