#Requires -Version 5.1

function Remove-DowserTransferSource {
    <#
    .SYNOPSIS
        Deletes source files recorded as hash-verified in a Start-DowserTransfer manifest.

    .NOTES
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
        -  Author:        Curtis Leggett                                  -
        =  Copyright:     2026 Divergent Cortex                           =
        -  Organization:  Divergent Cortex                                -
        =  Version:       See docs/CHANGELOG.md                           =
        =-=-                       =-=-=-=-=-=-=-=                     -=-=
        -  it is not water they seek, but the truth beneath the trees     -
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
        Date Created:   2026-08-16

    .DESCRIPTION
        Reads a JSON manifest produced by Start-DowserTransfer and deletes ONLY the
        source files recorded as hash-matched/verified in that manifest. Never runs as
        a side effect of Start-DowserTransfer; a manifest path must always be given
        explicitly, there is no implicit "last run" lookup. Before deleting each source
        file, re-hashes both the source file and the destination file and compares each
        against its recorded hash in the manifest, as a defense against a source file
        that changed after transfer but before this deletion pass, and against a stale
        or tampered manifest. Any entry whose source or destination hash no longer
        matches is logged and skipped, never deleted. Supports -WhatIf.

    .PARAMETER ManifestPath
        Path to the JSON manifest written by Start-DowserTransfer.

    .EXAMPLE
        Remove-DowserTransferSource -ManifestPath 'E:\Backup\DowserTransfer-Manifest_20260816_120000.json'

        Re-verifies and deletes every source file the manifest recorded as verified.

    .EXAMPLE
        Remove-DowserTransferSource -ManifestPath $manifest.ManifestPath -WhatIf

        Reports which source files would be deleted without deleting anything.

    .OUTPUTS
        PSCustomObject with Success, ManifestPath, TotalEntries, DeletedCount,
        SkippedCount, ReVerifyFailedCount, DeleteFailedCount.

    .LINK
        Start-DowserTransfer
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ManifestPath
    )

    Write-Log "Starting Remove-DowserTransferSource"

    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        Write-Log "Remove-DowserTransferSource manifest not found: '$ManifestPath'" -Severity Error
        Write-Log "Ending Remove-DowserTransferSource"
        return [pscustomobject]@{
            Success             = $false
            ManifestPath        = $ManifestPath
            TotalEntries        = 0
            DeletedCount        = 0
            SkippedCount        = 0
            ReVerifyFailedCount = 0
            DeleteFailedCount   = 0
        }
    }

    try {
        $manifest = Get-Content -LiteralPath $ManifestPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Log "Remove-DowserTransferSource could not read manifest '$ManifestPath': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Error
        Write-Log "Ending Remove-DowserTransferSource"
        return [pscustomobject]@{
            Success             = $false
            ManifestPath        = $ManifestPath
            TotalEntries        = 0
            DeletedCount        = 0
            SkippedCount        = 0
            ReVerifyFailedCount = 0
            DeleteFailedCount   = 0
        }
    }

    $items = @($manifest.Items)
    if ($items.Count -eq 0) {
        Write-Log "Remove-DowserTransferSource manifest '$ManifestPath' has no items" -Severity Warning
        Write-Log "Ending Remove-DowserTransferSource"
        return [pscustomobject]@{
            Success             = $true
            ManifestPath        = $ManifestPath
            TotalEntries        = 0
            DeletedCount        = 0
            SkippedCount        = 0
            ReVerifyFailedCount = 0
            DeleteFailedCount   = 0
        }
    }

    $deletedCount = 0
    $skippedCount = 0
    $reVerifyFailedCount = 0
    $deleteFailedCount = 0

    foreach ($manifestItem in $items) {
        if (-not $manifestItem.Success) {
            $skippedCount++
            continue
        }

        $currentSourceHash = $null
        try {
            $currentSourceHash = (Get-FileHash -LiteralPath $manifestItem.SourcePath -Algorithm SHA256 -ErrorAction Stop).Hash
        }
        catch {
            $reVerifyFailedCount++
            Write-Log "Remove-DowserTransferSource could not re-hash source '$($manifestItem.SourcePath)', skipping delete: $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Warning
            continue
        }

        if ($currentSourceHash -ne $manifestItem.SourceHash) {
            $reVerifyFailedCount++
            Write-Log "Remove-DowserTransferSource source hash no longer matches manifest for '$($manifestItem.SourcePath)' (manifest=$($manifestItem.SourceHash) current=$currentSourceHash), skipping delete" -Severity Warning
            continue
        }

        $currentDestHash = $null
        try {
            $currentDestHash = (Get-FileHash -LiteralPath $manifestItem.DestinationPath -Algorithm SHA256 -ErrorAction Stop).Hash
        }
        catch {
            $reVerifyFailedCount++
            Write-Log "Remove-DowserTransferSource could not re-hash destination '$($manifestItem.DestinationPath)', skipping delete of '$($manifestItem.SourcePath)': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Warning
            continue
        }

        if ($currentDestHash -ne $manifestItem.DestHash) {
            $reVerifyFailedCount++
            Write-Log "Remove-DowserTransferSource destination hash no longer matches manifest for '$($manifestItem.DestinationPath)' (manifest=$($manifestItem.DestHash) current=$currentDestHash), skipping delete of '$($manifestItem.SourcePath)'" -Severity Warning
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($manifestItem.SourcePath, 'Delete verified transfer source file')) {
            continue
        }

        try {
            Remove-Item -LiteralPath $manifestItem.SourcePath -Force -ErrorAction Stop
            $deletedCount++
            Write-Log "Remove-DowserTransferSource deleted verified source '$($manifestItem.SourcePath)'" -Severity Info
        }
        catch {
            $deleteFailedCount++
            Write-Log "Remove-DowserTransferSource failed deleting '$($manifestItem.SourcePath)': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Error
        }
    }

    Write-Log "Remove-DowserTransferSource completed: $deletedCount deleted, $skippedCount skipped (unverified), $reVerifyFailedCount re-verify failure(s), $deleteFailedCount delete failure(s), of $($items.Count) manifest entries" -Severity Info
    Write-Log "Ending Remove-DowserTransferSource"

    [pscustomobject]@{
        Success             = ($deleteFailedCount -eq 0 -and $reVerifyFailedCount -eq 0)
        ManifestPath        = $ManifestPath
        TotalEntries        = $items.Count
        DeletedCount        = $deletedCount
        SkippedCount        = $skippedCount
        ReVerifyFailedCount = $reVerifyFailedCount
        DeleteFailedCount   = $deleteFailedCount
    }
}
