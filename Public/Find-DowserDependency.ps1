function Find-DowserDependency {
    <#
    .SYNOPSIS
        Scans PowerShell files for dependency references and function definitions.

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
        Recursively scans .ps1 files under one or more search paths and reports
        dependency references: dot-sourced scripts, function definitions, and
        Import-Module calls. When specific function names are supplied, scans for
        those names instead of the default reference patterns. System and package
        directories are excluded by default. Results can include surrounding
        context lines and be exported to CSV.

    .PARAMETER SearchPath
        Primary directory to scan recursively. Defaults to the current location.

    .PARAMETER AdditionalPaths
        Extra directories to scan alongside SearchPath.

    .PARAMETER FunctionNames
        Specific function names to search for. When supplied, these replace the
        default reference patterns.

    .PARAMETER ExcludePaths
        Path fragments to exclude from the scan. Defaults to platform-appropriate
        system and package directories when not supplied.

    .PARAMETER IncludeContent
        Attach two lines of surrounding context to each match.

    .PARAMETER ExportResults
        Export the full result set to a timestamped CSV in the current directory.

    .EXAMPLE
        Find-DowserDependency -SearchPath $PWD -IncludeContent

        Scans the current directory for dependency references with context lines.

    .EXAMPLE
        Find-DowserDependency -FunctionNames @("Start-FastGroupPing", "Write-Log") -IncludeContent

        Scans for references to the named functions across the current location.

    .EXAMPLE
        Find-DowserDependency -SearchPath $PWD -AdditionalPaths @("\\Server\Share\Scripts") -ExportResults

        Scans the current location and a share, then exports the results to CSV.

    .OUTPUTS
        PSCustomObject
        Properties: SourceFile, LineNumber, Pattern, MatchedLine, LastModified,
        FileSize, and Context when IncludeContent is set.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$SearchPath = $PWD,

        [Parameter(Mandatory = $false)]
        [string[]]$AdditionalPaths,

        [Parameter(Mandatory = $false)]
        [string[]]$FunctionNames,

        [Parameter(Mandatory = $false)]
        [string[]]$ExcludePaths,

        [switch]$IncludeContent,
        [switch]$ExportResults
    )

    # IsWindows is null on ps 5.1 so -ne false means windows
    if (-not $PSBoundParameters.ContainsKey('ExcludePaths')) {
        if ($IsWindows -ne $false) {
            $ExcludePaths = @(
                '\$Recycle.Bin',
                '\Windows\',
                '\Program Files',
                '\Program Files (x86)',
                '\Users\'
            )
        }
        else {
            $ExcludePaths = @(
                '/proc/',
                '/sys/',
                '/dev/',
                '/usr/',
                '/.git/'
            )
        }
    }

    $searchPaths = @($SearchPath)
    if ($AdditionalPaths) {
        $searchPaths += $AdditionalPaths
    }

    if (-not $FunctionNames) {
        $patterns = @(
            '\. ["''].*\.ps1["'']',
            '\.[\\/ ].*\.ps1',
            'function\s+([A-Za-z0-9-_]+)',
            'Import-Module.*'
        )
    }
    else {
        $patterns = $FunctionNames | ForEach-Object { $_ }
    }

    $results = @()

    Write-Verbose "`nScanning for script dependencies..."
    Write-Verbose "Search Patterns: $($patterns -join ', ')"

    foreach ($path in $searchPaths) {
        Write-Verbose "`nScanning path: $path"
        
        $files = Get-ChildItem -Path $path -Recurse -Filter "*.ps1" -ErrorAction SilentlyContinue | 
            Where-Object { 
                $file = $_
                -not ($ExcludePaths | Where-Object { $file.FullName -like "*$_*" })
            }

        $fileCount = $files.Count
        $currentFile = 0

        foreach ($file in $files) {
            $currentFile++
            $percentComplete = [math]::Round(($currentFile / $fileCount) * 100, 2)
            Write-Progress -Activity "Scanning Files" -Status "$currentFile of $fileCount" -PercentComplete $percentComplete

            try {
                $content = Get-Content $file.FullName -ErrorAction Stop
                
                foreach ($pattern in $patterns) {
                    $matches = $content | Select-String -Pattern $pattern
                    
                    if ($matches) {
                        foreach ($match in $matches) {
                            $result = [PSCustomObject]@{
                                SourceFile   = $file.FullName
                                LineNumber   = $match.LineNumber
                                Pattern      = $pattern
                                MatchedLine  = $match.Line.Trim()
                                LastModified = $file.LastWriteTime
                                FileSize     = "{0:N2} KB" -f ($file.Length / 1KB)
                            }
                            
                            if ($IncludeContent) {
                                $contextLines = @()
                                $startLine = [Math]::Max(1, $match.LineNumber - 2)
                                $endLine = [Math]::Min($content.Count, $match.LineNumber + 2)
                                
                                for ($i = $startLine; $i -le $endLine; $i++) {
                                    $contextLines += "$(if($i -eq $match.LineNumber){'>'} else{' '}) $($i): $($content[$i-1])"
                                }
                                $result | Add-Member -NotePropertyName Context -NotePropertyValue ($contextLines -join "`n")
                            }
                            
                            $results += $result
                        }
                    }
                }
            }
            catch {
                Write-Warning "Error processing $($file.FullName): $_"
            }
        }
    }

    Write-Progress -Activity "Scanning Files" -Completed

    if ($results.Count -eq 0) {
        Write-Verbose "`nNo dependencies found."
        return
    }

    Write-Verbose "`nFound $($results.Count) dependencies across $($results.SourceFile | Select-Object -Unique | Measure-Object).Count files"

    $groupedResults = $results | Group-Object SourceFile

    foreach ($group in $groupedResults) {
        Write-Verbose "`nFile: $($group.Name)"
        Write-Verbose "Last Modified: $($group.Group[0].LastModified)"
        Write-Verbose "Size: $($group.Group[0].FileSize)"
        Write-Verbose "Dependencies found: $($group.Count)"
        
        foreach ($result in $group.Group) {
            Write-Verbose "`nLine $($result.LineNumber): $($result.MatchedLine)"
            if ($result.Context) {
                Write-Verbose "Context:"
                Write-Verbose $result.Context
            }
        }
    }

    if ($ExportResults) {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $exportPath = Join-Path $PWD "DependencyScan_$timestamp.csv"
        $results | Export-Csv -Path $exportPath -NoTypeInformation
        Write-Verbose "`nResults exported to: $exportPath"
    }

    return $results
}


