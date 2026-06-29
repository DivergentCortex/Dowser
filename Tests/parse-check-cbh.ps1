$targets = @(
    'Public/Get-DowserTemplate.ps1',
    'Public/Get-DowserTopology.ps1',
    'Public/Measure-DowserDirectory.ps1',
    'Public/Measure-DowserDiskUsage.ps1',
    'Public/New-DowserHiddenFolder.ps1',
    'Public/Test-DowserIntegrity.ps1'
)

$root = Split-Path -Parent $PSScriptRoot
$failed = $false

foreach ($rel in $targets) {
    $full = Join-Path $root $rel
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($full, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors -and $errors.Count -gt 0) {
        $failed = $true
        Write-Output "FAIL: $rel"
        foreach ($e in $errors) {
            Write-Output ("  L{0}: {1}" -f $e.Extent.StartLineNumber, $e.Message)
        }
    }
    else {
        Write-Output "OK: $rel parses clean"
    }
}

if ($failed) { exit 1 } else { exit 0 }
