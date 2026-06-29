#Requires -Version 5.1
function Test-DowserIntegrity {
    <#
    .SYNOPSIS
        Tests files and directories for corruption or structural integrity issues.

    .NOTES
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
        -  Author:        Curtis Leggett                                  -
        =  Copyright:     2026 Divergent Cortex                           =
        -  Organization:  Divergent Cortex                                -
        =  Version:       See docs/CHANGELOG.md                           =
        =-=-                       =-=-=-=-=-=-=-=                     -=-=
        -  it is not water they seek, but the truth beneath the trees     -
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

        Alias: dintegrity, dinteg
        Related: Test-DowserExtractable, Get-DowserReport, Expand-DowserExe

    .DESCRIPTION
        Layered integrity validation. Not one magic "is this corrupt" test.
    "Corrupt" depends on file type, so this cmdlet dispatches by category
    and reports what it checked and how confident it is.

    Layers:

    1. Zero-byte detection (all files). High confidence.

    2. Format-specific structural check dispatched by extension:
       - Archives (ZIP, 7z, RAR, CAB, MSU, TAR, GZ, WIM, ISO, MSI, etc.):
         7-Zip "7z t" test-extraction when 7-Zip is available. Falls back
         to native System.IO.Compression.ZipFile for ZIP family, expand.exe
         -D for CAB/MSU, and an OLE compound-file magic check for MSI.
       - PE files (EXE, DLL, SYS, OCX, DRV, SCR, etc.): MZ header,
         e_lfanew bounds, PE signature, COFF sanity, Optional Header magic,
         and section-table bounds. Catches truncation and header overwrites.
       - XML family (.xml, .xsd, .xsl, .xslt, .config, .manifest, .resx,
         .svg): XmlDocument parse. Catches malformed markup and truncation.
       - JSON (.json): ConvertFrom-Json parse.
       - PowerShell (.ps1, .psm1, .psd1): tokenize with AST parser.
       - Plain text (.txt, .ini, .inf, .log, .cmd, .bat, .vbs, .reg,
         .csv, .tsv, .yaml, .yml, .md): read + binary-sanity check (null
         bytes in a declared text file means truncation or encoding damage).
       - Generic: read-accessibility probe (first + last 512 bytes).

    3. Hygiene scan (always on). Flags files that a tool like SCCM or a
       publishing pipeline will trip over even if the content is fine:
       - Hidden or System attribute
       - Zone.Identifier alternate data stream (Mark-of-the-Web; Windows
         and SCCM frequently refuse to distribute or execute these)
       - Any other alternate data stream
       - Known residue names: Thumbs.db, desktop.ini, .DS_Store, ._*,
         ~$* (Office lock), *.tmp, *.bak, *.orig, *.swp, *.swo, *.lock,
         *.partial, *.crdownload, *.part
       If any hygiene finding is present on an otherwise-OK file, Status
       becomes "Residue".

    4. Hash computation (opt-in via -ComputeHash or implied by -BaselineCsv).
       SHA256.

    5. Baseline comparison (opt-in via -BaselineCsv). The CSV must have
       columns RelativePath, Length, SHA256. Files that differ or are
       missing from the baseline are flagged and flipped to "Suspicious".

    Status meaning:
       OK          Passed every check this cmdlet knows how to run.
       Corrupt     A structural validator failed.
       Error       A check could not run (unreadable, hash failure, etc.).
       Warning     Soft issue that does not prove damage (e.g., zero bytes).
       Suspicious  Baseline drift (size or hash mismatch).
       Residue     Otherwise-OK file carrying a hygiene flag (MOTW, Hidden,
                   residue filename). These are the SCCM-distribution killers.
       Unverified  Partial check only. Rare. Example: MSI detected by OLE
                   magic with no 7-Zip available for full structural test.

    Default output is a single summary object; full per-file array is
    stashed in $global:DowserIntegrityDetails for drill-down. Use
    -Detailed to stream per-file objects. Per-file stream defaults to
    problems only (Corrupt/Error/Warning/Suspicious/Residue). Use
    -IncludeClean to also emit OK and Unverified files.

.PARAMETER Path
    Path to a file or directory to test. Accepts pipeline input.

.PARAMETER Recurse
    When Path is a directory, recurse into subdirectories.

.PARAMETER Filter
    Wildcard filter for file names when scanning directories. Default: *

.PARAMETER SevenZipPath
    Path to 7z executable. On Windows, defaults to the standard 7-Zip install path.
    On Linux/macOS, defaults to '7z' (expected on PATH via package manager).

.PARAMETER SkipSevenZip
    Skip 7-Zip test extraction. Use only static/native validation.

.PARAMETER ComputeHash
    Compute SHA256 of each file and include it in the output. Automatically
    enabled when -BaselineCsv is specified.

.PARAMETER BaselineCsv
    Path to a baseline CSV with columns RelativePath, Length, SHA256.
    Each tested file is compared to its baseline entry. Hash mismatches,
    size mismatches, and missing-from-baseline entries become Issues and
    flip Status to Suspicious. Implies -ComputeHash.

.PARAMETER Detailed
    Stream the full per-file result objects through the pipeline (filtered
    by default to non-OK and non-Unverified files). Without this switch,
    the cmdlet emits a single summary object and stashes the full per-file
    array in $global:DowserIntegrityDetails for interactive drill-down.

.PARAMETER IncludeClean
    Include OK and Unverified files in the -Detailed stream. No effect on
    the default summary shape.

.EXAMPLE
    # Summary mode (default): one-line overview, details in the global.
    Test-DowserIntegrity -Path "D:\Downloads" -Recurse
    $global:DowserIntegrityDetails | Where-Object Status -eq 'Corrupt'

.EXAMPLE
    # Per-file stream mode for piping to CSV/export.
    Test-DowserIntegrity -Path "\\server\source\SPACE8" -Recurse -Detailed -BaselineCsv ".\SPACE8_baseline.csv" |
        Export-Csv .\SPACE8_validation.csv -NoTypeInformation

.EXAMPLE
    # Create a baseline manifest from a known-good source.
    # Baseline CSV must have columns: RelativePath, Length, SHA256.
    Test-DowserIntegrity -Path "\\goodsource\SPACE8" -Recurse -Detailed -ComputeHash -IncludeClean |
        Select-Object RelativePath, @{Name='Length'; Expression={$_.SizeBytes}}, SHA256 |
        Export-Csv .\SPACE8_baseline.csv -NoTypeInformation

.OUTPUTS
    Default: a single summary PSCustomObject (full per-file array stashed in
    $global:DowserIntegrityDetails). With -Detailed: per-file PSCustomObject results.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('FullName')]
        [string[]]$Path,

        [switch]$Recurse,

        [string]$Filter = '*',

        [string]$SevenZipPath = $(if ($IsWindows -eq $false) {
                '7z' 
            }
            else {
                Join-Path ${env:ProgramFiles} '7-Zip\7z.exe' 
            }),

        [switch]$SkipSevenZip,

        [switch]$ComputeHash,

        [string]$BaselineCsv,

        [switch]$Detailed,

        [switch]$IncludeClean
    )

    begin {
        $archiveExts = @(
            '.zip', '.7z', '.rar', '.cab', '.msu', '.tar', '.gz', '.bz2', '.xz',
            '.lzh', '.lha', '.arj', '.z', '.tgz', '.tbz2', '.txz',
            '.wim', '.iso', '.udf', '.msi', '.msp', '.nupkg', '.jar', '.war',
            '.ear', '.apk', '.ipa'
        )
        $peExts = @('.exe', '.dll', '.sys', '.ocx', '.drv', '.scr', '.cpl', '.ax', '.efi', '.mui')
        $zipNativeExts = @('.zip', '.nupkg', '.jar', '.war', '.ear', '.apk', '.ipa')
        $cabNativeExts = @('.cab', '.msu')
        $msiExts = @('.msi', '.msp')

        $xmlExts = @(
            '.xml', '.xsd', '.xsl', '.xslt', '.config', '.manifest',
            '.resx', '.svg', '.csproj', '.vbproj', '.vcxproj', '.props', '.targets'
        )
        $jsonExts = @('.json')
        $psExts = @('.ps1', '.psm1', '.psd1')
        $textExts = @(
            '.txt', '.ini', '.inf', '.log', '.cmd', '.bat', '.vbs',
            '.reg', '.csv', '.tsv', '.yaml', '.yml', '.md', '.markdown',
            '.cfg', '.conf', '.properties'
        )

        Write-Log "Starting Test-DowserIntegrity"
        $sevenZipAvailable = (-not $SkipSevenZip) -and (Test-Path -LiteralPath $SevenZipPath -PathType Leaf)
        if ($sevenZipAvailable) {
            Write-Log "Test-DowserIntegrity 7-Zip found at '$SevenZipPath'"
        }
        else {
            Write-Log "Test-DowserIntegrity 7-Zip not available; native-only validation for archives."
        }

        $expandExe = if ($IsWindows -eq $false) {
            $null 
        }
        else {
            Join-Path $env:SystemRoot 'System32\expand.exe' 
        }
        $hasExpand = $expandExe -and (Test-Path $expandExe)

        try {
            Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
            Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
            $zipNativeAvailable = $true
        }
        catch {
            Write-Log "System.IO.Compression unavailable: $($_.Exception.Message)" -Severity Verbose
            $zipNativeAvailable = $false
        }

        $baseline = $null
        if ($BaselineCsv) {
            if (-not (Test-Path -LiteralPath $BaselineCsv -PathType Leaf)) {
                throw "BaselineCsv not found: $BaselineCsv"
            }
            $baseline = @{}
            $rows = Import-Csv -LiteralPath $BaselineCsv
            $needed = @('RelativePath', 'Length', 'SHA256')
            $have = $rows | Select-Object -First 1 | ForEach-Object { $_.PSObject.Properties.Name }
            $missing = $needed | Where-Object { $_ -notin $have }
            if ($missing) {
                throw "BaselineCsv missing required columns: $($missing -join ', ')"
            }
            foreach ($row in $rows) {
                if ($row.RelativePath) {
                    $baseline[$row.RelativePath.ToUpperInvariant()] = $row
                }
            }
            Write-Log "Test-DowserIntegrity loaded baseline: $($baseline.Count) entries from '$BaselineCsv'"
            # baseline compare needs hashes
            $ComputeHash = $true
        }

        function New-IntegrityResult {
            param($File, [string]$Category, [string]$RelPath)
            [PSCustomObject]@{
                Path            = $File.FullName
                RelativePath    = $RelPath
                Name            = $File.Name
                Extension       = $File.Extension.ToLowerInvariant()
                SizeBytes       = $File.Length
                Size            = Format-DowserSize -DataValue $File.Length
                Category        = $Category
                Status          = 'Unknown'
                Method          = 'None'
                Confidence      = 'None'
                SHA256          = $null
                BaselineMatch   = $null
                Details         = ''
                Issues          = [System.Collections.Generic.List[string]]::new()
                SccmRisk        = $false
                SccmRiskReasons = @()
            }
        }

        function Test-ArchiveWith7Zip {
            param([string]$ArchivePath, [string]$SevenZip)
            $out = & $SevenZip t $ArchivePath '-y' 2>&1 | Out-String
            $code = $LASTEXITCODE
            [PSCustomObject]@{ ExitCode = $code; Output = $out }
        }

        function Test-ZipNative {
            param([string]$ZipPath)
            $zip = $null
            try {
                $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
                $entryCount = $zip.Entries.Count
                $buffer = New-Object byte[] 8192
                foreach ($entry in $zip.Entries) {
                    $stream = $null
                    try {
                        $stream = $entry.Open()
                        while (($stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                        }
                    }
                    finally {
                        if ($stream) {
                            $stream.Dispose()
                        }
                    }
                }
                [PSCustomObject]@{ Ok = $true; EntryCount = $entryCount; Error = '' }
            }
            catch {
                [PSCustomObject]@{ Ok = $false; EntryCount = 0; Error = $_.Exception.Message }
            }
            finally {
                if ($zip) {
                    $zip.Dispose()
                }
            }
        }

        function Test-CabNative {
            param([string]$CabPath, [string]$Expand)
            # -D lists contents only, no extraction
            $out = & $Expand '-D' $CabPath 2>&1 | Out-String
            $code = $LASTEXITCODE
            [PSCustomObject]@{ ExitCode = $code; Output = $out }
        }

        # ole magic check, fallback when no 7-zip
        function Test-MsiMagic {
            param([string]$MsiPath)
            $fs = $null
            try {
                $fs = [System.IO.File]::Open($MsiPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                $buf = New-Object byte[] 8
                $read = $fs.Read($buf, 0, 8)
                if ($read -lt 8) {
                    return [PSCustomObject]@{ Ok = $false; Error = 'File shorter than 8 bytes (cannot contain OLE header)' }
                }
                $expected = [byte[]](0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1)
                for ($i = 0; $i -lt 8; $i++) {
                    if ($buf[$i] -ne $expected[$i]) {
                        return [PSCustomObject]@{ Ok = $false; Error = 'Invalid OLE compound-file signature' }
                    }
                }
                [PSCustomObject]@{ Ok = $true; Error = '' }
            }
            catch {
                [PSCustomObject]@{ Ok = $false; Error = $_.Exception.Message }
            }
            finally {
                if ($fs) {
                    $fs.Dispose()
                }
            }
        }

        function Test-PeStructure {
            param([string]$PePath)

            $fs = $null
            $br = $null
            try {
                $fs = [System.IO.File]::Open($PePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                $br = New-Object System.IO.BinaryReader($fs)

                if ($fs.Length -lt 64) {
                    return [PSCustomObject]@{ Ok = $false; Issue = 'File smaller than DOS header (64 bytes)' }
                }

                $mz0 = $br.ReadByte()
                $mz1 = $br.ReadByte()
                if ($mz0 -ne 0x4D -or $mz1 -ne 0x5A) {
                    return [PSCustomObject]@{ Ok = $false; Issue = 'Missing MZ header' }
                }

                $fs.Position = 0x3C
                $peOffset = $br.ReadUInt32()
                if ($peOffset -le 0 -or ($peOffset + 24) -gt $fs.Length) {
                    return [PSCustomObject]@{ Ok = $false; Issue = "e_lfanew value $peOffset exceeds file bounds" }
                }

                $fs.Position = $peOffset
                $peSig = $br.ReadBytes(4)
                if ($peSig[0] -ne 0x50 -or $peSig[1] -ne 0x45 -or $peSig[2] -ne 0x00 -or $peSig[3] -ne 0x00) {
                    return [PSCustomObject]@{ Ok = $false; Issue = 'Invalid PE signature (expected PE\0\0)' }
                }

                # COFF header (20 bytes after PE sig)
                $null = $br.ReadUInt16()  # Machine
                $numSections = $br.ReadUInt16()
                $null = $br.ReadUInt32()  # TimeDateStamp
                $null = $br.ReadUInt32()  # PointerToSymbolTable
                $null = $br.ReadUInt32()  # NumberOfSymbols
                $sizeOptHdr = $br.ReadUInt16()
                $null = $br.ReadUInt16()  # Characteristics

                if ($numSections -eq 0) {
                    return [PSCustomObject]@{ Ok = $false; Issue = 'PE has zero sections' }
                }
                if ($numSections -gt 96) {
                    return [PSCustomObject]@{ Ok = $false; Issue = "PE section count $numSections exceeds 96" }
                }

                if ($sizeOptHdr -ge 2) {
                    $fs.Position = $peOffset + 24
                    $optMagic = $br.ReadUInt16()
                    if ($optMagic -ne 0x010B -and $optMagic -ne 0x020B -and $optMagic -ne 0x0107) {
                        return [PSCustomObject]@{ Ok = $false; Issue = ('Invalid Optional Header magic: 0x{0:X4}' -f $optMagic) }
                    }
                }

                $sectionTableOff = $peOffset + 24 + $sizeOptHdr
                $sectionTableEnd = $sectionTableOff + ($numSections * 40)
                if ($sectionTableEnd -gt $fs.Length) {
                    return [PSCustomObject]@{ Ok = $false; Issue = 'Section table extends past EOF' }
                }

                for ($i = 0; $i -lt $numSections; $i++) {
                    $fs.Position = $sectionTableOff + ($i * 40) + 16
                    $rawSize = $br.ReadUInt32()
                    $rawOff = $br.ReadUInt32()
                    if ($rawSize -gt 0) {
                        $end = [int64]$rawOff + [int64]$rawSize
                        if ($end -gt $fs.Length) {
                            return [PSCustomObject]@{
                                Ok    = $false
                                Issue = ('Section {0} extends past EOF (rawEnd={1} fileLen={2})' -f $i, $end, $fs.Length)
                            }
                        }
                    }
                }

                return [PSCustomObject]@{ Ok = $true; Issue = ''; SectionCount = $numSections }
            }
            catch {
                return [PSCustomObject]@{ Ok = $false; Issue = "PE parse error: $($_.Exception.Message)" }
            }
            finally {
                if ($br) {
                    $br.Dispose()
                }
                if ($fs) {
                    $fs.Dispose()
                }
            }
        }

        function Test-XmlParse {
            param([string]$XmlPath)
            try {
                $doc = New-Object System.Xml.XmlDocument
                $doc.XmlResolver = $null  # no DTD network fetches
                $doc.Load($XmlPath)
                [PSCustomObject]@{ Ok = $true; Error = '' }
            }
            catch {
                [PSCustomObject]@{ Ok = $false; Error = $_.Exception.Message }
            }
        }

        function Test-JsonParse {
            param([string]$JsonPath)
            try {
                $raw = Get-Content -LiteralPath $JsonPath -Raw -ErrorAction Stop
                if ([string]::IsNullOrWhiteSpace($raw)) {
                    return [PSCustomObject]@{ Ok = $false; Error = 'File is empty or whitespace only' }
                }
                $null = $raw | ConvertFrom-Json -ErrorAction Stop
                [PSCustomObject]@{ Ok = $true; Error = '' }
            }
            catch {
                [PSCustomObject]@{ Ok = $false; Error = $_.Exception.Message }
            }
        }

        function Test-PowerShellParse {
            param([string]$PsPath)
            try {
                $tokens = $null
                $errors = $null
                $null = [System.Management.Automation.Language.Parser]::ParseFile(
                    $PsPath,
                    [ref]$tokens,
                    [ref]$errors
                )
                if ($errors -and $errors.Count -gt 0) {
                    $first = $errors[0]
                    $msg = "{0} at line {1}" -f $first.Message, $first.Extent.StartLineNumber
                    return [PSCustomObject]@{ Ok = $false; Error = $msg; ErrorCount = $errors.Count }
                }
                [PSCustomObject]@{ Ok = $true; Error = ''; ErrorCount = 0 }
            }
            catch {
                [PSCustomObject]@{ Ok = $false; Error = $_.Exception.Message; ErrorCount = 1 }
            }
        }

        # nul bytes in a text file mean truncation or encoding damage
        function Test-TextSanity {
            param([string]$TextPath, [int64]$Length)
            $fs = $null
            try {
                $fs = [System.IO.File]::Open($TextPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                $toRead = [int][Math]::Min(4096, $Length)
                if ($toRead -le 0) {
                    return [PSCustomObject]@{ Ok = $true; Error = '' }
                }
                $buf = New-Object byte[] $toRead
                $read = $fs.Read($buf, 0, $toRead)

                # utf-16 has real nuls, skip it via bom
                $utf16 = $false
                if ($read -ge 2) {
                    if (($buf[0] -eq 0xFF -and $buf[1] -eq 0xFE) -or
                        ($buf[0] -eq 0xFE -and $buf[1] -eq 0xFF)) {
                        $utf16 = $true
                    }
                }

                if (-not $utf16) {
                    for ($i = 0; $i -lt $read; $i++) {
                        if ($buf[$i] -eq 0) {
                            return [PSCustomObject]@{ Ok = $false; Error = ('NUL byte at offset {0} in declared text file' -f $i) }
                        }
                    }
                }
                [PSCustomObject]@{ Ok = $true; Error = '' }
            }
            catch {
                [PSCustomObject]@{ Ok = $false; Error = $_.Exception.Message }
            }
            finally {
                if ($fs) {
                    $fs.Dispose()
                }
            }
        }

        function Test-ReadAccess {
            param([string]$FilePath)
            $fs = $null
            try {
                $fs = [System.IO.File]::Open($FilePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                $buf = New-Object byte[] 512
                $null = $fs.Read($buf, 0, 512)
                if ($fs.Length -gt 1024) {
                    $fs.Position = [Math]::Max(0, $fs.Length - 512)
                    $null = $fs.Read($buf, 0, 512)
                }
                [PSCustomObject]@{ Ok = $true; Error = '' }
            }
            catch {
                [PSCustomObject]@{ Ok = $false; Error = $_.Exception.Message }
            }
            finally {
                if ($fs) {
                    $fs.Dispose()
                }
            }
        }

        function Get-FirstErrorLine {
            param([string]$Text)
            if (-not $Text) {
                return ''
            }
            $lines = $Text -split "`r?`n" | Where-Object { $_ -match '\S' }
            $hit = $lines | Where-Object {
                $_ -match 'ERROR|WARNING|Data Error|CRC Failed|Headers Error|Unexpected end of archive|Sub items Errors'
            } | Select-Object -First 2
            if ($hit) {
                return ($hit -join ' | ')
            }
            return (($lines | Select-Object -Last 2) -join ' | ')
        }

        $residuePatterns = @(
            '^Thumbs\.db$',
            '^desktop\.ini$',
            '^\.DS_Store$',
            '^\._',            # macOS AppleDouble companions
            '^~\$',            # Office lock / temp
            '\.tmp$',
            '\.bak$',
            '\.orig$',
            '\.swp$',
            '\.swo$',
            '\.lock$',
            '\.partial$',
            '\.crdownload$',
            '\.part$'
        )

        function Get-HygieneFindings {
            param($File, [string[]]$Patterns)
            $findings = [System.Collections.Generic.List[string]]::new()

            if ($File.Attributes -band [System.IO.FileAttributes]::Hidden) {
                [void]$findings.Add('Hidden attribute set')
            }
            if ($File.Attributes -band [System.IO.FileAttributes]::System) {
                [void]$findings.Add('System attribute set')
            }

            foreach ($p in $Patterns) {
                if ($File.Name -match $p) {
                    [void]$findings.Add("Residue name pattern match: $($File.Name)")
                    break
                }
            }

            # zone.identifier ADS is the sccm killer
            try {
                $streams = Get-Item -LiteralPath $File.FullName -Stream '*' -ErrorAction Stop |
                    Where-Object { $_.Stream -ne ':$DATA' }
                foreach ($s in $streams) {
                    if ($s.Stream -eq 'Zone.Identifier') {
                        [void]$findings.Add('Zone.Identifier ADS present (Mark-of-the-Web; may block SCCM distribution and execution)')
                    }
                    else {
                        [void]$findings.Add("Alternate data stream present: $($s.Stream)")
                    }
                }
            }
            catch {
                # -Stream is windows ntfs only, nothing to find elsewhere
            }

            return @($findings)
        }

        $sccmRiskPatterns = @(
            'Zone.Identifier ADS present',
            'Hidden attribute set',
            'System attribute set',
            'Residue name pattern match',
            'Zero-byte file',
            '7z exit code',
            'expand.exe exit',
            'Hash mismatch vs baseline',
            'Size mismatch vs baseline',
            'Not present in baseline',
            'Invalid OLE compound-file signature',
            'Missing MZ header',
            'Invalid PE signature',
            'Section table extends past EOF',
            'extends past EOF',
            'Data Error',
            'CRC Failed',
            'Headers Error',
            'Unexpected end of archive',
            'NUL byte at offset'
        )

        $processedCount = 0
        $allResults = [System.Collections.Generic.List[object]]::new()

        $problemStatuses = @('Corrupt', 'Error', 'Warning', 'Suspicious', 'Residue')
    }

    process {
        foreach ($inputPath in $Path) {

            $files = @()
            $rootPath = $null

            if (Test-Path -LiteralPath $inputPath -PathType Container) {
                $rootPath = (Resolve-Path -LiteralPath $inputPath).Path
                $gciParams = @{
                    LiteralPath = $rootPath
                    Filter      = $Filter
                    File        = $true
                    ErrorAction = 'SilentlyContinue'
                }
                if ($Recurse) {
                    $gciParams.Recurse = $true
                }
                $files = @(Get-ChildItem @gciParams)
                if ($files.Count -eq 0) {
                    Write-Log "Test-DowserIntegrity no files matching '$Filter' found in '$inputPath'" -Severity Warning
                    continue
                }
                Write-Log "Test-DowserIntegrity found $($files.Count) file(s) in '$inputPath'"
            }
            elseif (Test-Path -LiteralPath $inputPath -PathType Leaf) {
                $files = @(Get-Item -LiteralPath $inputPath -ErrorAction SilentlyContinue)
                $rootPath = $files[0].DirectoryName
            }
            else {
                Write-Log "Test-DowserIntegrity path not found: '$inputPath'" -Severity Warning
                continue
            }

            foreach ($file in $files) {
                $processedCount++

                $relPath = $file.Name
                if ($rootPath -and $file.FullName.StartsWith($rootPath, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $relPath = $file.FullName.Substring($rootPath.Length).TrimStart('\', '/')
                    if (-not $relPath) {
                        $relPath = $file.Name
                    }
                }

                Write-Log "Testing ($processedCount): $relPath" -Severity Verbose

                $ext = $file.Extension.ToLowerInvariant()

                $category = 'Generic'
                if ($peExts -contains $ext) {
                    $category = 'PE' 
                }
                elseif ($archiveExts -contains $ext) {
                    $category = 'Archive' 
                }
                elseif ($xmlExts -contains $ext) {
                    $category = 'Xml' 
                }
                elseif ($jsonExts -contains $ext) {
                    $category = 'Json' 
                }
                elseif ($psExts -contains $ext) {
                    $category = 'PowerShell' 
                }
                elseif ($textExts -contains $ext) {
                    $category = 'Text' 
                }

                $result = New-IntegrityResult -File $file -Category $category -RelPath $relPath

                if ($file.Length -eq 0) {
                    $result.Status = 'Warning'
                    $result.Method = 'SizeCheck'
                    $result.Confidence = 'High'
                    $result.Details = 'File is empty (0 bytes)'
                    [void]$result.Issues.Add('Zero-byte file')
                }
                else {
                    switch ($category) {

                        'Archive' {
                            $handled = $false

                            if ($sevenZipAvailable) {
                                $r = Test-ArchiveWith7Zip -ArchivePath $file.FullName -SevenZip $SevenZipPath
                                if ($r.ExitCode -eq 0) {
                                    $result.Status = 'OK'
                                    $result.Method = '7-Zip'
                                    $result.Confidence = 'High'
                                    $result.Details = '7z t completed with exit code 0'
                                }
                                else {
                                    $result.Status = 'Corrupt'
                                    $result.Method = '7-Zip'
                                    $result.Confidence = 'High'
                                    $errTxt = Get-FirstErrorLine -Text $r.Output
                                    $result.Details = "7z t exit=$($r.ExitCode); $errTxt"
                                    [void]$result.Issues.Add("7z exit code $($r.ExitCode)")
                                    if ($errTxt) {
                                        [void]$result.Issues.Add($errTxt)
                                    }
                                }
                                $handled = $true
                            }
                            elseif ($zipNativeAvailable -and $zipNativeExts -contains $ext) {
                                $r = Test-ZipNative -ZipPath $file.FullName
                                if ($r.Ok) {
                                    $result.Status = 'OK'
                                    $result.Method = 'ZipFile'
                                    $result.Confidence = 'High'
                                    $result.Details = "ZipFile verified $($r.EntryCount) entries"
                                }
                                else {
                                    $result.Status = 'Corrupt'
                                    $result.Method = 'ZipFile'
                                    $result.Confidence = 'High'
                                    $result.Details = $r.Error
                                    [void]$result.Issues.Add($r.Error)
                                }
                                $handled = $true
                            }
                            elseif ($hasExpand -and $cabNativeExts -contains $ext) {
                                $r = Test-CabNative -CabPath $file.FullName -Expand $expandExe
                                if ($r.ExitCode -eq 0) {
                                    $result.Status = 'OK'
                                    $result.Method = 'expand.exe'
                                    $result.Confidence = 'Medium'
                                    $result.Details = 'expand.exe -D parsed cabinet successfully'
                                }
                                else {
                                    $result.Status = 'Corrupt'
                                    $result.Method = 'expand.exe'
                                    $result.Confidence = 'Medium'
                                    $errTxt = Get-FirstErrorLine -Text $r.Output
                                    $result.Details = "expand.exe exit=$($r.ExitCode); $errTxt"
                                    [void]$result.Issues.Add("expand.exe exit $($r.ExitCode)")
                                    if ($errTxt) {
                                        [void]$result.Issues.Add($errTxt)
                                    }
                                }
                                $handled = $true
                            }
                            elseif ($msiExts -contains $ext) {
                                $r = Test-MsiMagic -MsiPath $file.FullName
                                if ($r.Ok) {
                                    $result.Status = 'Unverified'
                                    $result.Method = 'MSI-Magic'
                                    $result.Confidence = 'Low'
                                    $result.Details = 'OLE compound-file signature valid. Install 7-Zip for full structural test.'
                                }
                                else {
                                    $result.Status = 'Corrupt'
                                    $result.Method = 'MSI-Magic'
                                    $result.Confidence = 'Medium'
                                    $result.Details = $r.Error
                                    [void]$result.Issues.Add($r.Error)
                                }
                                $handled = $true
                            }

                            if (-not $handled) {
                                $r = Test-ReadAccess -FilePath $file.FullName
                                if ($r.Ok) {
                                    $result.Status = 'Unverified'
                                    $result.Method = 'ReadCheck'
                                    $result.Confidence = 'Low'
                                    $result.Details = 'Archive read-accessible. Install 7-Zip for structural validation.'
                                }
                                else {
                                    $result.Status = 'Error'
                                    $result.Method = 'ReadCheck'
                                    $result.Confidence = 'High'
                                    $result.Details = $r.Error
                                    [void]$result.Issues.Add($r.Error)
                                }
                            }
                        }

                        'PE' {
                            $r = Test-PeStructure -PePath $file.FullName
                            if ($r.Ok) {
                                $result.Status = 'OK'
                                $result.Method = 'PE-Structural'
                                $result.Confidence = 'Medium'
                                $result.Details = "PE valid. $($r.SectionCount) section(s) bounded within file."
                            }
                            else {
                                $result.Status = 'Corrupt'
                                $result.Method = 'PE-Structural'
                                $result.Confidence = 'High'
                                $result.Details = $r.Issue
                                [void]$result.Issues.Add($r.Issue)
                            }
                        }

                        'Xml' {
                            $r = Test-XmlParse -XmlPath $file.FullName
                            if ($r.Ok) {
                                $result.Status = 'OK'
                                $result.Method = 'XmlDocument'
                                $result.Confidence = 'High'
                                $result.Details = 'XML parsed without errors.'
                            }
                            else {
                                $result.Status = 'Corrupt'
                                $result.Method = 'XmlDocument'
                                $result.Confidence = 'High'
                                $result.Details = $r.Error
                                [void]$result.Issues.Add("XML parse error: $($r.Error)")
                            }
                        }

                        'Json' {
                            $r = Test-JsonParse -JsonPath $file.FullName
                            if ($r.Ok) {
                                $result.Status = 'OK'
                                $result.Method = 'JsonParse'
                                $result.Confidence = 'High'
                                $result.Details = 'JSON parsed without errors.'
                            }
                            else {
                                $result.Status = 'Corrupt'
                                $result.Method = 'JsonParse'
                                $result.Confidence = 'High'
                                $result.Details = $r.Error
                                [void]$result.Issues.Add("JSON parse error: $($r.Error)")
                            }
                        }

                        'PowerShell' {
                            $r = Test-PowerShellParse -PsPath $file.FullName
                            if ($r.Ok) {
                                $result.Status = 'OK'
                                $result.Method = 'AstParser'
                                $result.Confidence = 'High'
                                $result.Details = 'AST parse returned 0 errors.'
                            }
                            else {
                                $result.Status = 'Corrupt'
                                $result.Method = 'AstParser'
                                $result.Confidence = 'High'
                                $result.Details = $r.Error
                                [void]$result.Issues.Add("PowerShell parse error: $($r.Error)")
                            }
                        }

                        'Text' {
                            $r = Test-TextSanity -TextPath $file.FullName -Length $file.Length
                            if ($r.Ok) {
                                $result.Status = 'OK'
                                $result.Method = 'TextSanity'
                                $result.Confidence = 'Medium'
                                $result.Details = 'Text file read-accessible with no binary contamination.'
                            }
                            else {
                                $result.Status = 'Corrupt'
                                $result.Method = 'TextSanity'
                                $result.Confidence = 'Medium'
                                $result.Details = $r.Error
                                [void]$result.Issues.Add($r.Error)
                            }
                        }

                        default {
                            # no validator for this type, readable is good enough, not suspicious
                            $r = Test-ReadAccess -FilePath $file.FullName
                            if ($r.Ok) {
                                $result.Status = 'OK'
                                $result.Method = 'ReadCheck'
                                $result.Confidence = 'Low'
                                $result.Details = 'Read-accessible. No format-specific validator for this extension.'
                            }
                            else {
                                $result.Status = 'Error'
                                $result.Method = 'ReadCheck'
                                $result.Confidence = 'High'
                                $result.Details = $r.Error
                                [void]$result.Issues.Add($r.Error)
                            }
                        }
                    }
                }

                $hygiene = Get-HygieneFindings -File $file -Patterns $residuePatterns
                foreach ($h in $hygiene) {
                    [void]$result.Issues.Add($h)
                }
                if ($hygiene.Count -gt 0 -and $result.Status -in @('OK', 'Unverified')) {
                    $result.Status = 'Residue'
                    if (-not $result.Details) {
                        $result.Details = "Hygiene: $($hygiene[0])"
                    }
                    else {
                        $result.Details = "$($result.Details) | Hygiene: $($hygiene[0])"
                    }
                }

                if ($ComputeHash) {
                    try {
                        $h = Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256 -ErrorAction Stop
                        $result.SHA256 = $h.Hash
                    }
                    catch {
                        Write-Log "Test-DowserIntegrity failed hashing '$($file.FullName)': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Error
                        [void]$result.Issues.Add("Hash failed: $($_.Exception.Message)")
                        if ($result.Status -in @('OK', 'Unverified')) {
                            $result.Status = 'Error'
                        }
                    }
                }

                if ($baseline) {
                    $key = $relPath.ToUpperInvariant()
                    if ($baseline.ContainsKey($key)) {
                        $base = $baseline[$key]
                        $sizeOk = $true
                        $hashOk = $true

                        if ([int64]$base.Length -ne $file.Length) {
                            $sizeOk = $false
                            [void]$result.Issues.Add("Size mismatch vs baseline (expected $($base.Length), got $($file.Length))")
                        }
                        if ($result.SHA256 -and $base.SHA256 -and
                            ($result.SHA256 -ne $base.SHA256)) {
                            $hashOk = $false
                            [void]$result.Issues.Add('Hash mismatch vs baseline')
                        }
                        $result.BaselineMatch = ($sizeOk -and $hashOk)
                        if (-not $result.BaselineMatch -and $result.Status -in @('OK', 'Unverified')) {
                            $result.Status = 'Suspicious'
                        }
                    }
                    else {
                        $result.BaselineMatch = $false
                        [void]$result.Issues.Add('Not present in baseline')
                        if ($result.Status -in @('OK', 'Unverified')) {
                            $result.Status = 'Suspicious'
                        }
                    }
                }

                $sccmRiskReasons = [System.Collections.Generic.List[string]]::new()
                if ($result.Status -in @('Corrupt', 'Error', 'Suspicious', 'Residue', 'Warning')) {
                    [void]$sccmRiskReasons.Add("Status: $($result.Status)")
                }
                foreach ($issue in $result.Issues) {
                    foreach ($p in $sccmRiskPatterns) {
                        if ($issue -match $p) {
                            [void]$sccmRiskReasons.Add($issue)
                            break
                        }
                    }
                }
                $result.SccmRisk = ($sccmRiskReasons.Count -gt 0)
                $result.SccmRiskReasons = @($sccmRiskReasons)

                [void]$allResults.Add($result)

                if ($Detailed) {
                    if ($IncludeClean -or ($result.Status -in $problemStatuses)) {
                        $result
                    }
                }
            }
        }
    }

    end {
        # publish detail to the global even in detailed mode
        $global:DowserIntegrityDetails = $allResults.ToArray()
        Write-Log "Test-DowserIntegrity processed $($allResults.Count) file(s)"

        if ($Detailed) {
            # per-file objects already streamed in process
            Write-Log "Ending Test-DowserIntegrity"
            return
        }

        $statusGroups = $allResults | Group-Object -Property Status -AsHashTable -AsString
        function Get-StatusCount {
            param([string]$Name)
            if ($statusGroups -and $statusGroups.ContainsKey($Name)) {
                return @($statusGroups[$Name]).Count
            }
            return 0
        }

        $problemList = $allResults | Where-Object { $_.Status -in $problemStatuses }
        $topProblems = $problemList | Select-Object -First 10 | ForEach-Object {
            '{0} [{1}]: {2}' -f $_.RelativePath, $_.Status, (($_.Issues | Select-Object -First 2) -join ' | ')
        }

        $sccmRiskList = $allResults | Where-Object { $_.SccmRisk }
        $topSccmRisks = $sccmRiskList | Select-Object -First 10 | ForEach-Object {
            '{0}: {1}' -f $_.RelativePath, ($_.SccmRiskReasons -join ' | ')
        }

        [PSCustomObject]@{
            TotalFiles    = $allResults.Count
            OK            = Get-StatusCount 'OK'
            Corrupt       = Get-StatusCount 'Corrupt'
            Error         = Get-StatusCount 'Error'
            Warning       = Get-StatusCount 'Warning'
            Suspicious    = Get-StatusCount 'Suspicious'
            Residue       = Get-StatusCount 'Residue'
            Unverified    = Get-StatusCount 'Unverified'
            ProblemCount  = $problemList.Count
            TopProblems   = $topProblems
            SccmRiskCount = $sccmRiskList.Count
            TopSccmRisks  = $topSccmRisks
            DetailsGlobal = '$global:DowserIntegrityDetails'
        }
        Write-Log "Ending Test-DowserIntegrity"
    }
}
