function Find-DowserDependency {
    # Example usage:
    <#
    # Search for specific functions
    Find-ScriptDependencies -FunctionNames @("Start-FastGroupPing", "Write-Log") -IncludeContent

    # Search all dependencies in multiple paths
    Find-ScriptDependencies -SearchPath `$PWD -AdditionalPaths @("\\Server\Share\Scripts") -ExportResults

    # Quick search in current directory
    Find-ScriptDependencies -SearchPath $PWD -IncludeContent
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

    # Default exclusions are platform-specific. The historic Windows defaults
    # (\Windows\, \Program Files, ...) never match Linux paths, so populate
    # sensible per-platform defaults only when the caller did not supply any.
    # Canonical guard: $IsWindows is $null on PS 5.1, so -ne $false means Windows.
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

    # Combine all search paths
    $searchPaths = @($SearchPath)
    if ($AdditionalPaths) {
        $searchPaths += $AdditionalPaths
    }

    # If no specific functions provided, look for dot-sourcing and function calls
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
        
        # Get all PS1 files, excluding specified paths
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

    # Display results
    if ($results.Count -eq 0) {
        Write-Verbose "`nNo dependencies found."
        return
    }

    Write-Verbose "`nFound $($results.Count) dependencies across $($results.SourceFile | Select-Object -Unique | Measure-Object).Count files"

    # Group results by source file for cleaner output
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

    # Export results if requested
    if ($ExportResults) {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $exportPath = Join-Path $PWD "DependencyScan_$timestamp.csv"
        $results | Export-Csv -Path $exportPath -NoTypeInformation
        Write-Verbose "`nResults exported to: $exportPath"
    }

    return $results
}


