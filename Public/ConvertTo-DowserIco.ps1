function ConvertTo-DowserIco {
    <#
    .SYNOPSIS
        Converts an image file into a multi-resolution Windows ICO file.
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
        Loads a source image through System.Drawing (GDI+) and writes a Windows ICO
        file containing one PNG-compressed entry per requested size. UNC source paths
        are staged to a temp file first because GDI+ reads them unreliably, and the
        image is read into memory before decoding for the same reason. Each entry is
        rendered at 32bpp ARGB with high-quality bicubic resampling, and the ICONDIR
        and directory entries are written manually, using a width/height byte of 0 for
        sizes of 256 or larger as the ICO format requires.

        Requested sizes are validated against 16, 32, 48, 64, 128, 256, and 512;
        invalid sizes are warned about and skipped, and when none remain the function
        falls back to 512. The output path defaults to the source name with a .ico
        extension in the source directory when -OutputFile is not given, and any
        missing output directory is created.

        Requires Windows because it depends on System.Drawing and GDI+; on other
        platforms it warns and returns $null.
    .PARAMETER InputFilePath
        Path to the source image to convert. UNC paths are supported and staged to
        temp before decoding.
    .PARAMETER OutputFile
        Path to write the .ico to. Defaults to the source file name with a .ico
        extension in the source directory.
    .PARAMETER IcoSizes
        One or more square pixel sizes to include in the icon. Valid values are 16,
        32, 48, 64, 128, 256, and 512. Defaults to 256. Aliases: IconSize, Size, Sizes.
    .PARAMETER MaxSize
        Accepted for interface compatibility. The current implementation does not act
        on this value. Defaults to 0.
    .EXAMPLE
        ConvertTo-DowserIco -InputFilePath 'C:\art\logo.png' -IcoSizes 16,32,48,256

        Writes logo.ico next to logo.png with four embedded resolutions.
    .EXAMPLE
        ConvertTo-DowserIco -InputFilePath '\\server\share\logo.jpg' -OutputFile 'C:\out\logo.ico'

        Stages the UNC source to temp, then writes a 256px icon to C:\out\logo.ico.
    .OUTPUTS
        System.String
        A 'Wrote icon: <path>' status line on success.

        System.Boolean
        $true on success, $false on failure (missing input, load error, write error).
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$InputFilePath,
        [Parameter(Mandatory=$false)]
        [string]$OutputFile,
        [Parameter(Mandatory=$false)]
        [Alias('IconSize','Size','Sizes')]
        [int[]]
        $IcoSizes = @(256),
        [Parameter(Mandatory=$false)]
        # MaxSize > 256 will produce a separate PNG alongside the ICO; default 0 disables.
        [int]
        $MaxSize = 0
    )

    Write-Log "Starting ConvertTo-DowserIco"

    # eq false not -not, $IsWindows is null on 5.1
    if ($IsWindows -eq $false) {
        Write-Log "ConvertTo-DowserIco requires Windows (System.Drawing/GDI+). Not available on this platform." -Severity Warning
        return $null
    }

    Add-Type -AssemblyName System.Drawing

    if (-not (Test-Path $InputFilePath)) {
        Write-Log "ConvertTo-DowserIco: input file '$InputFilePath' does not exist." -Severity Error
        return $false
    }

    $InputFilePath = (Resolve-Path $InputFilePath).Path

    # gdi+ chokes on unc, stage to temp first
    $tempFile = $null
    if ($InputFilePath -like '\\*') {
        $tempFile = Join-Path $env:TEMP "$([System.IO.Path]::GetRandomFileName())"
        Write-Log "UNC path detected. Copying to temp: '$tempFile'." -Severity Verbose
        try {
            Copy-Item -Path $InputFilePath -Destination $tempFile -Force -ErrorAction Stop
            $InputFilePath = $tempFile
            Write-Log "UNC file staged to temp successfully." -Severity Verbose
        }
        catch {
            Write-Log "ConvertTo-DowserIco failed copying UNC file '$InputFilePath' to temp: $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Error
            return $false
        }
    }

    if (-not $OutputFile) {
        $OutputFileName = [IO.Path]::GetFileNameWithoutExtension($InputFilePath) + '.ico'
        $OutputDir = Split-Path $InputFilePath -Parent
        $OutputFile = Join-Path $OutputDir $OutputFileName
    } else {
        # unresolved provider path, output does not exist yet
        $OutputFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputFile)
        $OutputDir = Split-Path $OutputFile -Parent
        if ($OutputDir -and -not (Test-Path $OutputDir)) {
            New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
        }
    }

    try {
        # read into memory, gdi+ unc reads are flaky
        $fileBytes = [System.IO.File]::ReadAllBytes($InputFilePath)
        $ms = New-Object System.IO.MemoryStream(, $fileBytes)
        $bitmap = [System.Drawing.Bitmap]::FromStream($ms)
    }
    catch {
        Write-Log "ConvertTo-DowserIco failed loading image '$InputFilePath': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Error
        return $false
    }

    # png-compressed ico, dir width/height byte is 0 for sizes >=256
    $IcoSizes = @($IcoSizes)
    if (-not $IcoSizes -or (@($IcoSizes) | Measure-Object).Count -eq 0) {
        $IcoSizes = @(256)
    }

    $validSizes = @(16,32,48,64,128,256,512)
    $sizes = $IcoSizes | ForEach-Object {
        $n = [int]$_
        if ($n -in $validSizes) { $n } else {
            Write-Log "ConvertTo-DowserIco: size $n not in valid set (16,32,48,64,128,256,512), skipping." -Severity Warning
            $null
        }
    } | Where-Object { $_ -ne $null } | Select-Object -Unique | Sort-Object

    if ($sizes.Count -eq 0) {
        $sizes = @(512)
        Write-Log "ConvertTo-DowserIco: no valid sizes specified, using default: 512px." -Severity Warning
    }
    $images = @()
    try {
        foreach ($s in $sizes) {
            # 32bpp argb avoids GetHicon errors
            $resized = New-Object System.Drawing.Bitmap($s, $s, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            try { $resized.SetResolution($bitmap.HorizontalResolution, $bitmap.VerticalResolution) } catch {}

            $g = [System.Drawing.Graphics]::FromImage($resized)
            $g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
            $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
            $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            $g.Clear([System.Drawing.Color]::Transparent)
            $g.DrawImage($bitmap, 0, 0, $s, $s)
            $g.Dispose()

            $msPng = New-Object System.IO.MemoryStream
            $resized.Save($msPng, [System.Drawing.Imaging.ImageFormat]::Png)
            $bytes = $msPng.ToArray()
            $msPng.Dispose()
            $resized.Dispose()

            $images += ,@($s, $bytes)
        }

        $fs = [System.IO.File]::Open($OutputFile, [System.IO.FileMode]::Create)
        $bw = New-Object System.IO.BinaryWriter($fs)

        # ICONDIR: Reserved(2) = 0, Type(2)=1 for icons, Count(2)
        $bw.Write([UInt16]0)
        $bw.Write([UInt16]1)
        $bw.Write([UInt16]($images.Count))

        # Calculate header size: 6 + 16 * count
        $headerSize = 6 + 16 * $images.Count
        $offset = $headerSize

        foreach ($img in $images) {
            $s = $img[0]
            $bytes = $img[1]
            # width/height byte is 0 for 256 or larger
            if ($s -ge 256) {
                $widthByte = [byte]0
            } else {
                $widthByte = [byte]$s
            }

            if ($s -ge 256) {
                $heightByte = [byte]0
            } else {
                $heightByte = [byte]$s
            }
            $bw.Write($widthByte)
            $bw.Write($heightByte)
            $bw.Write([byte]0) # color palette
            $bw.Write([byte]0) # reserved
            $bw.Write([UInt16]1) # color planes
            $bw.Write([UInt16]32) # bits per pixel
            $bw.Write([UInt32]($bytes.Length)) # size of image data
            $bw.Write([UInt32]($offset)) # offset of image data
            $offset += $bytes.Length
        }

        foreach ($img in $images) {
            $bw.Write($img[1])
        }

        $bw.Flush()
        $bw.Close()
        $fs.Close()

        Write-Log "Wrote icon: '$OutputFile'." -Severity Verbose
        Write-Log "Ending ConvertTo-DowserIco"
        return $true
    }
    catch {
        Write-Log "ConvertTo-DowserIco failed creating icon '$OutputFile': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Error
        return $false
    }
    finally {
        if ($fs) { $fs.Dispose() }
        if ($ms) { $ms.Dispose() }
        if ($bitmap) { $bitmap.Dispose() }
        if ($tempFile -and (Test-Path $tempFile)) {
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
            Write-Log "Temp file cleaned up." -Severity Verbose
        }
    }
}

# Usage:
# ConvertTo-Ico -InputFilePath "\\server\share\logo.jpg" -OutputFile "\\server\share\logo.ico"

