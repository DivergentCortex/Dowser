#Requires -Version 5.1

function Compare-DowserDirectory {
    <#
    .SYNOPSIS
        Compares two folders (or two files) by content and reports what is missing, extra, or changed.
    .NOTES
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
        -  Author:        Curtis Leggett                                  -
        =  Copyright:     2026 Divergent Cortex                           =
        -  Organization:  Divergent Cortex                                -
        =  Version:       See docs/CHANGELOG.md                           =
        =-=-                       =-=-=-=-=-=-=-=                     -=-=
        -  it is not water they seek, but the truth beneath the trees     -
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

        Alias: Compare-Directory (opt-in via Enable-DowserAliases)
        Original to Dowser (not ported). Read-only: never modifies either side.
    .DESCRIPTION
        Walks both trees, pairs files by relative path, and classifies each one:

          Same                   present on both sides with identical SHA256 content
          Changed                present on both sides, different size (Reason Size) or
                                 same size but different content (Reason Content)
          MissingFromDifference  present under -ReferencePath only
          ExtraInDifference      present under -DifferencePath only
          Unreadable             present on both sides but one could not be hashed

        Sizes are compared first; a file is hashed only when both sides have the same size,
        so large trees stay fast. It is git-agnostic: either side can be a git checkout, a
        plugin cache, a backup, or any folder.

        Folders named .git, node_modules, __pycache__, .venv, and venv are pruned from the walk
        on both sides by default (their contents are never enumerated); -NoDefaultExcludes
        turns that off. Symlinked directories are not followed.

        When both paths are files, the two files are compared directly.
    .PARAMETER ReferencePath
        The side treated as the source of truth (for example a git checkout). Position 0.
    .PARAMETER DifferencePath
        The side checked against it (for example an installed copy or cache). Position 1.
    .PARAMETER ExcludePattern
        Wildcards matched against each item's name and its relative path. Matching folders are
        pruned; matching files are skipped. Bare strings without wildcards match exactly.
    .PARAMETER NoDefaultExcludes
        Include .git, node_modules, __pycache__, .venv, and venv folders.
    .PARAMETER IncludeSame
        Also emit rows for identical files. By default only differences are emitted.
    .PARAMETER Summary
        Emit one summary object (counts plus InSync) instead of per-file rows.
    .EXAMPLE
        Compare-DowserDirectory ~/projects/cortex-plugins/cortex-toolbox ~/.claude/plugins/cache/divergentcortex/cortex-toolbox/unknown

        Lists every file that differs between the plugin source and the installed cache.
    .EXAMPLE
        Compare-DowserDirectory ~/src/app ~/backup/app -Summary

        One line: counts of Same/Changed/Missing/Extra and whether the two trees are in sync.
    .EXAMPLE
        Compare-DowserDirectory ./a ./b -ExcludePattern 'logs', '*.log'

        Ignores any logs folder and every .log file on both sides.
    .INPUTS
        None.
    .OUTPUTS
        PSCustomObject per file: Status, RelativePath, Reason, ReferenceSize, DifferenceSize,
        ReferenceLastWrite, DifferenceLastWrite. With -Summary, a single PSCustomObject:
        ReferencePath, DifferencePath, Same, Changed, MissingFromDifference, ExtraInDifference,
        Unreadable, InSync.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$ReferencePath,

        [Parameter(Mandatory = $true, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string]$DifferencePath,

        [string[]]$ExcludePattern = @(),

        [switch]$NoDefaultExcludes,

        [switch]$IncludeSame,

        [switch]$Summary
    )

    Write-Log "Starting Compare-DowserDirectory"

    $resolved = @{}
    foreach ($side in @('ReferencePath', 'DifferencePath')) {
        $value = (Get-Variable -Name $side -ValueOnly)
        try {
            $resolved[$side] = (Resolve-Path -LiteralPath $value -ErrorAction Stop).ProviderPath
        }
        catch {
            Write-Log "Compare-DowserDirectory: $side '$value' does not exist" -Severity Error
            throw "Compare-DowserDirectory: $side '$value' does not exist."
        }
    }
    $refRoot = $resolved['ReferencePath']
    $diffRoot = $resolved['DifferencePath']
    $refIsDir = Test-Path -LiteralPath $refRoot -PathType Container
    $diffIsDir = Test-Path -LiteralPath $diffRoot -PathType Container
    if ($refIsDir -ne $diffIsDir) {
        Write-Log "Compare-DowserDirectory: cannot compare a folder with a file ('$refRoot' vs '$diffRoot')" -Severity Error
        throw "Compare-DowserDirectory: both paths must be folders or both must be files ('$refRoot' vs '$diffRoot')."
    }

    # Bare strings match exactly; wildcards pass through unchanged.
    $patterns = @($ExcludePattern | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() })
    $excludeNames = if ($NoDefaultExcludes) { @() } else { @('.git', 'node_modules', '__pycache__', '.venv', 'venv') }

    if ($refIsDir) {
        $refScan = Get-DowserRelativeFileMap -Root $refRoot -ExcludeNames $excludeNames -ExcludePatterns $patterns
        $diffScan = Get-DowserRelativeFileMap -Root $diffRoot -ExcludeNames $excludeNames -ExcludePatterns $patterns
        $refMap = $refScan.Map
        $diffMap = $diffScan.Map
        if (($refScan.Errors + $diffScan.Errors) -gt 0) {
            Write-Log "Compare-DowserDirectory could not list $($refScan.Errors) reference and $($diffScan.Errors) difference folder(s); their contents are not compared" -Severity Warning
        }
    }
    else {
        # Two files: pair them under the reference file's name.
        $refItem = Get-Item -LiteralPath $refRoot -Force
        $diffItem = Get-Item -LiteralPath $diffRoot -Force
        $refMap = @{ $refItem.Name = $refItem }
        $diffMap = @{ $refItem.Name = $diffItem }
    }

    $counts = [ordered]@{ Same = 0; Changed = 0; MissingFromDifference = 0; ExtraInDifference = 0; Unreadable = 0 }
    $rows = New-Object System.Collections.Generic.List[object]

    function Add-CompareRow {
        param([string]$Status, [string]$RelativePath, [string]$Reason, $RefFile, $DiffFile)
        $counts[$Status]++
        if ($Summary -or ($Status -eq 'Same' -and -not $IncludeSame)) {
            return
        }
        $rows.Add([PSCustomObject][ordered]@{
                Status              = $Status
                RelativePath        = $RelativePath
                Reason              = $Reason
                ReferenceSize       = if ($RefFile) { $RefFile.Length } else { $null }
                DifferenceSize      = if ($DiffFile) { $DiffFile.Length } else { $null }
                ReferenceLastWrite  = if ($RefFile) { $RefFile.LastWriteTime } else { $null }
                DifferenceLastWrite = if ($DiffFile) { $DiffFile.LastWriteTime } else { $null }
            })
    }

    foreach ($rel in @($refMap.Keys)) {
        $refFile = $refMap[$rel]
        if (-not $diffMap.ContainsKey($rel)) {
            Add-CompareRow -Status 'MissingFromDifference' -RelativePath $rel -Reason '' -RefFile $refFile -DiffFile $null
            continue
        }
        $diffFile = $diffMap[$rel]
        if ($refFile.Length -ne $diffFile.Length) {
            Add-CompareRow -Status 'Changed' -RelativePath $rel -Reason 'Size' -RefFile $refFile -DiffFile $diffFile
            continue
        }
        try {
            $refHash = (Get-FileHash -LiteralPath $refFile.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
            $diffHash = (Get-FileHash -LiteralPath $diffFile.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
        }
        catch {
            Write-Log "Compare-DowserDirectory could not hash '$rel': $($_.Exception.Message)" -Severity Verbose
            Add-CompareRow -Status 'Unreadable' -RelativePath $rel -Reason $_.Exception.Message -RefFile $refFile -DiffFile $diffFile
            continue
        }
        if ($refHash -eq $diffHash) {
            Add-CompareRow -Status 'Same' -RelativePath $rel -Reason '' -RefFile $refFile -DiffFile $diffFile
        }
        else {
            Add-CompareRow -Status 'Changed' -RelativePath $rel -Reason 'Content' -RefFile $refFile -DiffFile $diffFile
        }
    }
    foreach ($rel in @($diffMap.Keys)) {
        if (-not $refMap.ContainsKey($rel)) {
            Add-CompareRow -Status 'ExtraInDifference' -RelativePath $rel -Reason '' -RefFile $null -DiffFile $diffMap[$rel]
        }
    }

    $inSync = ($counts.Changed + $counts.MissingFromDifference + $counts.ExtraInDifference + $counts.Unreadable) -eq 0
    Write-Log ("Compare-DowserDirectory: Same={0} Changed={1} MissingFromDifference={2} ExtraInDifference={3} Unreadable={4} InSync={5}" -f $counts.Same, $counts.Changed, $counts.MissingFromDifference, $counts.ExtraInDifference, $counts.Unreadable, $inSync)

    if ($Summary) {
        [PSCustomObject][ordered]@{
            ReferencePath         = $refRoot
            DifferencePath        = $diffRoot
            Same                  = $counts.Same
            Changed               = $counts.Changed
            MissingFromDifference = $counts.MissingFromDifference
            ExtraInDifference     = $counts.ExtraInDifference
            Unreadable            = $counts.Unreadable
            InSync                = $inSync
        }
    }
    else {
        $rows | Sort-Object Status, RelativePath
    }

    Write-Log "Ending Compare-DowserDirectory"
}
