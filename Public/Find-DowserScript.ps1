function Find-DowserScript {
    <#
    .SYNOPSIS
        Finds script files by extension, with optional recency filter.

    .NOTES
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
        -  Author:        Curtis Leggett                                  -
        =  Copyright:     2026 Divergent Cortex                           =
        -  Organization:  Divergent Cortex                                -
        =  Version:       See docs/CHANGELOG.md                           =
        =-=-                       =-=-=-=-=-=-=-=                     -=-=
        -  it is not water they seek, but the truth beneath the trees     -
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

        Alias: dscript
        Source: Find-Scripts.ps1 (standalone scripts), was hardcoded to a network share.

    .DESCRIPTION
        General-purpose script-file finder. Searches a path for files matching
        common scripting extensions (.ps1, .psm1, .py, .vbs, .sh, .bat, .cmd, etc.).
        Optionally filters to files modified within a recency window.

        Ported from standalone Find-Scripts.ps1, which was hardcoded to a single
        network share and is now generalized to any path and extension set.

    .PARAMETER Path
        Root path(s) to search. Defaults to the current directory. Accepts pipeline input.

    .PARAMETER Extensions
        Script extensions to include. Default covers the common scripting languages.

    .PARAMETER ModifiedWithin
        Recency filter in days. Only files modified within this many days are returned.
        Omit to return all matches regardless of age.

    .PARAMETER Recurse
        Recurse subdirectories. Default is $true. Pass -Recurse:$false to disable.

    .EXAMPLE
        Find-DowserScript -Path D:\Repos

        Returns every script file found under D:\Repos.

    .EXAMPLE
        Find-DowserScript -Path D:\Scripts -ModifiedWithin 30 -Extensions '.ps1','.psm1'

        Returns only .ps1 and .psm1 files under D:\Scripts modified in the last 30 days.

    .EXAMPLE
        'C:\Scripts','D:\Tools' | Find-DowserScript -Verbose

        Pipes two root paths in and scans both for script files.

    .INPUTS
        System.String
        Root path strings can be piped to this function.

    .OUTPUTS
        PSCustomObject
        Properties: Name, FullName, Extension, LastWriteTime, Size.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('FullName')]
        [string[]]$Path = $PWD,

        [string[]]$Extensions = @('.vbs', '.py', '.ps1', '.psm1', '.psd1', '.sh', '.bat', '.cmd'),

        [int]$ModifiedWithin,

        [switch]$Recurse = $true
    )

    begin {
        Write-Log "Starting Find-DowserScript"
    }

    process {
        foreach ($rootPath in $Path) {
            if (-not (Test-Path $rootPath)) {
                Write-Log "Find-DowserScript: path not found: '$rootPath'" -Severity Warning
                continue
            }

            Write-Log "Scanning '$rootPath' for script files..." -Severity Verbose

            $cutoff = $null
            if ($ModifiedWithin -and $ModifiedWithin -gt 0) {
                $cutoff = (Get-Date).AddDays(-$ModifiedWithin)
                Write-Log "Recency filter: modified within $ModifiedWithin days (after $($cutoff.ToString('yyyy-MM-dd')))" -Severity Verbose
            }

            try {
                $getAllParams = @{
                    Path        = $rootPath
                    Recurse     = [bool]$Recurse
                    File        = $true
                    ErrorAction = 'SilentlyContinue'
                }

                $files = Get-ChildItem @getAllParams
                $total = @($files).Count
                $processed = 0

                foreach ($file in $files) {
                    $processed++
                    $ext = [System.IO.Path]::GetExtension($file.Name)

                    if ($Extensions -notcontains $ext) {
                        continue 
                    }
                    if ($cutoff -and $file.LastWriteTime -lt $cutoff) {
                        continue 
                    }

                    $percentComplete = if ($total -gt 0) {
                        ($processed / $total) * 100 
                    }
                    else {
                        0 
                    }
                    Write-Progress -Activity "Find-DowserScript" -Status "Scanning $($file.FullName)" -PercentComplete $percentComplete

                    [PSCustomObject]@{
                        Name          = $file.Name
                        FullName      = $file.FullName
                        Extension     = $ext
                        LastWriteTime = $file.LastWriteTime
                        Size          = $file.Length
                    }
                }
            }
            catch {
                Write-Log "Find-DowserScript failed scanning '$rootPath': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Error
            }
            finally {
                Write-Progress -Activity "Find-DowserScript" -Status "Done" -Completed
            }
        }
    }

    end {
        Write-Log "Ending Find-DowserScript"
    }
}
