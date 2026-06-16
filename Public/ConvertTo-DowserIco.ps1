function ConvertTo-DowserIco {
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

    # platform guard: System.Drawing needs Windows GDI+ ($IsWindows null on 5.1 = Windows)
    if ($IsWindows -eq $false) {
        Write-Warning "ConvertTo-DowserIco requires Windows (System.Drawing/GDI+). Not available on this platform."
        return $null
    }

    Add-Type -AssemblyName System.Drawing

    if (-not (Test-Path $InputFilePath)) {
        Write-Error "Input file '$InputFilePath' does not exist."
        return $false
    }

    $InputFilePath = (Resolve-Path $InputFilePath).Path

    # If input is a UNC path, copy to temp first for processing
    $tempFile = $null
    if ($InputFilePath -like '\\*') {
        $tempFile = Join-Path $env:TEMP "$([System.IO.Path]::GetRandomFileName())"
        Write-Verbose "UNC path detected. Copying to temp: $tempFile"
        try {
            Copy-Item -Path $InputFilePath -Destination $tempFile -Force
            $InputFilePath = $tempFile
            Write-Verbose "  + File copied successfully"
        } catch {
            Write-Error "Failed to copy UNC file to temp: $_"
            return $false
        }
    }

    if (-not $OutputFile) {
        $OutputFileName = [IO.Path]::GetFileNameWithoutExtension($InputFilePath) + '.ico'
        $OutputDir = Split-Path $InputFilePath -Parent
        $OutputFile = Join-Path $OutputDir $OutputFileName
    } else {
        # Resolve tilde/PS-drive paths; output file may not exist yet so use unresolved provider path
        $OutputFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputFile)
        # If the user supplied an output path, ensure the directory exists (create if needed)
        $OutputDir = Split-Path $OutputFile -Parent
        if ($OutputDir -and -not (Test-Path $OutputDir)) {
            New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
        }
    }

    try {
        # Read file into memory (handles UNC paths better)
        $fileBytes = [System.IO.File]::ReadAllBytes($InputFilePath)
        $ms = New-Object System.IO.MemoryStream(, $fileBytes)
        $bitmap = [System.Drawing.Bitmap]::FromStream($ms)
    } catch {
        Write-Error "Failed to load image '$InputFilePath': $_"
        return $false
    }

    # Build multi-size ICO manually using PNG-compressed images (supported on modern Windows)
    # Accept requested ICO sizes up to 512. ICO directory width/height fields are 1 byte
    # (0 means 256). For sizes >=256 we set the width/height byte to 0 but embed the
    # full PNG image data at the requested resolution.
    $IcoSizes = @($IcoSizes)
    if (-not $IcoSizes -or (@($IcoSizes) | Measure-Object).Count -eq 0) {
        $IcoSizes = @(256)
    }

    # Validate sizes: only allow common icon sizes
    $validSizes = @(16,32,48,64,128,256,512)
    $sizes = $IcoSizes | ForEach-Object {
        $n = [int]$_
        if ($n -in $validSizes) { $n } else { 
            Write-Warning "Size $n not in valid set (16,32,48,64,128,256,512), skipping"
            $null 
        }
    } | Where-Object { $_ -ne $null } | Select-Object -Unique | Sort-Object
    
    if ($sizes.Count -eq 0) {
        $sizes = @(512)
        Write-Warning "No valid sizes specified, using default: 512px"
    }
    $images = @()
    try {
        foreach ($s in $sizes) {
            # Create resized bitmap using a compatible 32bpp ARGB pixel format to avoid GetHicon errors
            $resized = New-Object System.Drawing.Bitmap($s, $s, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            # Preserve original image DPI
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

            # store tuple: size, bytes
            $images += ,@($s, $bytes)
        }

        # Write ICO header and directory
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
            # width and height fields are 1 byte; 0 means 256 or larger
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

        # Write image data
        foreach ($img in $images) {
            $bw.Write($img[1])
        }

        $bw.Flush()
        $bw.Close()
        $fs.Close()

        Write-Output "Wrote icon: $OutputFile"
        return $true
    } catch {
        Write-Error "Failed to create/save icon: $_"
        return $false
    } finally {
        if ($fs) { $fs.Dispose() }
        if ($ms) { $ms.Dispose() }
        if ($bitmap) { $bitmap.Dispose() }
        if ($tempFile -and (Test-Path $tempFile)) {
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
            Write-Verbose "  + Temp file cleaned up"
        }
    }
}

# Usage:
# ConvertTo-Ico -InputFilePath "\\server.example.com\Root\project\VdiData\appname.jpg" -OutputFile "\\server.example.com\Root\project\VdiData\appname.ico"

