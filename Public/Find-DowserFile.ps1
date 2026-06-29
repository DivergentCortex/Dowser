function Find-DowserFile {
    <#
    .SYNOPSIS
        A high-performance file searching tool.

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
        Searches for files by name, wildcards, size, and dates.
        Uses Runspaces for high-performance parallel processing.

    .PARAMETER Path
        The directory path(s) to search.

    .PARAMETER Pattern
        Wildcard pattern to match file names (e.g., "*.ps1", "log_?.txt").
        Partial strings are auto-wrapped in wildcards: "cortex" becomes "*cortex*".

    .PARAMETER Recurse
        Search subdirectories recursively. Default is $true. Pass -Recurse:$false to disable.

    .PARAMETER MinSize
        Minimum file size (e.g., 1MB).

    .PARAMETER MaxSize
        Maximum file size (e.g., 1GB).

    .PARAMETER ModifiedAfter
        Find files modified after this date.

    .PARAMETER ModifiedBefore
        Find files modified before this date.

    .PARAMETER StopOnFirstMatch
        Return immediately after finding the first match.

    .PARAMETER UseRunspaces
        Enable multi-threaded processing. Default is $true. Pass -UseRunspaces:$false to disable.

    .PARAMETER ThreadCount
        Number of threads to use. Defaults to processor count.

    .EXAMPLE
        Find-DowserFile -Path "D:\Repos" -Pattern "*.ps1"

        Recursively finds all PowerShell scripts under D:\Repos using runspaces.

    .EXAMPLE
        Find-DowserFile -Path "D:\Logs" -Pattern "error" -ModifiedAfter (Get-Date).AddDays(-1) -MinSize 1MB

        Finds files whose name contains "error", modified in the last day, at least 1MB.

    .EXAMPLE
        'C:\Tools','D:\Scripts' | Find-DowserFile -Pattern "*.exe" -StopOnFirstMatch

        Pipes two roots in and returns the first matching executable found.

    .OUTPUTS
        PSCustomObject
        Properties: FullName, Name, Directory, Size, LastWriteTime, CreationTime.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [string[]]$Path,

        [Parameter(Position = 1)]
        [string]$Pattern = "*",

        [bool]$Recurse = $true,

        [string]$MinSize,
        [string]$MaxSize,

        [DateTime]$ModifiedAfter,
        [DateTime]$ModifiedBefore,

        [switch]$StopOnFirstMatch,

        [bool]$UseRunspaces = $true,
        [int]$ThreadCount = [Environment]::ProcessorCount
    )

    begin {
        $script:startTime = Get-Date
        Write-Verbose "Starting Find-DowserFile at $script:startTime"
        
        $minBytes = $null
        if (-not [string]::IsNullOrWhiteSpace($MinSize)) {
            $minBytes = ConvertTo-DowserBytes -SizeStr $MinSize
        }
        $maxBytes = $null
        if (-not [string]::IsNullOrWhiteSpace($MaxSize)) {
            $maxBytes = ConvertTo-DowserBytes -SizeStr $MaxSize
        }

        # bare strings get wrapped, already-wildcarded left alone
        if ($Pattern -ne "*" -and $Pattern -notmatch '[*?]') {
            $Pattern = "*$Pattern*"
            Write-Verbose "Pattern auto-wrapped to: $Pattern"
        }
    }

    process {
        foreach ($p in $Path) {
            if (-not (Test-Path $p)) {
                Write-Warning "Path not found: $p"
                continue
            }
            $p = (Resolve-Path $p).Path

            Write-Progress -Activity "Find-DowserFile" -Status "Scanning directory structure..." -PercentComplete -1
            
            $filesFound = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
            
            if ($UseRunspaces) {
                # partition by top-level dirs to spread across threads
                $topLevelItems = Get-ChildItem -Path $p -Directory -ErrorAction SilentlyContinue
                if ($Recurse) {
                    $scanTargets = @($p) + @($topLevelItems.FullName)
                }
                else {
                    $scanTargets = @($p)
                }

                $scriptBlock = {
                    param($chunk, $pattern, $recurse, $min, $max, $after, $before)
                    $res = @()
                    foreach ($targetPath in $chunk) {
                        $params = @{
                            Path        = $targetPath
                            File        = $true
                            ErrorAction = 'SilentlyContinue'
                            Force       = $true
                        }
                        if ($recurse) {
                            $params['Recurse'] = $true 
                        }
                        if ($pattern -ne "*") {
                            $params['Filter'] = $pattern 
                        }

                        Get-ChildItem @params | ForEach-Object {
                            $ok = $true
                            if ($min -and $_.Length -lt $min) {
                                $ok = $false 
                            }
                            if ($max -and $_.Length -gt $max) {
                                $ok = $false 
                            }
                            if ($after -and $_.LastWriteTime -lt $after) {
                                $ok = $false 
                            }
                            if ($before -and $_.LastWriteTime -gt $before) {
                                $ok = $false 
                            }

                            if ($ok) {
                                $res += $_.FullName
                            }
                        }
                    }
                    return $res
                }

                $results = Invoke-DowserRunspacePool -InputObject $scanTargets -ScriptBlock $scriptBlock -ArgumentList @($Pattern, $Recurse, $minBytes, $maxBytes, $ModifiedAfter, $ModifiedBefore) -ThreadCount $ThreadCount -ProgressActivity "Scanning Files" -ProgressStatus "Scanning targets..."
                
                foreach ($r in $results) {
                    $filesFound.Add($r) 
                }
            }
            else {
                $params = @{
                    Path        = $p
                    Recurse     = $Recurse
                    File        = $true
                    ErrorAction = 'SilentlyContinue'
                    Force       = $true
                }
                if ($Pattern -ne "*") {
                    $params['Filter'] = $Pattern 
                }
                
                Get-ChildItem @params | ForEach-Object {
                    $ok = $true
                    if ($minBytes -and $_.Length -lt $minBytes) {
                        $ok = $false 
                    }
                    if ($maxBytes -and $_.Length -gt $maxBytes) {
                        $ok = $false 
                    }
                    if ($ModifiedAfter -and $_.LastWriteTime -lt $ModifiedAfter) {
                        $ok = $false 
                    }
                    if ($ModifiedBefore -and $_.LastWriteTime -gt $ModifiedBefore) {
                        $ok = $false 
                    }

                    if ($ok) {
                        $filesFound.Add($_.FullName)
                        if ($StopOnFirstMatch) {
                            return 
                        }
                    }
                }
            }

            $allPaths = $filesFound.ToArray() | Select-Object -Unique
            $count = @($allPaths).Count
            Write-Verbose "Found $count files matching basic criteria."
            
            if ($count -gt 0) {
                Write-Progress -Activity "Find-DowserFile" -Status "Retrieving file objects..." -PercentComplete -1
                if ($StopOnFirstMatch) {
                    $firstFile = Get-Item -LiteralPath $allPaths[0] -ErrorAction SilentlyContinue
                    [PSCustomObject]@{
                        FullName      = $firstFile.FullName
                        Name          = $firstFile.Name
                        Directory     = $firstFile.DirectoryName
                        Size          = $firstFile.Length
                        LastWriteTime = $firstFile.LastWriteTime
                        CreationTime  = $firstFile.CreationTime
                    }
                }
                else {
                    $allPaths | ForEach-Object {
                        $f = Get-Item -LiteralPath $_ -ErrorAction SilentlyContinue
                        [PSCustomObject]@{
                            FullName      = $f.FullName
                            Name          = $f.Name
                            Directory     = $f.DirectoryName
                            Size          = $f.Length
                            LastWriteTime = $f.LastWriteTime
                            CreationTime  = $f.CreationTime
                        }
                    }
                }
            }
        }
    }
    end {
        $duration = New-TimeSpan -Start $script:startTime -End (Get-Date)
        Write-Verbose "Find-DowserFile completed in $($duration.TotalSeconds) seconds."
    }
}