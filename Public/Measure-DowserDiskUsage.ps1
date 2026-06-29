#Requires -Version 5.1
function Measure-DowserDiskUsage {
    <#
    .SYNOPSIS
        WinDirStat-style recursive disk-usage report for a directory tree.

    .NOTES
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
        -  Author:        Curtis Leggett                                  -
        =  Copyright:     2026 Divergent Cortex                           =
        -  Organization:  Divergent Cortex                                -
        =  Version:       See docs/CHANGELOG.md                           =
        =-=-                       =-=-=-=-=-=-=-=                     -=-=
        -  it is not water they seek, but the truth beneath the trees     -
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

        Alias: ddu
        Related: Measure-DowserDirectory (immediate-subdir sizing, no recursion, no ranking)

    .DESCRIPTION
        Scans a directory tree recursively and produces three ranked sections:
    biggest directories (by rollup size), biggest individual files, and
    file counts/sizes grouped by extension. Each section is emitted as
    structured PSCustomObjects to the pipeline and rendered as formatted
    console output via Write-Verbose.

    Unlike Measure-DowserDirectory (which measures immediate subdirs only
    with no ranking or extension breakdown), Measure-DowserDiskUsage
    performs a full recursive rollup and is the "what is eating my space"
    answer tool.

    Use -ExportHtml to write a self-contained HTML report with a treemap
    visualization (area proportional to disk usage) and the three ranked
    tables.

.PARAMETER Path
    Root directory to scan. Defaults to the current directory.
    Accepts pipeline input by value and by FullName property.

.PARAMETER TopN
    How many entries to show in the biggest-directories and biggest-files
    rankings. Defaults to 15.

.PARAMETER MinSize
    Minimum file size for the biggest-files ranking. Accepts human-readable
    strings like "10MB", "500KB". Parsed via ConvertTo-DowserBytes. Files
    below this threshold are excluded from the file ranking only; they still
    count toward directory rollups and the total.

.PARAMETER ExportHtml
    Path for the HTML report. When provided, writes a self-contained HTML
    file with inline CSS, a treemap, and the three ranked tables.

.PARAMETER ExcludePath
    One or more directory names (not full paths) to skip during the scan.
    Matched case-insensitively against each directory Name. For example:
    -ExcludePath '.git','node_modules'.

.EXAMPLE
    Measure-DowserDiskUsage

.EXAMPLE
    Measure-DowserDiskUsage -Path D:\Projects -TopN 20

.EXAMPLE
    Measure-DowserDiskUsage -Path C:\Repos -MinSize 100MB -ExportHtml C:\tmp\disk.html

.EXAMPLE
    Get-Item D:\Work | Measure-DowserDiskUsage -ExcludePath '.git','node_modules'

.OUTPUTS
    PSCustomObject ranked entries for biggest directories, biggest files, and per-extension totals.
#>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('FullName')]
        [string[]]$Path = '.',

        [int]$TopN = 15,

        [string]$MinSize,

        [string]$ExportHtml,

        [string[]]$ExcludePath
    )

    begin {
        # parse once so process can filter cheaply
        $minBytes = $null
        if ($PSBoundParameters.ContainsKey('MinSize') -and $MinSize) {
            $minBytes = ConvertTo-DowserBytes -SizeString $MinSize
        }
    }

    process {
        foreach ($rootPath in $Path) {
            $resolvedRoot = (Resolve-Path -LiteralPath $rootPath -ErrorAction SilentlyContinue).Path
            if (-not $resolvedRoot) {
                Write-Warning "Cannot resolve path: $rootPath"
                continue
            }
            if (-not (Test-Path -LiteralPath $resolvedRoot -PathType Container)) {
                Write-Warning "Not a directory: $resolvedRoot"
                continue
            }

            Write-Progress -Activity 'Measure-DowserDiskUsage' `
                -Status "Enumerating files under $resolvedRoot" -PercentComplete 0

            # ordinal on case-sensitive linux so Foo and foo stay distinct keys
            # IsWindows null on 5.1 means windows, use ignorecase there
            $dirComparer = if ($IsWindows -eq $false) {
                [System.StringComparer]::Ordinal
            }
            else {
                [System.StringComparer]::OrdinalIgnoreCase
            }
            $dirSizes = [System.Collections.Generic.Dictionary[string, long]]::new($dirComparer)
            $allFiles = [System.Collections.Generic.List[PSCustomObject]]::new()
            $totalBytes = [long]0
            $totalCount = [int]0

            $excludeSet = [System.Collections.Generic.HashSet[string]]::new(
                [System.StringComparer]::OrdinalIgnoreCase)
            if ($ExcludePath) {
                foreach ($ex in $ExcludePath) {
                    [void]$excludeSet.Add($ex) 
                }
            }

            $queue = [System.Collections.Generic.Queue[System.IO.DirectoryInfo]]::new()
            try {
                $queue.Enqueue([System.IO.DirectoryInfo]::new($resolvedRoot))
            }
            catch {
                Write-Warning "Cannot open root $resolvedRoot : $($_.Exception.Message)"
                continue
            }

            $fileCount = 0
            while ($queue.Count -gt 0) {
                $currentDir = $queue.Dequeue()

                if ($excludeSet.Count -gt 0 -and $excludeSet.Contains($currentDir.Name)) {
                    Write-Verbose "Skipping excluded directory: $($currentDir.FullName)"
                    continue
                }

                # skip symlinks and junctions to dodge loops, but never the root
                $isRoot = $dirComparer.Equals($currentDir.FullName, $resolvedRoot)
                if (-not $isRoot -and ($currentDir.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
                    Write-Verbose "Skipping reparse point: $($currentDir.FullName)"
                    continue
                }

                $dirFiles = $null
                try {
                    $dirFiles = $currentDir.EnumerateFiles()
                }
                catch {
                    Write-Verbose "Access denied (files) in $($currentDir.FullName): $($_.Exception.Message)"
                }

                if ($dirFiles) {
                    foreach ($fi in $dirFiles) {
                        if ($fi.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                            Write-Verbose "Skipping reparse point file: $($fi.FullName)"
                            continue
                        }

                        $sz = $fi.Length
                        $totalBytes += $sz
                        $totalCount++
                        $fileCount++

                        $ext = $fi.Extension
                        if ([string]::IsNullOrEmpty($ext)) {
                            $ext = '<none>'
                        }
                        else {
                            $ext = $ext.ToLower()
                        }

                        $allFiles.Add([PSCustomObject]@{
                                FullName  = $fi.FullName
                                SizeBytes = $sz
                                Extension = $ext
                            })

                        # roll size up every ancestor through resolvedRoot
                        $ancestor = $currentDir.FullName
                        while ($true) {
                            if (-not $dirSizes.ContainsKey($ancestor)) {
                                $dirSizes[$ancestor] = [long]0
                            }
                            $dirSizes[$ancestor] += $sz
                            if ($dirComparer.Equals($ancestor, $resolvedRoot)) {
                                break 
                            }
                            $parentPath = [System.IO.Path]::GetDirectoryName($ancestor)
                            if (-not $parentPath -or $parentPath.Length -lt $resolvedRoot.Length) {
                                break 
                            }
                            $ancestor = $parentPath
                        }

                        if ($fileCount % 500 -eq 0) {
                            Write-Progress -Activity 'Measure-DowserDiskUsage' `
                                -Status "Scanning... $fileCount files" -PercentComplete -1
                        }
                    }
                }

                $subDirs = $null
                try {
                    $subDirs = $currentDir.EnumerateDirectories()
                }
                catch {
                    Write-Verbose "Access denied (dirs) in $($currentDir.FullName): $($_.Exception.Message)"
                }

                if ($subDirs) {
                    foreach ($sd in $subDirs) {
                        $queue.Enqueue($sd)
                    }
                }
            }

            Write-Progress -Activity 'Measure-DowserDiskUsage' `
                -Status 'Building report sections' -PercentComplete 80

            $bigDirs = $dirSizes.GetEnumerator() |
                Where-Object { -not $dirComparer.Equals($_.Key, $resolvedRoot) } |
                Sort-Object Value -Descending |
                Select-Object -First $TopN

            $dirObjects = foreach ($entry in $bigDirs) {
                $relPath = $entry.Key.Substring($resolvedRoot.Length).TrimStart(
                    [System.IO.Path]::DirectorySeparatorChar, '/')
                if (-not $relPath) {
                    $relPath = '.' 
                }

                $pct = if ($totalBytes -gt 0) {
                    [Math]::Round($entry.Value / $totalBytes * 100, 1)
                }
                else {
                    0 
                }
                $barLen = [Math]::Round($pct / 2)
                $bar = ('#' * [int]$barLen).PadRight(50)

                [PSCustomObject][Ordered]@{
                    Section    = 'BiggestDirectories'
                    RelPath    = $relPath
                    SizeBytes  = $entry.Value
                    Size       = Format-DowserSize -DataValue $entry.Value
                    PctOfTotal = $pct
                    Bar        = $bar
                    RootPath   = $resolvedRoot
                }
            }

            $filteredFiles = if ($null -ne $minBytes) {
                $allFiles | Where-Object { $_.SizeBytes -ge $minBytes }
            }
            else {
                $allFiles
            }

            $bigFiles = $filteredFiles |
                Sort-Object SizeBytes -Descending |
                Select-Object -First $TopN

            $fileObjects = foreach ($f in $bigFiles) {
                $relPath = $f.FullName.Substring($resolvedRoot.Length).TrimStart(
                    [System.IO.Path]::DirectorySeparatorChar, '/')
                $pct = if ($totalBytes -gt 0) {
                    [Math]::Round($f.SizeBytes / $totalBytes * 100, 1)
                }
                else {
                    0 
                }
                $barLen = [Math]::Round($pct / 2)
                $bar = ('#' * [int]$barLen).PadRight(50)

                [PSCustomObject][Ordered]@{
                    Section    = 'BiggestFiles'
                    RelPath    = $relPath
                    SizeBytes  = $f.SizeBytes
                    Size       = Format-DowserSize -DataValue $f.SizeBytes
                    PctOfTotal = $pct
                    Bar        = $bar
                    RootPath   = $resolvedRoot
                }
            }

            $extMap = [System.Collections.Generic.Dictionary[string, long]]::new(
                [System.StringComparer]::OrdinalIgnoreCase)
            $extCount = [System.Collections.Generic.Dictionary[string, int]]::new(
                [System.StringComparer]::OrdinalIgnoreCase)

            foreach ($f in $allFiles) {
                $e = $f.Extension
                if ($extMap.ContainsKey($e)) {
                    $extMap[$e] += $f.SizeBytes
                    $extCount[$e]++
                }
                else {
                    $extMap[$e] = $f.SizeBytes
                    $extCount[$e] = 1
                }
            }

            $extObjects = $extMap.GetEnumerator() |
                Sort-Object Value -Descending |
                ForEach-Object {
                    $pct = if ($totalBytes -gt 0) {
                        [Math]::Round($_.Value / $totalBytes * 100, 1)
                    }
                    else {
                        0 
                    }
                    $barLen = [Math]::Round($pct / 2)
                    $bar = ('#' * [int]$barLen).PadRight(50)
                    [PSCustomObject][Ordered]@{
                        Section    = 'ByExtension'
                        Extension  = $_.Key
                        SizeBytes  = $_.Value
                        Size       = Format-DowserSize -DataValue $_.Value
                        FileCount  = $extCount[$_.Key]
                        PctOfTotal = $pct
                        Bar        = $bar
                        RootPath   = $resolvedRoot
                    }
                }

            Write-Progress -Activity 'Measure-DowserDiskUsage' -Completed

            $summaryObject = [PSCustomObject][Ordered]@{
                Section    = 'Summary'
                RootPath   = $resolvedRoot
                TotalSize  = Format-DowserSize -DataValue $totalBytes
                TotalBytes = $totalBytes
                TotalFiles = $totalCount
                ScannedAt  = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
            }

            $sep = '-' * 70
            Write-Verbose $sep
            Write-Verbose "Disk Usage Report: $resolvedRoot"
            Write-Verbose ("Total: {0}  ({1} files)" -f (Format-DowserSize -DataValue $totalBytes), $totalCount)
            Write-Verbose $sep

            Write-Verbose ''
            Write-Verbose "BIGGEST DIRECTORIES (top $TopN)"
            Write-Verbose $sep
            foreach ($d in $dirObjects) {
                Write-Verbose ("{0,-50} {1,10}  {2,5}%  [{3}]" -f $d.RelPath, $d.Size, $d.PctOfTotal, $d.Bar)
            }

            Write-Verbose ''
            Write-Verbose "BIGGEST FILES (top $TopN)"
            Write-Verbose $sep
            foreach ($f in $fileObjects) {
                Write-Verbose ("{0,-50} {1,10}  {2,5}%  [{3}]" -f $f.RelPath, $f.Size, $f.PctOfTotal, $f.Bar)
            }

            Write-Verbose ''
            Write-Verbose 'BY EXTENSION'
            Write-Verbose $sep
            foreach ($e in $extObjects) {
                Write-Verbose ("{0,-12} {1,10}  {2,5}%  {3,6} files  [{4}]" -f `
                        $e.Extension, $e.Size, $e.PctOfTotal, $e.FileCount, $e.Bar)
            }

            $summaryObject
            foreach ($o in $dirObjects) {
                $o 
            }
            foreach ($o in $fileObjects) {
                $o 
            }
            foreach ($o in $extObjects) {
                $o 
            }

            if ($ExportHtml) {
                try {
                    $htmlContent = _Build-DduHtml `
                        -SummaryObject $summaryObject `
                        -DirObjects $dirObjects `
                        -FileObjects $fileObjects `
                        -ExtObjects $extObjects `
                        -RootPath $resolvedRoot `
                        -TopN $TopN `
                        -TotalBytes $totalBytes `
                        -DirSizes $dirSizes `
                        -DirComparer $dirComparer
                    $htmlContent | Out-File -FilePath $ExportHtml -Encoding UTF8 -ErrorAction Stop
                    Write-Verbose "HTML report written to: $ExportHtml"
                }
                catch {
                    Write-Warning "Failed to write HTML to $ExportHtml : $($_.Exception.Message)"
                }
            }
        }
    }

    end {
    }
}

# lives here, only Measure-DowserDiskUsage calls it
function _Build-DduHtml {
    param(
        [PSCustomObject]$SummaryObject,
        $DirObjects,
        $FileObjects,
        $ExtObjects,
        [string]$RootPath,
        [int]$TopN,
        [long]$TotalBytes,
        [System.Collections.Generic.Dictionary[string, long]]$DirSizes,
        [System.StringComparer]$DirComparer
    )

    # palette must match Get-DowserReport.ps1
    $css = @'
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
    .bar-cell { font-family: monospace; font-size: 11px; color: #4ec9b0; }
    #ddu-treemap { width: 100%; height: 500px; position: relative; margin-top: 10px; background: #252526; border: 1px solid #3c3c3c; border-radius: 4px; overflow: hidden; }
    .ddu-block { position: absolute; box-sizing: border-box; border: 1px solid #1e1e1e; overflow: hidden; cursor: default; }
    .ddu-block:hover { opacity: 0.8; }
    .ddu-label { color: #fff; font-size: 11px; font-family: Segoe UI, sans-serif; padding: 2px 4px; overflow: hidden; white-space: nowrap; text-overflow: ellipsis; pointer-events: none; }
    #ddu-tip { position: fixed; background: #252526; border: 1px solid #3c3c3c; color: #d4d4d4; padding: 8px 12px; font-size: 12px; border-radius: 4px; pointer-events: none; display: none; z-index: 100; }
</style>
'@

    $summaryHtml = @"
<div class='summary'>
    <span><span class='label'>Root:</span>       <span class='value'>$([System.Security.SecurityElement]::Escape($SummaryObject.RootPath))</span></span>
    <span><span class='label'>Total Size:</span> <span class='value'>$([System.Security.SecurityElement]::Escape($SummaryObject.TotalSize))</span></span>
    <span><span class='label'>Files:</span>      <span class='value'>$($SummaryObject.TotalFiles)</span></span>
    <span><span class='label'>Scanned:</span>    <span class='value'>$([System.Security.SecurityElement]::Escape($SummaryObject.ScannedAt))</span></span>
</div>
"@

    # immediate children only so nested dirs are not double-counted
    $tmColors = @('#264f78', '#1e5f5f', '#3a3a6b', '#1e4d4d', '#2d4a2d', '#4d2d2d', '#4d3a1e', '#2d2d4d')
    $tmDenominator = if ($TotalBytes -gt 0) {
        [double]$TotalBytes 
    }
    else {
        1.0 
    }

    $immChildren = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($kv in $DirSizes.GetEnumerator()) {
        if ($DirComparer.Equals($kv.Key, $RootPath)) {
            continue 
        }
        $parentOfKey = [System.IO.Path]::GetDirectoryName($kv.Key)
        if ($DirComparer.Equals($parentOfKey, $RootPath)) {
            $childName = [System.IO.Path]::GetFileName($kv.Key)
            $immChildren.Add([PSCustomObject]@{ Name = $childName; SizeBytes = $kv.Value })
        }
    }
    $tmItems = @($immChildren | Sort-Object SizeBytes -Descending | Select-Object -First ([Math]::Min($TopN, 20)))

    # remainder is bytes outside any immediate subdir
    $allImmTotal = [long]0
    foreach ($ic in $immChildren) {
        $allImmTotal += $ic.SizeBytes 
    }
    $rootFileBytes = $TotalBytes - $allImmTotal

    $tmBlocksHtml = ''
    $leftPct = 0.0
    $colorIdx = 0
    foreach ($ti in $tmItems) {
        $widthPct = [Math]::Round($ti.SizeBytes / $tmDenominator * 100, 2)
        $label = [System.Security.SecurityElement]::Escape($ti.Name)
        $sizeStr = [System.Security.SecurityElement]::Escape((Format-DowserSize -DataValue $ti.SizeBytes))
        $pct = [Math]::Round($ti.SizeBytes / $tmDenominator * 100, 1)
        $color = $tmColors[$colorIdx % $tmColors.Count]
        $colorIdx++

        # data attrs hold escaped strings, js reads them via textContent
        $tmBlocksHtml += @"
<div class='ddu-block' style='left:${leftPct}%;top:0;width:${widthPct}%;height:100%;background:${color};'
     data-path='$label' data-size='$sizeStr' data-pct='$pct'
     onmouseenter='dduShowTip(event,this)' onmouseleave='dduHideTip()'>
  <div class='ddu-label'>$label</div>
  <div class='ddu-label' style='color:#4ec9b0'>$sizeStr ($pct%)</div>
</div>
"@
        $leftPct = [Math]::Round($leftPct + $widthPct, 2)
    }
    if ($rootFileBytes -gt 0) {
        $widthPct = [Math]::Round($rootFileBytes / $tmDenominator * 100, 2)
        $sizeStr = [System.Security.SecurityElement]::Escape((Format-DowserSize -DataValue $rootFileBytes))
        $pct = [Math]::Round($rootFileBytes / $tmDenominator * 100, 1)
        $tmBlocksHtml += @"
<div class='ddu-block ddu-remainder' style='left:${leftPct}%;top:0;width:${widthPct}%;height:100%;background:#3a3a3a;'
     data-path='(root files)' data-size='$sizeStr' data-pct='$pct'
     onmouseenter='dduShowTip(event,this)' onmouseleave='dduHideTip()'>
  <div class='ddu-label'>(root files)</div>
  <div class='ddu-label' style='color:#4ec9b0'>$sizeStr ($pct%)</div>
</div>
"@
    }

    # textContent only here, never innerHTML on user data
    $treemapHtml = @"
<div id='ddu-treemap'>
$tmBlocksHtml
</div>
<div id='ddu-tip'></div>
<script>
    (function() {
        var tip = document.getElementById('ddu-tip');
        function dduShowTip(e, el) {
            var line1 = document.createElement('strong');
            line1.textContent = el.getAttribute('data-path');
            var line2 = document.createElement('span');
            line2.textContent = el.getAttribute('data-size') + ' (' + el.getAttribute('data-pct') + '% of total)';
            while (tip.firstChild) { tip.removeChild(tip.firstChild); }
            tip.appendChild(line1);
            tip.appendChild(document.createElement('br'));
            tip.appendChild(line2);
            tip.style.display = 'block';
            tip.style.left = (e.clientX + 12) + 'px';
            tip.style.top  = (e.clientY + 12) + 'px';
        }
        function dduHideTip() { tip.style.display = 'none'; }
        window.dduShowTip = dduShowTip;
        window.dduHideTip = dduHideTip;
        document.getElementById('ddu-treemap').addEventListener('mousemove', function(e) {
            if (tip.style.display === 'block') {
                tip.style.left = (e.clientX + 12) + 'px';
                tip.style.top  = (e.clientY + 12) + 'px';
            }
        });
    })();
</script>
"@

    $dirTableHtml = _DduTableHtml -Rows $DirObjects  `
        -Cols @('RelPath', 'Size', 'PctOfTotal', 'Bar') `
        -Headers @('Directory', 'Size', '% of Total', 'Bar')
    $fileTableHtml = _DduTableHtml -Rows $FileObjects `
        -Cols @('RelPath', 'Size', 'PctOfTotal', 'Bar') `
        -Headers @('File', 'Size', '% of Total', 'Bar')
    $extTableHtml = _DduTableHtml -Rows $ExtObjects  `
        -Cols @('Extension', 'Size', 'FileCount', 'PctOfTotal', 'Bar') `
        -Headers @('Extension', 'Size', 'Files', '% of Total', 'Bar')

    return @"
<!DOCTYPE html>
<html>
<head>
    <meta charset='UTF-8'>
    <title>Measure-DowserDiskUsage - $([System.Security.SecurityElement]::Escape($SummaryObject.ScannedAt))</title>
    $css
</head>
<body>
    <h1>Dowser Disk Usage Report</h1>
    <p>Generated: $([System.Security.SecurityElement]::Escape($SummaryObject.ScannedAt))</p>
    <h2>Summary</h2>
    $summaryHtml
    <h2>Disk Usage Treemap (Top $TopN Directories)</h2>
    $treemapHtml
    <h2>Biggest Directories (Top $TopN)</h2>
    $dirTableHtml
    <h2>Biggest Files (Top $TopN)</h2>
    $fileTableHtml
    <h2>By Extension</h2>
    $extTableHtml
</body>
</html>
"@
}

function _DduTableHtml {
    param($Rows, [string[]]$Cols, [string[]]$Headers)
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append('<table><thead><tr>')
    for ($i = 0; $i -lt $Headers.Count; $i++) {
        [void]$sb.Append("<th>$($Headers[$i])</th>")
    }
    [void]$sb.Append('</tr></thead><tbody>')
    foreach ($row in $Rows) {
        [void]$sb.Append('<tr>')
        foreach ($col in $Cols) {
            $val = $row.$col
            if ($col -eq 'Bar') {
                [void]$sb.Append("<td class='bar-cell'>$val</td>")
            }
            else {
                $escaped = [System.Security.SecurityElement]::Escape("$val")
                [void]$sb.Append("<td>$escaped</td>")
            }
        }
        [void]$sb.Append('</tr>')
    }
    [void]$sb.Append('</tbody></table>')
    return $sb.ToString()
}
