#Requires -Version 5.1
<#
.SYNOPSIS
    Tests whether an executable can be simply extracted using archive tools.

.DESCRIPTION
    Analyzes EXE files to determine if they contain extractable archive payloads
    (ZIP, 7z, CAB, RAR, NSIS, Inno Setup, etc.) or if they are compiled binaries
    that require decompilation tools (ILSpy, dnSpy, Exe2Aut, Ghidra).

    Uses a multi-tier static analysis approach (no execution of target binaries):
    1. PE header parsing: MZ/PE validation, .NET COM_DESCRIPTOR, section names
    2. Overlay analysis: archive signatures at overlay offset + near-EOF markers
    3. Version string fingerprinting for known frameworks
    4. Binary string scanning for compiler/tool signatures
    5. Native Windows detection (ZipFile, expand.exe) - no third-party tools
    6. 7-Zip listing as the definitive oracle when available

    Classification categories:
    - Extractable:        Real file payloads (use 7z x or Expand-DowserExe)
    - ResourcesOnly:      PE resources only (icons, manifests) - not useful payloads
    - DecompileRequired:  Compiled code needing reverse-engineering tools
    - UPX_Packed:         UPX compressed - unpack with upx -d first, then re-analyze
    - NotPE:              Not a valid PE file

    Reference: docs/exe-static-classification-reference.md

.PARAMETER Path
    Path to an EXE file or directory containing EXE files. Accepts pipeline input.

.PARAMETER Recurse
    When Path is a directory, search subdirectories for EXE files.

.PARAMETER Filter
    Wildcard filter for file names when scanning directories. Default: *.exe

.PARAMETER SevenZipPath
    Path to 7z executable. On Windows, defaults to the standard 7-Zip install path.
    On Linux/macOS, defaults to '7z' (expected on PATH via package manager).

.PARAMETER SkipSevenZip
    Skip the 7-Zip oracle entirely. Use only static analysis.

.EXAMPLE
    Test-DowserExtractable -Path "C:\Tools\Setup.exe"

.EXAMPLE
    Get-ChildItem D:\Installers -Filter *.exe | Test-DowserExtractable

.EXAMPLE
    Test-DowserExtractable -Path "D:\Downloads" -Recurse

.EXAMPLE
    Test-DowserExtractable -Path "\\server\share\installer.exe"

.NOTES
    Author: Curtis Leggett / Divergent Cortex
    Alias: dtest, dtestexe
    Related: Expand-DowserExe, Get-DowserProperty
    Source: docs/exe-static-classification-reference.md (verityvulture + verityfactseeker merge)
#>

# EXE extractability probe. multi-tier static analysis + optional 7-Zip oracle.
# does NOT execute the target binary. all analysis is read-only.

function Test-DowserExtractable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('FullName')]
        [string[]]$Path,

        [switch]$Recurse,

        [string]$Filter = '*.exe',

        [string]$SevenZipPath = $(if ($IsWindows -eq $false) { '7z' } else { Join-Path ${env:ProgramFiles} '7-Zip\7z.exe' }),

        [switch]$SkipSevenZip
    )

    begin {
        $has7Zip = $false
        if (-not $SkipSevenZip) {
            $has7Zip = Test-Path -LiteralPath $SevenZipPath
            if ($has7Zip) { Write-Verbose "7-Zip found at: $SevenZipPath" }
            else { Write-Verbose "7-Zip not found at $SevenZipPath - static analysis only" }
        }

        # expand.exe for native CAB detection
        $expandExe = if ($IsWindows -eq $false) { $null } else { Join-Path $env:SystemRoot 'System32\expand.exe' }
        $hasExpand = $expandExe -and (Test-Path $expandExe)

        # -------------------------------------------------------------------
        # 7z Type= values that indicate extractable content
        # Source: 7-Zip CPP/7zip/Archive/ handlers
        # -------------------------------------------------------------------
        $extractable7zTypes = @(
            'Nsis', '7z', 'Zip', 'Cab', 'Rar', 'Rar5', 'Inno',
            'Msi', 'Compound', 'Wim', 'Iso', 'Tar', 'GZip', 'BZip2',
            'Xz', 'Lzma', 'Lzma86', 'Lzh', 'Arj', 'Cpio', 'Rpm',
            'Deb', 'Dmg', 'Hfs', 'Udf', 'Fat', 'Ntfs', 'Ext',
            'SquashFs', 'Ppmd'
        )
        $nonExtractable7zTypes = @('PE', 'Elf', 'Macho', 'Swf', 'Te', 'Efi')

        # -------------------------------------------------------------------
        # PE section patterns (internal structure, not useful payloads)
        # -------------------------------------------------------------------
        $peSectionPatterns = @(
            '^\.text$', '^\.rdata$', '^\.data$', '^\.reloc$', '^\.pdata$',
            '^\.edata$', '^\.idata$', '^\.tls$', '^\.debug$', '^\.bss$',
            '^\.CRT$', '^\.rsrc', '^\.ndata$', '^\.gfids$', '^\.textbss$',
            '^\[0\]$', '^\[1\]$'
        )

        # -------------------------------------------------------------------
        # Framework-specific PE section names [HIGH_CONFIDENCE]
        # -------------------------------------------------------------------
        $sectionFingerprints = @{
            '.ndata'        = @{ Framework = 'NSIS';       Extractable = $true;  Note = 'NSIS installer - unique section' }
            '.wixburn'      = @{ Framework = 'WiX_Burn';   Extractable = $true;  Note = 'WiX Burn bootstrapper' }
            '.go.buildinfo' = @{ Framework = 'Go_Native';  Extractable = $false; Note = 'Go binary (1.13+)' }
        }
        # UPX and Delphi checked separately (need multiple section matches)

        # -------------------------------------------------------------------
        # VersionInfo fingerprints (expanded from research)
        # -------------------------------------------------------------------
        $frameworkFingerprints = [ordered]@{
            'NSIS'             = @{ Patterns = @('Nullsoft', 'NSIS', 'Nullsoft Install System'); Extractable = $true }
            'InnoSetup'        = @{ Patterns = @('Inno Setup', 'Jordan Russell', 'Martijn Laan'); Extractable = $true }
            'InstallShield'    = @{ Patterns = @('InstallShield', 'Flexera', 'Acresso', 'Macrovision'); Extractable = $true }
            'WiX'              = @{ Patterns = @('Windows Installer XML', 'WiX Toolset'); Extractable = $true }
            'WinRAR_SFX'       = @{ Patterns = @('WinRAR SFX', 'WinRAR self-extracting', 'WinRAR archiver', 'Alexander Roshal', 'win.rar GmbH'); Extractable = $true }
            '7Zip_SFX'         = @{ Patterns = @('7-Zip Self-extracting', '7-Zip SFX', '7z SFX', 'Igor Pavlov'); Extractable = $true }
            'WinZip_SFX'       = @{ Patterns = @('WinZip Self-Extractor', 'WZSFX', 'WZSEPE32'); Extractable = $true }
            'IExpress'         = @{ Patterns = @('IExpress'); Extractable = $true }
            'AdvancedInstaller'= @{ Patterns = @('Caphyon', 'Advanced Installer'); Extractable = $true }
            'InstallAware'     = @{ Patterns = @('InstallAware Software'); Extractable = $false }
            'ps2exe'           = @{ Patterns = @('PS2EXE', 'ps2exe', 'Ingo Karstein', 'Markus Scholtes', 'MScholtes'); Extractable = $false }
            'AutoIt'           = @{ Patterns = @('AutoIt v3 Script', 'AutoIt Team', 'Jonathan Bennett', 'Aut2Exe'); Extractable = $false }
            'AutoHotkey'       = @{ Patterns = @('AutoHotkey Foundation', 'AutoHotkey.com'); Extractable = $false }
            'PyInstaller'      = @{ Patterns = @('PyInstaller'); Extractable = $false }
            'Electron'         = @{ Patterns = @('Electron'); Extractable = $false }
            'Squirrel'         = @{ Patterns = @('Squirrel.Windows'); Extractable = $false }
        }

        # Also check OriginalFilename separately (very reliable for some tools)
        $originalFilenameFingerprints = @{
            'AutoHotkey.exe'   = @{ Framework = 'AutoHotkey';  Extractable = $false }
            'AutoHotkey64.exe' = @{ Framework = 'AutoHotkey';  Extractable = $false }
            'AutoIt3.exe'      = @{ Framework = 'AutoIt';      Extractable = $false }
            '7z.sfx'           = @{ Framework = '7Zip_SFX';    Extractable = $true }
            '7zS.sfx'          = @{ Framework = '7Zip_SFX';    Extractable = $true }
            '7zSD.sfx'         = @{ Framework = '7Zip_SFX';    Extractable = $true }
            'Default.SFX'      = @{ Framework = 'WinRAR_SFX';  Extractable = $true }
            'WinCon.SFX'       = @{ Framework = 'WinRAR_SFX';  Extractable = $true }
            'WZSFX.EXE'        = @{ Framework = 'WinZip_SFX';  Extractable = $true }
            'WZSEPE32.EXE'     = @{ Framework = 'WinZip_SFX';  Extractable = $true }
        }

        # -------------------------------------------------------------------
        # Overlay archive signatures (checked at overlay start)
        # -------------------------------------------------------------------
        # Format: Name, Bytes, MinLength
        $overlaySignatures = @(
            @{ Name = '7z';   Bytes = [byte[]]@(0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C); Extractable = $true }
            @{ Name = 'RAR4'; Bytes = [byte[]]@(0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00); Extractable = $true }
            @{ Name = 'RAR5'; Bytes = [byte[]]@(0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00); Extractable = $true }
            @{ Name = 'CAB';  Bytes = [byte[]]@(0x4D, 0x53, 0x43, 0x46); Extractable = $true }
            @{ Name = 'WIM';  Bytes = [byte[]]@(0x4D, 0x53, 0x57, 0x49, 0x4D, 0x00, 0x00, 0x00); Extractable = $true }
            @{ Name = 'MSI';  Bytes = [byte[]]@(0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1); Extractable = $true }
        )

        # ZIP EOCD signature for backward scan
        $zipEOCD = [byte[]]@(0x50, 0x4B, 0x05, 0x06)

        # PyInstaller PKG trailer magic (scan last 4096 bytes)
        # Source: PyInstaller bootloader/src/pyi_archive.c
        $pyiMagic = [byte[]]@(0x4D, 0x45, 0x49, 0x0C, 0x0B, 0x0A, 0x0B, 0x0E)

        # AutoIt v3 compiled script signature
        $autoItMagic = [byte[]]@(0x41, 0x55, 0x33, 0x21, 0x45, 0x41, 0x30, 0x36)

        # NSIS block magic (little-endian 0xDEADBEEF)
        $nsisDeadbeef = [byte[]]@(0xEF, 0xBE, 0xAD, 0xDE)

        # Max file size for full byte read (100 MB)
        $maxReadSize = 104857600

        # Helper: match byte sequence at offset
        function Test-ByteMatch {
            param([byte[]]$Source, [int]$Offset, [byte[]]$Pattern)
            if ($Offset + $Pattern.Length -gt $Source.Length) { return $false }
            for ($i = 0; $i -lt $Pattern.Length; $i++) {
                if ($Source[$Offset + $i] -ne $Pattern[$i]) { return $false }
            }
            return $true
        }

        # Helper: scan byte range for pattern
        function Find-BytePattern {
            param([byte[]]$Source, [int]$Start, [int]$End, [byte[]]$Pattern)
            $pLen = $Pattern.Length
            $limit = [Math]::Min($End, $Source.Length - $pLen)
            for ($i = $Start; $i -le $limit; $i++) {
                $match = $true
                for ($j = 0; $j -lt $pLen; $j++) {
                    if ($Source[$i + $j] -ne $Pattern[$j]) { $match = $false; break }
                }
                if ($match) { return $i }
            }
            return -1
        }
    }

    process {
        foreach ($inputPath in $Path) {
            # Resolve to actual EXE files
            $exeFiles = @()
            if (Test-Path -LiteralPath $inputPath -PathType Container) {
                $gciParams = @{
                    LiteralPath = $inputPath
                    Filter      = $Filter
                    File        = $true
                    ErrorAction = 'SilentlyContinue'
                }
                if ($Recurse) { $gciParams.Recurse = $true }
                $exeFiles = @(Get-ChildItem @gciParams)
                if ($exeFiles.Count -eq 0) {
                    Write-Warning "No files matching '$Filter' found in: $inputPath"
                    continue
                }
                Write-Verbose "Found $($exeFiles.Count) file(s) in: $inputPath"
            }
            elseif (Test-Path -LiteralPath $inputPath -PathType Leaf) {
                $exeFiles = @(Get-Item -LiteralPath $inputPath -ErrorAction SilentlyContinue)
            }
            else {
                Write-Warning "Path not found: $inputPath"
                continue
            }

            foreach ($file in $exeFiles) {
                Write-Verbose "Analyzing: $($file.FullName)"

                $result = [PSCustomObject]@{
                    Path             = $file.FullName
                    Name             = $file.Name
                    SizeBytes        = $file.Length
                    Size             = Format-DowserSize -DataValue $file.Length
                    IsPE             = $false
                    IsNET            = $false
                    Extractable      = $false
                    Classification   = 'Unknown'
                    InstallerType    = $null
                    ArchiveType      = $null
                    DetectionMethod  = 'None'
                    Confidence       = 'None'
                    FileCount        = 0
                    Details          = ''
                    SectionNames     = ''
                    HasOverlay       = $false
                    OverlaySize      = 0
                    Detections       = [System.Collections.Generic.List[string]]::new()
                }

                # =============================================================
                # Read file bytes
                # =============================================================
                $bytes = $null
                $fullRead = $false
                try {
                    if ($file.Length -gt $maxReadSize) {
                        Write-Verbose "  Large file ($($result.Size)) - reading headers + overlay regions only"
                    }
                    else {
                        $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
                        $fullRead = $true
                    }
                }
                catch {
                    Write-Warning "Cannot read file: $($file.FullName) - $($_.Exception.Message)"
                    $result.Details = "File read error: $($_.Exception.Message)"
                    $result
                    continue
                }

                # For large files, read just the first 4KB for headers
                if (-not $fullRead) {
                    try {
                        $headerStream = [System.IO.File]::OpenRead($file.FullName)
                        $headerSize = [Math]::Min(4096, $file.Length)
                        $bytes = New-Object byte[] $headerSize
                        $headerStream.Read($bytes, 0, $headerSize) | Out-Null
                        $headerStream.Close()
                    }
                    catch {
                        Write-Warning "Cannot read headers: $($file.FullName)"
                        $result.Details = "Header read error"
                        $result
                        continue
                    }
                }

                # =============================================================
                # Step 1: MZ / PE Validation
                # =============================================================
                if ($bytes.Length -lt 64 -or $bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) {
                    $result.Classification = 'NotPE'
                    $result.DetectionMethod = 'PEHeader'
                    $result.Confidence = 'High'
                    $result.Details = 'Not a PE file (no MZ header)'
                    $result
                    continue
                }

                $result.IsPE = $true
                $peOffset = [BitConverter]::ToUInt32($bytes, 0x3C)

                if ($peOffset + 4 -ge $bytes.Length -or
                    $bytes[$peOffset] -ne 0x50 -or $bytes[$peOffset + 1] -ne 0x45 -or
                    $bytes[$peOffset + 2] -ne 0x00 -or $bytes[$peOffset + 3] -ne 0x00) {
                    $result.Classification = 'NotPE'
                    $result.DetectionMethod = 'PEHeader'
                    $result.Confidence = 'High'
                    $result.Details = 'Invalid PE signature'
                    $result
                    continue
                }

                # =============================================================
                # Step 2: Parse COFF + Optional Header + COM_DESCRIPTOR
                # =============================================================
                $numSections    = [BitConverter]::ToUInt16($bytes, $peOffset + 6)
                $sizeOfOptHdr   = [BitConverter]::ToUInt16($bytes, $peOffset + 20)
                $optHeaderStart = $peOffset + 24
                $sectionTableOff = $optHeaderStart + $sizeOfOptHdr

                # PE32 vs PE32+
                $optMagic = 0
                $isPE32Plus = $false
                if ($optHeaderStart + 2 -lt $bytes.Length) {
                    $optMagic = [BitConverter]::ToUInt16($bytes, $optHeaderStart)
                    $isPE32Plus = ($optMagic -eq 0x020B)
                }

                # COM_DESCRIPTOR (data directory index 14) - .NET detection
                $ddBaseOffset = if ($isPE32Plus) { 112 } else { 96 }
                $ddStart = $optHeaderStart + $ddBaseOffset
                if ($ddStart + 4 -lt $bytes.Length) {
                    $numberOfRvaAndSizes = [BitConverter]::ToInt32($bytes, $ddStart)
                    if ($numberOfRvaAndSizes -gt 14) {
                        $comDescOff = $ddStart + 4 + (14 * 8)
                        if ($comDescOff + 8 -lt $bytes.Length) {
                            $comRVA  = [BitConverter]::ToUInt32($bytes, $comDescOff)
                            $comSize = [BitConverter]::ToUInt32($bytes, $comDescOff + 4)
                            if ($comRVA -gt 0 -and $comSize -ge 72) {
                                $result.IsNET = $true
                                $result.Detections.Add('.NET assembly: COM_DESCRIPTOR non-zero [HIGH_CONFIDENCE]')
                                Write-Verbose '  .NET assembly detected (COM_DESCRIPTOR)'
                            }
                        }
                    }
                }

                # =============================================================
                # Step 3: Section Name Analysis
                # =============================================================
                $sections = @()
                $maxSectionEnd = 0
                for ($s = 0; $s -lt $numSections; $s++) {
                    $sOff = $sectionTableOff + ($s * 40)
                    if ($sOff + 40 -gt $bytes.Length) { break }
                    $sName   = [System.Text.Encoding]::ASCII.GetString($bytes, $sOff, 8).TrimEnd([char]0)
                    $rawOff  = [BitConverter]::ToUInt32($bytes, $sOff + 20)
                    $rawSize = [BitConverter]::ToUInt32($bytes, $sOff + 16)
                    $sections += [PSCustomObject]@{ Name = $sName; RawOffset = $rawOff; RawSize = $rawSize }
                    $end = $rawOff + $rawSize
                    if ($end -gt $maxSectionEnd) { $maxSectionEnd = $end }
                }
                $sectionNameList = $sections | ForEach-Object { $_.Name }
                $result.SectionNames = $sectionNameList -join ', '

                # Check framework-specific section names
                foreach ($secFp in $sectionFingerprints.GetEnumerator()) {
                    if ($sectionNameList -contains $secFp.Key) {
                        $sfVal = $secFp.Value
                        $result.Detections.Add("$($sfVal.Framework): '$($secFp.Key)' section [HIGH_CONFIDENCE]")
                        Write-Verbose "  Section match: $($secFp.Key) -> $($sfVal.Framework)"
                        if (-not $result.InstallerType) {
                            $result.InstallerType = $sfVal.Framework
                            $result.Extractable = $sfVal.Extractable
                            $result.Classification = if ($sfVal.Extractable) { 'Extractable' } else { 'DecompileRequired' }
                            $result.DetectionMethod = 'SectionName'
                            $result.Confidence = 'High'
                            $result.Details = $sfVal.Note
                        }
                    }
                }

                # UPX detection: UPX0 + UPX1 sections or UPX! at last 4 bytes
                $hasUPX0 = $sectionNameList -contains 'UPX0'
                $hasUPX1 = $sectionNameList -contains 'UPX1'
                $hasUPXMagic = $false
                if ($fullRead -and $bytes.Length -ge 4) {
                    $tail4 = [System.Text.Encoding]::ASCII.GetString($bytes, $bytes.Length - 4, 4)
                    $hasUPXMagic = ($tail4 -eq 'UPX!')
                }
                if (($hasUPX0 -and $hasUPX1) -or $hasUPXMagic) {
                    $result.Detections.Add('UPX packed: section names and/or UPX! overlay [HIGH_CONFIDENCE]')
                    Write-Verbose '  UPX packed binary detected'
                    if (-not $result.InstallerType) {
                        $result.InstallerType = 'UPX_Packed'
                        $result.Extractable = $false
                        $result.Classification = 'UPX_Packed'
                        $result.DetectionMethod = 'SectionName'
                        $result.Confidence = 'High'
                        $result.Details = 'UPX packed - unpack with upx -d first, then re-analyze'
                    }
                }

                # Delphi detection: uppercase CODE/DATA sections or DVCLAL resource
                if ($sectionNameList -contains 'CODE' -and $sectionNameList -contains 'DATA') {
                    $result.Detections.Add('Delphi: uppercase CODE/DATA sections [HIGH_CONFIDENCE]')
                    if (-not $result.InstallerType) {
                        $result.InstallerType = 'Delphi_Native'
                        $result.Extractable = $false
                        $result.Classification = 'DecompileRequired'
                        $result.DetectionMethod = 'SectionName'
                        $result.Confidence = 'High'
                        $result.Details = 'Delphi compiled binary'
                    }
                }

                # =============================================================
                # Step 4: Overlay Analysis
                # =============================================================
                $overlayOffset = $maxSectionEnd
                $overlaySize = [Math]::Max(0, $file.Length - $overlayOffset)
                $result.HasOverlay = ($overlaySize -gt 64)
                $result.OverlaySize = $overlaySize

                if ($result.HasOverlay -and $fullRead -and $overlayOffset -lt $bytes.Length) {
                    $ovAvailable = $bytes.Length - $overlayOffset

                    # Check overlay start for known archive signatures
                    foreach ($ovSig in $overlaySignatures) {
                        if (Test-ByteMatch $bytes $overlayOffset $ovSig.Bytes) {
                            $result.Detections.Add("$($ovSig.Name)_SFX: signature at overlay offset $overlayOffset [HIGH_CONFIDENCE]")
                            Write-Verbose "  Overlay match: $($ovSig.Name) at offset $overlayOffset"
                            $result.ArchiveType = $ovSig.Name
                            $result.Extractable = $ovSig.Extractable
                            $result.Classification = 'Extractable'
                            $result.DetectionMethod = 'OverlaySig'
                            $result.Confidence = 'High'
                            $result.Details = "$($ovSig.Name) archive embedded at overlay offset $overlayOffset"
                            break
                        }
                    }

                    # Inno Setup string at overlay start
                    if (-not $result.ArchiveType -and $ovAvailable -ge 50) {
                        $ovStr = [System.Text.Encoding]::ASCII.GetString($bytes, $overlayOffset, [Math]::Min(50, $ovAvailable))
                        if ($ovStr -match 'Inno Setup Setup Data') {
                            $result.Detections.Add('InnoSetup: overlay magic string [HIGH_CONFIDENCE]')
                            Write-Verbose '  Inno Setup overlay data found'
                            $result.ArchiveType = 'Inno'
                            $result.InstallerType = 'InnoSetup'
                            $result.Extractable = $true
                            $result.Classification = 'Extractable'
                            $result.DetectionMethod = 'OverlaySig'
                            $result.Confidence = 'High'
                            $result.Details = 'Inno Setup installer - overlay data block'
                        }
                    }

                    # ZIP EOCD backward scan (last 65557 bytes, validated with commentLen)
                    if (-not $result.ArchiveType) {
                        $eocdSearchStart = [Math]::Max(0, $bytes.Length - 65557)
                        for ($i = $bytes.Length - 22; $i -ge $eocdSearchStart; $i--) {
                            if (Test-ByteMatch $bytes $i $zipEOCD) {
                                if ($i + 20 + 2 -le $bytes.Length) {
                                    $commentLen = [BitConverter]::ToUInt16($bytes, $i + 20)
                                    if (($i + 22 + $commentLen) -eq $bytes.Length) {
                                        $result.Detections.Add("ZIP_SFX: validated EOCD at offset $i [HIGH_CONFIDENCE]")
                                        Write-Verbose "  ZIP EOCD found at offset $i (commentLen=$commentLen)"
                                        $result.ArchiveType = 'ZIP'
                                        $result.Extractable = $true
                                        $result.Classification = 'Extractable'
                                        $result.DetectionMethod = 'OverlaySig'
                                        $result.Confidence = 'High'
                                        $result.Details = "Embedded ZIP archive (EOCD at offset $i)"
                                        break
                                    }
                                }
                            }
                        }
                    }

                    # PyInstaller MEI magic (last 4096 bytes)
                    $pyiStart = [Math]::Max(0, $bytes.Length - 4096)
                    $pyiOffset = Find-BytePattern $bytes $pyiStart ($bytes.Length - 1) $pyiMagic
                    if ($pyiOffset -ge 0) {
                        $result.Detections.Add("PyInstaller: MEI PKG trailer at offset $pyiOffset [HIGH_CONFIDENCE]")
                        Write-Verbose "  PyInstaller PKG magic at offset $pyiOffset"
                        if (-not $result.InstallerType -or $result.InstallerType -eq 'DotNet_Unknown') {
                            $result.InstallerType = 'PyInstaller'
                            $result.Extractable = $false
                            $result.Classification = 'DecompileRequired'
                            $result.DetectionMethod = 'OverlaySig'
                            $result.Confidence = 'High'
                            $result.Details = 'PyInstaller packaged - use pyinstxtractor for extraction'
                        }
                    }

                    # AutoIt AU3!EA06 magic (scan overlay region)
                    $auOffset = Find-BytePattern $bytes $overlayOffset ([Math]::Min($overlayOffset + 1048576, $bytes.Length - 1)) $autoItMagic
                    if ($auOffset -ge 0) {
                        $result.Detections.Add("AutoIt: AU3!EA06 signature at offset $auOffset [HIGH_CONFIDENCE]")
                        Write-Verbose "  AutoIt compiled script marker at offset $auOffset"
                        if (-not $result.InstallerType) {
                            $result.InstallerType = 'AutoIt'
                            $result.Extractable = $false
                            $result.Classification = 'DecompileRequired'
                            $result.DetectionMethod = 'OverlaySig'
                            $result.Confidence = 'High'
                            $result.Details = 'AutoIt compiled script - use Exe2Aut for decompilation'
                        }
                    }
                }

                # =============================================================
                # Step 5: VersionInfo Fingerprinting
                # =============================================================
                try {
                    $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($file.FullName)
                    $versionFields = @(
                        $versionInfo.FileDescription,
                        $versionInfo.ProductName,
                        $versionInfo.CompanyName,
                        $versionInfo.InternalName,
                        $versionInfo.LegalCopyright,
                        $versionInfo.Comments
                    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                    $allVersionText = $versionFields -join ' '

                    # Check OriginalFilename separately (very reliable)
                    $origFn = $versionInfo.OriginalFilename
                    if ($origFn -and $originalFilenameFingerprints.ContainsKey($origFn)) {
                        $ofFp = $originalFilenameFingerprints[$origFn]
                        $result.Detections.Add("$($ofFp.Framework): OriginalFilename='$origFn' [HIGH_CONFIDENCE]")
                        if (-not $result.InstallerType) {
                            $result.InstallerType = $ofFp.Framework
                            $result.Extractable = $ofFp.Extractable
                            $result.Classification = if ($ofFp.Extractable) { 'Extractable' } else { 'DecompileRequired' }
                            $result.DetectionMethod = 'VersionInfo'
                            $result.Confidence = 'High'
                            $result.Details = "Matched OriginalFilename: $origFn"
                        }
                    }

                    # Check all version text against framework patterns
                    if ($allVersionText) {
                        foreach ($fw in $frameworkFingerprints.GetEnumerator()) {
                            $matched = $false
                            foreach ($pattern in $fw.Value.Patterns) {
                                if ($allVersionText.IndexOf($pattern, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                                    $result.Detections.Add("$($fw.Key): VersionInfo match '$pattern' [HIGH_CONFIDENCE]")
                                    Write-Verbose "  VersionInfo: $($fw.Key) ('$pattern')"
                                    if (-not $result.InstallerType) {
                                        $result.InstallerType = $fw.Key
                                        $result.Extractable = $fw.Value.Extractable
                                        $result.Classification = if ($fw.Value.Extractable) { 'Extractable' } else { 'DecompileRequired' }
                                        $result.DetectionMethod = 'VersionInfo'
                                        $result.Confidence = 'High'
                                        $result.Details = "Matched '$pattern' in version strings"
                                    }
                                    $matched = $true
                                    break
                                }
                            }
                            if ($matched) { break }
                        }
                    }
                }
                catch {
                    Write-Verbose "VersionInfo read error for $($file.Name): $($_.Exception.Message)"
                }

                # =============================================================
                # Step 6: Binary String Scanning (first+last 1MB if full read)
                # =============================================================
                if ($fullRead -and $result.Classification -eq 'Unknown') {
                    $scanEnd = [Math]::Min($bytes.Length, 1048576)
                    $tailStart = [Math]::Max(0, $bytes.Length - 1048576)

                    # Extract ASCII strings from scan regions for pattern matching
                    $headStr = [System.Text.Encoding]::ASCII.GetString($bytes, 0, $scanEnd)
                    $tailStr = if ($tailStart -gt 0) {
                        [System.Text.Encoding]::ASCII.GetString($bytes, $tailStart, $bytes.Length - $tailStart)
                    } else { '' }
                    $scanText = $headStr + $tailStr

                    # Go binary: buildinf magic or .go.buildinfo string
                    if ($scanText.Contains([char]0xFF + ' Go buildinf:') -or $scanText.Contains('.go.buildinfo')) {
                        $result.Detections.Add('Go binary: buildinf marker [HIGH_CONFIDENCE]')
                        if (-not $result.InstallerType) {
                            $result.InstallerType = 'Go_Native'
                            $result.Extractable = $false
                            $result.Classification = 'DecompileRequired'
                            $result.DetectionMethod = 'BinaryString'
                            $result.Confidence = 'High'
                            $result.Details = 'Go compiled binary'
                        }
                    }

                    # Rust binary: panic string
                    if ($scanText.Contains('panicked at') -and $scanText.Contains('unwrap()')) {
                        $result.Detections.Add('Rust binary: panic string [HEURISTIC]')
                        if (-not $result.InstallerType) {
                            $result.InstallerType = 'Rust_Native'
                            $result.Extractable = $false
                            $result.Classification = 'DecompileRequired'
                            $result.DetectionMethod = 'BinaryString'
                            $result.Confidence = 'Medium'
                            $result.Details = 'Rust compiled binary (heuristic: panic string)'
                        }
                    }

                    # Electron
                    if ($scanText.Contains('ELECTRON_RUN_AS_NODE')) {
                        $result.Detections.Add('Electron: ELECTRON_RUN_AS_NODE string [HIGH_CONFIDENCE]')
                        if (-not $result.InstallerType) {
                            $result.InstallerType = 'Electron'
                            $result.Extractable = $false
                            $result.Classification = 'DecompileRequired'
                            $result.DetectionMethod = 'BinaryString'
                            $result.Confidence = 'High'
                            $result.Details = 'Electron application - use asar extract for resources'
                        }
                    }

                    # Node.js SEA
                    if ($scanText.Contains('SEA_FUSE_fce680ab2cc467b6e072b8b5df1996b2')) {
                        $result.Detections.Add('Node.js SEA: fuse string [HIGH_CONFIDENCE]')
                        if (-not $result.InstallerType) {
                            $result.InstallerType = 'NodeJS_SEA'
                            $result.Extractable = $false
                            $result.Classification = 'DecompileRequired'
                            $result.DetectionMethod = 'BinaryString'
                            $result.Confidence = 'High'
                            $result.Details = 'Node.js Single Executable Application'
                        }
                    }

                    # PyInstaller _MEIPASS string (backup if trailer wasn't found)
                    if ($scanText.Contains('_MEIPASS') -and -not ($result.InstallerType -eq 'PyInstaller')) {
                        $result.Detections.Add('PyInstaller: _MEIPASS string [HIGH_CONFIDENCE]')
                        if (-not $result.InstallerType) {
                            $result.InstallerType = 'PyInstaller'
                            $result.Extractable = $false
                            $result.Classification = 'DecompileRequired'
                            $result.DetectionMethod = 'BinaryString'
                            $result.Confidence = 'High'
                            $result.Details = 'PyInstaller packaged - use pyinstxtractor'
                        }
                    }

                    # AutoIt text marker (backup)
                    if ($scanText.Contains('This is a compiled AutoIt script') -and -not ($result.InstallerType -eq 'AutoIt')) {
                        $result.Detections.Add('AutoIt: compiled script text marker [HIGH_CONFIDENCE]')
                        if (-not $result.InstallerType) {
                            $result.InstallerType = 'AutoIt'
                            $result.Extractable = $false
                            $result.Classification = 'DecompileRequired'
                            $result.DetectionMethod = 'BinaryString'
                            $result.Confidence = 'High'
                            $result.Details = 'AutoIt compiled script - use Exe2Aut'
                        }
                    }
                }

                # =============================================================
                # Step 7: Native Windows Detection (no third-party tools)
                # =============================================================
                # Try System.IO.Compression.ZipFile for embedded ZIP
                if ($result.Classification -eq 'Unknown' -or $result.Detections.Count -eq 0) {
                    try {
                        Add-Type -AssemblyName System.IO.Compression -ErrorAction SilentlyContinue
                        $zip = [System.IO.Compression.ZipFile]::OpenRead($file.FullName)
                        $entryCount = $zip.Entries.Count
                        $zip.Dispose()
                        if ($entryCount -gt 0) {
                            $result.Detections.Add("ZIP: System.IO.Compression found $entryCount entries [HIGH_CONFIDENCE]")
                            Write-Verbose "  Native ZIP detection: $entryCount entries"
                            $result.ArchiveType = 'ZIP'
                            $result.Extractable = $true
                            $result.Classification = 'Extractable'
                            $result.DetectionMethod = 'NativeZip'
                            $result.Confidence = 'High'
                            $result.FileCount = $entryCount
                            $result.Details = "Embedded ZIP with $entryCount entries (detected via .NET ZipFile)"
                        }
                    }
                    catch {
                        # Not a valid ZIP - that's fine, continue
                    }
                }

                # Try expand.exe for embedded CAB
                if ($hasExpand -and ($result.Classification -eq 'Unknown' -or $result.Detections.Count -eq 0)) {
                    try {
                        $expandOutput = & $expandExe '-D' $file.FullName 2>&1 | Out-String
                        if ($LASTEXITCODE -eq 0 -and $expandOutput -match '\S') {
                            $result.Detections.Add('CAB: expand.exe -D succeeded [HIGH_CONFIDENCE]')
                            Write-Verbose '  Native CAB detection via expand.exe'
                            $result.ArchiveType = 'CAB'
                            $result.Extractable = $true
                            $result.Classification = 'Extractable'
                            $result.DetectionMethod = 'NativeCAB'
                            $result.Confidence = 'High'
                            $result.Details = 'Embedded CAB archive (detected via expand.exe)'
                        }
                    }
                    catch {
                        # expand.exe failed - not a CAB, continue
                    }
                }

                # =============================================================
                # Step 8: 7-Zip Oracle (definitive, overrides earlier tiers)
                # =============================================================
                if ($has7Zip) {
                    try {
                        $7zOutput = & $SevenZipPath l $file.FullName 2>&1 | Out-String
                        $7zLines = $7zOutput -split "`r?`n"

                        # Parse all Type= lines
                        $foundTypes = @()
                        foreach ($line in $7zLines) {
                            if ($line -match '^\s*Type\s*=\s*(.+)$') {
                                $foundTypes += $Matches[1].Trim()
                            }
                        }

                        # Parse file listing between separator lines
                        $separatorIndices = @()
                        for ($idx = 0; $idx -lt $7zLines.Count; $idx++) {
                            if ($7zLines[$idx] -match '^-{10,}') { $separatorIndices += $idx }
                        }

                        $listedFileNames = @()
                        $listedDirCount = 0
                        if ($separatorIndices.Count -ge 2) {
                            $listStart = $separatorIndices[0] + 1
                            $listEnd   = $separatorIndices[1] - 1
                            for ($idx = $listStart; $idx -le $listEnd; $idx++) {
                                $listLine = $7zLines[$idx]
                                if ([string]::IsNullOrWhiteSpace($listLine)) { continue }
                                if ($listLine -match '[\.DRHSA]{5}\s+(\d+)\s+(\d+)\s+(.+)$') {
                                    $entryName = $Matches[3].Trim()
                                    if ($listLine -match '\sD[\.RHSA]*\s') { $listedDirCount++ }
                                    else { $listedFileNames += $entryName }
                                }
                            }
                        }

                        # Classify: real payload vs PE sections
                        $realFiles = @()
                        $peSections = @()
                        foreach ($name in $listedFileNames) {
                            $isPeSec = $false
                            foreach ($pat in $peSectionPatterns) {
                                if ($name -match $pat) { $isPeSec = $true; break }
                            }
                            if ($isPeSec) { $peSections += $name } else { $realFiles += $name }
                        }

                        # Check for extractable archive type
                        $detectedArchiveType = $null
                        foreach ($t in $foundTypes) {
                            if ($t -in $extractable7zTypes) {
                                $detectedArchiveType = $t
                                break
                            }
                        }

                        # 7-Zip verdict (overrides earlier tiers)
                        if ($detectedArchiveType -or $realFiles.Count -gt 0) {
                            $result.Extractable = $true
                            $result.Classification = 'Extractable'
                            $result.FileCount = $realFiles.Count
                            $result.DetectionMethod = '7Zip'
                            $result.Confidence = 'High'
                            $result.ArchiveType = if ($detectedArchiveType) { $detectedArchiveType } else {
                                ($foundTypes | Where-Object { $_ -notin $nonExtractable7zTypes } | Select-Object -First 1)
                            }
                            if (-not $result.ArchiveType) { $result.ArchiveType = $foundTypes[0] }
                            $result.Details = "7-Zip: $($realFiles.Count) extractable files (Type: $($foundTypes -join ', '))"
                            $result.Detections.Add("7-Zip: Type=$($foundTypes -join ','), $($realFiles.Count) real files [HIGH_CONFIDENCE]")
                            Write-Verbose "  7-Zip: EXTRACTABLE - $($realFiles.Count) files, Type=$($foundTypes -join ', ')"
                        }
                        elseif ($peSections.Count -gt 0 -and $realFiles.Count -eq 0) {
                            $hasRsrc = [bool]($peSections | Where-Object { $_ -match '\.rsrc' })
                            $classification = if ($hasRsrc -and -not $result.InstallerType) { 'ResourcesOnly' } else { $result.Classification }
                            if ($classification -eq 'Unknown') { $classification = 'DecompileRequired' }
                            $result.Extractable = $false
                            $result.Classification = $classification
                            $result.FileCount = 0
                            $result.DetectionMethod = '7Zip'
                            $result.Confidence = 'High'
                            $shortList = ($peSections | Select-Object -First 3) -join ', '
                            $result.Details = "7-Zip: PE sections only ($($peSections.Count) entries: $shortList$(if ($peSections.Count -gt 3) { '...' }))"
                            $result.Detections.Add("7-Zip: Type=$($foundTypes -join ','), PE sections only [HIGH_CONFIDENCE]")
                            Write-Verbose '  7-Zip: NOT EXTRACTABLE - PE sections only'
                        }
                        elseif ($foundTypes.Count -gt 0) {
                            if ($result.Classification -eq 'Unknown') {
                                $result.Extractable = $false
                                $result.Classification = 'DecompileRequired'
                                $result.DetectionMethod = '7Zip'
                                $result.Confidence = 'High'
                                $result.Details = "7-Zip: Type=$($foundTypes -join ', '), no extractable content"
                            }
                        }
                    }
                    catch {
                        Write-Verbose "7-Zip error for $($file.Name): $($_.Exception.Message)"
                    }
                }

                # =============================================================
                # Fallback Classification
                # =============================================================
                if ($result.Classification -eq 'Unknown') {
                    if ($result.IsNET) {
                        $result.Extractable = $false
                        $result.Classification = 'DecompileRequired'
                        $result.DetectionMethod = 'PEHeader'
                        $result.Confidence = 'Medium'
                        $result.Details = '.NET assembly (COM_DESCRIPTOR) - use ILSpy or dnSpy'
                    }
                    elseif ($result.HasOverlay -and $result.OverlaySize -gt 1024) {
                        $result.Extractable = $false
                        $result.Classification = 'Unknown'
                        $result.DetectionMethod = 'Static'
                        $result.Confidence = 'Low'
                        $ovSizeStr = Format-DowserSize -DataValue $result.OverlaySize
                        $result.Details = "PE with $ovSizeStr overlay - unrecognized format"
                    }
                    elseif ($result.IsPE) {
                        $result.Extractable = $false
                        $result.Classification = 'DecompileRequired'
                        $result.DetectionMethod = 'PEHeader'
                        $result.Confidence = 'Low'
                        $result.Details = 'Native PE binary - no embedded archive signatures found'
                    }
                }

                # Convert Detections list to array for cleaner output
                $result.Detections = @($result.Detections)
                $result
            }
        }
    }
}
