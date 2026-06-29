$files = @(
    "$PSScriptRoot/Public/Find-DowserRecentLog.ps1",
    "$PSScriptRoot/Public/Find-DowserScript.ps1",
    "$PSScriptRoot/Public/Find-DowserString.ps1",
    "$PSScriptRoot/Public/Invoke-DowserFastSearch.ps1",
    "$PSScriptRoot/Public/Invoke-DowserNumericSort.ps1"
)
foreach ($f in $files) {
    $leaf = Split-Path $f -Leaf
    $errs = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$null, [ref]$errs)
    $bytes = [System.IO.File]::ReadAllBytes($f)
    $nonAscii = @($bytes | Where-Object { $_ -gt 127 }).Count
    if ($errs.Count -eq 0 -and $nonAscii -eq 0) {
        Write-Output "$leaf : PARSE CLEAN, ASCII OK"
    }
    else {
        $msg = "$leaf :"
        if ($errs.Count -gt 0) { $msg += " PARSE ERRORS [" + (($errs | ForEach-Object { $_.Message }) -join '; ') + "]" }
        if ($nonAscii -gt 0) { $msg += " NON-ASCII bytes: $nonAscii" }
        Write-Output $msg
    }
}
