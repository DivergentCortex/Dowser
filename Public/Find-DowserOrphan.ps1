function Find-DowserOrphan {
    <#
    .SYNOPSIS
        Scans a directory to identify files that are not referenced by any other text-based files in the directory.

    .DESCRIPTION
        This function performs the following steps:
        1. Recursively finds all files in the specified SearchPath.
        2. Identifies "Scanner" files (text-based files like .ps1, .xml, .json, etc.) that might contain references.
        3. Reads the content of all Scanner files and tokenizes them (splits by common delimiters).
        4. Builds a map of Token -> List of Files containing that token.
        5. Checks each file in the directory to see if its Name appears in the token map from *other* files.
        6. Reports files that have zero external references as potential orphans.

    .PARAMETER SearchPath
        The root directory to scan. Defaults to current location.

    .PARAMETER ExcludePaths
        Array of folder names or paths to exclude (e.g., .git, .vscode, node_modules).

    .PARAMETER TextExtensions
        Extensions to treat as "Scanner" files (files to read content from). 
        Defaults to common code and config formats.

    .EXAMPLE
        Find-OrphanFiles -SearchPath "C:\MyProject"
        Finds all orphan files in C:\MyProject.

    .EXAMPLE
        Find-OrphanFiles -SearchPath . -ExcludePaths "TestResults","Build"
        Scans current directory excluding specific folders.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$SearchPath = $PWD,

        [string[]]$ExcludePaths = @('.git', '.vscode', '.vs', 'bin', 'obj', 'node_modules'),

        [string[]]$TextExtensions = @(
            '.ps1', '.psm1', '.psd1', 
            '.bat', '.cmd', '.vbs', 
            '.xml', '.json', '.yaml', '.yml', '.config', 
            '.sql', '.md', '.txt', '.html', '.css', '.js', '.ts', '.php', '.py'
        )
    )

    $SearchPath = Resolve-Path $SearchPath
    Write-Verbose "Scanning for orphan files in: $SearchPath"

    Write-Verbose "Inventorying files..."
    $allFiles = Get-ChildItem -Path $SearchPath -Recurse -File | Where-Object {
        $path = $_.FullName
        $exclude = $false
        foreach ($ex in $ExcludePaths) {
            # match the segment on either path separator
            if (($path -like "*\$ex\*") -or ($path -like "*/$ex/*")) { $exclude = $true; break }
        }
        -not $exclude
    }

    $fileCount = $allFiles.Count
    Write-Verbose "Found $fileCount files."

    $tokenMap = @{}

    # keep dots hyphens underscores so filenames survive the split
    $splitPattern = "[^a-zA-Z0-9._-]"

    $scannerFiles = $allFiles | Where-Object { $TextExtensions -contains $_.Extension }
    $scannerCount = $scannerFiles.Count
    $processed = 0

    Write-Verbose "Analyzing content of $scannerCount text files..."

    foreach ($file in $scannerFiles) {
        $processed++
        if ($processed % 10 -eq 0) {
            Write-Progress -Activity "Indexing Content" -Status "$processed / $scannerCount" -PercentComplete (($processed / $scannerCount) * 100)
        }

        try {
            $content = Get-Content -Path $file.FullName -Raw -ErrorAction Stop
            if ([string]::IsNullOrWhiteSpace($content)) { continue }

            $tokens = $content -split $splitPattern | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

            foreach ($token in $tokens) {
                if (-not $tokenMap.ContainsKey($token)) {
                    $tokenMap[$token] = [System.Collections.Generic.HashSet[string]]::new()
                }
                [void]$tokenMap[$token].Add($file.FullName)
            }
        }
        catch {
            Write-Warning "Could not read $($file.FullName)"
        }
    }
    Write-Progress -Activity "Indexing Content" -Completed

    $orphans = @()
    $referenced = @()

    Write-Verbose "Checking for references..."

    foreach ($file in $allFiles) {
        $name = $file.Name
        $isReferenced = $false

        if ($tokenMap.ContainsKey($name)) {
            # a file referencing only itself is still an orphan
            $referencingFiles = $tokenMap[$name]
            foreach ($refFile in $referencingFiles) {
                if ($refFile -ne $file.FullName) {
                    $isReferenced = $true
                    break
                }
            }
        }

        if ($isReferenced) {
            $referenced += $file
        }
        else {
            $orphans += $file
        }
    }

    Write-Verbose "`nAnalysis Complete."
    Write-Verbose "Total Files: $fileCount"
    Write-Verbose "Referenced:  $($referenced.Count)"
    Write-Verbose "Orphans:     $($orphans.Count)"

    if ($orphans.Count -gt 0) {
        Write-Verbose "`nPotential Orphan Files (No external references found):"
        # preview to verbose so the return stays clean fileinfo objects
        $orphans | Select-Object FullName, Length, LastWriteTime | Format-Table -AutoSize | Out-String | Write-Verbose
    }

    return $orphans
}

