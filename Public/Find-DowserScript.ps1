function Find-DowserScript {
    <#
    .SYNOPSIS
        Finds script files by extension, with optional recency filter.

    .DESCRIPTION
        General-purpose script-file finder. Searches a path for files matching
        common scripting extensions (.ps1, .psm1, .py, .vbs, .sh, .bat, .cmd, etc.).
        Optionally filters to files modified within a recency window.

        Ported from standalone Find-Scripts.ps1 (was hardcoded to a single network share; now generalized).

    .PARAMETER Path
        Root path(s) to search. Accepts pipeline input.

    .PARAMETER Extensions
        Script extensions to include. Default covers the common scripting languages.

    .PARAMETER ModifiedWithin
        Recency filter in days. Only files modified within this many days are returned.
        Omit to return all matches regardless of age.

    .PARAMETER Recurse
        Recurse subdirectories. Default is $true. Pass -Recurse:$false to disable.

    .EXAMPLE
        Find-DowserScript -Path D:\Repos

    .EXAMPLE
        Find-DowserScript -Path D:\Scripts -ModifiedWithin 30 -Extensions '.ps1','.psm1'

    .EXAMPLE
        'C:\Scripts','D:\Tools' | Find-DowserScript -Verbose

    .NOTES
        Alias: dscript
        Source: Find-Scripts.ps1 (standalone scripts -- was hardcoded to a network share)
        Generalized: path, extensions, recency window all parameterized.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('FullName')]
        [string[]]$Path = $PWD,

        [string[]]$Extensions = @('.vbs', '.py', '.ps1', '.psm1', '.psd1', '.sh', '.bat', '.cmd'),

        [int]$ModifiedWithin,

        [bool]$Recurse = $true
    )

    process {
        foreach ($rootPath in $Path) {
            if (-not (Test-Path $rootPath)) {
                Write-Warning "Path not found: $rootPath"
                continue
            }

            Write-Verbose "Scanning '$rootPath' for script files..."

            $cutoff = $null
            if ($ModifiedWithin -and $ModifiedWithin -gt 0) {
                $cutoff = (Get-Date).AddDays(-$ModifiedWithin)
                Write-Verbose "Recency filter: modified within $ModifiedWithin days (after $($cutoff.ToString('yyyy-MM-dd')))"
            }

            try {
                $getAllParams = @{
                    Path        = $rootPath
                    Recurse     = [bool]$Recurse
                    File        = $true
                    ErrorAction = 'SilentlyContinue'
                }

                $files    = Get-ChildItem @getAllParams
                $total    = @($files).Count
                $processed = 0

                foreach ($file in $files) {
                    $processed++
                    $ext = [System.IO.Path]::GetExtension($file.Name)

                    if ($Extensions -notcontains $ext) { continue }
                    if ($cutoff -and $file.LastWriteTime -lt $cutoff) { continue }

                    $percentComplete = if ($total -gt 0) { ($processed / $total) * 100 } else { 0 }
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
                Write-Warning "Error scanning '$rootPath': $_"
            }
            finally {
                Write-Progress -Activity "Find-DowserScript" -Status "Done" -Completed
            }
        }
    }
}
