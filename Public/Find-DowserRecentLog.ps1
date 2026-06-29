function Find-DowserRecentLog {
    <#
    .SYNOPSIS
        Find the most recently modified copy of a named file across one or more search paths.

    .NOTES
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
        -  Author:        Curtis Leggett                                  -
        =  Copyright:     2026 Divergent Cortex                           =
        -  Organization:  Divergent Cortex                                -
        =  Version:       See docs/CHANGELOG.md                           =
        =-=-                       =-=-=-=-=-=-=-=                     -=-=
        -  it is not water they seek, but the truth beneath the trees     -
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

        Alias: dlog
        Source: Find-MostRecentLog.ps1 (standalone scripts), a bare script, no params, hardcoded.

    .DESCRIPTION
        Useful for locating the canonical or newest copy of a shared helper (e.g. Write-Log.ps1)
        when multiple copies exist across a drive. Returns the newest match by default; use -All
        to get all copies ranked by LastWriteTime descending.

        Replaces Find-MostRecentLog.ps1, which was a bare script hardcoded to hunt for
        Write-Log_Ps20.ps1 on D:. This version is fully parameterized.

    .PARAMETER FileName
        The file name (or wildcard pattern) to search for. Example: 'Write-Log.ps1', '*.config'.

    .PARAMETER Path
        Root path(s) to search. Defaults to current directory. Accepts pipeline input.

    .PARAMETER All
        Return all found copies ranked by LastWriteTime descending, not just the newest.

    .PARAMETER Recurse
        Recurse subdirectories. Default $true. Pass -Recurse:$false to disable.

    .EXAMPLE
        Find-DowserRecentLog -FileName 'Write-Log.ps1' -Path D:\

        Returns the newest copy of Write-Log.ps1 found anywhere under D:.

    .EXAMPLE
        Find-DowserRecentLog -FileName '*.config' -All -Verbose

        Returns every .config file under the current directory, newest first.

    .EXAMPLE
        'D:\Repos','C:\Scripts' | Find-DowserRecentLog -FileName 'Write-Log.ps1'

        Pipes two root paths in and searches both for Write-Log.ps1.

    .INPUTS
        System.String
        Root path strings can be piped to this function.

    .OUTPUTS
        PSCustomObject
        Properties: FullName, LastWriteTime, Length.
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

    begin {
        Write-Log "Starting Find-DowserRecentLog"
    }

    process {
        foreach ($rootPath in $Path) {
            if (-not (Test-Path $rootPath)) {
                Write-Log "Find-DowserRecentLog: path not found: '$rootPath'" -Severity Warning
                continue
            }

            Write-Log "Searching '$rootPath' for '$FileName'..." -Severity Verbose

            try {
                $searchParams = @{
                    Path        = $rootPath
                    Filter      = $FileName
                    Recurse     = [bool]$Recurse
                    File        = $true
                    ErrorAction = 'SilentlyContinue'
                }

                $found = @(Get-ChildItem @searchParams | Sort-Object LastWriteTime -Descending)

                Write-Log "Found $($found.Count) copy/copies of '$FileName' in '$rootPath'" -Severity Verbose

                if ($found.Count -eq 0) {
                    Write-Log "No copies of '$FileName' found under '$rootPath'" -Severity Warning
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
                    Write-Log "Most recent: $($newest.FullName) @ $($newest.LastWriteTime)" -Severity Verbose
                    [PSCustomObject]@{
                        FullName      = $newest.FullName
                        LastWriteTime = $newest.LastWriteTime
                        Length        = $newest.Length
                    }
                }
            }
            catch {
                Write-Log "Find-DowserRecentLog failed searching '$rootPath': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Error
            }
        }
    }

    end {
        Write-Log "Ending Find-DowserRecentLog"
    }
}
