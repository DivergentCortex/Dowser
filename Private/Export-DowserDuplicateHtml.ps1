function Export-DowserDuplicateHtml {
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$ReportPath,

        [Parameter(Mandatory)]
        [System.Collections.IEnumerable]$DuplicateSets,

        [Parameter(Mandatory)]
        [int]$FilesScanned,

        [Parameter(Mandatory)]
        [string]$RootPath,

        [Parameter(Mandatory)]
        [string]$HashAlgorithm,

        [int]$TopN = 50
    )

    $contentSets = @($DuplicateSets | Where-Object Mode -eq 'Content')
    $duplicateFiles = 0
    $reclaimableBytes = [long]0
    foreach ($set in $contentSets) {
        $duplicateFiles += $set.Count - 1
        $reclaimableBytes += [long]$set.Files[0].Size * ($set.Count - 1)
    }

    $escape = {
        param([object]$Value)
        [System.Security.SecurityElement]::Escape([string]$Value)
    }

    $setHtml = [System.Text.StringBuilder]::new()
    $rank = 0
    foreach ($set in ($contentSets | Sort-Object { [long]$_.Files[0].Size * ($_.Count - 1) } -Descending | Select-Object -First $TopN)) {
        $rank++
        $size = [long]$set.Files[0].Size
        $reclaimable = $size * ($set.Count - 1)
        $name = & $escape $set.MatchKey
        $hash = & $escape $set.Hash
        $setSize = & $escape (Format-DowserSize -DataValue $size)
        $reclaimableSize = & $escape (Format-DowserSize -DataValue $reclaimable)

        [void]$setHtml.AppendLine("<details class='duplicate-set'>")
        [void]$setHtml.AppendLine("  <summary><span class='rank'>$rank</span><span class='name'>$name</span><span class='metric'>$($set.Count) copies, $reclaimableSize reclaimable</span></summary>")
        [void]$setHtml.AppendLine("  <div class='set-meta'>Hash algorithm: $HashAlgorithm<br>Hash: <code>$hash</code><br>Each file: $setSize</div>")
        [void]$setHtml.AppendLine("  <ol class='file-list'>")
        foreach ($file in $set.Files) {
            $filePath = & $escape $file.Path
            [void]$setHtml.AppendLine("    <li><code>$filePath</code></li>")
        }
        [void]$setHtml.AppendLine('  </ol>')
        [void]$setHtml.AppendLine('</details>')
    }

    $emptyHtml = if ($contentSets.Count -eq 0) {
        "<p class='empty'>No byte-identical duplicate files were found.</p>"
    }
    else {
        $setHtml.ToString()
    }
    $root = & $escape $RootPath
    $totalReclaimable = & $escape (Format-DowserSize -DataValue $reclaimableBytes)
    $summaryRows = @(
        "<dl class='summary-grid'>"
        "  <div><dt>Files scanned</dt><dd>$FilesScanned</dd></div>"
        "  <div><dt>Exact duplicate sets</dt><dd>$($contentSets.Count)</dd></div>"
        "  <div><dt>Redundant files</dt><dd>$duplicateFiles</dd></div>"
        "  <div><dt>Potential space recovery</dt><dd>$totalReclaimable</dd></div>"
        '</dl>'
    ) -join [Environment]::NewLine

    $html = @"
<!DOCTYPE html>
<html lang='en'>
<head>
<meta charset='utf-8'>
<title>Dowser duplicate report</title>
<style>
* { box-sizing: border-box; }
body {
    margin: 0;
    background: oklch(0.18 0.01 216);
    color: oklch(0.95 0.01 216);
    font-family: "IBM Plex Sans", "Segoe UI", sans-serif;
    font-size: clamp(1rem, 0.95rem + 0.3vw, 1.2rem);
    line-height: 1.5;
}
main { width: 90%; max-width: 90rem; margin: clamp(2rem, 6vw, 6rem) auto; }
header { display: grid; grid-template-columns: minmax(0, 3fr) minmax(13rem, 1fr); gap: 2rem; align-items: end; border-bottom: 1px solid oklch(0.32 0.014 216); padding-bottom: 2rem; }
h1 { max-width: 12ch; margin: 0; font-size: clamp(2.5rem, 1rem + 6vw, 6rem); line-height: 0.96; letter-spacing: -0.04em; }
header p { margin: 0; color: oklch(0.70 0.02 216); overflow-wrap: anywhere; }
h2 { margin: clamp(3rem, 6vw, 5rem) 0 1rem; font-size: clamp(1.6rem, 1.2rem + 2vw, 3rem); line-height: 1; letter-spacing: -0.025em; }
.summary-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(12rem, 1fr)); margin: 0; border-top: 1px solid oklch(0.32 0.014 216); border-left: 1px solid oklch(0.32 0.014 216); }
.summary-grid div { min-height: 8rem; padding: 1.2rem; border-right: 1px solid oklch(0.32 0.014 216); border-bottom: 1px solid oklch(0.32 0.014 216); background: oklch(0.24 0.014 216); }
dt { color: oklch(0.70 0.02 216); font-size: clamp(0.78rem, 0.74rem + 0.2vw, 0.9rem); letter-spacing: 0.08em; text-transform: uppercase; }
dd { margin: 0.5rem 0 0; color: oklch(0.66 0.17 216); font-size: clamp(1.4rem, 1rem + 1.3vw, 2.2rem); font-weight: 650; }
.duplicate-set { border-top: 1px solid oklch(0.32 0.014 216); }
.duplicate-set:last-child { border-bottom: 1px solid oklch(0.32 0.014 216); }
summary { display: grid; grid-template-columns: 3rem minmax(0, 1fr) auto; gap: 1rem; align-items: baseline; cursor: pointer; padding: 1rem 0; list-style: none; }
summary::-webkit-details-marker { display: none; }
summary:hover .name { color: oklch(0.66 0.17 216); }
summary:focus-visible { outline: 2px solid oklch(0.66 0.17 216); outline-offset: 4px; }
.rank { color: oklch(0.70 0.02 216); font-variant-numeric: tabular-nums; }
.name { min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; transition: color 180ms cubic-bezier(0.22, 1, 0.36, 1); }
.metric { color: oklch(0.76 0.15 72); font-variant-numeric: tabular-nums; white-space: nowrap; }
.set-meta, .file-list { margin: 0 0 1.25rem 4rem; color: oklch(0.70 0.02 216); }
code { color: oklch(0.95 0.01 216); font-family: "IBM Plex Mono", Consolas, monospace; font-size: clamp(0.78rem, 0.74rem + 0.2vw, 0.92rem); overflow-wrap: anywhere; }
.file-list { padding-left: 1.5rem; }
.file-list li { margin: 0.5rem 0; padding-left: 0.25rem; }
.empty { color: oklch(0.70 0.02 216); }
@media (max-width: 44rem) {
    header { grid-template-columns: 1fr; }
    summary { grid-template-columns: 2rem minmax(0, 1fr); }
    .metric { grid-column: 2; }
    .set-meta, .file-list { margin-left: 2rem; }
}
@media (prefers-reduced-motion: reduce) { * { transition: none !important; } }
</style>
</head>
<body>
<main>
<header>
    <h1>Exact duplicate files</h1>
    <p>Root: <code>$root</code><br>Proof: full-file $HashAlgorithm hash</p>
</header>
<section aria-labelledby='summary'>
    <h2 id='summary'>Cleanup evidence</h2>
    $summaryRows
</section>
<section aria-labelledby='sets'>
    <h2 id='sets'>Duplicate sets</h2>
    $emptyHtml
</section>
</main>
</body>
</html>
"@

    $parentPath = [System.IO.Path]::GetDirectoryName($ReportPath)
    try {
        if ($parentPath -and -not (Test-Path -LiteralPath $parentPath)) {
            New-Item -ItemType Directory -Path $parentPath -Force -ErrorAction Stop | Out-Null
        }
        [System.IO.File]::WriteAllText(
            $ReportPath,
            $html,
            [System.Text.UTF8Encoding]::new($false))
        Write-Log "Find-DowserDuplicate wrote HTML report to '$ReportPath'." -Severity Info
        return [PSCustomObject]@{ Success = $true; ReportPath = $ReportPath; Error = $null }
    }
    catch {
        Write-Log "Find-DowserDuplicate failed writing HTML report '$ReportPath': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Error
        return [PSCustomObject]@{ Success = $false; ReportPath = $ReportPath; Error = $_.Exception.Message }
    }
}
