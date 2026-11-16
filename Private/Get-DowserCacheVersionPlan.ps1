function Get-DowserCacheVersionPlan {
    <#
    .SYNOPSIS
        Lists every version folder a VersionedCache rule covers and decides which are kept.
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
        Walks <Root>/<marketplace>/<plugin>/<version> for the rule and gives each version folder
        a row. A row is kept, with the reasons listed, when it is a symlink (never followed or
        removed), the installPath of an installed plugin, held by a running process (InUse),
        the version a running seat started on (InUseByStart, from Get-DowserSeatVersionHold),
        one of the newest KeepNewest versions by dotted number, or a version with no numeric
        order such as a commit hash. When the installed manifest or the process scan could not
        be read, every row is kept for that reason, because nothing can be proved unused. A
        marketplace or plugin folder that is itself a link keeps all its versions (ParentSymlink),
        because a delete there would reach outside the cache. A row with no keep reason has
        Decision Remove. Only folder names, link attributes and creation times are read here;
        sizes are measured later, for removal candidates only.

        A held string names a version when it contains <marketplace>/<plugin>/<version>/, so a
        process that reached the cache through a link to its root is still matched.
    .PARAMETER Rule
        A VersionedCache rule from Get-DowserRetentionRule.
    .PARAMETER InstalledPath
        installPath folders from the rule's installed manifest.
    .PARAMETER InstalledKnown
        False when the rule has a manifest that could not be read.
    .PARAMETER ProcessPath
        Paths held by running processes.
    .PARAMETER ProcessKnown
        False when the process scan failed.
    .PARAMETER Seat
        Running seats from Get-DowserActiveProcessPath, each with Name, StartKnown and StartUtc.
        Only the seats named in the rule's SeatProcessNames are used.
    .EXAMPLE
        Get-DowserCacheVersionPlan -Rule $rule -InstalledPath $paths -InstalledKnown $true -ProcessPath $held -ProcessKnown $true -Seat $seats

        Returns one row per version folder with its keep or remove decision.
    .OUTPUTS
        PSCustomObject with Success, Rows, Reason, ExceptionType, Message, ExitCode.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Rule,

        [string[]]$InstalledPath = @(),

        [bool]$InstalledKnown = $true,

        [string[]]$ProcessPath = @(),

        [bool]$ProcessKnown = $true,

        [object[]]$Seat = @()
    )

    $separator = [System.IO.Path]::DirectorySeparatorChar
    $ruleSeats = @($Seat | Where-Object { $Rule.SeatProcessNames -contains $_.Name })
    $testLink = {
        param([System.IO.FileSystemInfo]$info)
        return [bool]($info.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -or ($null -ne $info.LinkTarget)
    }

    $comparer = [System.StringComparer]::Ordinal
    if ($IsWindows -ne $false) {
        $comparer = [System.StringComparer]::OrdinalIgnoreCase
    }
    $installed = [System.Collections.Generic.HashSet[string]]::new($comparer)
    foreach ($path in $InstalledPath) {
        [void]$installed.Add($path.TrimEnd('/', '\'))
    }

    $rows = [System.Collections.Generic.List[object]]::new()
    $firstFailure = $null

    foreach ($marketplace in $Rule.Marketplaces) {
        foreach ($plugin in $Rule.Plugins) {
            $pluginPath = Join-Path (Join-Path $Rule.Root $marketplace) $plugin
            if (-not (Test-Path -LiteralPath $pluginPath -PathType Container)) {
                Write-Log "CacheVersionPlan found no folder '$pluginPath' for rule '$($Rule.Name)'" -Severity Verbose
                continue
            }

            $versionFolders = @()
            $parentIsLink = $false
            try {
                Write-Log "Attempting CacheVersionList on '$pluginPath'" -Severity Verbose
                $parentIsLink = (& $testLink ([System.IO.DirectoryInfo]::new($pluginPath))) -or (& $testLink ([System.IO.DirectoryInfo]::new((Join-Path $Rule.Root $marketplace))))
                $versionFolders = @([System.IO.DirectoryInfo]::new($pluginPath).GetDirectories())
            }
            catch {
                Write-Log "CacheVersionList failed on '$pluginPath': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Warning
                if ($null -eq $firstFailure) { $firstFailure = $_ }
                continue
            }

            # creation times only matter when a seat is running
            $births = @{}
            if ($ruleSeats.Count -gt 0) {
                $births = (Get-DowserFolderBirthTime -Path @($versionFolders | ForEach-Object { $_.FullName })).Births
            }

            $pluginRows = foreach ($folder in $versionFolders) {
                $isLink = [bool]($folder.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -or ($null -ne $folder.LinkTarget)
                [pscustomobject]@{
                    Rule           = $Rule.Name
                    Marketplace    = $marketplace
                    Plugin         = $plugin
                    Version        = $folder.Name
                    Path           = $folder.FullName
                    IsSymlink      = $isLink
                    LastWriteTime  = $folder.LastWriteTime
                    BirthUtc       = $births[$folder.FullName]
                    VersionKey     = Get-DowserVersionKey -Version $folder.Name
                    Decision       = 'Keep'
                    Reasons        = [System.Collections.Generic.List[string]]::new()
                    SizeBytes      = $null
                    Size           = $null
                    FileCount      = $null
                    NewestFileDate = $null
                    Removed        = $false
                    Failure        = $null
                }
            }

            $rankable = @($pluginRows | Where-Object { -not $_.IsSymlink -and $null -ne $_.VersionKey } | Sort-Object VersionKey -Descending)
            $newest = @($rankable | Select-Object -First $Rule.KeepNewest)
            $seatHold = Get-DowserSeatVersionHold -Version @($pluginRows | Where-Object { -not $_.IsSymlink }) -Seat $ruleSeats

            foreach ($row in $pluginRows) {
                if ($row.IsSymlink) { $row.Reasons.Add('Symlink') }
                elseif ($null -eq $row.VersionKey) { $row.Reasons.Add('UnrankableVersion') }
                elseif ($newest -contains $row) { $row.Reasons.Add('Newest') }
                if ($parentIsLink) { $row.Reasons.Add('ParentSymlink') }
                if ($installed.Contains($row.Path.TrimEnd('/', '\'))) { $row.Reasons.Add('Installed') }
                if ($ProcessKnown) {
                    $versionMark = $separator + $marketplace + $separator + $plugin + $separator + $row.Version + $separator
                    foreach ($held in $ProcessPath) {
                        if (($held + $separator).IndexOf($versionMark, [System.StringComparison]::Ordinal) -ge 0) {
                            $row.Reasons.Add('InUse')
                            break
                        }
                    }
                    if ($seatHold.AllHeld) { $row.Reasons.Add($seatHold.Reason) }
                    elseif ($seatHold.HeldVersions -contains $row.Version) { $row.Reasons.Add('InUseByStart') }
                }
                else {
                    $row.Reasons.Add('ProcessScanFailed')
                }
                if (-not $InstalledKnown) { $row.Reasons.Add('InstalledManifestUnreadable') }
                if ($row.Reasons.Count -eq 0) { $row.Decision = 'Remove' }
                $rows.Add($row)
            }
        }
    }

    $failed = $null -ne $firstFailure
    return [pscustomobject]@{
        Success       = -not $failed
        Rows          = $rows.ToArray()
        Reason        = if ($failed) { 'VersionListFailed' } else { $null }
        ExceptionType = if ($failed) { $firstFailure.Exception.GetType().Name } else { $null }
        Message       = if ($failed) { $firstFailure.Exception.Message } else { $null }
        ExitCode      = if ($failed) { Get-WindowsErrorCode -Exception $firstFailure } else { 0 }
    }
}
