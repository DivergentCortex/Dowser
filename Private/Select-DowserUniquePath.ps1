#Requires -Version 5.1

function Select-DowserUniquePath {
    <#
    .SYNOPSIS
        Deduplicates a path list in O(n), preserving first-seen order.
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
        Replaces `Select-Object -Unique` on large path arrays. Select-Object -Unique
        compares each incoming item against every item it has already kept, which is
        O(n^2). On a 40,000-path list that measures at ~37 seconds; a quarter-million
        paths puts it past 20 minutes with no progress output, which reads as a hang.
        A HashSet gives the same result in a single pass.

        Comparison is Ordinal, matching Select-Object -Unique, which is case-sensitive
        on PowerShell 7. This is required on Linux, where File.txt and file.txt are two
        different files and both must survive deduplication.

        Duplicates only arise when a symlink cycle causes the same directory to be
        enumerated twice, so the kept ordering follows first appearance.
    .PARAMETER Path
        The path strings to deduplicate. Null and empty entries are skipped.
    .EXAMPLE
        $allFiles = Select-DowserUniquePath -Path $gatherResults

        Deduplicates the file list returned from a parallel gather pass.
    .INPUTS
        System.String[]
    .OUTPUTS
        System.String[]
        The unique paths, in first-seen order.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [AllowNull()]
        [string[]]$Path
    )

    $unique = [System.Collections.Generic.List[string]]::new()

    if (-not $Path) {
        return $unique.ToArray()
    }

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

    foreach ($p in $Path) {
        if ([string]::IsNullOrEmpty($p)) {
            continue
        }
        if ($seen.Add($p)) {
            $unique.Add($p)
        }
    }

    return $unique.ToArray()
}
