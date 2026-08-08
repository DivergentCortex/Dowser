#Requires -Version 5.1

# two-phase parallel file report. gather dirs first, analyze chunks in phase 2.
# runspace block has its own size formatter, cant reach Format-DowserSize from there
# ConvertTo-DowserBytes handles MinSize/MaxSize string parsing from module Private.

function Get-DowserReport {
    <#
    .SYNOPSIS
        File metrics reporting tool with parallel runspace processing.
    .NOTES
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
        -  Author:        Curtis Leggett                                  -
        =  Copyright:     2026 Divergent Cortex                           =
        -  Organization:  Divergent Cortex                                -
        =  Version:       See docs/CHANGELOG.md                           =
        =-=-                       =-=-=-=-=-=-=-=                     -=-=
        -  it is not water they seek, but the truth beneath the trees     -
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

        Ported from: Get-FileReport.ps1 (standalone scripts)
        Uses: Private\Format-DowserSize, Private\ConvertTo-DowserBytes
        Note: The runspace analyzeScriptBlock contains a local inline size formatter
              because module-scope functions are not reachable from runspace threads.
              This is intentional. Do not refactor it out.
    .DESCRIPTION
        Scans a single file, folder, or entire directory tree and produces a detailed
        metrics report including file size, line count, word count, character count,
        timestamps, attributes, and optionally file ownership.

        Uses RunspacePool-based parallel processing for both file gathering and file
        analysis phases.
    .PARAMETER Path
        The file or directory path(s) to analyze. Accepts pipeline input.
        Can be a single file, a folder, or multiple paths.
    .PARAMETER Pattern
        Wildcard pattern to match file names (e.g., "*.ps1", "*.log"). Default is "*".
    .PARAMETER Extensions
        Array of extension filters (e.g., '*.ps1','*.txt','*.csv').
    .PARAMETER Depth
        How many levels deep to scan. Default is 0 (target folder only).
        Use -1 for unlimited recursion. Examples: 0 = current folder only,
        1 = target + immediate subfolders, -1 = full recursive.
    .PARAMETER IncludeOwner
        Include file owner from ACL. Slower due to Get-Acl calls. Off by default.
    .PARAMETER MinSize
        Minimum file size filter (e.g., "1KB", "10MB").
    .PARAMETER MaxSize
        Maximum file size filter (e.g., "500MB", "1GB").
    .PARAMETER UseRunspaces
        Enable multi-threaded processing. Default is $true.
    .PARAMETER ThreadCount
        Number of threads for parallel processing. Defaults to processor count.
    .PARAMETER ExportCsv
        Path to automatically export results as CSV.
    .PARAMETER ExportHtml
        Path to automatically export results as formatted HTML report.
    .PARAMETER SortBy
        Property to sort results by. Default is 'FullName'.
    .PARAMETER Descending
        Sort results in descending order.
    .EXAMPLE
        Get-DowserReport -Path "D:\Scripts"

        Reports metrics for the files directly under D:\Scripts.
    .EXAMPLE
        Get-DowserReport -Path "D:\Scripts\MyScript.ps1"

        Reports metrics for a single file.
    .EXAMPLE
        Get-DowserReport -Path "D:\Logs" -Extensions '*.log','*.txt' -Depth -1 -ExportCsv "D:\report.csv"

        Recursively reports .log and .txt files and exports the result to CSV.
    .EXAMPLE
        Get-DowserReport -Path "D:\Projects" -IncludeOwner -SortBy Size -Descending

        Reports with owner column, sorted by size descending.
    .EXAMPLE
        Get-DowserReport -Path "D:\Projects" -Depth -1

        Recursively reports every file under D:\Projects.
    .INPUTS
        System.String
        You can pipe one or more paths to this function.
    .OUTPUTS
        PSCustomObject
        Structured file metrics for downstream processing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [string[]]$Path,

        [Parameter(Position = 1)]
        [string]$Pattern = "*",

        [string[]]$Extensions,

        [ValidateRange(-1, 100)]
        [int]$Depth = 0,

        [switch]$IncludeOwner,

        [string]$MinSize,

        [string]$MaxSize,

        [switch]$UseRunspaces = $true,

        [int]$ThreadCount = [Environment]::ProcessorCount,

        [string]$ExportCsv,

        [string]$ExportHtml,

        [ValidateSet("Name", "FullName", "Size", "LineCount", "WordCount", "CharCount", "CreationTime", "LastWriteTime", "Extension")]
        [string]$SortBy = "FullName",

        [switch]$Descending
    )

    begin {
        $script:startTime = Get-Date
        $script:allResults = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))
        $script:errorCount = 0

        $minBytes = if ($MinSize) {
            ConvertTo-DowserBytes -SizeString $MinSize 
        }
        else {
            $null 
        }
        $maxBytes = if ($MaxSize) {
            ConvertTo-DowserBytes -SizeString $MaxSize 
        }
        else {
            $null 
        }

        # wrap bare strings so partial names match
        if ($Pattern -ne "*" -and $Pattern -notmatch '[*?]') {
            $Pattern = "*$Pattern*"
            Write-Log "Pattern auto-wrapped to: $Pattern" -Severity Verbose
        }

        Write-Log "Starting Get-DowserReport"
        Write-Log "Get-DowserReport params: Threads=$ThreadCount Depth=$Depth UseRunspaces=$UseRunspaces" -Severity Verbose
    }

    process {
        foreach ($p in $Path) {
            if (-not (Test-Path $p)) {
                Write-Log "Get-DowserReport path not found: '$p'" -Severity Warning
                continue
            }

            $resolvedPath = (Resolve-Path $p).ProviderPath
            $isSingleFile = (Test-Path $resolvedPath -PathType Leaf)

            # ================================================================
            # SINGLE FILE MODE - skip runspaces entirely
            # ================================================================
            if ($isSingleFile) {
                Write-Log "Single file mode: $resolvedPath" -Severity Verbose
                $fileItem = Get-Item -LiteralPath $resolvedPath -Force -ErrorAction SilentlyContinue
                if (-not $fileItem) {
                    continue 
                }

                $lineCount = 0
                $wordCount = 0
                $charCount = 0
                try {
                    $content = Get-Content -LiteralPath $fileItem.FullName -Raw -ErrorAction Stop
                    if ($content) {
                        $lines = $content -split "`n"
                        $lineCount = $lines.Count
                        $charCount = $content.Length
                        $wordCount = ($content -split '\s+' | Where-Object { $_ -ne '' }).Count
                    }
                }
                catch {
                    Write-Log "Could not read content of $($fileItem.FullName): $_" -Severity Verbose
                }

                $owner = $null
                if ($IncludeOwner) {
                    try {
                        $acl = Get-Acl -LiteralPath $fileItem.FullName -ErrorAction Stop
                        $owner = $acl.Owner
                    }
                    catch {
                        $owner = "ACCESS DENIED"
                    }
                }

                $resultProps = [ordered]@{
                    RelativeFolder = '.'
                    FullName       = $fileItem.FullName
                    Name           = $fileItem.Name
                    Extension      = $fileItem.Extension
                    Directory      = $fileItem.DirectoryName
                    Size           = $fileItem.Length
                    SizeFormatted  = (Format-DowserSize -DataValue $fileItem.Length)
                    LineCount      = $lineCount
                    WordCount      = $wordCount
                    CharCount      = $charCount
                    CreationTime   = $fileItem.CreationTime.ToString("yyyy-MM-dd HH:mm:ss")
                    LastWriteTime  = $fileItem.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
                    LastAccessTime = $fileItem.LastAccessTime.ToString("yyyy-MM-dd HH:mm:ss")
                    Attributes     = $fileItem.Attributes.ToString()
                    IsReadOnly     = $fileItem.IsReadOnly
                    IsHidden       = [bool]($fileItem.Attributes -band [System.IO.FileAttributes]::Hidden)
                    IsSystem       = [bool]($fileItem.Attributes -band [System.IO.FileAttributes]::System)
                }
                if ($IncludeOwner) {
                    $resultProps['Owner'] = $owner 
                }

                $obj = [PSCustomObject]$resultProps
                [void]$script:allResults.Add($obj)
                continue
            }

            # ================================================================
            # PHASE 1: FILE GATHERING (runspace pool, directory-partitioned)
            # ================================================================
            Write-Progress -Activity "Get-DowserReport" -Status "Scanning directory structure..." -PercentComplete -1

            $filesFound = New-Object System.Collections.Concurrent.ConcurrentBag[string]

            $gatherScriptBlock = {
                param($TargetPath, $Pattern, $Extensions, $ScanDepth, $MinBytes, $MaxBytes)

                $params = @{
                    Path        = $TargetPath
                    File        = $true
                    ErrorAction = 'SilentlyContinue'
                    Force       = $true
                }
                if ($ScanDepth -eq -1) {
                    $params['Recurse'] = $true
                }
                elseif ($ScanDepth -gt 0) {
                    $params['Recurse'] = $true
                    $params['Depth'] = $ScanDepth
                }
                if ($Pattern -ne "*") {
                    $params['Filter'] = $Pattern 
                }

                Get-ChildItem @params | ForEach-Object {
                    $file = $_
                    if ($Extensions) {
                        $matchesExt = $false
                        foreach ($ext in $Extensions) {
                            if ($file.Name -like $ext) {
                                $matchesExt = $true; break 
                            }
                        }
                        if (-not $matchesExt) {
                            return 
                        }
                    }
                    if ($MinBytes -and $file.Length -lt $MinBytes) {
                        return 
                    }
                    if ($MaxBytes -and $file.Length -gt $MaxBytes) {
                        return 
                    }
                    $file.FullName
                }
            }

            if ($UseRunspaces) {
                $topLevelDirs = Get-ChildItem -Path $resolvedPath -Directory -ErrorAction SilentlyContinue
                if ($Depth -ne 0 -and $topLevelDirs) {
                    $scanTargets = @($resolvedPath) + @($topLevelDirs.FullName)
                }
                else {
                    $scanTargets = @($resolvedPath)
                }

                $gatherPool = [RunspaceFactory]::CreateRunspacePool(1, $ThreadCount)
                $gatherPool.Open()
                $gatherJobs = New-Object System.Collections.ArrayList

                foreach ($target in $scanTargets) {
                    $ps = [PowerShell]::Create()
                    $ps.RunspacePool = $gatherPool
                    [void]$ps.AddScript($gatherScriptBlock)
                    [void]$ps.AddArgument($target)
                    [void]$ps.AddArgument($Pattern)
                    [void]$ps.AddArgument($Extensions)
                    if (@($scanTargets).Count -gt 1 -and $target -eq $resolvedPath) {
                        $targetDepth = 0
                    }
                    elseif (@($scanTargets).Count -gt 1 -and $Depth -gt 0) {
                        $targetDepth = $Depth - 1
                    }
                    else {
                        $targetDepth = $Depth
                    }
                    [void]$ps.AddArgument($targetDepth)
                    [void]$ps.AddArgument($minBytes)
                    [void]$ps.AddArgument($maxBytes)

                    $job = $ps.BeginInvoke()
                    [void]$gatherJobs.Add([PSCustomObject]@{ Pipe = $ps; Result = $job })
                }

                $totalGatherJobs = @($gatherJobs).Count
                while ($gatherJobs | Where-Object { -not $_.Result.IsCompleted }) {
                    $completed = ($gatherJobs | Where-Object { $_.Result.IsCompleted }).Count
                    Write-Progress -Activity "Get-DowserReport" `
                        -Status "Gathering files... ($completed / $totalGatherJobs dirs scanned)" `
                        -PercentComplete (($completed / $totalGatherJobs) * 100) -Id 1
                    Start-Sleep -Milliseconds 100
                }
                Write-Progress -Activity "Get-DowserReport" -Status "File gathering complete" -PercentComplete 100 -Id 1 -Completed

                foreach ($j in $gatherJobs) {
                    try {
                        $res = $j.Pipe.EndInvoke($j.Result)
                        foreach ($r in $res) {
                            $filesFound.Add($r) 
                        }
                    }
                    catch {
                        Write-Log "Error in file gather thread: $_" -Severity Verbose
                        $script:errorCount++
                    }
                    finally {
                        $j.Pipe.Dispose()
                    }
                }
                $gatherPool.Close()
                $gatherPool.Dispose()

            }
            else {
                Write-Log "Single-threaded file gathering" -Severity Verbose
                $gatherResults = & $gatherScriptBlock $resolvedPath $Pattern $Extensions $Depth $minBytes $maxBytes
                foreach ($r in $gatherResults) {
                    $filesFound.Add($r) 
                }
            }

            $allPaths = $filesFound.ToArray() | Select-Object -Unique
            $fileCount = @($allPaths).Count
            Write-Log "Found $fileCount files matching criteria" -Severity Verbose

            if ($fileCount -eq 0) {
                Write-Log "Get-DowserReport no files found in '$resolvedPath' matching criteria" -Severity Warning
                continue
            }

            # ================================================================
            # PHASE 2: FILE ANALYSIS (runspace pool, chunked processing)
            # ================================================================

            # inline formatter, runspace cant reach Format-DowserSize, dont redirect
            $analyzeScriptBlock = {
                param($FilePaths, $DoIncludeOwner, $ScanRoot)

                $results = @()
                foreach ($filePath in $FilePaths) {
                    $fileItem = $null
                    try {
                        $fileItem = Get-Item -LiteralPath $filePath -Force -ErrorAction Stop
                    }
                    catch {
                        continue 
                    }

                    $lineCount = 0
                    $wordCount = 0
                    $charCount = 0
                    try {
                        $reader = [System.IO.StreamReader]::new($filePath)
                        $content = $reader.ReadToEnd()
                        $reader.Close()
                        $reader.Dispose()
                        if ($content) {
                            $lines = $content -split "`n"
                            $lineCount = $lines.Count
                            $charCount = $content.Length
                            $wordCount = ($content -split '\s+' | Where-Object { $_ -ne '' }).Count
                        }
                    }
                    catch {
                        $lineCount = -1
                        $wordCount = -1
                        $charCount = -1
                    }

                    $owner = $null
                    if ($DoIncludeOwner) {
                        try {
                            $acl = Get-Acl -LiteralPath $fileItem.FullName -ErrorAction Stop
                            $owner = $acl.Owner
                        }
                        catch {
                            $owner = "ACCESS DENIED" 
                        }
                    }

                    # cant reach Format-DowserSize from runspace scope
                    $bytes = $fileItem.Length
                    $sizeFormatted = "$bytes B"
                    if ($bytes -ge 1TB) {
                        $sizeFormatted = "{0:N2} TB" -f ($bytes / 1TB) 
                    }
                    elseif ($bytes -ge 1GB) {
                        $sizeFormatted = "{0:N2} GB" -f ($bytes / 1GB) 
                    }
                    elseif ($bytes -ge 1MB) {
                        $sizeFormatted = "{0:N2} MB" -f ($bytes / 1MB) 
                    }
                    elseif ($bytes -ge 1KB) {
                        $sizeFormatted = "{0:N2} KB" -f ($bytes / 1KB) 
                    }

                    $relFolder = '.'
                    if ($ScanRoot -and $fileItem.DirectoryName) {
                        $sep = [System.IO.Path]::DirectorySeparatorChar
                        $normRoot = $ScanRoot.Replace('/', $sep).TrimEnd($sep)
                        $normDir = $fileItem.DirectoryName.Replace('/', $sep).TrimEnd($sep)
                        if ([string]::Equals($normDir, $normRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                            $relFolder = '.'
                        }
                        elseif ($normDir.StartsWith($normRoot + $sep, [System.StringComparison]::OrdinalIgnoreCase)) {
                            $relFolder = $normDir.Substring($normRoot.Length + 1)
                        }
                        else {
                            $relFolder = Split-Path $fileItem.DirectoryName -Leaf
                        }
                    }

                    $props = @{
                        RelativeFolder = $relFolder
                        FullName       = $fileItem.FullName
                        Name           = $fileItem.Name
                        Extension      = $fileItem.Extension
                        Directory      = $fileItem.DirectoryName
                        Size           = $bytes
                        SizeFormatted  = $sizeFormatted
                        LineCount      = $lineCount
                        WordCount      = $wordCount
                        CharCount      = $charCount
                        CreationTime   = $fileItem.CreationTime.ToString("yyyy-MM-dd HH:mm:ss")
                        LastWriteTime  = $fileItem.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
                        LastAccessTime = $fileItem.LastAccessTime.ToString("yyyy-MM-dd HH:mm:ss")
                        Attributes     = $fileItem.Attributes.ToString()
                        IsReadOnly     = $fileItem.IsReadOnly
                        IsHidden       = [bool]($fileItem.Attributes -band [System.IO.FileAttributes]::Hidden)
                        IsSystem       = [bool]($fileItem.Attributes -band [System.IO.FileAttributes]::System)
                    }
                    if ($DoIncludeOwner) {
                        $props['Owner'] = $owner 
                    }

                    $results += [PSCustomObject]$props
                }
                return $results
            }

            if ($UseRunspaces) {
                $chunkSize = [Math]::Ceiling($fileCount / $ThreadCount)
                if ($chunkSize -lt 1) {
                    $chunkSize = 1 
                }

                $analyzePool = [RunspaceFactory]::CreateRunspacePool(1, $ThreadCount)
                $analyzePool.Open()
                $analyzeJobs = New-Object System.Collections.ArrayList

                $counter = 0
                while ($counter -lt $fileCount) {
                    $chunk = $allPaths | Select-Object -Skip $counter -First $chunkSize
                    $counter += $chunkSize

                    $ps = [PowerShell]::Create()
                    $ps.RunspacePool = $analyzePool
                    [void]$ps.AddScript($analyzeScriptBlock)
                    [void]$ps.AddArgument($chunk)
                    [void]$ps.AddArgument([bool]$IncludeOwner)
                    [void]$ps.AddArgument($resolvedPath)

                    $job = $ps.BeginInvoke()
                    [void]$analyzeJobs.Add([PSCustomObject]@{ Pipe = $ps; Result = $job })
                }

                $totalAnalyzeJobs = @($analyzeJobs).Count
                while ($analyzeJobs | Where-Object { -not $_.Result.IsCompleted }) {
                    $completed = ($analyzeJobs | Where-Object { $_.Result.IsCompleted }).Count
                    Write-Progress -Activity "Get-DowserReport" `
                        -Status "Analyzing files... ($completed / $totalAnalyzeJobs chunks done)" `
                        -PercentComplete (($completed / $totalAnalyzeJobs) * 100) -Id 2
                    Start-Sleep -Milliseconds 100
                }
                Write-Progress -Activity "Get-DowserReport" -Status "Analysis complete" -PercentComplete 100 -Id 2 -Completed

                foreach ($j in $analyzeJobs) {
                    try {
                        $jobResults = $j.Pipe.EndInvoke($j.Result)
                        foreach ($row in $jobResults) {
                            [void]$script:allResults.Add($row) 
                        }
                    }
                    catch {
                        Write-Log "Error in analysis thread: $_" -Severity Verbose
                        $script:errorCount++
                    }
                    finally {
                        $j.Pipe.Dispose()
                    }
                }
                $analyzePool.Close()
                $analyzePool.Dispose()

            }
            else {
                Write-Log "Single-threaded file analysis" -Severity Verbose
                $analysisResults = & $analyzeScriptBlock $allPaths ([bool]$IncludeOwner) $resolvedPath
                foreach ($row in $analysisResults) {
                    [void]$script:allResults.Add($row) 
                }
            }
        }
    }

    end {
        if (@($script:allResults).Count -eq 0) {
            Write-Log "Get-DowserReport no files were analyzed" -Severity Warning
            Write-Log "Ending Get-DowserReport"
            return
        }

        if ($Depth -ne 0) {
            $sortedResults = $script:allResults | Sort-Object RelativeFolder, $SortBy
            if ($Descending) {
                $sortedResults = $script:allResults | Sort-Object RelativeFolder, @{Expression = $SortBy; Descending = $true }
            }
        }
        else {
            $sortParams = @{ Property = $SortBy }
            if ($Descending) {
                $sortParams['Descending'] = $true 
            }
            $sortedResults = $script:allResults | Sort-Object @sortParams
        }

        # grouped view only for multi-dir scans
        if ($Depth -ne 0) {
            $groupedType = 'FileReport.GroupedResult'
            $ownerHeader = ''
            $ownerColumn = ''
            if ($IncludeOwner) {
                $ownerHeader = '<TableColumnHeader><Label>Owner</Label><Width>25</Width></TableColumnHeader>'
                $ownerColumn = '<TableColumnItem><PropertyName>Owner</PropertyName></TableColumnItem>'
            }

            $formatXml = @"
<?xml version="1.0" encoding="utf-8"?>
<Configuration>
    <ViewDefinitions>
        <View>
            <Name>FileReport.GroupedView</Name>
            <ViewSelectedBy>
                <TypeName>$groupedType</TypeName>
            </ViewSelectedBy>
            <GroupBy>
                <PropertyName>RelativeFolder</PropertyName>
                <Label>Folder</Label>
            </GroupBy>
            <TableControl>
                <TableHeaders>
                    <TableColumnHeader><Label>Name</Label><Width>40</Width></TableColumnHeader>
                    <TableColumnHeader><Label>Size</Label><Width>12</Width><Alignment>Right</Alignment></TableColumnHeader>
                    <TableColumnHeader><Label>Lines</Label><Width>8</Width><Alignment>Right</Alignment></TableColumnHeader>
                    <TableColumnHeader><Label>Words</Label><Width>8</Width><Alignment>Right</Alignment></TableColumnHeader>
                    <TableColumnHeader><Label>Chars</Label><Width>8</Width><Alignment>Right</Alignment></TableColumnHeader>
                    <TableColumnHeader><Label>LastWriteTime</Label><Width>20</Width></TableColumnHeader>
                    $ownerHeader
                </TableHeaders>
                <TableRowEntries>
                    <TableRowEntry>
                        <TableColumnItems>
                            <TableColumnItem><PropertyName>Name</PropertyName></TableColumnItem>
                            <TableColumnItem><PropertyName>SizeFormatted</PropertyName></TableColumnItem>
                            <TableColumnItem><PropertyName>LineCount</PropertyName></TableColumnItem>
                            <TableColumnItem><PropertyName>WordCount</PropertyName></TableColumnItem>
                            <TableColumnItem><PropertyName>CharCount</PropertyName></TableColumnItem>
                            <TableColumnItem><PropertyName>LastWriteTime</PropertyName></TableColumnItem>
                            $ownerColumn
                        </TableColumnItems>
                    </TableRowEntry>
                </TableRowEntries>
            </TableControl>
        </View>
    </ViewDefinitions>
</Configuration>
"@
            $tempFormatFile = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'FileReport.format.ps1xml')
            $formatXml | Set-Content -Path $tempFormatFile -Encoding UTF8
            Update-FormatData -PrependPath $tempFormatFile -ErrorAction SilentlyContinue

            foreach ($obj in $sortedResults) {
                $obj.PSObject.TypeNames.Insert(0, $groupedType)
            }
        }
        else {
            $defaultDisplay = @('Name', 'SizeFormatted', 'LineCount', 'WordCount', 'CharCount', 'LastWriteTime', 'CreationTime')
            if ($IncludeOwner) {
                $defaultDisplay += 'Owner' 
            }
            $defaultSet = New-Object System.Management.Automation.PSPropertySet('DefaultDisplayPropertySet', [string[]]$defaultDisplay)
            $memberInfo = [System.Management.Automation.PSMemberInfo[]]@($defaultSet)
            foreach ($obj in $sortedResults) {
                $obj | Add-Member -MemberType MemberSet -Name PSStandardMembers -Value $memberInfo -Force
            }
        }

        $sortedResults | Write-Output

        $duration = New-TimeSpan -Start $script:startTime -End (Get-Date)
        $totalFiles = @($sortedResults).Count
        $totalSize = ($sortedResults | Measure-Object -Property Size -Sum).Sum
        $totalLines = ($sortedResults | Where-Object { $_.LineCount -ge 0 } | Measure-Object -Property LineCount -Sum).Sum
        $totalWords = ($sortedResults | Where-Object { $_.WordCount -ge 0 } | Measure-Object -Property WordCount -Sum).Sum
        $totalChars = ($sortedResults | Where-Object { $_.CharCount -ge 0 } | Measure-Object -Property CharCount -Sum).Sum
        $binaryFiles = ($sortedResults | Where-Object { $_.LineCount -eq -1 }).Count
        $readableFiles = $totalFiles - $binaryFiles
        $avgSize = if ($totalFiles -gt 0) {
            [long]($totalSize / $totalFiles) 
        }
        else {
            0 
        }
        $avgLines = if ($readableFiles -gt 0) {
            [Math]::Round($totalLines / $readableFiles, 1) 
        }
        else {
            0 
        }

        $extensionBreakdown = $sortedResults | Group-Object Extension |
            Sort-Object Count -Descending |
            Select-Object -First 10 |
            ForEach-Object { "$($_.Name): $($_.Count)" }

        Write-Log " " -Severity Verbose
        Write-Log "--- Get-DowserReport Summary ---" -Severity Verbose
        Write-Log ("  {0,-22}: {1}" -f "Total Files", $totalFiles) -Severity Verbose
        Write-Log ("  {0,-22}: {1}" -f "Readable Files", $readableFiles) -Severity Verbose
        Write-Log ("  {0,-22}: {1}" -f "Binary/Locked Files", $binaryFiles) -Severity Verbose
        Write-Log ("  {0,-22}: {1}" -f "Total Size", (Format-DowserSize -DataValue $totalSize)) -Severity Verbose
        Write-Log ("  {0,-22}: {1}" -f "Average File Size", (Format-DowserSize -DataValue $avgSize)) -Severity Verbose
        Write-Log ("  {0,-22}: {1:N0}" -f "Total Lines", $totalLines) -Severity Verbose
        Write-Log ("  {0,-22}: {1:N0}" -f "Total Words", $totalWords) -Severity Verbose
        Write-Log ("  {0,-22}: {1:N0}" -f "Total Characters", $totalChars) -Severity Verbose
        Write-Log ("  {0,-22}: {1}" -f "Avg Lines/File", $avgLines) -Severity Verbose
        if ($script:errorCount -gt 0) {
            Write-Log ("  {0,-22}: {1}" -f "Errors Encountered", $script:errorCount) -Severity Verbose
        }
        Write-Log ("  {0,-22}: {1}" -f "Top Extensions", ($extensionBreakdown -join ", ")) -Severity Verbose
        Write-Log ("  {0,-22}: {1:F2}s" -f "Execution Time", $duration.TotalSeconds) -Severity Verbose
        Write-Log " " -Severity Verbose

        if ($ExportCsv) {
            Write-Log "Get-DowserReport exporting CSV to '$ExportCsv'" -Severity Verbose
            try {
                $sortedResults | Export-Csv -Path $ExportCsv -NoTypeInformation -ErrorAction Stop
                Write-Log "Get-DowserReport CSV exported to '$ExportCsv'" -Severity Verbose
            }
            catch {
                Write-Log "Get-DowserReport failed exporting CSV to '$ExportCsv': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Warning
            }
        }

        if ($ExportHtml) {
            Write-Log "Get-DowserReport exporting HTML report to '$ExportHtml'" -Severity Verbose
            try {
                $htmlHead = @"
<style>
    body { font-family: Segoe UI, Tahoma, sans-serif; margin: 20px; background: #1e1e1e; color: #d4d4d4; }
    h1 { color: #569cd6; border-bottom: 2px solid #569cd6; padding-bottom: 8px; }
    h2 { color: #4ec9b0; margin-top: 30px; }
    table { border-collapse: collapse; width: 100%; margin-top: 10px; font-size: 13px; }
    th { background: #264f78; color: #fff; padding: 8px 12px; text-align: left; border: 1px solid #3c3c3c; }
    td { padding: 6px 12px; border: 1px solid #3c3c3c; }
    tr:nth-child(even) { background: #2d2d2d; }
    tr:nth-child(odd)  { background: #252526; }
    tr:hover           { background: #37373d; }
    .summary { background: #252526; padding: 15px; border-radius: 4px; border: 1px solid #3c3c3c; margin-bottom: 20px; }
    .summary span { display: inline-block; margin-right: 30px; }
    .label { color: #9cdcfe; }
    .value { color: #ce9178; font-weight: bold; }
</style>
"@
                $summaryHtml = @"
<div class='summary'>
    <span><span class='label'>Total Files:</span> <span class='value'>$totalFiles</span></span>
    <span><span class='label'>Total Size:</span>  <span class='value'>$(Format-DowserSize -DataValue $totalSize)</span></span>
    <span><span class='label'>Total Lines:</span> <span class='value'>$($totalLines.ToString('N0'))</span></span>
    <span><span class='label'>Total Words:</span> <span class='value'>$($totalWords.ToString('N0'))</span></span>
    <span><span class='label'>Total Chars:</span> <span class='value'>$($totalChars.ToString('N0'))</span></span>
    <span><span class='label'>Duration:</span>    <span class='value'>$("{0:F2}s" -f $duration.TotalSeconds)</span></span>
</div>
"@
                $displayProps = @('Name', 'Directory', 'SizeFormatted', 'LineCount', 'WordCount', 'CharCount', 'LastWriteTime', 'CreationTime', 'Extension')
                if ($IncludeOwner) {
                    $displayProps += 'Owner' 
                }

                $tableHtml = $sortedResults |
                    Select-Object $displayProps |
                    ConvertTo-Html -Fragment

                $fullHtml = @"
<!DOCTYPE html>
<html>
<head>
    <title>Get-DowserReport - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') PST</title>
    $htmlHead
</head>
<body>
    <h1>Dowser File Report</h1>
    <p>Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') PST</p>
    <h2>Summary</h2>
    $summaryHtml
    <h2>File Details</h2>
    $tableHtml
</body>
</html>
"@
                $fullHtml | Out-File -FilePath $ExportHtml -Encoding UTF8 -ErrorAction Stop
                Write-Log "Get-DowserReport HTML report exported to '$ExportHtml'" -Severity Verbose
            }
            catch {
                Write-Log "Get-DowserReport failed exporting HTML to '$ExportHtml': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Warning
            }
        }
        Write-Log "Ending Get-DowserReport"
    }
}

function Compare-DowserReport {
    <#
    .SYNOPSIS
        Compares two Get-DowserReport snapshots and shows what changed.
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
        Takes a "before" and "after" set of Get-DowserReport results and produces
        a detailed diff showing new files, removed files, and changed files with
        deltas for size, line count, word count, and character count.
    .PARAMETER Before
        The baseline snapshot (output from a previous Get-DowserReport call).
    .PARAMETER After
        The current snapshot (output from a new Get-DowserReport call).
    .PARAMETER ShowUnchanged
        Include unchanged files in the output. Default is $false.
    .EXAMPLE
        $before = Get-DowserReport -Path .\project
        # ... make changes ...
        $after = Get-DowserReport -Path .\project
        Compare-DowserReport -Before $before -After $after

        Captures a baseline, then diffs it against a fresh snapshot after edits.
    .OUTPUTS
        PSCustomObject
        One object per file carrying change status and per-metric deltas.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Before,

        [Parameter(Mandatory = $true)]
        [object[]]$After,

        [switch]$ShowUnchanged
    )

    begin {
        Write-Log "Starting Compare-DowserReport"
        $results = [System.Collections.ArrayList]::new()

        function Format-Delta {
            param([long]$Value)
            if ($Value -gt 0) {
                return "+$Value" 
            }
            if ($Value -lt 0) {
                return "$Value" 
            }
            return "0"
        }

        function Format-SizeDelta {
            param([long]$Bytes)
            $sign = if ($Bytes -ge 0) {
                "+" 
            }
            else {
                "" 
            }
            if ([Math]::Abs($Bytes) -ge 1MB) {
                return "$sign$("{0:N2}" -f ($Bytes / 1MB)) MB" 
            }
            if ([Math]::Abs($Bytes) -ge 1KB) {
                return "$sign$("{0:N2}" -f ($Bytes / 1KB)) KB" 
            }
            return "$sign$Bytes B"
        }
    }

    process {
        $beforeMap = @{}
        foreach ($item in $Before) {
            $beforeMap[$item.Name] = $item 
        }

        $afterMap = @{}
        foreach ($item in $After) {
            $afterMap[$item.Name] = $item 
        }

        foreach ($name in $afterMap.Keys) {
            if (-not $beforeMap.ContainsKey($name)) {
                $a = $afterMap[$name]
                [void]$results.Add([PSCustomObject]@{
                        Status        = "NEW"
                        Name          = $name
                        SizeBefore    = $null
                        SizeAfter     = $a.SizeFormatted
                        SizeDelta     = Format-SizeDelta $a.Size
                        LinesBefore   = $null
                        LinesAfter    = $a.LineCount
                        LinesDelta    = Format-Delta $a.LineCount
                        WordsBefore   = $null
                        WordsAfter    = $a.WordCount
                        WordsDelta    = Format-Delta $a.WordCount
                        CharsBefore   = $null
                        CharsAfter    = $a.CharCount
                        CharsDelta    = Format-Delta $a.CharCount
                        LastWriteTime = $a.LastWriteTime
                    })
            }
        }

        foreach ($name in $beforeMap.Keys) {
            if (-not $afterMap.ContainsKey($name)) {
                $b = $beforeMap[$name]
                [void]$results.Add([PSCustomObject]@{
                        Status        = "REMOVED"
                        Name          = $name
                        SizeBefore    = $b.SizeFormatted
                        SizeAfter     = $null
                        SizeDelta     = Format-SizeDelta (-$b.Size)
                        LinesBefore   = $b.LineCount
                        LinesAfter    = $null
                        LinesDelta    = Format-Delta (-$b.LineCount)
                        WordsBefore   = $b.WordCount
                        WordsAfter    = $null
                        WordsDelta    = Format-Delta (-$b.WordCount)
                        CharsBefore   = $b.CharCount
                        CharsAfter    = $null
                        CharsDelta    = Format-Delta (-$b.CharCount)
                        LastWriteTime = $b.LastWriteTime
                    })
            }
        }

        foreach ($name in $afterMap.Keys) {
            if ($beforeMap.ContainsKey($name)) {
                $b = $beforeMap[$name]
                $a = $afterMap[$name]

                $sizeDiff = $a.Size - $b.Size
                $lineDiff = $a.LineCount - $b.LineCount
                $wordDiff = $a.WordCount - $b.WordCount
                $charDiff = $a.CharCount - $b.CharCount

                $isChanged = ($sizeDiff -ne 0) -or ($lineDiff -ne 0) -or ($wordDiff -ne 0) -or ($charDiff -ne 0)

                if ($isChanged) {
                    [void]$results.Add([PSCustomObject]@{
                            Status        = "CHANGED"
                            Name          = $name
                            SizeBefore    = $b.SizeFormatted
                            SizeAfter     = $a.SizeFormatted
                            SizeDelta     = Format-SizeDelta $sizeDiff
                            LinesBefore   = $b.LineCount
                            LinesAfter    = $a.LineCount
                            LinesDelta    = Format-Delta $lineDiff
                            WordsBefore   = $b.WordCount
                            WordsAfter    = $a.WordCount
                            WordsDelta    = Format-Delta $wordDiff
                            CharsBefore   = $b.CharCount
                            CharsAfter    = $a.CharCount
                            CharsDelta    = Format-Delta $charDiff
                            LastWriteTime = $a.LastWriteTime
                        })
                }
                elseif ($ShowUnchanged) {
                    [void]$results.Add([PSCustomObject]@{
                            Status        = "UNCHANGED"
                            Name          = $name
                            SizeBefore    = $b.SizeFormatted
                            SizeAfter     = $a.SizeFormatted
                            SizeDelta     = "0 B"
                            LinesBefore   = $b.LineCount
                            LinesAfter    = $a.LineCount
                            LinesDelta    = "0"
                            WordsBefore   = $b.WordCount
                            WordsAfter    = $a.WordCount
                            WordsDelta    = "0"
                            CharsBefore   = $b.CharCount
                            CharsAfter    = $a.CharCount
                            CharsDelta    = "0"
                            LastWriteTime = $a.LastWriteTime
                        })
                }
            }
        }
    }

    end {
        $statusOrder = @{ 'NEW' = 1; 'CHANGED' = 2; 'REMOVED' = 3; 'UNCHANGED' = 4 }
        $sorted = $results | Sort-Object { $statusOrder[$_.Status] }, Name

        $defaultDisplay = @('Status', 'Name', 'SizeDelta', 'LinesDelta', 'WordsDelta', 'CharsDelta')
        $defaultSet = New-Object System.Management.Automation.PSPropertySet('DefaultDisplayPropertySet', [string[]]$defaultDisplay)
        $memberInfo = [System.Management.Automation.PSMemberInfo[]]@($defaultSet)
        foreach ($obj in $sorted) {
            $obj | Add-Member -MemberType MemberSet -Name PSStandardMembers -Value $memberInfo -Force
        }

        $sorted | Write-Output

        $newCount = @($sorted | Where-Object { $_.Status -eq 'NEW' }).Count
        $changedCount = @($sorted | Where-Object { $_.Status -eq 'CHANGED' }).Count
        $removedCount = @($sorted | Where-Object { $_.Status -eq 'REMOVED' }).Count
        $unchangedCount = @($Before).Count - $changedCount - $removedCount

        $allChanged = $sorted | Where-Object { $_.Status -ne 'UNCHANGED' }
        $totalSizeDelta = 0
        $totalLineDelta = 0
        $totalWordDelta = 0
        $totalCharDelta = 0
        foreach ($item in $allChanged) {
            $b = if ($beforeMap.ContainsKey($item.Name)) {
                $beforeMap[$item.Name] 
            }
            else {
                $null 
            }
            $a = if ($afterMap.ContainsKey($item.Name)) {
                $afterMap[$item.Name]  
            }
            else {
                $null 
            }
            if ($a -and $b) {
                $totalSizeDelta += ($a.Size - $b.Size)
                $totalLineDelta += ($a.LineCount - $b.LineCount)
                $totalWordDelta += ($a.WordCount - $b.WordCount)
                $totalCharDelta += ($a.CharCount - $b.CharCount)
            }
            elseif ($a) {
                $totalSizeDelta += $a.Size; $totalLineDelta += $a.LineCount
                $totalWordDelta += $a.WordCount; $totalCharDelta += $a.CharCount
            }
            elseif ($b) {
                $totalSizeDelta -= $b.Size; $totalLineDelta -= $b.LineCount
                $totalWordDelta -= $b.WordCount; $totalCharDelta -= $b.CharCount
            }
        }

        Write-Log "Ending Compare-DowserReport"
        Write-Log " " -Severity Verbose
        Write-Log "--- Compare-DowserReport Summary ---" -Severity Verbose
        Write-Log ("  {0,-18}: {1}" -f "New Files", $newCount) -Severity Verbose
        Write-Log ("  {0,-18}: {1}" -f "Changed Files", $changedCount) -Severity Verbose
        Write-Log ("  {0,-18}: {1}" -f "Removed Files", $removedCount) -Severity Verbose
        Write-Log ("  {0,-18}: {1}" -f "Unchanged Files", $unchangedCount) -Severity Verbose
        Write-Log ("  {0,-18}: {1}" -f "Net Size", (Format-SizeDelta $totalSizeDelta)) -Severity Verbose
        Write-Log ("  {0,-18}: {1}" -f "Net Lines", (Format-Delta $totalLineDelta)) -Severity Verbose
        Write-Log ("  {0,-18}: {1}" -f "Net Words", (Format-Delta $totalWordDelta)) -Severity Verbose
        Write-Log ("  {0,-18}: {1}" -f "Net Characters", (Format-Delta $totalCharDelta)) -Severity Verbose
    }
}
