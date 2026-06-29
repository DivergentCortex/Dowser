# Dowser: Canonical Static-Analysis Reference

## Static Classification of Windows .EXE Files — Extractable vs Requires Decompilation

### Version: 2026.04.15.002 | Sources: verityvulture + verityfactseeker deep-research merges

---

> **Merge note**: This document consolidates two independent deep-research outputs:
>
> - `verityvulture` run `2026-04-15__1410` (sources: 18+ primary; evidence map in Appendix B)
> - `verityfactseeker` artifact `dowser-pe-static-analysis-reference.md` v2026.04.15.001
>
> Where the two sources disagreed, the more authoritative source (direct source-code citation) wins;
> conflicts and resolutions are documented in Appendix B (Disagreements).

---

## TABLE OF CONTENTS

1. [Magic Bytes and Embedded Archive Signatures](#1-magic-bytes-and-embedded-archive-signatures)
2. [Installer Framework Detection](#2-installer-framework-detection)
3. [Script-to-EXE Wrapper Detection](#3-script-to-exe-wrapper-detection)
4. [.NET Assembly Detection](#4-net-assembly-detection)
5. [7-Zip `7z l` Output Parsing](#5-7-zip-7z-l-output-parsing)
6. [Windows Built-in Detection Methods](#6-windows-built-in-detection-methods)
7. [PE Header Analysis for Classification](#7-pe-header-analysis-for-classification)
8. [Decision Matrix: Extractable vs Requires Decompilation](#8-decision-matrix)
9. [PowerShell Reference Implementation Skeleton](#9-powershell-reference-implementation-skeleton)
10. [Source Citations and Authoritative References](#10-source-citations-and-authoritative-references)
11. [Appendix A: Quick-Reference Hex Signatures](#appendix-a-quick-reference-hex-signatures)
12. [Appendix B: Evidence Map and Disagreements](#appendix-b-evidence-map-and-disagreements)

---

## TERMINOLOGY

- **HIGH_CONFIDENCE**: Definitive signature match — a unique byte sequence or structural marker
  with near-zero false-positive rate, derivable from primary source specification or source code.
- **HEURISTIC**: Probabilistic match — a pattern that strongly suggests the type but can appear
  in other contexts or is undocumented in primary specs.
- **Extractable**: 7-Zip, expand.exe, extrac32.exe, System.IO.Compression, or Windows Shell can
  unpack into usable artifacts (DLLs, scripts, configs, MSIs, installers).
- **Requires Decompilation**: Payload is compiled native code, .NET IL, or bytecode requiring
  ILSpy, dnSpy, Exe2Aut, Ghidra, Binary Ninja, pyinstxtractor, etc.

---

## 1. MAGIC BYTES AND EMBEDDED ARCHIVE SIGNATURES

### 1.1 PE File Structure Primer

Every Windows EXE begins with:

```
Offset 0x00:      4D 5A                ("MZ") — DOS header magic
Offset 0x3C:      DWORD e_lfanew       — offset to PE signature
Offset [e_lfanew]: 50 45 00 00         ("PE\x00\x00") — PE signature
```

The PE signature is followed by:

- `IMAGE_FILE_HEADER` (20 bytes)
- `IMAGE_OPTIONAL_HEADER` (96 bytes PE32 / 112 bytes PE32+)
- Section table (40 bytes per entry)
- Raw section data

The region **after** all section data (i.e., after `PointerToRawData + SizeOfRawData` of the last
section) is called the **overlay**. Self-extracting archives embed their payload in:

1. A dedicated PE section (commonly `.rsrc` or a custom section like `.ndata`)
2. The overlay (appended after all PE sections)
3. Both (index in overlay, data in sections)

### 1.2 Exact Archive Magic Bytes

#### ZIP Archive [HIGH_CONFIDENCE]

```
Local File Header:    50 4B 03 04  ("PK\x03\x04") — at each file entry
Central Directory:    50 4B 01 02  ("PK\x01\x02") — per-file in EOCD region
End of Central Dir:   50 4B 05 06  ("PK\x05\x06") — exactly once, ≥22 bytes from EOF
End of CD (ZIP64):    50 4B 06 06  ("PK\x06\x06") — ZIP64 EOCD record
```

**Scanning strategy — EOCD is the reliable locator**:

- EOCD is exactly 22 bytes minimum: `50 4B 05 06 [diskNum:2] [startDisk:2] [entriesOnDisk:2] [totalEntries:2] [CDSize:4] [CDOffset:4] [commentLen:2]`
- Search last 65,557 bytes (22 + max comment 65,535) from EOF for the EOCD signature
- Validate: `i + 22 + commentLen == fileLength`
- If valid, check `CDOffset` field — if it points into valid PE section data, it is an embedded ZIP

**Important**: `System.IO.Compression.ZipFile.OpenRead()` uses EOCD scanning internally.
Calling it on a PE+ZIP SFX will **succeed** automatically, finding the embedded ZIP. [HIGH_CONFIDENCE]

**Source**: PKWARE APPNOTE.TXT §4.3 — https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT

```powershell
function Find-EmbeddedZip {
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $searchStart = [Math]::Max(0, $bytes.Length - 65557)
    for ($i = $bytes.Length - 22; $i -ge $searchStart; $i--) {
        if ($bytes[$i]   -eq 0x50 -and $bytes[$i+1] -eq 0x4B -and
            $bytes[$i+2] -eq 0x05 -and $bytes[$i+3] -eq 0x06) {
            $commentLen = [BitConverter]::ToUInt16($bytes, $i + 20)
            if (($i + 22 + $commentLen) -eq $bytes.Length) {
                $cdOffset = [BitConverter]::ToUInt32($bytes, $i + 16)
                return [PSCustomObject]@{ Found=$true; EocdOffset=$i; CdOffset=$cdOffset }
            }
        }
    }
    return [PSCustomObject]@{ Found=$false }
}
```

#### 7-Zip Archive [HIGH_CONFIDENCE]

```
Signature: 37 7A BC AF 27 1C  (6 bytes, "7z\xBC\xAF\x27\x1C")
```

**Source**: 7-Zip source `CPP/7zip/Archive/7z/7zHeader.h`:

```cpp
const Byte kSignature[kSignatureSize] = {'7', 'z', 0xBC, 0xAF, 0x27, 0x1C};
```

https://github.com/ip7z/7zip/blob/main/CPP/7zip/Archive/7z/7zHeader.h

For 7-Zip SFX, the archive begins immediately after the SFX stub PE. Typical stub sizes:

- `7z.sfx` (GUI): ~120,000–130,000 bytes
- `7zSD.sfx` (no GUI): ~40,000–50,000 bytes
- `7zCon.sfx` (console): varies

Scan the full file for `37 7A BC AF 27 1C`. If found at offset > 0x1000 (past normal PE headers),
treat as embedded 7z.

#### CAB (Microsoft Cabinet) [HIGH_CONFIDENCE]

```
Signature:    4D 53 43 46  ("MSCF")
Reserved1:    00 00 00 00  (must be zero — validation check)
CabinetSize:  DWORD        (total cabinet size)
Reserved2:    00 00 00 00  (must be zero — validation check)
FirstOffset:  DWORD        (offset of first CFFILE entry)
```

Full CAB header detail (36 bytes total):

```
Offset  Size  Field
0       4     signature: 4D 53 43 46
4       4     reserved1 (0)
8       4     cbCabinet (total cabinet size)
12      4     reserved2 (0)
16      4     coffFiles (offset of first CFFILE entry)
20      4     reserved3 (0)
24      1     versionMinor (must be 3)
25      1     versionMajor (must be 1)
26      2     cFolders
28      2     cFiles
30      2     flags
32      2     setID
34      2     iCabinet
```

**Source**: [MS-CAB] Cabinet File Format §2.2 — https://docs.microsoft.com/en-us/openspecs/windows_protocols/ms-cab/

`expand.exe` and `extrac32.exe` both scan for `MSCF` anywhere in an EXE and will find embedded CABs.

```powershell
function Find-EmbeddedCab {
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $sig = [byte[]](0x4D,0x53,0x43,0x46,0x00,0x00,0x00,0x00)
    for ($i = 0; $i -le ($bytes.Length - 36); $i++) {
        $match = $true
        for ($j = 0; $j -lt $sig.Length; $j++) {
            if ($bytes[$i+$j] -ne $sig[$j]) { $match = $false; break }
        }
        if ($match) {
            $cabSize = [BitConverter]::ToUInt32($bytes, $i + 8)
            if (($i + $cabSize) -le $bytes.Length) {
                return [PSCustomObject]@{ Found=$true; Offset=$i; CabSize=$cabSize }
            }
        }
    }
    return [PSCustomObject]@{ Found=$false }
}
```

#### RAR Archive [HIGH_CONFIDENCE]

```
RAR 1.5–4.x: 52 61 72 21 1A 07 00     (7 bytes: "Rar!\x1A\x07\x00")
RAR 5.0+:    52 61 72 21 1A 07 01 00   (8 bytes: "Rar!\x1A\x07\x01\x00")
```

**Source**: RARLAB UnRAR source `rarformat.h` (RAR5 marker block, `static const byte HEADER5_MARK[8]`).
WinRAR SFX stubs are typically 350–550 KB; the RAR archive appears at the overlay offset.

#### WIM (Windows Imaging Format) [HIGH_CONFIDENCE]

```
Signature: 4D 53 57 49 4D 00 00 00  (8 bytes: "MSWIM\0\0\0")
```

Full WIM header starts at offset 0:

```
Offset  Size  Field
0       8     ImageTag: 4D 53 57 49 4D 00 00 00  "MSWIM\0\0\0"
8       4     cbSize (header size, 208 bytes for WIM 1.13)
12      4     dwVersion: 000E 0001 or 000D 0001
```

WIM total header: 208 bytes.
**Source**: [MS-WIM] — https://docs.microsoft.com/en-us/openspecs/windows_protocols/ms-wim/

#### XZ / LZMA2 Stream [HIGH_CONFIDENCE]

```
XZ stream header: FD 37 7A 58 5A 00  (6 bytes: "\xFD7zXZ\x00")
```

**Source**: https://tukaani.org/xz/xz-file-format-1.1.0.txt §2.1.1

#### LZMA Standalone Stream [HEURISTIC]

```
Properties byte: 5D  (most common: LC=3, LP=0, PB=2)
Dictionary size: 4 bytes LE DWORD (commonly 00 00 80 00 = 8 MB)
Uncompressed size: 8 bytes (UInt64, or FF FF FF FF FF FF FF FF if unknown)
```

HEURISTIC only — 0x5D is not a unique byte. Cross-reference with other evidence.
Note: 7-Zip uses LZMA internally for 7z containers; the 7z container signature is the reliable outer marker.

#### GZIP [HIGH_CONFIDENCE]

```
Signature: 1F 8B 08  (3 bytes; 08 = deflate method, always present)
```

#### BZIP2 [HIGH_CONFIDENCE]

```
Stream magic: 42 5A 68  ("BZh")
Block header:  31 41 59 26 53 59  (6 bytes — pi digits, immediately after stream magic + block size)
```

#### ZSTD [HIGH_CONFIDENCE]

```
Frame magic: 28 B5 2F FD  (4 bytes, little-endian value 0xFD2FB528)
```

#### MSI / OLE Compound File [HIGH_CONFIDENCE]

```
Signature: D0 CF 11 E0 A1 B1 1A E1  (8 bytes at offset 0)
```

MSI files are OLE Compound Files. If this signature appears in an EXE overlay, it contains an embedded MSI.

#### ISO 9660 [HIGH_CONFIDENCE — rarely embedded]

```
Primary Volume Descriptor at offset 0x8001 (sector 16, 2048-byte sectors):
Bytes 0x8001–0x8005: 01 43 44 30 30 31  (type byte 0x01 + "CD001")
```

Occasionally seen in dropper payloads; not a common EXE-wrapper format.

### 1.3 SFX Stub Identification (VersionInfo Fingerprints)

#### 7-Zip SFX Stubs [HIGH_CONFIDENCE]

**VersionInfo** (VS_VERSIONINFO resource):

```
FileDescription: "7-Zip Self-extracting Archive"            (7z.sfx GUI)
                 "7-Zip Self-extracting Archive (console)"  (7zCon.sfx)
                 "7-Zip SFX"                                (older variants)
CompanyName:     "Igor Pavlov"
ProductName:     "7-Zip"
OriginalFilename: "7z.sfx" or "7zS.sfx" or "7zSD.sfx"
```

**Archive location**: At `overlayOffset` = `max(section.PointerToRawData + section.SizeOfRawData)`.
The 6-byte 7z signature `37 7A BC AF 27 1C` will appear at this exact offset.
**Source**: 7-Zip source `CPP/7zip/Bundles/SFXWin/` and `CPP/7zip/Bundles/SFXCon/`

#### WinRAR SFX Stubs [HIGH_CONFIDENCE]

**VersionInfo**:

```
FileDescription:  "WinRAR self-extracting archive"  (or "RAR SFX")
ProductName:      "WinRAR"
CompanyName:      "Alexander Roshal" (older) or "win.rar GmbH" (newer)
OriginalFilename: "Default.SFX" or "WinCon.SFX" or "WinRAR.exe"
```

**Internal PE resources**: Contains RT_RCDATA resource named `"RAR"` or with ID 1000.
**Archive location**: RAR signature `52 61 72 21 1A 07 xx` in overlay. Stub typically 350–550 KB.

#### WinZip SFX [HIGH_CONFIDENCE]

**VersionInfo**:

```
FileDescription: "WinZip Self-Extractor" or "WinZip Self-Extractor Personal Edition"
CompanyName:     "WinZip International LLC" (modern) or "WinZip Computing" (older)
                 or "Corel Corporation" (post-2012 acquisition) or "Nico Mak Computing" (legacy)
OriginalFilename: "WZSFX.EXE" or "WZSEPE32.EXE"
```

**Archive location**: ZIP EOCD in overlay.

#### Info-ZIP / UnZip SFX [HEURISTIC]

**Strings in `.text` section** (not VersionInfo — VersionInfo often minimal or user-customized):

```
"Info-ZIP's"    (literal string in binary)
"unzip"         (lowercase)
"unzipsfx"      (or "UnZipSFX")
```

**Archive location**: ZIP EOCD in overlay; UnZip SFX searches from EOF backward for EOCD.
**Source**: Info-ZIP source: `unzip/SFX/Makefile` and `funzip.c`

#### IExpress SFX [HIGH_CONFIDENCE]

Built into Windows (used by Windows Update packages and hotfixes):

```
VersionInfo ProductName: "IExpress"  (or user-customized)
```

**Internal resource**: Always contains embedded CAB (`MSCF` signature). The CAB is embedded as a
resource of custom type `CABINET` or in the overlay.
**Detection**: `expand.exe -D <file>` will list IExpress CAB contents.
**Source**: Windows SDK; IExpress documentation.

### 1.4 Overlay Offset Calculation

```powershell
function Get-PeOverlayOffset {
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) { return -1 }

    $peOffset       = [BitConverter]::ToUInt32($bytes, 0x3C)
    if ($bytes[$peOffset]   -ne 0x50 -or $bytes[$peOffset+1] -ne 0x45 -or
        $bytes[$peOffset+2] -ne 0x00 -or $bytes[$peOffset+3] -ne 0x00) { return -1 }

    $numberOfSections = [BitConverter]::ToUInt16($bytes, $peOffset + 6)
    $sizeOfOptHeader  = [BitConverter]::ToUInt16($bytes, $peOffset + 20)
    $sectionTableOff  = $peOffset + 24 + $sizeOfOptHeader

    $maxEnd = 0
    for ($i = 0; $i -lt $numberOfSections; $i++) {
        $sOff    = $sectionTableOff + ($i * 40)
        $rawOff  = [BitConverter]::ToUInt32($bytes, $sOff + 20)  # PointerToRawData
        $rawSize = [BitConverter]::ToUInt32($bytes, $sOff + 16)  # SizeOfRawData
        $end = $rawOff + $rawSize
        if ($end -gt $maxEnd) { $maxEnd = $end }
    }
    return [PSCustomObject]@{
        OverlayOffset = $maxEnd
        OverlaySize   = ($bytes.Length - $maxEnd)
        HasOverlay    = (($bytes.Length - $maxEnd) -gt 0)
    }
}
```

---

## 2. INSTALLER FRAMEWORK DETECTION

### 2.1 NSIS (Nullsoft Scriptable Install System)

#### [HIGH_CONFIDENCE] `.ndata` Section Name

NSIS installers almost always have a PE section named `.ndata`. This section name does not appear
in any other common framework. It is the **most reliable NSIS indicator**.

#### [HIGH_CONFIDENCE] NSIS Block Magic Bytes

The NSIS data block begins with the "deadbeef" signature (little-endian):

```
EF BE AD DE  (= 0xDEADBEEF in little-endian — NSIS magic at start of first header)
```

**Byte-order note**: The raw bytes are `EF BE AD DE`, NOT `DE AD BE EF`. The NSIS source
`Source/exehead/` checks for `0xDEADBEEF` as a DWORD — stored little-endian on x86 this
becomes `EF BE AD DE` on disk. (Confirmed from verityvulture disagreements §10.)

NSIS source: `Contrib/Header/fileform.h`:

```c
#define NSIS_SIGNATURE { 0xEF, 0xBE, 0xAD, 0xDE }
```

https://sourceforge.net/p/nsis/code/HEAD/tree/NSIS/trunk/Contrib/Header/fileform.h

#### [HIGH_CONFIDENCE] VersionInfo Strings

```
FileDescription: "Nullsoft Install System vX.XX"  (highly indicative when present)
CompanyName:     "Nullsoft, Inc." or "Nullsoft"
Comments:        "Nullsoft Install System"
```

**Important**: Many NSIS installers customize or strip VersionInfo. The `.ndata` section is
**more reliable** than VersionInfo. NSIS does NOT auto-populate VersionInfo.

#### [HIGH_CONFIDENCE] 7-Zip `Type =` output

```
Type = Nsis
```

7-Zip has a dedicated NSIS handler (`CPP/7zip/Archive/NsisHandler.cpp`).
**Caveat**: Some custom-compressed or newer NSIS installers may fool 7-Zip into reporting `Type = PE`.
The `.ndata` section check is more reliable for detection; 7z `Type = Nsis` is confirmation.

#### Import Table

```
REQUIRED: kernel32.dll, user32.dll
COMMON:   gdi32.dll, shell32.dll, advapi32.dll, ole32.dll, oleaut32.dll, comctl32.dll
NSIS hardware detection: may import setupapi.dll
ABSENT:   mscoree.dll (NSIS is pure C++)
```

### 2.2 Inno Setup

#### [HIGH_CONFIDENCE] Overlay Magic String

Inno Setup stores setup data as an overlay. The magic string appears at the **very start of the overlay**:

```
"Inno Setup Setup Data (1.0)\r\n\x1A"  (Inno 1.x)
"Inno Setup Setup Data (4.0)\r\n\x1A"  (Inno 4.x)
"Inno Setup Setup Data (5.0)\r\n\x1A"  (Inno 5.x)
"Inno Setup Setup Data (5.1)\r\n\x1A"
"Inno Setup Setup Data (5.6.2)\r\n\x1A"
"Inno Setup Setup Data (6.x.x)\r\n\x1A" (Inno 6.x)
```

Hex for the common Inno 5.x header start:

```
49 6E 6E 6F 20 53 65 74 75 70 20 53 65 74 75 70 20 44 61 74 61 20 28 35 ...
= "Inno Setup Setup Data (5..."
```

#### [HIGH_CONFIDENCE] rDlPtS block (older Inno 1.x–4.x)

```
72 44 6C 50 74 53  ("rDlPtS") — Inno Setup 1.x–4.x data block identifier
```

#### [HEURISTIC] VersionInfo Strings

```
Comments: "This installation was built with Inno Setup."  (often present)
```

FileDescription is user-set; OriginalFilename is often "setup.exe" (not unique).
**Reliable check is the overlay magic string, not VersionInfo.**

#### [HIGH_CONFIDENCE] 7-Zip `Type =` output

```
Type = Inno
```

7-Zip has a dedicated InnoSetup handler (`CPP/7zip/Archive/InnoHandler.cpp`).
Lists files with `{app}\`, `{tmp}\` path prefixes.

#### PE Sections

Standard only: `.text`, `.data`, `.rsrc`, `.reloc`. No special NSIS-like section.

```powershell
function Test-InnoSetup {
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $overlay = Get-PeOverlayOffset $Path
    if (-not $overlay.HasOverlay) { return $false }
    $headerBytes = $bytes[$overlay.OverlayOffset..($overlay.OverlayOffset + 63)]
    $headerStr = [System.Text.Encoding]::ASCII.GetString($headerBytes)
    return $headerStr -match "Inno Setup Setup Data"
}
```

**Source**: innoextract — https://github.com/dscharrer/innoextract
Official Inno Setup — https://jrsoftware.org/isinfo.php

### 2.3 InstallShield

#### [HIGH_CONFIDENCE] VersionInfo Strings

```
ProductName:  contains "InstallShield"  (present in most bootstrappers)
CompanyName:  "Flexera Software LLC" or "Acresso Software Inc." or
              "Macrovision Corporation" or "InstallShield Software Corporation"
LegalCopyright: contains "Flexera Software" or predecessors
OriginalFilename: often "Setup.exe" or "ISSetup.exe"
```

`ProductName` containing "InstallShield" is the **primary HIGH_CONFIDENCE** VersionInfo marker.

#### [HIGH_CONFIDENCE] Resource Marker

```
Resource type "SETUP" contains stream beginning with: 49 53 53 45 54 55 50 00 = "ISSETUP\0"
```

InstallShield packages also commonly embed CAB files as resources with type `CABINET` or resource ID 0.
The CAB `MSCF` signature appears within the `.rsrc` section.

#### [HIGH_CONFIDENCE] Internal Strings

```
"_ISMSIDLLS"  — InstallShield merge module marker
"ISSetup.dll" — InstallShield setup DLL name (literal)
"_SETUP.DLL"
"setup.lid"   — Language ID file
```

#### 7-Zip `Type =` output

```
Type = Compound   (for MSI-wrapped InstallShield packages)
Type = PE         (for pure bootstrapper EXE — 7z cannot extract)
```

InstallShield cabinet files use a proprietary CAB format handled by `i6comp`/`i5comp`, not 7-Zip.

### 2.4 WiX Toolset / MSI Burn Bootstrapper

#### [HIGH_CONFIDENCE] WiX Burn — PE Section Name

```
Section name: ".wixburn"  (8 bytes null-padded: 2E 77 69 78 62 75 72 6E 00 00)
```

This section contains the Burn manifest in structured binary format.

#### [HIGH_CONFIDENCE] WiX Burn — Resource Name

```
Resource type RT_RCDATA, name "WIXBURN_MANIFEST"  (definitive)
Resource type "WIXBURN" may also be present
```

**Source**: WiX toolset source `src/burn/engine/section.h`:

```c
#define BURN_SECTION_NAME ".wixburn"
```

https://github.com/wixtoolset/wix/

#### [HIGH_CONFIDENCE] MSI Detection (OLE Compound File)

```
Signature: D0 CF 11 E0 A1 B1 1A E1  (8 bytes at offset 0 of any MSI stream)
```

If this signature appears in an EXE overlay, the EXE contains an embedded MSI.

#### 7-Zip `Type =` output

```
Type = Msi       (for .msi files — 7z can extract MSI tables and streams)
Type = PE        (for WiX Burn bootstrapper EXE — 7z treats as PE)
Type = Compound  (for OLE2 compound files)
```

### 2.5 Advanced Installer

#### [HIGH_CONFIDENCE] VersionInfo

```
CompanyName: "Caphyon"  — definitive marker for Advanced Installer-built packages
ProductName: "Advanced Installer"
```

**Source**: Caphyon Advanced Installer output analysis (verityvulture evidence map).

#### [HIGH_CONFIDENCE] Internal String

```
"AI_SetupDir"   — resource identifier string embedded in binary
"Advanced Installer"  — appears in binary text/resources
```

#### 7-Zip `Type =` output

```
Type = Inno   (if using Inno Setup backend — common)
Type = PE     (for native AI bootstrapper)
Type = Nsis   (if using NSIS backend)
```

Advanced Installer can generate NSIS-based, Inno-based, or proprietary installers.

### 2.6 InstallAware

#### [HIGH_CONFIDENCE] VersionInfo

```
FileDescription: contains "InstallAware"
CompanyName:     "InstallAware Software Corporation"
ProductName:     contains "InstallAware"
```

#### [HEURISTIC] Section Names

InstallAware uses a proprietary compression scheme; may have `.iobj` or other custom sections.

#### 7-Zip `Type =`

```
Type = PE  (no dedicated handler; not extractable via 7z)
```

### 2.7 Smart Install Maker

#### [HEURISTIC] VersionInfo

```
ProductName:  "Smart Install Maker"  (in default builds)
CompanyName:  "Inf Solution" or custom (NOT "Nico Mak Computing" — that is WinZip)
```

**Note**: "Nico Mak Computing" is WinZip's parent company — do not confuse.

#### Internal String

```
"Smart Install Maker"  — appears in `.text` or `.rsrc` section data
```

### 2.8 CreateInstall

#### [HEURISTIC] VersionInfo

```
CompanyName: "Gentee, Inc."
ProductName: "CreateInstall"
```

#### Internal Marker

```
"CREATEINSTALL" or "CreateInstall"  — literal string in binary
```

### 2.9 Actual Installer

#### [HEURISTIC] VersionInfo

```
Comments:    "Created by Actual Installer"  (default branding)
CompanyName: "Actual Installer"
ProductName: user-set
```

### 2.10 Squirrel (GitHub/Electron Update Framework)

#### [HIGH_CONFIDENCE] Internal Strings

```
"Squirrel.Windows"     — literal string
"--squirrel-install"   — argument string in binary
```

Used by GitHub Desktop, Slack (older), Discord.
VersionInfo FileDescription is often "Setup" (very generic — not reliable alone).

### 2.11 Installer Framework Detection Summary Table

| Framework           | Section Name | VersionInfo Marker (HIGH_CONF)            | Internal / Resource Marker         | 7z Type=         |
| ------------------- | ------------ | ----------------------------------------- | ---------------------------------- | ---------------- |
| NSIS                | `.ndata`     | FileDesc: "Nullsoft Install System"       | `EF BE AD DE` in .ndata/.rsrc      | `Nsis`           |
| Inno Setup          | Standard     | Comments: "built with Inno Setup" [HEUR]  | "Inno Setup Setup Data" in overlay | `Inno`           |
| InstallShield       | Standard     | ProductName: contains "InstallShield"     | `ISSETUP\0` resource; `_ISMSIDLLS` | `Compound`/`PE`  |
| WiX Burn            | `.wixburn`   | (developer-set)                           | `WIXBURN_MANIFEST` resource        | `PE` (wrapper)   |
| MSI (pure)          | N/A          | N/A (not EXE)                             | `D0 CF 11 E0` at byte 0            | `Msi`/`Compound` |
| Advanced Installer  | Standard     | CompanyName: "Caphyon"                    | "AI_SetupDir" string               | `Inno`/`PE`      |
| InstallAware        | Custom       | CompanyName: "InstallAware Software Corp" | Internal strings                   | `PE`             |
| Smart Install Maker | Standard     | ProductName: "Smart Install Maker"        | "Smart Install Maker" string       | `PE`             |
| CreateInstall       | Standard     | CompanyName: "Gentee, Inc."               | "CREATEINSTALL" string             | `PE`             |
| Squirrel            | Standard     | FileDesc: "Setup" [HEUR]                  | "Squirrel.Windows" string          | `PE`             |
| WinRAR SFX          | Standard     | ProductName: "WinRAR"                     | RAR sig in overlay                 | `Rar`/`Rar5`     |
| 7-Zip SFX           | Standard     | CompanyName: "Igor Pavlov"                | `37 7A BC AF 27 1C` in overlay     | `7z`             |
| WinZip SFX          | Standard     | FileDesc: "WinZip Self-Extractor"         | ZIP EOCD in overlay                | `Zip`            |
| IExpress            | Standard     | ProductName: "IExpress"                   | `MSCF` in .rsrc or overlay         | `Cab`            |

---

## 3. SCRIPT-TO-EXE WRAPPER DETECTION

### 3.1 ps2exe (PowerShell to EXE)

**Maintained variants**:

- Ingo Karstein original (2014) / Markus Scholtes fork (active): https://github.com/MScholtes/PS2EXE

**Extractable**: NO (via 7-Zip). Requires ILSpy/dnSpy or .NET reflection.

#### [HIGH_CONFIDENCE] .NET Assembly + mscoree.dll Import

ps2exe produces .NET assemblies. The PE imports `mscoree.dll` with function `_CorExeMain`.

```
Import: mscoree.dll -> _CorExeMain
```

Additionally: `IMAGE_DIRECTORY_ENTRY_COM_DESCRIPTOR` (data directory index 14) is non-zero (see §4).

#### [HIGH_CONFIDENCE] Embedded Script Resource

The PowerShell script is compiled into a .NET assembly as an embedded managed resource:

- Markus Scholtes version: resource named `"$PS2EXE_SCRIPT"` or similar pattern
- General pattern: resource matching `ps2exe`, `Script`, `.ps1`, or `SCRIPT`
- Assembly references include `System.Management.Automation` (the PS engine)

```powershell
function Test-IsPs2exe {
    param([string]$Path)
    try {
        $asm = [System.Reflection.Assembly]::ReflectionOnlyLoadFrom($Path)
        $resources = $asm.GetManifestResourceNames()
        $hasPsScript = $resources | Where-Object { $_ -match 'ps2exe|Script|\.ps1|SCRIPT' }
        return [PSCustomObject]@{
            IsPs2exe   = ($null -ne $hasPsScript -and @($hasPsScript).Count -gt 0)
            Confidence = if ($hasPsScript) {'HIGH_CONFIDENCE'} else {'HEURISTIC'}
            Resources  = $resources
        }
    } catch { return [PSCustomObject]@{ IsPs2exe=$false; Error=$_.Exception.Message } }
}
```

**Note**: `ReflectionOnlyLoadFrom` is deprecated in .NET 5+. Use `MetadataLoadContext` instead (see §4.6).

#### [HEURISTIC] VersionInfo

No fixed fingerprint — authors customize freely. Default FileVersion is often "0.0.0.0".

#### 7-Zip `Type =`

```
Type = PE  (not extractable via 7z; .NET metadata sections shown as PE paths)
```

### 3.2 AutoIt Compiled Scripts (Aut2Exe)

**Extractable**: NO (via 7-Zip). Requires Exe2Aut (https://exe2aut.com/) or myAut2Exe.

#### [HIGH_CONFIDENCE] Compiled Script Block Magic

The compiled script block appears in the PE overlay or `.rsrc` section:

```
AU3!EA06 = 41 55 33 21 45 41 30 36  (8 bytes, AutoIt v3 primary signature)
```

Older versions:

```
AU3!EA05 = 41 55 33 21 45 41 30 35  (AutoIt v3 older)
AU3!EA02 = 41 55 33 21 45 41 30 32  (AutoIt v2)
```

The 4-byte prefix `41 55 33 21` ("AU3!") also appears at the start of the RCDATA resource.

**Source**: AutoIt v3 reverse engineering community; AutoIt documentation. The `AU3!EA06` signature
is not in official docs but is confirmed across multiple independent analyses.

#### [HIGH_CONFIDENCE] Resource Pattern

```
Resource type: RT_RCDATA (type 10 = 0x0A)
Resource name: "SCRIPT" or ">AUTOIT SCRIPT<" pattern
```

#### [HIGH_CONFIDENCE] VersionInfo (default — frequently overridden)

```
FileDescription: "AutoIt v3 Script"
ProductName:     "AutoIt v3 Script"
CompanyName:     "AutoIt Team"
LegalCopyright:  "(c)20xx:  Jonathan Bennett & AutoIt Team"
OriginalFilename: "AutoIt3.exe" or the compiled script name
```

#### [HIGH_CONFIDENCE] Definitive Binary String

```
"This is a compiled AutoIt script. AV researchers see: www.autoitscript.com/antivirus"
```

This exact string appears verbatim in the `.text` section of all Aut2Exe compiled scripts.

#### Import Table

AutoIt: `kernel32.dll`, `user32.dll`, `gdi32.dll`, `comctl32.dll`; often `oleaut32.dll`, `ole32.dll`.
Does NOT import `mscoree.dll`.

### 3.3 AutoHotkey Compiled Scripts

**Extractable**: NO (via 7-Zip). Requires AHK decompiler (Exe2Ahk or resource extraction).

#### [HIGH_CONFIDENCE] Resource Containing Script

```
Resource type: RT_RCDATA (10)
Resource name: ">AUTOHOTKEY SCRIPT<"  (literal string, exact match)
```

#### [HIGH_CONFIDENCE] VersionInfo (default — overridable)

```
OriginalFilename: "AutoHotkey.exe"  (v1) or "AutoHotkey64.exe" (v2)  — very reliable
FileDescription:  "AutoHotkey"
CompanyName:      "AutoHotkey Foundation LLC" (v2) or "AutoHotkey.com" (v1)
ProductName:      "AutoHotkey"
```

#### Import Table

`kernel32.dll`, `user32.dll`, `gdi32.dll`, `comctl32.dll`, `comdlg32.dll`. No `mscoree.dll`.

### 3.4 PyInstaller

**Extractable**: Partial — requires `pyinstxtractor` (https://github.com/extremecoders-re/pyinstxtractor).
7-Zip reports `Type = PE` and cannot extract the PKG archive.

#### [HIGH_CONFIDENCE] CArchive PKG Trailer Magic

PyInstaller appends a CArchive (PKG format) to the bootloader PE. The PKG magic is at a
**fixed 24-byte trailer** near EOF:

```
Magic: 4D 45 49 0C 0B 0A 0B 0E  (8 bytes: "MEI\x0c\x0b\x0a\x0b\x0e")
```

PKG cookie structure (24 bytes from end of archive):

```
Offset  Size  Field
0       8     magic: 4D 45 49 0C 0B 0A 0B 0E
8       4     pkg_length (total size of PKG archive)
12      4     toc_offset (Table of Contents offset from archive start)
16      4     toc_length
20      4     py_version (major*10 + minor, e.g., 38 for Python 3.8)
```

**Source**: PyInstaller bootloader source `bootloader/src/pyi_archive.c`:

```c
#define MAGIC "MEI\014\013\012\013\016"
```

https://github.com/pyinstaller/pyinstaller

**CONFLICT RESOLVED**: verityfactseeker listed `4D 45 49 00 00 00 00 00` — this is INCORRECT.
The authoritative verityvulture source (direct from bootloader C source) gives `4D 45 49 0C 0B 0A 0B 0E`.

Scan the **last 4,096 bytes** (not exact EOF - 24) to handle alignment variations across versions.

```powershell
function Test-IsPyInstaller {
    param([string]$Path)
    $magic = [byte[]](0x4D,0x45,0x49,0x0C,0x0B,0x0A,0x0B,0x0E)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $startPos = [Math]::Max(0, $bytes.Length - 4096)
    for ($i = $startPos; $i -le $bytes.Length - 8; $i++) {
        $match = $true
        for ($j = 0; $j -lt 8; $j++) { if ($bytes[$i+$j] -ne $magic[$j]) { $match=$false; break } }
        if ($match) {
            $pkgLen = [BitConverter]::ToUInt32($bytes, $i + 8)
            $pyVer  = [BitConverter]::ToUInt32($bytes, $i + 20)
            return [PSCustomObject]@{ Found=$true; Offset=$i; PkgLength=$pkgLen; PyVersionCode=$pyVer; Confidence='HIGH_CONFIDENCE' }
        }
    }
    return [PSCustomObject]@{ Found=$false }
}
```

#### [HIGH_CONFIDENCE] Binary Strings

```
"_MEIPASS"                       — PyInstaller temp directory name (always present)
"pyi-windows-manifest-filename"  — PyInstaller manifest injection string
"PyInstaller:"                   — appears in --version output string embedded in binary
```

#### 7-Zip `Type =`

```
Type = PE  (bootloader is a small C stub; PKG archive not recognized by 7z)
```

The PKG archive requires `pyinstxtractor.py` or `pyi-archive-viewer` (included with PyInstaller).

### 3.5 cx_Freeze

**Extractable**: NO (stub EXE is a thin launcher; real content in DLLs alongside it).

#### [HEURISTIC] Detection

cx_Freeze creates a **directory** structure, not typically a single EXE with embedded archive.

```
Imports: python3X.dll  (explicit import, visible in import table)
Strings: "cx_Freeze", "bootstrap"
```

When ZIP-mode is enabled: creates `library.zip` alongside the EXE — not embedded in the EXE.
If single EXE with embedded ZIP is found: scan for ZIP signatures (py stdlib may be ZIP-compressed).

### 3.6 Nuitka

**Extractable**: NO — compiled native C code. Requires Ghidra/IDA Pro.

#### [HEURISTIC] Detection

```
Imports: python3X.dll (explicit or static link) OR standard MSVCRT only
Strings: "NUITKA_VERSION"  (env variable name injected into binary)
         "__compiled__"    (Nuitka-injected attribute name)
         "nuitka"          (may appear in metadata strings)
```

Nuitka compiles Python → C → native machine code. No bytecode to extract.

### 3.7 pkg (Node.js / Vercel)

**Extractable**: Partial — VFS ZIP in overlay is technically extractable, but contents are compiled `.node` modules.

#### [HIGH_CONFIDENCE] Internal Strings

Vercel pkg:

```
"/snapshot/"             — virtual filesystem path prefix
"PKG_PAYLOAD_POSITION"   — environment variable name (trailer)
"pkg/payload"            — payload identifier string
```

Node.js SEA (Single Executable Application, Node 18+):

```
"SEA_FUSE_fce680ab2cc467b6e072b8b5df1996b2"  — Node.js SEA fuse string [DEFINITIVE]
"NODE_SEA_BLOB"                               — SEA blob name
```

**Source**: https://nodejs.org/api/single-executable-applications.html;
Node.js SEA fuse: https://github.com/nodejs/node/blob/main/src/node_sea.h

#### Overlay

pkg appends the Node.js runtime and payload ZIP to the EXE overlay. The ZIP can be detected
with the ZIP EOCD scan. 7-Zip may extract virtual filesystem paths (`/snapshot/...`).

### 3.8 Electron (ASAR packed)

**Extractable**: YES — ASAR format; use `npx asar extract app.asar output/`.

#### [HIGH_CONFIDENCE] ASAR Magic Bytes

ASAR is a pickle-based format. Header structure:

```
Bytes 0–3:   04 00 00 00  (uint32 LE = 4, header size indicator)
Bytes 4–7:   XX XX XX XX  (size of header JSON pickle)
Bytes 8–11:  XX XX XX XX  (pickle size again)
Bytes 12–15: XX XX XX XX  (JSON string length)
Bytes 16+:   {"files":{   (JSON header data starts here)
```

Scan for `04 00 00 00` followed within 20 bytes by `{"files":`.

For Electron EXEs, ASAR is typically in `resources/app.asar` **alongside** the EXE.
In single-file builds (electron-builder portable), ASAR may be embedded in the EXE overlay.

#### [HIGH_CONFIDENCE] Binary Strings

```
"ELECTRON_RUN_AS_NODE"    — environment variable (always present)
"--type=renderer"         — Chromium argument
"Chromium"                — embedded in binary
"v8_context_snapshot"     — V8 snapshot reference
"app.asar"                — path string (if hardcoded)
```

#### 7-Zip `Type =`

```
Type = PE  (standard PE analysis; ASAR not understood by 7z directly)
```

### 3.9 Go Compiled Binaries

**Extractable**: NO — compiled native code. Requires Ghidra/Binary Ninja.

#### [HIGH_CONFIDENCE] Import Table

```
kernel32.dll ONLY  (or kernel32 + ntdll + ws2_32 for network programs)
```

No C runtime, no VCRUNTIME. Minimal imports are a strong Go indicator.
A binary with ONLY `kernel32.dll` is very likely Go or a hand-crafted/packed binary.

#### [HIGH_CONFIDENCE] Go Build Info Magic

```
"\xff Go buildinf:"  = FF 20 47 6F 20 62 75 69 6C 64 69 6E 66 3A  (14 bytes)
```

Located in `.data` or `.rodata` section.
**Source**: Go toolchain `cmd/link`; also `debug/buildinfo` package in Go stdlib.

#### [HIGH_CONFIDENCE] `.go.buildinfo` PE Section (Go 1.13+)

```
Section name: ".go.buildinfo"  (14 bytes + null padding)
```

This section contains: Go version string, module path, build settings.
Definitive Go binary indicator (added Go 1.13+).
**Source**: Go 1.13 release notes; `go version -m <binary>` behavior.

#### [MEDIUM_CONFIDENCE] Additional Go Section Names

```
.noptrdata  — Go no-pointer data section
.noptrbss   — Go no-pointer BSS section
```

These section names are Go-specific but less universally present than `.go.buildinfo`.

```powershell
function Test-IsGoBinary {
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    # Check for .go.buildinfo section name (most reliable)
    $goSig = [System.Text.Encoding]::ASCII.GetBytes('.go.buildinfo')
    for ($i = 0; $i -lt $bytes.Length - $goSig.Length; $i++) {
        $match = $true
        for ($j = 0; $j -lt $goSig.Length; $j++) { if ($bytes[$i+$j] -ne $goSig[$j]) {$match=$false;break} }
        if ($match) { return [PSCustomObject]@{ IsGo=$true; SigOffset=$i; Confidence='HIGH_CONFIDENCE' } }
    }
    # Fallback: check for Go buildinf magic
    $magic = [byte[]](0xFF,0x20,0x47,0x6F,0x20,0x62,0x75,0x69,0x6C,0x64,0x69,0x6E,0x66,0x3A)
    for ($i = 0; $i -lt $bytes.Length - $magic.Length; $i++) {
        $match = $true
        for ($j = 0; $j -lt $magic.Length; $j++) { if ($bytes[$i+$j] -ne $magic[$j]) {$match=$false;break} }
        if ($match) { return [PSCustomObject]@{ IsGo=$true; SigOffset=$i; Confidence='HIGH_CONFIDENCE'; Method='buildinf_magic' } }
    }
    return [PSCustomObject]@{ IsGo=$false }
}
```

### 3.10 Rust Compiled Binaries

**Extractable**: NO — compiled native code. Requires Ghidra/IDA Pro.

#### [HIGH_CONFIDENCE] Panic String

```
"panicked at"  — Rust panic message (literal, always present in Rust binaries)
"called `Option::unwrap()` on a `None` value"  — very distinctive Rust string
```

#### [HEURISTIC] Import Table

```
MSVC toolchain: kernel32.dll, VCRUNTIME140.dll, api-ms-win-crt-*.dll (UCRT chain)
GNU/MinGW:      kernel32.dll, msvcrt.dll
```

### 3.11 Script-to-EXE Detection Summary Table

| Tool        | Magic/Binary Marker                         | VersionInfo Default                | .NET? | Extractable?             |
| ----------- | ------------------------------------------- | ---------------------------------- | ----- | ------------------------ |
| ps2exe      | mscoree.dll import; COM_DESCRIPTOR non-zero | Custom (blank defaults)            | YES   | NO (needs ILSpy)         |
| AutoIt      | `41 55 33 21 45 41 30 36` in overlay/rsrc   | "AutoIt v3 Script" / "AutoIt Team" | NO    | NO (needs Exe2Aut)       |
| AutoHotkey  | `>AUTOHOTKEY SCRIPT<` resource name         | OriginalFilename="AutoHotkey.exe"  | NO    | NO (needs Exe2Ahk)       |
| PyInstaller | `4D 45 49 0C 0B 0A 0B 0E` near EOF          | Custom (none by default)           | NO    | Partial (pyinstxtractor) |
| cx_Freeze   | python3X.dll import                         | Custom                             | NO    | NO (stub EXE)            |
| Nuitka      | "NUITKA_VERSION" string; python3X.dll [opt] | Custom                             | NO    | NO (compiled native)     |
| pkg (Node)  | "PKG_PAYLOAD_POSITION"; "/snapshot/"        | Custom                             | NO    | Partial (ZIP in overlay) |
| Electron    | "ELECTRON_RUN_AS_NODE" string               | App-specific                       | NO    | YES (ASAR tool)          |
| Go          | FF 20 47 6F... ; `.go.buildinfo` section    | None                               | NO    | NO (compiled native)     |
| Rust        | "panicked at" string                        | None                               | NO    | NO (compiled native)     |

---

## 4. .NET ASSEMBLY DETECTION

### 4.1 CLI Header Location (Exact Byte Offsets)

The .NET CLI header (`IMAGE_COR20_HEADER`, also called `COM_DESCRIPTOR`) is found via data
directory index 14 in the PE Optional Header.

**Step-by-step offset calculation**:

```
File[0x00]         = 4D 5A  (MZ)
File[0x3C..0x3F]   = DWORD e_lfanew (PeOffset)

File[PeOffset+0..3]   = 50 45 00 00  (PE\0\0)
File[PeOffset+4]      = IMAGE_FILE_HEADER (20 bytes total):
  [+0]  Machine          : WORD
  [+2]  NumberOfSections : WORD
  [+4]  TimeDateStamp    : DWORD
  [+8]  PtrToSymTable    : DWORD
  [+12] NumSymbols       : DWORD
  [+16] SizeOfOptHeader  : WORD   <-- read this
  [+18] Characteristics  : WORD

IMAGE_OPTIONAL_HEADER begins at: PeOffset + 4 + 20 = PeOffset + 24
  [+0]  Magic: WORD
        0x010B = PE32   (32-bit)
        0x020B = PE32+  (64-bit)
```

**For PE32 (Magic = 0x010B)**:

```
Optional header data directories start at: PeOffset + 24 + 96 = PeOffset + 120
COM_DESCRIPTOR entry (index 14, 8 bytes each):
  RVA:  File[PeOffset + 24 + 96  + (14 * 8) + 0] = File[PeOffset + 232]
  Size: File[PeOffset + 24 + 96  + (14 * 8) + 4] = File[PeOffset + 236]
```

**For PE32+ (Magic = 0x020B)**:

```
Optional header data directories start at: PeOffset + 24 + 112 = PeOffset + 136
COM_DESCRIPTOR entry:
  RVA:  File[PeOffset + 24 + 112 + (14 * 8) + 0] = File[PeOffset + 248]
  Size: File[PeOffset + 24 + 112 + (14 * 8) + 4] = File[PeOffset + 252]
```

**Interpretation**:

```
If RVA == 0 AND Size == 0:  NOT a .NET assembly
If RVA != 0 AND Size >= 72: IS a .NET assembly  [HIGH_CONFIDENCE]
```

**Source**: ECMA-335 §25.3.3; Microsoft PE/COFF Specification v14.0 §6.1.3.3
https://www.ecma-international.org/publications-and-standards/standards/ecma-335/
https://docs.microsoft.com/en-us/windows/win32/debug/pe-format

### 4.2 IMAGE_COR20_HEADER Structure

```c
typedef struct IMAGE_COR20_HEADER {
    DWORD  cb;                         // [+0]  Must be >= 72
    WORD   MajorRuntimeVersion;        // [+4]  e.g., 2
    WORD   MinorRuntimeVersion;        // [+6]  e.g., 5
    DWORD  MetaDataRVA;                // [+8]  RVA of .NET metadata root
    DWORD  MetaDataSize;               // [+12]
    DWORD  Flags;                      // [+16] COMIMAGE_FLAGS_*
    DWORD  EntryPointTokenOrRVA;       // [+20]
    DWORD  ResourcesRVA;               // [+24]
    DWORD  ResourcesSize;              // [+28]
    DWORD  StrongNameSignatureRVA;     // [+32]
    DWORD  StrongNameSignatureSize;    // [+36]
    DWORD  CodeManagerTableRVA;        // [+40] (reserved)
    DWORD  CodeManagerTableSize;       // [+44]
    DWORD  VTableFixupsRVA;            // [+48]
    DWORD  VTableFixupsSize;           // [+52]
    DWORD  ExportAddressTableJumpsRVA; // [+56] (reserved)
    DWORD  ExportAddressTableJumpsSize;// [+60]
    DWORD  ManagedNativeHeaderRVA;     // [+64] (reserved)
    DWORD  ManagedNativeHeaderSize;    // [+68]
} IMAGE_COR20_HEADER;  // Total: 72 bytes minimum
```

**Flags field** (COMIMAGE_FLAGS):

```
0x00000001  COMIMAGE_FLAGS_ILONLY           — Pure IL (no native code)
0x00000002  COMIMAGE_FLAGS_32BITREQUIRED    — 32-bit only
0x00000004  COMIMAGE_FLAGS_IL_LIBRARY       — DLL, not EXE
0x00000008  COMIMAGE_FLAGS_STRONGNAMESIGNED — Has strong name
0x00000010  COMIMAGE_FLAGS_NATIVE_ENTRYPOINT— Native entry point (mixed mode)
0x00010000  COMIMAGE_FLAGS_TRACKDEBUGDATA
0x00020000  COMIMAGE_FLAGS_PREFER32BIT      — Prefer 32-bit
```

### 4.3 .NET Metadata Root Signature

The .NET metadata root begins at MetaDataRVA and starts with:

```
42 53 4A 42  ("BSJB")  [HIGH_CONFIDENCE]
```

This 4-byte "BSJB" magic identifies the .NET metadata root. Scanning a .NET assembly's `.text`
section for this 4-byte sequence will locate the metadata root.

### 4.4 PowerShell .NET Detection (Raw PE Method — Safe for Untrusted Binaries)

```powershell
function Test-DotNetAssembly {
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 64 -or $bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) {
        return [PSCustomObject]@{IsDotNet=$false; Reason="Not a PE file"}
    }
    $peOffset = [BitConverter]::ToUInt32($bytes, 0x3C)
    if ($bytes[$peOffset+0] -ne 0x50 -or $bytes[$peOffset+1] -ne 0x45 -or
        $bytes[$peOffset+2] -ne 0x00 -or $bytes[$peOffset+3] -ne 0x00) {
        return [PSCustomObject]@{IsDotNet=$false; Reason="No PE signature"}
    }
    $optHeaderOffset = $peOffset + 24
    $optMagic = [BitConverter]::ToUInt16($bytes, $optHeaderOffset)
    $comDirOffset = if ($optMagic -eq 0x010B) {  # PE32
        $optHeaderOffset + 96 + (14 * 8)
    } elseif ($optMagic -eq 0x020B) {             # PE32+
        $optHeaderOffset + 112 + (14 * 8)
    } else {
        return [PSCustomObject]@{IsDotNet=$false; Reason="Unknown PE magic: 0x$("{0:X4}" -f $optMagic)"}
    }
    if ($comDirOffset + 8 -ge $bytes.Length) {
        return [PSCustomObject]@{IsDotNet=$false; Reason="COM_DESCRIPTOR out of range"}
    }
    $comRVA  = [BitConverter]::ToUInt32($bytes, $comDirOffset)
    $comSize = [BitConverter]::ToUInt32($bytes, $comDirOffset + 4)
    $isDotNet = ($comRVA -ne 0 -and $comSize -ge 72)
    return [PSCustomObject]@{
        IsDotNet   = $isDotNet
        ComRVA     = "0x{0:X8}" -f $comRVA
        ComSize    = $comSize
        PEMagic    = if ($optMagic -eq 0x010B) {"PE32"} else {"PE32+"}
        Confidence = if ($isDotNet) {"HIGH_CONFIDENCE"} else {"HIGH_CONFIDENCE_NEGATIVE"}
    }
}
```

### 4.5 Easier Method: AssemblyName (Loads Metadata — Not for Untrusted Files)

```powershell
try {
    $asmName = [System.Reflection.AssemblyName]::GetAssemblyName($exePath)
    # Success: definitely a .NET assembly [HIGH_CONFIDENCE]
    # Returns: Name, Version, Culture, GetPublicKeyToken()
} catch [System.BadImageFormatException] {
    # NOT a .NET assembly
} catch [System.IO.FileLoadException] {
    # Could be .NET but policy blocked loading
}
```

**Caveat**: This loads file metadata into the AppDomain. For untrusted binaries, prefer the
raw byte-offset method in §4.4.

### 4.6 MetadataLoadContext (.NET 5+ — Replacement for ReflectionOnlyLoadFrom)

```powershell
# .NET 5+ safe reflection (ReflectionOnlyLoadFrom is deprecated/throws in .NET 5+)
Add-Type -AssemblyName System.Reflection.MetadataLoadContext
$resolver = [System.Reflection.PathAssemblyResolver]::new([string[]]@($Path))
$ctx = [System.Reflection.MetadataLoadContext]::new($resolver)
$asm = $ctx.LoadFromAssemblyPath($Path)
$resourceNames = $asm.GetManifestResourceNames()
$ctx.Dispose()
```

**Source**: https://docs.microsoft.com/en-us/dotnet/api/system.reflection.metadataloadcontext

### 4.7 Distinguishing .NET Wrapper vs Extractable .NET Deployment

#### ps2exe / Script Wrapper .NET [NOT Extractable]

- COM_DESCRIPTOR populated (IsDotNet=true)
- Single EXE, small (10 KB–500 KB typically)
- Imports ONLY `mscoree.dll`
- `GetManifestResourceNames()` returns 1–3 resources; one matches `SCRIPT`/`ps2exe`
- Assembly references include `System.Management.Automation`

#### ClickOnce [NOT Embedded — Downloads Payload]

- Imports `dfshim.dll` (ClickOnce deployment shim) [HIGH_CONFIDENCE]
- VersionInfo `Comments` often contains "ClickOnce"
- The actual payload is NOT embedded in the EXE; it is a network launcher

#### .NET Single-File Bundle (.NET 5+) [Extractable via dotnet-bundle-extract]

`dotnet publish --self-contained true --single-file true` embeds all DLLs as resources.

Detection signatures — two complementary methods:

**Method A** — ASCII string embedded in binary [HIGH_CONFIDENCE]:

```
".NET Bundle"  = 2E 4E 45 54 20 42 75 6E 64 6C 65  (11 bytes, near EOF)
```

Bundle GUID string also present: `"6b6f9bd7-da7b-4cc3-8e3e-e18e64949b88"`

**Method B** — 32-byte BundleSignature near EOF [HIGH_CONFIDENCE]:

```
8B 12 02 B9 6A 61 20 38 D6 AF 45 6E 60 F9 A4 98
89 9D 35 C2 0D 01 35 FD 90 5D 0F 00 20 60 91 50
```

**Source**: .NET runtime source `src/installer/managed/Microsoft.NET.HostModel/Bundle/Manifest.cs`:

```csharp
public static readonly byte[] BundleSignature = {
    0x8b, 0x12, 0x02, 0xb9, 0x6a, 0x61, 0x20, 0x38,
    0xd6, 0xaf, 0x45, 0x6e, 0x60, 0xf9, 0xa4, 0x98,
    0x89, 0x9d, 0x35, 0xc2, 0x0d, 0x01, 0x35, 0xfd,
    0x90, 0x5d, 0x0f, 0x00, 0x20, 0x60, 0x91, 0x50
};
```

https://github.com/dotnet/runtime/blob/main/src/installer/managed/Microsoft.NET.HostModel/Bundle/Manifest.cs

Scan last 1 MB for either signature.

`GetManifestResourceNames()` returns names like `"MyApp.dll"`, `"System.Text.Json.dll"`, etc.
These embedded DLLs **are extractable** via `GetManifestResourceStream` or `dotnet-bundle-extract`.

#### Costura.Fody [Extractable DLLs via ILSpy/dnSpy]

Costura.Fody embeds dependent DLLs as compressed .NET manifest resources:

```
Resource name pattern: costura.<assemblyname>.dll.compressed   [HIGH_CONFIDENCE]
                       costura.<assemblyname>.dll
```

`"costura."` prefix is Costura-specific. DLLs are GZip-compressed; extractable via reflection.
**Source**: https://github.com/Fody/Costura

---

## 5. 7-ZIP `7z l` OUTPUT PARSING

### 5.1 Complete Type= Value Reference

`7z l <file>` outputs `Type = <value>`. This value comes directly from the archive handler name.
**Source**: 7-Zip source `CPP/7zip/UI/Common/ArchiveCommandLine.cpp` and handlers in `CPP/7zip/Archive/`.

| Type= Value | Meaning                                 | Extractable?  | Notes                      |
| ----------- | --------------------------------------- | ------------- | -------------------------- |
| `PE`        | Windows PE (native/unrecognized format) | NO            | PE sections shown as paths |
| `7z`        | 7-Zip archive                           | YES           |                            |
| `Zip`       | ZIP / OOXML / JAR / APK                 | YES           |                            |
| `Rar`       | RAR v1.5–4.x                            | YES           |                            |
| `Rar5`      | RAR v5.0+                               | YES           |                            |
| `Cab`       | Microsoft Cabinet                       | YES           | Also: `expand.exe`         |
| `Iso`       | ISO 9660 / UDF disc image               | YES           |                            |
| `Msi`       | Windows Installer MSI (OLE2)            | YES           |                            |
| `Nsis`      | NSIS installer                          | YES           | Full file tree             |
| `Inno`      | Inno Setup installer                    | YES           | `{app}\` path prefixes     |
| `Compound`  | OLE2 Compound Document (generic)        | YES           | MSI, old Office docs       |
| `Wim`       | Windows Imaging Format                  | YES           | Also: DISM                 |
| `Tar`       | TAR archive                             | YES           |                            |
| `GZip`      | .gz                                     | YES           |                            |
| `BZip2`     | .bz2                                    | YES           |                            |
| `Xz`        | XZ / LZMA2 stream                       | YES           |                            |
| `Lzma`      | Raw LZMA stream                         | YES           |                            |
| `Lzma86`    | LZMA86 stream                           | YES           |                            |
| `Lzh`       | LHA/LZH archive                         | YES           |                            |
| `Arj`       | ARJ archive                             | YES           |                            |
| `Cpio`      | CPIO archive                            | YES           |                            |
| `Rpm`       | RPM package                             | YES           |                            |
| `Deb`       | Debian package                          | YES           |                            |
| `Dmg`       | Apple disk image                        | YES (limited) |                            |
| `Hfs`       | HFS/HFS+ filesystem                     | YES           |                            |
| `Udf`       | UDF filesystem                          | YES           |                            |
| `Fat`       | FAT filesystem image                    | YES           |                            |
| `Ntfs`      | NTFS filesystem image                   | YES           |                            |
| `SquashFs`  | SquashFS filesystem                     | YES           |                            |
| `Ext`       | ext2/3/4 filesystem                     | YES           |                            |
| `Swf`       | SWF Flash file                          | NO            | Analysis only              |
| `Swfc`      | Compressed SWF                          | Partial       |                            |
| `Ppmd`      | PPMd stream                             | YES           |                            |
| `Elf`       | ELF binary                              | NO            | Analysis only              |
| `Macho`     | Mach-O binary                           | NO            | Analysis only              |

**KEY RULE**: When 7-Zip opens an SFX .exe, it identifies the **inner** archive format and reports
THAT as Type= (not "SFX"). A WinRAR SFX shows `Type = Rar5`, a 7-Zip SFX shows `Type = 7z`,
an NSIS installer shows `Type = Nsis`, a plain PE shows `Type = PE`.

### 5.2 PE-Section Paths vs Real File Paths

When `Type = PE`, 7-Zip lists PE sections and resources as virtual paths — NOT real files:

**PE-section path patterns** (NOT real files):

```
.text              .rdata             .data              .rsrc
.reloc             .bss               .edata             .idata
.pdata             .tls               .debug             .ndata
.wixburn           UPX0               UPX1               UPX2
.rsrc\1\RT_ICON\1  .rsrc\1\VERSION\1  .rsrc\1\RT_RCDATA\SCRIPT
```

**Real file path patterns** (appear when 7-Zip recognizes an embedded archive format):

```
$PLUGINSDIR\InstallOptions.dll   (NSIS plugin)
{app}\program.exe                (Inno Setup {app} placeholder)
[TARGETDIR]\setup.ini            (InstallShield target)
install\file.cfg                 (general embedded file)
setup.exe                        (embedded executable)
```

**Decision rule**:

- If ALL paths match PE section patterns (`.`-prefixed or known section names) → `Type = PE` only, NOT extractable
- If paths include real-looking file names with extensions (`.dll`, `.exe`, `.cfg`, `.msi`) → extractable
- Exception: `.rsrc\1\RCDATA\<name>` can contain extractable resources

### 5.3 Nested Archive Inspection

7-Zip does NOT auto-recurse into nested archives in `7z l`. The `Type =` shows the outermost
recognized format.

To inspect nested content, use the `#` virtual path separator:

```cmd
7z l outer.exe#inner.zip
7z l outer.exe#archive.7z
```

To recursively list all nested:

```cmd
7z l -r installer.exe
```

**Note**: NSIS and Inno Setup 7z handlers DO partially unpack the installer and show inner files.

```powershell
function Get-7zType {
    param([string]$FilePath, [string]$SevenZipPath = "7z.exe")
    $result = & $SevenZipPath l $FilePath 2>&1 | Select-String "^Type\s*="
    if ($result) { return ($result.Line -split "=", 2)[1].Trim() }
    return $null
}

function Test-7zExtractable {
    param([string]$FilePath, [string]$SevenZipPath = "7z.exe")
    $nonExtractable = @("PE", "Elf", "Macho", "Swf", "Te", "Efi")
    $type = Get-7zType $FilePath $SevenZipPath
    if ($null -eq $type) { return $false }
    return ($type -notin $nonExtractable)
}
```

### 5.4 7-Zip Detection Behaviors by Framework

| Input                  | Type=            | Lists real files? | Notes                             |
| ---------------------- | ---------------- | ----------------- | --------------------------------- |
| NSIS .exe              | `Nsis`           | YES               | Full file tree (caveat: see §10)  |
| Inno .exe              | `Inno`           | YES               | {app}\ paths                      |
| 7z SFX .exe            | `7z`             | YES               | Archive contents                  |
| WinRAR SFX .exe        | `Rar`/`Rar5`     | YES               | Archive contents                  |
| WinZip SFX .exe        | `Zip`            | YES               | Archive contents                  |
| WinZip SFX .exe        | `Zip`            | YES               | Archive contents                  |
| InstallShield .exe     | `Compound`/`PE`  | Partial           | May need IS-specific tools        |
| WiX Burn .exe          | `PE`             | NO (sections)     | `.wixburn` present but not parsed |
| MSI .msi               | `Msi`/`Compound` | YES               | Tables and streams                |
| ps2exe .exe            | `PE`             | NO                | .NET sections only                |
| AutoIt .exe            | `PE`             | NO                | PE sections only                  |
| PyInstaller .exe       | `PE`             | NO                | Needs pyinstxtractor              |
| Native C++/Go/Rust EXE | `PE`             | NO                | PE sections only                  |

---

## 6. WINDOWS BUILT-IN DETECTION METHODS

### 6.1 System.Reflection.AssemblyName::GetAssemblyName()

```powershell
try {
    $asmName = [System.Reflection.AssemblyName]::GetAssemblyName($exePath)
    # SUCCESS = definitely a .NET assembly [HIGH_CONFIDENCE]
    $asmName.FullName          # "MyApp, Version=1.0.0.0, Culture=neutral, ..."
    $asmName.Version           # System.Version object
    $asmName.GetPublicKeyToken() # null = unsigned; non-null = strong-named
    $asmName.ProcessorArchitecture  # Amd64, X86, MSIL, etc.
} catch [System.BadImageFormatException] {
    # NOT a .NET assembly (or corrupt)
} catch [System.IO.FileLoadException] {
    # Could be .NET but policy blocked
}
```

**Caveat**: Loads metadata into AppDomain. Use raw PE method (§4.4) for untrusted binaries.

### 6.2 System.Diagnostics.FileVersionInfo::GetVersionInfo()

```powershell
$fvi = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($exePath)
$fvi | Select-Object `
    FileName, FileDescription, FileVersion, FileVersionRaw,
    ProductName, ProductVersion, ProductVersionRaw,
    CompanyName, LegalCopyright, LegalTrademarks,
    OriginalFilename, InternalName,
    Language, Comments, PrivateBuild, SpecialBuild,
    IsDebug, IsPatched, IsPreRelease, IsPrivateBuild, IsSpecialBuild
```

**What this reveals**: All VS_VERSION_INFO StringFileInfo strings. `OriginalFilename` is critical —
it often reveals the true product name (e.g., "AutoIt3.exe").
Works on ANY PE file (not just .NET). Returns empty strings (not null) for absent fields.
This is a **pure resource parse** — calls `GetFileVersionInfo` Win32 API on `.rsrc` section. Safe.

```powershell
function Get-InstallerFramework {
    param([string]$Path)
    $fvi = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($Path)
    $indicators = @()
    if ($fvi.FileDescription -match "Nullsoft|NSIS" -or $fvi.CompanyName -match "Nullsoft") {
        $indicators += "NSIS [HIGH_CONFIDENCE]"
    }
    if ($fvi.Comments -match "Inno Setup" -or $fvi.FileDescription -match "Inno Setup") {
        $indicators += "InnoSetup [HIGH_CONFIDENCE]"
    }
    if ($fvi.ProductName -match "InstallShield" -or
        $fvi.CompanyName -match "Flexera|Acresso|Macrovision|InstallShield") {
        $indicators += "InstallShield [HIGH_CONFIDENCE]"
    }
    if ($fvi.CompanyName -match "Caphyon") { $indicators += "AdvancedInstaller [HIGH_CONFIDENCE]" }
    if ($fvi.FileDescription -match "AutoIt|Aut2Exe" -or $fvi.CompanyName -match "AutoIt Team") {
        $indicators += "AutoIt [HIGH_CONFIDENCE]"
    }
    if ($fvi.ProductName -match "^AutoHotkey$" -or $fvi.OriginalFilename -match "AutoHotkey") {
        $indicators += "AutoHotkey [HIGH_CONFIDENCE]"
    }
    if ($fvi.FileDescription -match "7-Zip Self-extract" -or $fvi.CompanyName -match "Igor Pavlov") {
        $indicators += "7zSFX [HIGH_CONFIDENCE]"
    }
    if ($fvi.FileDescription -match "WinRAR self-extract" -or
        $fvi.CompanyName -match "win\.rar|Alexander Roshal" -or $fvi.ProductName -match "^WinRAR$") {
        $indicators += "WinRARSFX [HIGH_CONFIDENCE]"
    }
    if ($fvi.FileDescription -match "WinZip Self-Extractor" -or
        $fvi.CompanyName -match "WinZip|Corel Corporation") {
        $indicators += "WinZipSFX [HIGH_CONFIDENCE]"
    }
    if ($fvi.Comments -match "Advanced Installer") { $indicators += "AdvancedInstaller [HIGH_CONFIDENCE]" }
    return [PSCustomObject]@{
        Indicators       = $indicators
        FileDescription  = $fvi.FileDescription
        ProductName      = $fvi.ProductName
        CompanyName      = $fvi.CompanyName
        OriginalFilename = $fvi.OriginalFilename
        Comments         = $fvi.Comments
    }
}
```

### 6.3 ZIP Detection via System.IO.Compression (No Third-Party Tools)

```powershell
function Test-EmbeddedZipNative {
    param([string]$Path)
    Add-Type -AssemblyName System.IO.Compression
    # Method 1: ZipFile.OpenRead() uses EOCD scan internally — WILL find embedded ZIPs in SFX EXEs
    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
        $count = $zip.Entries.Count
        $zip.Dispose()
        return [PSCustomObject]@{ HasZip=$true; EntryCount=$count; Method="ZipFile.OpenRead"; Confidence="HIGH_CONFIDENCE" }
    } catch {}
    # Method 2: Manual EOCD scan
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $searchLen = [Math]::Min($bytes.Length, 65557)
    $searchStart = $bytes.Length - $searchLen
    for ($i = $bytes.Length - 22; $i -ge $searchStart; $i--) {
        if ($bytes[$i] -eq 0x50 -and $bytes[$i+1] -eq 0x4B -and
            $bytes[$i+2] -eq 0x05 -and $bytes[$i+3] -eq 0x06) {
            $commentLen = [BitConverter]::ToUInt16($bytes, $i + 20)
            if (($i + 22 + $commentLen) -eq $bytes.Length) {
                return [PSCustomObject]@{ HasZip=$true; EocdOffset=$i; Method="EOCD-scan"; Confidence="HIGH_CONFIDENCE" }
            }
        }
    }
    return [PSCustomObject]@{ HasZip=$false }
}
```

**Key behavior**: `ZipFile.OpenRead()` / `ZipArchive` use EOCD scanning internally — they search
backward from EOF. This means they WILL find a ZIP embedded in a PE's overlay automatically.

### 6.4 Shell.Application COM Object Extended Properties

```powershell
$shell = New-Object -ComObject Shell.Application
$folder = $shell.NameSpace((Split-Path $exePath -Parent))
$file = $folder.ParseName((Split-Path $exePath -Leaf))
$properties = @{}
for ($i = 0; $i -lt 50; $i++) {
    $name = $folder.GetDetailsOf($null, $i)
    $val  = $folder.GetDetailsOf($file, $i)
    if ($name -and $val) { $properties[$name] = $val }
}
```

**What this reveals**: File description, product name, company, file version, Authenticode status.
**Limitation**: Shell.Application is essentially a UI wrapper over the same data as FileVersionInfo.
Does NOT reveal archive type or SFX status beyond VersionInfo.
For some SFX types (WinRAR SFX), the `Type` shell property (index 9) may show "WinRAR SFX Archive".

### 6.5 expand.exe and extrac32.exe (Built-in CAB Detection)

Both tools are built into all Windows versions:

- `%SystemRoot%\System32\expand.exe`
- `%SystemRoot%\System32\extrac32.exe`

```powershell
function Test-ContainsCab {
    param([string]$Path)
    $expandExe = "$env:SystemRoot\System32\expand.exe"
    $result = & $expandExe "-D" $Path 2>&1
    return [PSCustomObject]@{
        HasCab     = ($LASTEXITCODE -eq 0)
        Contents   = $result
        Confidence = "HIGH_CONFIDENCE"
    }
}
```

**Scope**: Detects pure CABs, IExpress EXEs, some InstallShield packages, Windows hotfix/update EXEs.
**Does NOT detect**: 7-Zip, RAR, ZIP, NSIS/Inno Setup.

Both tools scan for `MSCF` anywhere in the file — they will find embedded CABs in EXEs.

### 6.6 .NET Reflection for Embedded Resource Inspection (No Execution)

```powershell
function Get-DotNetEmbeddedResources {
    param([string]$Path)
    try {
        # .NET 4.x: ReflectionOnlyLoadFrom (deprecated in .NET 5+)
        $asm = [System.Reflection.Assembly]::ReflectionOnlyLoadFrom($Path)
        $resources = $asm.GetManifestResourceNames()
        return [PSCustomObject]@{
            IsDotNet     = $true
            Resources    = $resources | ForEach-Object {
                $stream = $asm.GetManifestResourceStream($_)
                [PSCustomObject]@{
                    Name        = $_
                    Size        = if ($stream) { $stream.Length } else { 0 }
                    IsScript    = ($_ -match 'script|ps1|powershell|SCRIPT' -or $_ -match '\.ps1$')
                    IsDll       = ($_ -match '\.dll(\.compressed)?$')
                    IsCostura   = ($_ -match '^costura\.')
                }
            }
            AssemblyName = $asm.FullName
        }
    } catch {
        return [PSCustomObject]@{ IsDotNet=$false; Error=$_.Exception.Message }
    }
}
```

`ReflectionOnlyLoadFrom` does NOT execute code. Safe for static analysis on trusted files.
For .NET 5+, use `MetadataLoadContext` (see §4.6).

---

## 7. PE HEADER ANALYSIS FOR CLASSIFICATION

### 7.1 Import Table as Primary Classifier

The import table (data directory index 1) reveals which DLLs are statically linked.

#### [HIGH_CONFIDENCE] .NET Assembly

```
REQUIRED: mscoree.dll  —  _CorExeMain (EXE) or _CorDllMain (DLL)
```

No other common framework mandates `mscoree.dll`. Finding this import = .NET, guaranteed.

#### [HIGH_CONFIDENCE] Go Binary (gc toolchain)

```
Typically ONLY: kernel32.dll  (5–15 imports)
Sometimes:      ntdll.dll, ws2_32.dll (network programs)
NEVER:          mscoree.dll, VCRUNTIME140.dll, MSVCRT.dll, python3X.dll
```

Go runtime is statically compiled. Very few imports are a strong Go indicator.

#### [HIGH_CONFIDENCE] Delphi

```
REQUIRED: kernel32.dll, user32.dll, gdi32.dll
COMMON:   advapi32.dll
DLL mode: "rtl70.bpl", "vcl70.bpl" (dynamically-linked Borland/Embarcadero runtime)
STRINGS:  "Embarcadero", "Borland", "TApplication", "TForm" in binary
```

Also: `DVCLAL` resource in RT_RCDATA section — Delphi VCL Application License [HIGH_CONFIDENCE]:

```
Resource name: "DVCLAL"  in the RT_RCDATA section  [HIGH_CONFIDENCE — definitively Delphi]
```

Also: `PACKAGEINFO` resource for Delphi package-aware applications.

#### [HEURISTIC] Rust (MSVC toolchain)

```
COMMON:   kernel32.dll, VCRUNTIME140.dll, api-ms-win-crt-runtime-l1-1-0.dll (UCRT chain)
```

#### [HEURISTIC] Rust (GNU/MinGW toolchain)

```
COMMON:   kernel32.dll, msvcrt.dll
```

#### [HEURISTIC] C/C++ MSVC

```
COMMON:   kernel32.dll, user32.dll, VCRUNTIME140.dll, msvcp140.dll
```

#### NSIS Specific

```
REQUIRED: kernel32.dll, user32.dll
COMMON:   gdi32.dll, shell32.dll, advapi32.dll, ole32.dll, oleaut32.dll, comctl32.dll
HARDWARE: setupapi.dll (when NSIS handles hardware detection)
ABSENT:   mscoree.dll
```

### 7.2 PE Section Name Fingerprints

Section names are 8-byte null-padded ASCII strings in the section table.

**Standard sections** (any compiler):

```
.text   .rdata   .data   .bss   .rsrc   .reloc   .edata   .idata   .pdata   .tls   .debug
```

**Framework-specific sections** [confidence noted]:

| Section Name    | Framework                | Confidence      |
| --------------- | ------------------------ | --------------- |
| `.ndata`        | NSIS                     | HIGH_CONFIDENCE |
| `UPX0`          | UPX packer               | HIGH_CONFIDENCE |
| `UPX1`          | UPX packer               | HIGH_CONFIDENCE |
| `UPX2`          | UPX packer (rare)        | HIGH_CONFIDENCE |
| `.wixburn`      | WiX Burn bootstrapper    | HIGH_CONFIDENCE |
| `.go.buildinfo` | Go (1.13+)               | HIGH_CONFIDENCE |
| `.noptrdata`    | Go                       | MEDIUM          |
| `.noptrbss`     | Go                       | MEDIUM          |
| `CODE`          | Delphi (uppercase)       | HIGH_CONFIDENCE |
| `DATA`          | Delphi (uppercase)       | HIGH_CONFIDENCE |
| `BSS`           | Delphi (uppercase)       | HIGH_CONFIDENCE |
| `.textbss`      | MSVC incremental (debug) | LOW             |
| `.gfids`        | MSVC with CFG            | LOW             |
| `.pyi`          | PyInstaller (rare)       | MEDIUM          |
| `_TEXT`         | Watcom C                 | LOW             |

#### UPX Detection [HIGH_CONFIDENCE]

```
Section names exactly "UPX0" and "UPX1" in section table   [HIGH_CONFIDENCE]
UPX overlay magic: 55 50 58 21  ("UPX!")  at exactly FILE_SIZE - 4 bytes  [HIGH_CONFIDENCE]
```

```powershell
function Test-UPXPacked {
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    # Check last 4 bytes for UPX! magic
    if ($bytes.Length -ge 4) {
        $tail = [System.Text.Encoding]::ASCII.GetString($bytes, $bytes.Length-4, 4)
        if ($tail -eq "UPX!") {
            return [PSCustomObject]@{IsUPX=$true; Confidence="HIGH_CONFIDENCE"; Method="UPX! overlay magic"}
        }
    }
    # Check section names
    $peOffset    = [BitConverter]::ToUInt32($bytes, 0x3C)
    $numSections = [BitConverter]::ToUInt16($bytes, $peOffset + 6)
    $sizeOptHdr  = [BitConverter]::ToUInt16($bytes, $peOffset + 20)
    $secStart    = $peOffset + 24 + $sizeOptHdr
    $upx0 = $false; $upx1 = $false
    for ($i = 0; $i -lt $numSections; $i++) {
        $name = [System.Text.Encoding]::ASCII.GetString($bytes, $secStart + ($i*40), 8).TrimEnd([char]0)
        if ($name -eq "UPX0") { $upx0 = $true }
        if ($name -eq "UPX1") { $upx1 = $true }
    }
    if ($upx0 -and $upx1) {
        return [PSCustomObject]@{IsUPX=$true; Confidence="HIGH_CONFIDENCE"; Method="UPX section names"}
    }
    return [PSCustomObject]@{IsUPX=$false}
}
```

### 7.3 PE Characteristics Field

`IMAGE_FILE_HEADER.Characteristics` at `PeOffset + 22` (2 bytes):

```
0x0002  IMAGE_FILE_EXECUTABLE_IMAGE    — Valid EXE (always set for .exe)
0x0020  IMAGE_FILE_LARGE_ADDRESS_AWARE — Can address >2 GB (common in 64-bit)
0x0100  IMAGE_FILE_32BIT_MACHINE       — 32-bit machine word
0x0200  IMAGE_FILE_DEBUG_STRIPPED      — Debug info removed
0x2000  IMAGE_FILE_DLL                 — This is a DLL (not EXE)
```

`IMAGE_OPTIONAL_HEADER.DllCharacteristics` at `OptHdrOffset + 70` (PE32) or `OptHdrOffset + 70` (PE32+):

```
0x0020  DYNAMIC_BASE          — ASLR enabled
0x0040  FORCE_INTEGRITY       — Code integrity check required
0x0100  NX_COMPAT             — DEP compatible
0x0400  NO_SEH                — No structured exception handling
0x4000  GUARD_CF              — Control Flow Guard (CFG) enabled
0x8000  TERMINAL_SERVER_AWARE
```

High-entropy ASLR + CFG + NX_COMPAT = modern compiled application (MSVC/Clang/Rust). Absence of
DYNAMIC_BASE suggests older or stripped binary. These flags help classify vintage/compiler.

### 7.4 Machine Type Values

```
0x014C  IMAGE_FILE_MACHINE_I386    — x86 32-bit
0x8664  IMAGE_FILE_MACHINE_AMD64   — x64 64-bit
0x01C4  IMAGE_FILE_MACHINE_ARMNT   — ARM Thumb-2 (ARM32)
0xAA64  IMAGE_FILE_MACHINE_ARM64   — ARM64
```

A `Machine = 0x014C` binary with non-zero COM_DESCRIPTOR = MSIL-only/.NET AnyCPU binary compiled for compatibility.

### 7.5 Subsystem Values

`IMAGE_OPTIONAL_HEADER.Subsystem` (PE32: at `OptHdrOffset + 68`; PE32+: same relative offset):

```
0x0001  IMAGE_SUBSYSTEM_NATIVE           — Driver / native application
0x0002  IMAGE_SUBSYSTEM_WINDOWS_GUI      — Windows GUI (no console window)
0x0003  IMAGE_SUBSYSTEM_WINDOWS_CUI      — Console application
0x000E  IMAGE_SUBSYSTEM_WINDOWS_CE_GUI   — Windows CE
```

Classification hints:

- GUI subsystem + .NET → likely WinForms or WPF app
- CUI subsystem + .NET → likely ps2exe console (or any .NET console app)
- GUI subsystem + no .NET + ONLY kernel32.dll imports → likely Go binary or minimal C program

### 7.6 PowerShell PE Section Extractor

```powershell
function Get-PESections {
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $peOffset    = [BitConverter]::ToUInt32($bytes, 0x3C)
    $numSections = [BitConverter]::ToUInt16($bytes, $peOffset + 6)
    $sizeOptHdr  = [BitConverter]::ToUInt16($bytes, $peOffset + 20)
    $secStart    = $peOffset + 24 + $sizeOptHdr
    $sections = @()
    for ($i = 0; $i -lt $numSections; $i++) {
        $sOff = $secStart + ($i * 40)
        $name = [System.Text.Encoding]::ASCII.GetString($bytes, $sOff, 8).TrimEnd([char]0)
        $virtualSize = [BitConverter]::ToUInt32($bytes, $sOff + 8)
        $virtualAddr = [BitConverter]::ToUInt32($bytes, $sOff + 12)
        $rawSize     = [BitConverter]::ToUInt32($bytes, $sOff + 16)
        $rawOffset   = [BitConverter]::ToUInt32($bytes, $sOff + 20)
        $sections   += [PSCustomObject]@{
            Name        = $name
            VirtualSize = $virtualSize
            VirtualAddr = "0x{0:X8}" -f $virtualAddr
            RawSize     = $rawSize
            RawOffset   = "0x{0:X8}" -f $rawOffset
        }
    }
    return $sections
}
```

---

## 8. DECISION MATRIX

### 8.1 Extractability Decision Tree

```
Is it a PE? (MZ at offset 0, PE\0\0 at e_lfanew)
│
├── NO: Check for raw archive magic at offset 0
│   ├── 50 4B 03 04 → ZIP → EXTRACTABLE (7-Zip, ZipFile)
│   ├── 37 7A BC AF 27 1C → 7z → EXTRACTABLE
│   ├── 4D 53 43 46 → CAB → EXTRACTABLE (7-Zip, expand.exe)
│   └── D0 CF 11 E0 A1 B1 1A E1 → MSI/OLE → EXTRACTABLE (7-Zip, Type=Msi)
│
└── YES: It's a PE — proceed:
    │
    ├── Step 1: .NET check — COM_DESCRIPTOR (data dir index 14) non-zero?
    │   └── YES: .NET Assembly [HIGH_CONFIDENCE]
    │       ├── Imports ONLY mscoree.dll?
    │       │   └── YES: Managed binary
    │       │       ├── Resources contain "costura.*" → Costura.Fody → DLLs extractable via ILSpy
    │       │       ├── ".NET Bundle" or 32-byte BundleSignature near EOF → Single-file bundle
    │       │       │   → Extractable via dotnet-bundle-extract [NOT 7-Zip]
    │       │       ├── Resources contain "SCRIPT"/"ps2exe"/"PowerShell" → ps2exe
    │       │       │   → NOT extractable by 7-Zip; needs ILSpy/dnSpy
    │       │       └── dfshim.dll import → ClickOnce → payload NOT embedded
    │       └── Otherwise → Pure .NET application → Requires ILSpy/dnSpy for code
    │
    ├── Step 2: Section names
    │   ├── Has ".ndata" → NSIS → EXTRACTABLE (7-Zip, Type=Nsis) [HIGH_CONFIDENCE]
    │   ├── Has ".wixburn" or resource "WIXBURN_MANIFEST" → WiX Burn → EXTRACTABLE (WiX tools) [HIGH_CONF]
    │   ├── Has "UPX0"/"UPX1" or UPX! last 4 bytes → UPX packed → UNPACK with upx -d first
    │   ├── Has ".go.buildinfo" → Go binary → REQUIRES DECOMPILATION [HIGH_CONFIDENCE]
    │   └── Has "CODE"/"DATA" (uppercase) → Delphi → REQUIRES DECOMPILATION [HIGH_CONFIDENCE]
    │
    ├── Step 3: 7-Zip Type= (if 7z.exe available)
    │   ├── Nsis, Inno, 7z, Zip, Rar, Rar5, Cab, Msi, Wim, GZip, BZip2, Xz, ... → EXTRACTABLE
    │   └── PE → continue to step 4
    │
    ├── Step 4: Overlay / embedded archive scan
    │   ├── 37 7A BC AF 27 1C at overlay start → 7z SFX → EXTRACTABLE [HIGH_CONFIDENCE]
    │   ├── 52 61 72 21 1A 07 00 at overlay → RAR4 SFX → EXTRACTABLE [HIGH_CONFIDENCE]
    │   ├── 52 61 72 21 1A 07 01 00 at overlay → RAR5 SFX → EXTRACTABLE [HIGH_CONFIDENCE]
    │   ├── 4D 53 43 46 anywhere (EOCD validated) → CAB SFX → EXTRACTABLE [HIGH_CONFIDENCE]
    │   ├── "Inno Setup Setup Data" at overlay start → Inno Setup → EXTRACTABLE [HIGH_CONFIDENCE]
    │   ├── ZIP EOCD (50 4B 05 06) valid near EOF → ZIP SFX → EXTRACTABLE [HIGH_CONFIDENCE]
    │   ├── 4D 53 57 49 4D 00 00 00 anywhere → WIM embedded → EXTRACTABLE (7z/wimlib) [HIGH_CONF]
    │   ├── 4D 45 49 0C 0B 0A 0B 0E in last 4 KB → PyInstaller → REQUIRES pyinstxtractor
    │   └── 41 55 33 21 45 41 30 36 anywhere → AutoIt compiled → REQUIRES Exe2Aut
    │
    ├── Step 5: VersionInfo / binary strings
    │   ├── CompanyName "Igor Pavlov" → 7-Zip SFX → EXTRACTABLE
    │   ├── CompanyName "win.rar GmbH" / "Alexander Roshal" → WinRAR SFX → EXTRACTABLE
    │   ├── FileDescription "WinZip Self-Extractor" → WinZip SFX → EXTRACTABLE
    │   ├── FileDescription contains "Nullsoft Install" → NSIS → EXTRACTABLE
    │   ├── ProductName contains "InstallShield" → InstallShield → MAYBE (version-dependent)
    │   ├── CompanyName "Caphyon" → Advanced Installer → MAYBE (depends on output type)
    │   ├── OriginalFilename "AutoHotkey.exe" → AHK → REQUIRES DECOMPILATION
    │   ├── FileDescription "AutoIt v3 Script" → AutoIt → REQUIRES Exe2Aut
    │   ├── "_MEIPASS" string in binary → PyInstaller → REQUIRES pyinstxtractor
    │   ├── "ELECTRON_RUN_AS_NODE" string → Electron → EXTRACTABLE (ASAR tool)
    │   ├── "panicked at" string → Rust → REQUIRES DECOMPILATION
    │   └── "Squirrel.Windows" string → Squirrel → check for ZIP in overlay
    │
    └── Step 6: Import table fallback
        ├── ONLY mscoree.dll → .NET (already covered step 1 if COM_DESC was zero — re-check)
        ├── python3X.dll → cx_Freeze / Nuitka → likely NOT extractable
        ├── ONLY kernel32.dll (minimal) → Go binary → REQUIRES DECOMPILATION
        └── Standard Win32 set → Native C/C++/Delphi → REQUIRES DECOMPILATION
```

### 8.2 Confidence Levels Summary Table

| Detection Method                           | Confidence Level | False Positive Risk |
| ------------------------------------------ | ---------------- | ------------------- |
| COM_DESCRIPTOR non-zero                    | HIGH_CONFIDENCE  | Near zero           |
| NSIS `.ndata` section                      | HIGH_CONFIDENCE  | Near zero           |
| NSIS `EF BE AD DE` magic in .ndata         | HIGH_CONFIDENCE  | Very low            |
| 7z signature `37 7A BC AF 27 1C`           | HIGH_CONFIDENCE  | Very low            |
| RAR4 sig `52 61 72 21 1A 07 00`            | HIGH_CONFIDENCE  | Very low            |
| RAR5 sig `52 61 72 21 1A 07 01 00`         | HIGH_CONFIDENCE  | Very low            |
| ZIP EOCD `50 4B 05 06` validated           | HIGH_CONFIDENCE  | Low                 |
| CAB `MSCF` with validated size             | HIGH_CONFIDENCE  | Very low            |
| "Inno Setup Setup Data" in overlay         | HIGH_CONFIDENCE  | Near zero           |
| `.wixburn` section                         | HIGH_CONFIDENCE  | Near zero           |
| `WIXBURN_MANIFEST` resource                | HIGH_CONFIDENCE  | Near zero           |
| UPX section names + UPX! overlay magic     | HIGH_CONFIDENCE  | Near zero           |
| AutoIt sig `41 55 33 21 45 41 30 36`       | HIGH_CONFIDENCE  | Very low            |
| `mscoree.dll` import                       | HIGH_CONFIDENCE  | Near zero           |
| PyInstaller `4D 45 49 0C 0B 0A 0B 0E`      | HIGH_CONFIDENCE  | Very low            |
| `.go.buildinfo` section name               | HIGH_CONFIDENCE  | Near zero           |
| `FF 20 47 6F ...` Go buildinf magic        | HIGH_CONFIDENCE  | Low                 |
| WIM `4D 53 57 49 4D 00 00 00`              | HIGH_CONFIDENCE  | Very low            |
| `DVCLAL` resource name                     | HIGH_CONFIDENCE  | Near zero (Delphi)  |
| "AutoIt v3 Script" VersionInfo             | HIGH_CONFIDENCE  | Low (customizable)  |
| OriginalFilename "AutoHotkey.exe"          | HIGH_CONFIDENCE  | Low (customizable)  |
| CompanyName "Igor Pavlov"                  | HIGH_CONFIDENCE  | Low (customizable)  |
| CompanyName "Caphyon"                      | HIGH_CONFIDENCE  | Low (customizable)  |
| "\_MEIPASS" string in binary               | HIGH_CONFIDENCE  | Low                 |
| "ELECTRON_RUN_AS_NODE" string              | HIGH_CONFIDENCE  | Low                 |
| `BSJB` .NET metadata magic                 | HIGH_CONFIDENCE  | Near zero           |
| .NET BundleSignature (32 bytes)            | HIGH_CONFIDENCE  | Near zero           |
| CompanyName "Nullsoft" only                | HEURISTIC        | Medium              |
| Only `kernel32.dll` imported               | HEURISTIC        | Medium              |
| "panicked at" string                       | HEURISTIC        | Low                 |
| Large overlay with no recognized signature | HEURISTIC        | High                |
| `.noptrdata` section name                  | HEURISTIC        | Low                 |
| `.noptrbss` section name                   | HEURISTIC        | Low                 |

### 8.3 Extractable vs Requires Decompilation — Summary

**EXTRACTABLE** (7-Zip or built-in tools):

```
NSIS installer          — 7z (Type=Nsis)
Inno Setup installer    — 7z (Type=Inno), innoextract
WinRAR SFX              — 7z (Type=Rar/Rar5)
7-Zip SFX               — 7z (Type=7z)
WinZip SFX              — 7z (Type=Zip), ZipFile
Info-ZIP SFX            — 7z (Type=Zip)
IExpress                — expand.exe, 7z (Type=Cab)
MSI                     — 7z (Type=Msi)
WIM                     — 7z (Type=Wim), DISM
Costura.Fody .NET       — ILSpy/dnSpy resource extraction
.NET single-file bundle — dotnet-bundle-extract
WiX Burn                — WiX tools (partial; 7z sees Type=PE)
```

**REQUIRES DECOMPILATION / SPECIALIZED TOOL**:

```
ps2exe                  — ILSpy/dnSpy (or .NET reflection)
AutoIt                  — Exe2Aut, myAut2Exe
AutoHotkey              — AHK decompiler tools
PyInstaller             — pyinstxtractor (not 7-Zip)
cx_Freeze               — No single-EXE extraction; companion files needed
Nuitka                  — Ghidra/IDA Pro (compiled native)
Pure .NET apps          — ILSpy/dnSpy
Go binaries             — Ghidra/Binary Ninja
Rust binaries           — Ghidra/IDA Pro
Delphi native           — Ghidra/IDA Pro
Native C/C++ binaries   — Ghidra/IDA Pro/Binary Ninja
Electron                — ASAR extraction (asar extract), then JS reversing
pkg (Node.js)           — pkg-fetch + VFS extraction tools
```

---

## 9. POWERSHELL REFERENCE IMPLEMENTATION SKELETON

### 9.1 Master Classification Function

```powershell
#Requires -Version 5.1
Add-Type -AssemblyName System.IO.Compression

function Get-ExeClassification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$SevenZipPath = "7z.exe"
    )

    $result = [ordered]@{
        Path             = $Path
        FileSize         = (Get-Item $Path).Length
        IsExtractable    = $false
        ExtractWith      = @()
        Framework        = "Unknown"
        Confidence       = "UNKNOWN"
        IsDotNet         = $false
        HasOverlay       = $false
        OverlaySignature = $null
        Detections       = [System.Collections.Generic.List[string]]::new()
        SevenZipType     = $null
    }

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 64) { $result.Framework = "TooSmall"; return [PSCustomObject]$result }

    # Step 1: MZ check
    if ($bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) {
        $raw = $bytes[0..7]
        if ($raw[0] -eq 0x50 -and $raw[1] -eq 0x4B) {
            $result.Framework="ZIP"; $result.IsExtractable=$true; $result.ExtractWith=@("7-Zip","ZipFile")
            $result.Confidence="HIGH_CONFIDENCE"; return [PSCustomObject]$result
        }
        if ($raw[0] -eq 0x37 -and $raw[1] -eq 0x7A -and $raw[2] -eq 0xBC -and $raw[3] -eq 0xAF) {
            $result.Framework="7z"; $result.IsExtractable=$true; $result.ExtractWith=@("7-Zip")
            $result.Confidence="HIGH_CONFIDENCE"; return [PSCustomObject]$result
        }
        if ($raw[0] -eq 0x4D -and $raw[1] -eq 0x53 -and $raw[2] -eq 0x43 -and $raw[3] -eq 0x46) {
            $result.Framework="CAB"; $result.IsExtractable=$true; $result.ExtractWith=@("7-Zip","expand.exe")
            $result.Confidence="HIGH_CONFIDENCE"; return [PSCustomObject]$result
        }
        $result.Framework="Unknown_NonPE"; return [PSCustomObject]$result
    }

    # Step 2: PE parse
    $peOffset     = [BitConverter]::ToUInt32($bytes, 0x3C)
    $optOffset    = $peOffset + 24
    $optMagic     = [BitConverter]::ToUInt16($bytes, $optOffset)
    $numSections  = [BitConverter]::ToUInt16($bytes, $peOffset + 6)
    $sizeOptHdr   = [BitConverter]::ToUInt16($bytes, $peOffset + 20)
    $sectionStart = $optOffset + $sizeOptHdr

    # Step 3: Section names
    $sections = @()
    for ($i = 0; $i -lt $numSections; $i++) {
        $sOff = $sectionStart + ($i * 40)
        $name    = [System.Text.Encoding]::ASCII.GetString($bytes, $sOff, 8).TrimEnd([char]0)
        $rawOff  = [BitConverter]::ToUInt32($bytes, $sOff + 20)
        $rawSize = [BitConverter]::ToUInt32($bytes, $sOff + 16)
        $sections += [PSCustomObject]@{Name=$name; RawOffset=$rawOff; RawSize=$rawSize}
    }
    $result['SectionNames'] = $sections.Name -join ", "

    if ($sections.Name -contains ".ndata") {
        $result.Detections.Add("NSIS: .ndata section [HIGH_CONFIDENCE]")
        $result.Framework="NSIS"; $result.IsExtractable=$true; $result.ExtractWith=@("7-Zip"); $result.Confidence="HIGH_CONFIDENCE"
    }
    if ($sections.Name -contains ".wixburn") {
        $result.Detections.Add("WiX_Burn: .wixburn section [HIGH_CONFIDENCE]")
        $result.Framework="WiX_Burn"; $result.IsExtractable=$true; $result.ExtractWith=@("WiX_tools","7-Zip_partial"); $result.Confidence="HIGH_CONFIDENCE"
    }
    if ($sections.Name -contains ".go.buildinfo") {
        $result.Detections.Add("Go_Binary: .go.buildinfo section [HIGH_CONFIDENCE]")
        $result.Framework="Go_Native"; $result.IsExtractable=$false; $result.Confidence="HIGH_CONFIDENCE"
    }
    if ($sections.Name -contains "UPX0" -and $sections.Name -contains "UPX1") {
        $result.Detections.Add("UPX_packed: UPX0/UPX1 sections [HIGH_CONFIDENCE]")
        $result.Framework="UPX_Packed"; $result.IsExtractable=$false; $result.Confidence="HIGH_CONFIDENCE"
    }
    # UPX! last 4 bytes
    if ($bytes.Length -ge 4 -and [System.Text.Encoding]::ASCII.GetString($bytes, $bytes.Length-4, 4) -eq "UPX!") {
        $result.Detections.Add("UPX_packed: UPX! overlay magic [HIGH_CONFIDENCE]")
        if ($result.Framework -eq "Unknown") { $result.Framework="UPX_Packed"; $result.IsExtractable=$false; $result.Confidence="HIGH_CONFIDENCE" }
    }

    # Step 4: .NET detection
    $comDirBase = if ($optMagic -eq 0x010B) { $optOffset + 96 } else { $optOffset + 112 }
    $comDirOff  = $comDirBase + (14 * 8)
    if ($comDirOff + 8 -lt $bytes.Length) {
        $comRVA  = [BitConverter]::ToUInt32($bytes, $comDirOff)
        $comSize = [BitConverter]::ToUInt32($bytes, $comDirOff + 4)
        if ($comRVA -ne 0 -and $comSize -ge 72) {
            $result.IsDotNet = $true
            $result.Detections.Add(".NET_Assembly: COM_DESCRIPTOR non-zero [HIGH_CONFIDENCE]")
            if ($result.Framework -eq "Unknown") { $result.Framework = "DotNet_Unknown" }
        }
    }

    # Step 5: Overlay detection
    $maxEnd = 0
    foreach ($s in $sections) {
        $end = $s.RawOffset + $s.RawSize
        if ($end -gt $maxEnd) { $maxEnd = $end }
    }
    $overlaySize = $bytes.Length - $maxEnd
    $result.HasOverlay = ($overlaySize -gt 64)

    if ($result.HasOverlay) {
        $ov = $bytes[$maxEnd..($maxEnd + [Math]::Min(15, $overlaySize-1))]

        # 7z
        if ($ov[0] -eq 0x37 -and $ov[1] -eq 0x7A -and $ov[2] -eq 0xBC -and $ov[3] -eq 0xAF -and $ov[4] -eq 0x27 -and $ov[5] -eq 0x1C) {
            $result.OverlaySignature="7z"; $result.IsExtractable=$true; $result.ExtractWith=@("7-Zip")
            $result.Framework="7z_SFX"; $result.Confidence="HIGH_CONFIDENCE"
            $result.Detections.Add("7z_SFX: 7z signature in overlay [HIGH_CONFIDENCE]")
        }
        # RAR4
        elseif ($ov[0] -eq 0x52 -and $ov[1] -eq 0x61 -and $ov[2] -eq 0x72 -and $ov[3] -eq 0x21 -and $ov[4] -eq 0x1A -and $ov[5] -eq 0x07 -and $ov[6] -eq 0x00) {
            $result.OverlaySignature="RAR4"; $result.IsExtractable=$true; $result.ExtractWith=@("7-Zip")
            $result.Framework="WinRAR_SFX"; $result.Confidence="HIGH_CONFIDENCE"
            $result.Detections.Add("WinRAR_SFX: RAR4 signature in overlay [HIGH_CONFIDENCE]")
        }
        # RAR5
        elseif ($ov[0] -eq 0x52 -and $ov[1] -eq 0x61 -and $ov[2] -eq 0x72 -and $ov[3] -eq 0x21 -and $ov[4] -eq 0x1A -and $ov[5] -eq 0x07 -and $ov[6] -eq 0x01) {
            $result.OverlaySignature="RAR5"; $result.IsExtractable=$true; $result.ExtractWith=@("7-Zip")
            $result.Framework="WinRAR_SFX"; $result.Confidence="HIGH_CONFIDENCE"
            $result.Detections.Add("WinRAR_SFX: RAR5 signature in overlay [HIGH_CONFIDENCE]")
        }
        # CAB
        elseif ($ov[0] -eq 0x4D -and $ov[1] -eq 0x53 -and $ov[2] -eq 0x43 -and $ov[3] -eq 0x46) {
            $result.OverlaySignature="CAB"; $result.IsExtractable=$true; $result.ExtractWith=@("7-Zip","expand.exe")
            $result.Framework="IExpress_or_CAB_SFX"; $result.Confidence="HIGH_CONFIDENCE"
            $result.Detections.Add("CAB_SFX: MSCF signature in overlay [HIGH_CONFIDENCE]")
        }
        # Inno Setup string
        $ovStr = [System.Text.Encoding]::ASCII.GetString($bytes, $maxEnd, [Math]::Min(50, $overlaySize))
        if ($ovStr -match "Inno Setup Setup Data") {
            $result.OverlaySignature="Inno"; $result.IsExtractable=$true; $result.ExtractWith=@("7-Zip","innounp","innoextract")
            $result.Framework="InnoSetup"; $result.Confidence="HIGH_CONFIDENCE"
            $result.Detections.Add("InnoSetup: 'Inno Setup Setup Data' in overlay [HIGH_CONFIDENCE]")
        }
        # ZIP EOCD scan
        if ($null -eq $result.OverlaySignature) {
            $ss2 = [Math]::Max($maxEnd, $bytes.Length - 65557)
            for ($i = $bytes.Length - 22; $i -ge $ss2; $i--) {
                if ($bytes[$i] -eq 0x50 -and $bytes[$i+1] -eq 0x4B -and $bytes[$i+2] -eq 0x05 -and $bytes[$i+3] -eq 0x06) {
                    $cLen = [BitConverter]::ToUInt16($bytes, $i + 20)
                    if (($i + 22 + $cLen) -eq $bytes.Length) {
                        $result.OverlaySignature="ZIP"; $result.IsExtractable=$true; $result.ExtractWith=@("7-Zip","ZipFile")
                        $result.Framework="ZIP_SFX"; $result.Confidence="HIGH_CONFIDENCE"
                        $result.Detections.Add("ZIP_SFX: ZIP EOCD valid in overlay [HIGH_CONFIDENCE]")
                        break
                    }
                }
            }
        }
        # PyInstaller PKG magic
        $pkgMagic = [byte[]](0x4D,0x45,0x49,0x0C,0x0B,0x0A,0x0B,0x0E)
        $pkgStart = [Math]::Max(0, $bytes.Length - 4096)
        for ($i = $pkgStart; $i -le $bytes.Length - 8; $i++) {
            $m = $true; for ($j=0;$j -lt 8;$j++){if($bytes[$i+$j]-ne$pkgMagic[$j]){$m=$false;break}}
            if ($m) {
                $result.Detections.Add("PyInstaller: PKG magic 4D 45 49 0C 0B 0A 0B 0E [HIGH_CONFIDENCE]")
                if ($result.Framework -eq "Unknown" -or $result.Framework -eq "DotNet_Unknown") {
                    $result.Framework="PyInstaller"; $result.IsExtractable=$false; $result.Confidence="HIGH_CONFIDENCE"
                }
                break
            }
        }
    }

    # Step 6: VersionInfo
    $fvi = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($Path)
    $result['VersionInfo'] = [ordered]@{
        FileDescription  = $fvi.FileDescription
        ProductName      = $fvi.ProductName
        CompanyName      = $fvi.CompanyName
        OriginalFilename = $fvi.OriginalFilename
        Comments         = $fvi.Comments
    }
    if ($fvi.FileDescription -match "AutoIt|Aut2Exe" -or $fvi.CompanyName -match "AutoIt Team") {
        $result.Detections.Add("AutoIt: VersionInfo [HIGH_CONFIDENCE]")
        $result.Framework="AutoIt"; $result.IsExtractable=$false; $result.Confidence="HIGH_CONFIDENCE"
    }
    if ($fvi.ProductName -match "^AutoHotkey$" -or $fvi.OriginalFilename -match "AutoHotkey") {
        $result.Detections.Add("AutoHotkey: VersionInfo [HIGH_CONFIDENCE]")
        $result.Framework="AutoHotkey"; $result.IsExtractable=$false; $result.Confidence="HIGH_CONFIDENCE"
    }
    if ($fvi.FileDescription -match "7-Zip Self-extract" -or ($fvi.CompanyName -match "Igor Pavlov" -and $result.HasOverlay)) {
        $result.Detections.Add("7zSFX: VersionInfo [HIGH_CONFIDENCE]")
        if ($result.Framework -eq "Unknown") { $result.Framework="7z_SFX"; $result.IsExtractable=$true }
    }
    if ($fvi.FileDescription -match "WinRAR self-extract" -or $fvi.ProductName -match "^WinRAR$") {
        $result.Detections.Add("WinRAR_SFX: VersionInfo [HIGH_CONFIDENCE]")
        if ($result.Framework -eq "Unknown") { $result.Framework="WinRAR_SFX"; $result.IsExtractable=$true }
    }
    if ($fvi.Comments -match "Inno Setup" -or $fvi.FileDescription -match "Inno Setup") {
        $result.Detections.Add("InnoSetup: VersionInfo [HIGH_CONFIDENCE]")
        if ($result.Framework -eq "Unknown") { $result.Framework="InnoSetup"; $result.IsExtractable=$true }
    }
    if ($fvi.CompanyName -match "Caphyon") {
        $result.Detections.Add("AdvancedInstaller: CompanyName Caphyon [HIGH_CONFIDENCE]")
        if ($result.Framework -eq "Unknown") { $result.Framework="AdvancedInstaller" }
    }

    # Step 7: 7-Zip query
    if (Get-Command $SevenZipPath -ErrorAction SilentlyContinue) {
        $szOutput = & $SevenZipPath l $Path 2>&1
        $typeLine = $szOutput | Select-String "^Type\s*=" | Select-Object -First 1
        if ($typeLine) {
            $result.SevenZipType = ($typeLine.Line -split "=",2)[1].Trim()
            $noExtract = @("PE","Elf","Macho","Swf","Te","Efi")
            if ($result.SevenZipType -notin $noExtract) {
                $result.IsExtractable=$true; $result.Confidence="HIGH_CONFIDENCE"
                if ($result.Framework -eq "Unknown" -or $result.Framework -eq "DotNet_Unknown") {
                    $result.Framework=$result.SevenZipType
                }
            }
        }
    }

    # Final confidence assignment
    if ($result.Confidence -eq "UNKNOWN") {
        $result.Confidence = if ($result.Detections.Count -gt 0) {"HEURISTIC"} else {"UNCLASSIFIED"}
    }
    return [PSCustomObject]$result
}
```

---

## 10. SOURCE CITATIONS AND AUTHORITATIVE REFERENCES

### 10.1 PE/COFF Specifications

- **Microsoft PE/COFF Specification v14.0** (all field offsets, data directories, section tables):
  https://docs.microsoft.com/en-us/windows/win32/debug/pe-format

- **ECMA-335 Common Language Infrastructure** (CLI/COM_DESCRIPTOR header, .NET metadata):
  https://www.ecma-international.org/publications-and-standards/standards/ecma-335/
  (Partition II §25.3: PE/COFF Extensions; §25.3.3: CLI header)

### 10.2 Archive Format Specifications

- **ZIP**: PKWARE APPNOTE.TXT §4.3
  https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT

- **7-Zip format**: 7-Zip source `CPP/7zip/Archive/7z/7zHeader.h`
  https://github.com/ip7z/7zip/blob/main/CPP/7zip/Archive/7z/7zHeader.h

- **CAB**: [MS-CAB] Cabinet File Format §2.2
  https://docs.microsoft.com/en-us/openspecs/windows_protocols/ms-cab/

- **WIM**: [MS-WIM] Windows Imaging Format
  https://docs.microsoft.com/en-us/openspecs/windows_protocols/ms-wim/

- **RAR**: RARLAB documentation; unrar source `rarformat.h`
  https://www.rarlab.com/rar_add.htm

- **XZ/LZMA2**: XZ File Format specification §2.1.1
  https://tukaani.org/xz/xz-file-format-1.1.0.txt

- **7-Zip archive handlers** (Type= values): 7-Zip source `CPP/7zip/Archive/`
  https://github.com/ip7z/7zip/tree/main/CPP/7zip/Archive

### 10.3 Installer Frameworks

- **NSIS** (fileform.h, magic values, section structure):
  https://sourceforge.net/p/nsis/code/HEAD/tree/NSIS/trunk/Contrib/Header/fileform.h
  https://github.com/kichik/nsis (Source/exehead/)

- **Inno Setup** (official source):
  https://github.com/jrsoftware/issrc
  innounp unpacker: https://sourceforge.net/projects/innounp/
  innoextract: https://github.com/dscharrer/innoextract

- **WiX Burn** (burn section header, WIXBURN_MANIFEST):
  https://github.com/wixtoolset/wix/blob/develop/src/burn/engine/section.h
  https://github.com/wixtoolset/wix/

- **7-Zip archive command line** (Type= value reference):
  https://github.com/ip7z/7zip/blob/main/CPP/7zip/UI/Common/ArchiveCommandLine.cpp

### 10.4 Script-to-EXE Tools

- **ps2exe** (Markus Scholtes fork): https://github.com/MScholtes/PS2EXE

- **AutoIt / Exe2Aut**:
  AutoIt: https://www.autoitscript.com/
  Exe2Aut: https://exe2aut.com/

- **AutoHotkey**: https://github.com/AutoHotkey/AutoHotkey

- **PyInstaller** (CArchive / PKG format — `pyi_archive.c`):
  https://github.com/pyinstaller/pyinstaller
  pyinstxtractor: https://github.com/extremecoders-re/pyinstxtractor

- **Node.js SEA fuse string**:
  https://nodejs.org/api/single-executable-applications.html
  https://github.com/nodejs/node/blob/main/src/node_sea.h

- **Electron ASAR format**: https://github.com/electron/asar

- **Costura.Fody** (embedded DLL naming): https://github.com/Fody/Costura

- **.NET Single-file bundle format** (BundleSignature, 32-byte magic):
  https://github.com/dotnet/runtime/blob/main/src/installer/managed/Microsoft.NET.HostModel/Bundle/Manifest.cs

- **Go build info** (`.go.buildinfo` section, buildinf magic):
  https://pkg.go.dev/runtime/debug#ReadBuildInfo
  https://github.com/golang/go/blob/master/src/debug/buildinfo/buildinfo.go

### 10.5 Windows API References

- **GetFileVersionInfo** (VersionInfo/VS_VERSIONINFO reading):
  https://docs.microsoft.com/en-us/windows/win32/api/winver/nf-winver-getfileversioninfow

- **expand.exe** documentation:
  https://docs.microsoft.com/en-us/windows-server/administration/windows-commands/expand

- **System.IO.Compression.ZipArchive** (.NET):
  https://docs.microsoft.com/en-us/dotnet/api/system.io.compression.ziparchive

- **MetadataLoadContext** (.NET 5+ reflection):
  https://docs.microsoft.com/en-us/dotnet/api/system.reflection.metadataloadcontext

### 10.6 Reverse Engineering References

- **PE format deep dive** (Corkami):
  https://github.com/corkami/docs/blob/master/PE/PE.md

- **UPX format** (magic constants):
  https://github.com/upx/upx

- **Microsoft Cabinet SDK** (MSCF full header specification):
  https://docs.microsoft.com/en-us/previous-versions/ms974336(v=msdn.10)

---

## APPENDIX A: QUICK-REFERENCE HEX SIGNATURES

```
Format          | Magic Bytes (Hex)                          | Len | Location in File
----------------|---------------------------------------------|-----|---------------------------
PE/MZ           | 4D 5A                                       | 2   | Offset 0x00 (always)
PE signature    | 50 45 00 00                                 | 4   | At e_lfanew
.NET (indirect) | Non-zero at COM_DESCRIPTOR data dir #14     | —   | PE opt header +96/+112
.NET metadata   | 42 53 4A 42  ("BSJB")                       | 4   | At MetaDataRVA
ZIP EOCD        | 50 4B 05 06                                 | 4   | ≤65557 bytes from EOF
ZIP LFH         | 50 4B 03 04                                 | 4   | Each file entry
7z              | 37 7A BC AF 27 1C                           | 6   | Archive start
CAB             | 4D 53 43 46 00 00 00 00                     | 8   | Cabinet header offset 0
RAR4            | 52 61 72 21 1A 07 00                        | 7   | Archive start
RAR5            | 52 61 72 21 1A 07 01 00                     | 8   | Archive start
WIM             | 4D 53 57 49 4D 00 00 00                     | 8   | File start
XZ              | FD 37 7A 58 5A 00                           | 6   | Stream start
GZip            | 1F 8B 08                                    | 3   | Stream start
BZip2           | 42 5A 68  ("BZh")                           | 3   | Stream start
ZSTD            | 28 B5 2F FD                                 | 4   | Frame start
MSI/OLE         | D0 CF 11 E0 A1 B1 1A E1                     | 8   | File start
NSIS magic      | EF BE AD DE                                 | 4   | In .ndata or .rsrc
AutoIt v3       | 41 55 33 21 45 41 30 36  ("AU3!EA06")       | 8   | Overlay / .rsrc resource
PyInstaller     | 4D 45 49 0C 0B 0A 0B 0E  ("MEI\x0c\x0b\x0a\x0b\x0e") | 8 | Last 4096 bytes
.NET Bundle     | 8B 12 02 B9 6A 61 20 38 D6 AF 45 6E ...     | 32  | Near EOF
.NET Bundle str | 2E 4E 45 54 20 42 75 6E 64 6C 65 (".NET Bundle") | 11 | Near EOF
UPX!            | 55 50 58 21                                 | 4   | Last 4 bytes of file
Go buildinf     | FF 20 47 6F 20 62 75 69 6C 64 69 6E 66 3A  | 14  | In .data/.rodata
```

**PE Section Names of Note**:

```
.ndata         → NSIS (HIGH_CONFIDENCE — unique to NSIS)
.wixburn       → WiX Burn bootstrapper (HIGH_CONFIDENCE)
UPX0 / UPX1   → UPX packer (HIGH_CONFIDENCE)
.go.buildinfo  → Go binary ≥1.13 (HIGH_CONFIDENCE)
.noptrdata     → Go binary (MEDIUM)
CODE / DATA    → Delphi (uppercase, HIGH_CONFIDENCE)
```

---

## APPENDIX B: EVIDENCE MAP AND DISAGREEMENTS

### B.1 Source Attribution by Finding

The following table maps each hard claim to its primary source, as derived from the verityvulture
evidence map (`research/runs/2026-04-15__1410/report.md` §Evidence Map):

| Claim                                           | Confidence      | Primary Source                                                      |
| ----------------------------------------------- | --------------- | ------------------------------------------------------------------- |
| ZIP EOCD `50 4B 05 06` structure                | HIGH_CONFIDENCE | PKWARE APPNOTE.TXT §4.3.16; .NET ZipArchive source                  |
| 7z sig `37 7A BC AF 27 1C`                      | HIGH_CONFIDENCE | 7-Zip source `CPP/7zip/Archive/7z/7zHeader.h`                       |
| RAR4 sig `52 61 72 21 1A 07 00`                 | HIGH_CONFIDENCE | RARLAB UnRAR source `rarformat.h`                                   |
| CAB sig `4D 53 43 46`                           | HIGH_CONFIDENCE | Microsoft Cabinet SDK specification                                 |
| WIM sig `4D 53 57 49 4D 00 00 00`               | HIGH_CONFIDENCE | Microsoft [MS-WIM] specification                                    |
| NSIS `.ndata` section                           | HIGH_CONFIDENCE | NSIS source `Source/exehead/`, NSIS wiki                            |
| NSIS 7z `Type = Nsis`                           | HIGH_CONFIDENCE | 7-Zip source `CPP/7zip/Archive/NsisHandler.cpp`                     |
| Inno "Inno Setup Setup Data" string             | HIGH_CONFIDENCE | innoextract source; jrsoftware.org                                  |
| Inno 7z `Type = Inno`                           | HIGH_CONFIDENCE | 7-Zip source `CPP/7zip/Archive/InnoHandler.cpp`                     |
| COM_DESCRIPTOR at data dir index 14             | HIGH_CONFIDENCE | ECMA-335 §25.3.3; MSDN PE Format §6.1.3.3                           |
| PE32 data dir offset +96 from opt hdr           | HIGH_CONFIDENCE | Microsoft PE/COFF spec §3.4.2                                       |
| PE32+ data dir offset +112 from opt hdr         | HIGH_CONFIDENCE | Microsoft PE/COFF spec §3.4.3                                       |
| ps2exe imports only mscoree.dll                 | HIGH_CONFIDENCE | ps2exe source; ILSpy analysis                                       |
| AutoIt sig `41 55 33 21 45 41 30 36` (AU3!EA06) | HIGH_CONFIDENCE | AutoIt v3 RE community references (multiple independent analyses)   |
| PyInstaller magic `4D 45 49 0C 0B 0A 0B 0E`     | HIGH_CONFIDENCE | PyInstaller bootloader `bootloader/src/pyi_archive.c`               |
| .NET bundle 32-byte BundleSignature             | HIGH_CONFIDENCE | .NET runtime source `src/installer/managed/Microsoft.NET.HostModel` |
| .NET bundle ".NET Bundle" ASCII string          | HIGH_CONFIDENCE | .NET runtime source (same); embedded in file near EOF               |
| Costura.Fody "costura.\*" resource naming       | HIGH_CONFIDENCE | Costura.Fody source `github.com/Fody/Costura`                       |
| Go `.go.buildinfo` section (Go 1.13+)           | HIGH_CONFIDENCE | Go release notes 1.13; `go version -m <binary>` behavior            |
| Go `.noptrdata`/`.noptrbss` sections            | MEDIUM          | Go toolchain PE output analysis; community references               |
| Delphi `CODE`/`DATA` uppercase sections         | HIGH_CONFIDENCE | Embarcadero Delphi PE output; multiple PE analysis tools confirm    |
| Delphi `DVCLAL` resource name                   | HIGH_CONFIDENCE | Delphi VCL documentation; PE analysis of Delphi-built EXEs          |
| WiX Burn `.wixburn` section                     | HIGH_CONFIDENCE | WiX toolset source `src/burn/engine/section.h`                      |
| WiX Burn `WIXBURN_MANIFEST` resource            | HIGH_CONFIDENCE | WiX toolset Burn engine source                                      |
| MSI/OLE sig `D0 CF 11 E0 A1 B1 1A E1`           | HIGH_CONFIDENCE | Microsoft OLE2/CFBF specification                                   |
| `Type = PE` for non-extractable                 | HIGH_CONFIDENCE | 7-Zip PE handler behavior; widely documented                        |
| expand.exe CAB detection                        | HIGH_CONFIDENCE | Microsoft Cabinet SDK; Windows built-in behavior                    |
| ZipFile.OpenRead() finds embedded ZIP           | HIGH_CONFIDENCE | .NET System.IO.Compression docs; EOCD-based ZIP locator             |
| AutoHotkey OriginalFilename "AutoHotkey.exe"    | HIGH_CONFIDENCE | AHK source; default VersionInfo set by Aut2Exe                      |
| InstallShield CompanyName "Flexera/Acresso"     | HIGH_CONFIDENCE | InstallShield bootstrapper VersionInfo templates                    |
| Advanced Installer CompanyName "Caphyon"        | HIGH_CONFIDENCE | Caphyon Advanced Installer output analysis                          |
| WinZip FileDesc "WinZip Self-Extractor"         | HIGH_CONFIDENCE | WinZip SFX documentation; Corel/WinZip product strings              |
| BSJB .NET metadata magic                        | HIGH_CONFIDENCE | ECMA-335 §24.2.1 (Metadata root structure)                          |
| Node.js SEA fuse string "SEA_FUSE_fce680..."    | HIGH_CONFIDENCE | Node.js source `src/node_sea.h`                                     |

### B.2 Disagreements and Resolutions

The following conflicts were identified between the two source documents and resolved:

**1. PyInstaller PKG trailer magic bytes**

- verityfactseeker: `4D 45 49 00 00 00 00 00` ("MEI\x00\x00\x00\x00\x00")
- verityvulture: `4D 45 49 0C 0B 0A 0B 0E` ("MEI\x0c\x0b\x0a\x0b\x0e") — from source code
- **RESOLUTION**: verityvulture wins. Direct citation of `bootloader/src/pyi_archive.c`:
  `#define MAGIC "MEI\014\013\012\013\016"`. The factseeker value is incorrect.
  Scan last 4096 bytes (not exact EOF - 24) to handle version variation.

**2. NSIS DEADBEEF byte order**

- Both sources agree on `EF BE AD DE` as the on-disk bytes (little-endian 0xDEADBEEF on x86).
- Some third-party descriptions write it as `DE AD BE EF` (big-endian display). This is wrong.
- **RESOLUTION**: `EF BE AD DE` on disk. Confirmed by NSIS source `first_header.siginfo` check.

**3. WIM signature length**

- verityvulture: 6 bytes `4D 53 57 49 4D 00`
- verityfactseeker: 8 bytes `4D 53 57 49 4D 00 00 00`
- **RESOLUTION**: Both are valid subsets. The [MS-WIM] spec defines an 8-byte ImageTag. Using
  8 bytes is more precise and reduces false positives — this document uses 8 bytes.

**4. AutoIt magic bytes**

- verityfactseeker: `41 55 33 21` (4 bytes — "AU3!")
- verityvulture: `41 55 33 21 45 41 30 36` (8 bytes — "AU3!EA06", AutoIt v3 primary)
- **RESOLUTION**: Both are present in compiled scripts. The 4-byte prefix appears in the RCDATA
  resource; the full 8-byte form is the definitive block marker for v3. Both included in §3.2.
  Older versions use `EA05` or `EA02` as the last two bytes. Scan for 4-byte prefix, validate
  next 4 bytes for version disambiguation.

**5. 7-Zip's handling of NSIS installers**

- verityvulture §10 notes: 7-Zip's NSIS handler can fail to parse some NSIS versions or
  custom-compressed installers, falling back to reporting `Type = PE` even for genuine NSIS.
- **RESOLUTION**: Use `.ndata` PE section check as the **primary** NSIS detector;
  7z `Type = Nsis` is a confirmation, not the only signal.

**6. ReflectionOnlyLoadFrom safety**

- verityfactseeker recommends `ReflectionOnlyLoadFrom` for .NET 4.x.
- verityvulture notes it is deprecated in .NET 5+ (throws PlatformNotSupportedException).
- **RESOLUTION**: For .NET 5+ environments, use `MetadataLoadContext` (§4.6). Both methods
  noted in this document. The raw PE byte-offset method (§4.4) is always safe regardless of
  .NET version and is preferred for untrusted binaries.

**7. Advanced Installer detection**

- verityfactseeker: "AI_SetupDir" resource string as internal marker
- verityvulture: CompanyName "Caphyon" as HIGH_CONFIDENCE VersionInfo marker
- **RESOLUTION**: Both are valid and complementary. CompanyName "Caphyon" is the more
  reliable indicator when VersionInfo is not stripped. "AI_SetupDir" string is useful when
  VersionInfo has been customized. Both included in §2.5.

**8. WiX Burn markers**

- verityfactseeker: `.wixburn` PE section name as definitive
- verityvulture: `WIXBURN_MANIFEST` resource name as definitive
- **RESOLUTION**: Both are correct; they are complementary signals from the same binary.
  Modern WiX Burn executables have both. Check for either; both included in §2.4.

---

_Document: exe-static-classification-reference.md_
_Version: 2026.04.15.002 — Canonical merged reference_
_Sources: verityvulture run 2026-04-15\_\_1410 + verityfactseeker artifact 2026.04.15.001_
_Scope: Static analysis only. No execution of binaries._
_Last updated: 2026-04-15_
