#Requires -Version 5.1

function Start-DowserTransfer {
    <#
    .SYNOPSIS
        Copies one or more files or directories to a destination with pre-flight
        free-space checks and per-file hash verification.

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
        Enumerates every file under each -Source path, sums the bytes to move, and
        confirms the -Destination volume has enough free space (with a safety headroom
        margin) before touching a single byte. Reparse points (symlinks and junctions)
        found while walking a directory source are skipped and logged, never followed.
        If two sources would resolve to the same destination path, the whole run is
        refused before any byte moves rather than letting two workers race the same
        file. Copies run across a shared runspace pool:
        each file is hashed (SHA256) at the source before copy, copied, hashed again at
        the destination, and marked verified only when the two hashes match. A hash
        mismatch is a hard per-file failure and that file is never reported as migrated.
        This function only copies and verifies; it never deletes source files. After a
        real run it writes a JSON manifest of every file's verification result. That
        manifest is the required input to Remove-DowserTransferSource for a later,
        separate deletion pass. Supports -WhatIf: a dry run reports the real file count
        and byte total it would move and touches nothing.

    .PARAMETER Source
        One or more source file or directory paths. Accepts pipeline input. Directory
        sources are copied recursively, preserving their internal structure under a
        folder named after the source directory inside -Destination.

    .PARAMETER Destination
        Destination directory. Created on demand as files are copied into it.

    .PARAMETER HeadroomPercent
        Safety margin required on top of the total bytes to copy, as a percentage of
        that total. The destination volume must have at least
        TotalBytes * (1 + HeadroomPercent/100) free before any copy starts. Default 10.

    .PARAMETER ManifestPath
        Path to the JSON verification manifest written after a real run. Defaults to a
        timestamped file inside -Destination. Not written on a -WhatIf dry run.

    .PARAMETER ThreadCount
        Maximum concurrent copy-and-verify workers. Defaults to the lower of 8 or the
        processor count.

    .EXAMPLE
        Start-DowserTransfer -Source 'D:\Projects\App' -Destination 'E:\Backup'

        Copies D:\Projects\App into E:\Backup\App, verifying every file by hash, then
        writes a manifest under E:\Backup.

    .EXAMPLE
        Get-ChildItem 'D:\Exports' -File | Start-DowserTransfer -Destination 'E:\Archive' -WhatIf

        Pipes individual files in and reports what would be copied and how many bytes,
        without copying anything.

    .OUTPUTS
        PSCustomObject with Success, DryRun, FileCount, TotalBytes, BytesCopied,
        FailureCount, ManifestPath, and Destination.

    .LINK
        Remove-DowserTransferSource
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('FullName')]
        [string[]]$Source,

        [Parameter(Mandatory = $true)]
        [string]$Destination,

        [ValidateRange(0, 1000)]
        [int]$HeadroomPercent = 10,

        [string]$ManifestPath,

        [ValidateRange(1, 64)]
        [int]$ThreadCount = [Math]::Min(8, [Environment]::ProcessorCount)
    )

    begin {
        Write-Log "Starting Start-DowserTransfer"
        $sourceInputs = [System.Collections.Generic.List[string]]::new()
    }

    process {
        foreach ($sourcePath in $Source) {
            $sourceInputs.Add($sourcePath)
        }
    }

    end {
        $emptyResult = {
            param($DestinationValue, $FileCountValue, $TotalBytesValue)
            [pscustomobject]@{
                Success      = $false
                DryRun       = $false
                FileCount    = $FileCountValue
                TotalBytes   = $TotalBytesValue
                BytesCopied  = 0
                FailureCount = 0
                ManifestPath = $null
                Destination  = $DestinationValue
            }
        }

        if (Test-Path -LiteralPath $Destination -PathType Leaf) {
            Write-Log "Start-DowserTransfer destination '$Destination' exists and is not a directory" -Severity Error
            Write-Log "Ending Start-DowserTransfer"
            return (& $emptyResult $Destination 0 0)
        }

        try {
            $resolvedDestination = [System.IO.Path]::GetFullPath($Destination)
        }
        catch {
            Write-Log "Start-DowserTransfer could not resolve destination path '$Destination': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Error
            Write-Log "Ending Start-DowserTransfer"
            return (& $emptyResult $Destination 0 0)
        }

        $transferItems = [System.Collections.Generic.List[object]]::new()
        foreach ($rawSource in $sourceInputs) {
            try {
                $sourceItem = Get-Item -LiteralPath $rawSource -ErrorAction Stop
            }
            catch {
                Write-Log "Start-DowserTransfer could not resolve source '$rawSource': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Warning
                continue
            }

            if (-not $sourceItem.PSIsContainer) {
                $transferItems.Add([pscustomobject]@{
                    SourcePath      = $sourceItem.FullName
                    DestinationPath = Join-Path $resolvedDestination $sourceItem.Name
                    Size            = $sourceItem.Length
                })
                continue
            }

            try {
                $walkStack = [System.Collections.Generic.Stack[string]]::new()
                $walkStack.Push($sourceItem.FullName)
                while ($walkStack.Count -gt 0) {
                    $currentDir = $walkStack.Pop()
                    $dirEntries = Get-ChildItem -LiteralPath $currentDir -ErrorAction Stop
                    foreach ($entry in $dirEntries) {
                        if (($entry.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                            Write-Log "Start-DowserTransfer skipped reparse point (symlink/junction) '$($entry.FullName)'" -Severity Warning
                            continue
                        }
                        if ($entry.PSIsContainer) {
                            $walkStack.Push($entry.FullName)
                        }
                        else {
                            $relative = $entry.FullName.Substring($sourceItem.FullName.Length).TrimStart('\', '/')
                            $transferItems.Add([pscustomobject]@{
                                SourcePath      = $entry.FullName
                                DestinationPath = Join-Path $resolvedDestination (Join-Path $sourceItem.Name $relative)
                                Size            = $entry.Length
                            })
                        }
                    }
                }
            }
            catch {
                Write-Log "Start-DowserTransfer could not enumerate '$($sourceItem.FullName)': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Warning
                continue
            }
        }

        if ($transferItems.Count -eq 0) {
            Write-Log 'Start-DowserTransfer found no files to transfer among the given sources' -Severity Warning
            Write-Log "Ending Start-DowserTransfer"
            return (& $emptyResult $resolvedDestination 0 0)
        }

        $totalBytes = ($transferItems | Measure-Object -Property Size -Sum).Sum
        if ($null -eq $totalBytes) {
            $totalBytes = 0
        }

        $duplicateDestinations = @($transferItems | Group-Object -Property DestinationPath | Where-Object { $_.Count -gt 1 })
        if ($duplicateDestinations.Count -gt 0) {
            $collisionList = ($duplicateDestinations | ForEach-Object { $_.Name }) -join '; '
            Write-Log "Start-DowserTransfer found $($duplicateDestinations.Count) colliding destination path(s) among the given sources, refusing to proceed: $collisionList" -Severity Error
            Write-Log "Ending Start-DowserTransfer"
            return (& $emptyResult $resolvedDestination $transferItems.Count $totalBytes)
        }

        try {
            if ($IsWindows -eq $false) {
                $matchedDrive = [System.IO.DriveInfo]::GetDrives() | Where-Object {
                    $mountRoot = $_.RootDirectory.FullName.TrimEnd('/')
                    $resolvedDestination -eq $mountRoot -or $resolvedDestination.StartsWith("$mountRoot/", [System.StringComparison]::Ordinal)
                } | Sort-Object { $_.RootDirectory.FullName.Length } -Descending | Select-Object -First 1
                $availableBytes = $matchedDrive.AvailableFreeSpace
            }
            else {
                $driveRoot = [System.IO.Path]::GetPathRoot($resolvedDestination)
                $availableBytes = [System.IO.DriveInfo]::new($driveRoot).AvailableFreeSpace
            }
        }
        catch {
            Write-Log "Start-DowserTransfer could not resolve free space for '$resolvedDestination': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Error
            Write-Log "Ending Start-DowserTransfer"
            return (& $emptyResult $resolvedDestination $transferItems.Count $totalBytes)
        }

        $requiredBytes = [long][Math]::Ceiling($totalBytes * (1 + ($HeadroomPercent / 100)))
        if ($availableBytes -lt $requiredBytes) {
            Write-Log "Start-DowserTransfer insufficient free space on '$resolvedDestination': need $requiredBytes bytes ($totalBytes bytes to copy plus $HeadroomPercent% headroom), only $availableBytes bytes available" -Severity Error
            Write-Log "Ending Start-DowserTransfer"
            return (& $emptyResult $resolvedDestination $transferItems.Count $totalBytes)
        }

        if (-not $PSCmdlet.ShouldProcess($resolvedDestination, "Transfer $($transferItems.Count) file(s) totaling $totalBytes bytes")) {
            Write-Log "Start-DowserTransfer dry-run: would transfer $($transferItems.Count) file(s), $totalBytes bytes, to '$resolvedDestination' ($availableBytes bytes available, $requiredBytes bytes required with headroom)" -Severity Info
            Write-Log "Ending Start-DowserTransfer"
            return [pscustomobject]@{
                Success      = $true
                DryRun       = $true
                FileCount    = $transferItems.Count
                TotalBytes   = $totalBytes
                BytesCopied  = 0
                FailureCount = 0
                ManifestPath = $null
                Destination  = $resolvedDestination
            }
        }

        $poolOutcome = Invoke-DowserTransferPool -TransferItem $transferItems.ToArray() -ThreadCount $ThreadCount -TotalBytes $totalBytes

        if (-not $poolOutcome.PoolStarted) {
            Write-Log "Start-DowserTransfer transfer pool failed to start, no files were transferred" -Severity Error
            Write-Log "Ending Start-DowserTransfer"
            return (& $emptyResult $resolvedDestination $transferItems.Count $totalBytes)
        }

        $results = @($poolOutcome.Results)

        $successCount = @($results | Where-Object { $_.Success }).Count
        $failureCount = $results.Count - $successCount
        $bytesCopied = ($results | Where-Object { $_.Success } | Measure-Object -Property BytesCopied -Sum).Sum
        if ($null -eq $bytesCopied) {
            $bytesCopied = 0
        }

        if ($PSBoundParameters.ContainsKey('ManifestPath') -and -not [string]::IsNullOrWhiteSpace($ManifestPath)) {
            $resolvedManifestPath = $ManifestPath
        }
        else {
            $resolvedManifestPath = Join-Path $resolvedDestination "DowserTransfer-Manifest_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
        }

        $manifest = [pscustomobject]@{
            GeneratedAt     = (Get-Date).ToString('o')
            Destination     = $resolvedDestination
            HeadroomPercent = $HeadroomPercent
            TotalFiles      = $results.Count
            TotalBytes      = $totalBytes
            SuccessCount    = $successCount
            FailureCount    = $failureCount
            Items           = $results
        }

        try {
            $manifestDir = Split-Path -Path $resolvedManifestPath -Parent
            if ($manifestDir -and -not (Test-Path -LiteralPath $manifestDir)) {
                New-Item -ItemType Directory -Path $manifestDir -Force -ErrorAction Stop | Out-Null
            }
        }
        catch {
            Write-Log "Start-DowserTransfer could not create manifest directory for '$resolvedManifestPath': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Error
        }

        try {
            $manifestJson = $manifest | ConvertTo-Json -Depth 6
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText($resolvedManifestPath, $manifestJson, $utf8NoBom)
            Write-Log "Start-DowserTransfer wrote manifest to '$resolvedManifestPath'" -Severity Info
        }
        catch {
            Write-Log "Start-DowserTransfer could not write manifest '$resolvedManifestPath': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Error
            $resolvedManifestPath = $null
        }

        Write-Log "Start-DowserTransfer completed: $successCount / $($results.Count) file(s) verified, $bytesCopied / $totalBytes bytes copied, $failureCount failure(s)" -Severity Info
        Write-Log "Ending Start-DowserTransfer"

        [pscustomobject]@{
            Success      = ($failureCount -eq 0 -and $results.Count -eq $transferItems.Count)
            DryRun       = $false
            FileCount    = $results.Count
            TotalBytes   = $totalBytes
            BytesCopied  = $bytesCopied
            FailureCount = $failureCount
            ManifestPath = $resolvedManifestPath
            Destination  = $resolvedDestination
        }
    }
}
