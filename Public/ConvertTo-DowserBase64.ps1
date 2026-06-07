function ConvertTo-DowserBase64 {
<#
.SYNOPSIS
    Converts images to Base64 strings and vice-versa using pure PowerShell.

.DESCRIPTION
    This script converts image files (JPG, PNG, GIF, etc.) into Base64 strings.
    It can also decode Base64 strings back into image files.
    
    Features:
    - Pure PowerShell/.NET implementation (No Python dependency).
    - Clipboard support.
    - Data URI header generation.
    - Decoding support.

.PARAMETER ImagePath
    Path to the input image file (encoding) or text file/string (decoding).

.PARAMETER OutputFile
    Path to save the result.

.PARAMETER Decode
    Switch to decode Base64 back to an image.

.PARAMETER IncludeHeader
    Adds 'data:image/<type>;base64,' header.

.PARAMETER CopyToClipboard
    Copies result to clipboard (text for encode, not supported for decode output).
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, Position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
    [Alias('ImagePath', 'FullName')]
    [string]$Path,

    [Parameter(Position=1)]
    [string]$OutputFile,

    [switch]$Decode,

    [switch]$IncludeHeader,

    [switch]$CopyToClipboard
)

$ErrorActionPreference = "Stop"

# --- Main Execution ---

$resolvedInput = $Path
if (Test-Path $Path) {
    $resolvedInput = (Resolve-Path $Path).Path
} elseif (-not $Decode) {
    Write-Error "Input file '$Path' not found."
    return
}

if ($OutputFile) {
    $OutputFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputFile)
}

# 1. DECODE MODE
if ($Decode) {
    if (-not $OutputFile) {
        Write-Error "Output file is required for decoding."
        return
    }

    Write-Verbose "Decoding Base64 to Image..."
    
    try {
        # Check if input is a file or raw string
        if (Test-Path $resolvedInput) {
            $b64Str = Get-Content $resolvedInput -Raw
        } else {
            $b64Str = $Path
        }

        # Strip header if present (e.g. data:image/png;base64,...)
        if ($b64Str -match "base64,") { 
            $b64Str = $b64Str.Split(",")[1] 
        }
        
        $b64Str = $b64Str.Trim()
        
        $bytes = [Convert]::FromBase64String($b64Str)
        [System.IO.File]::WriteAllBytes($OutputFile, $bytes)
        Write-Verbose "Decoded successfully to: $OutputFile"
    } catch {
        Write-Error "PowerShell decoding failed: $_"
    }
}
# 2. ENCODE MODE
else {
    Write-Verbose "Converting Image to Base64..."
    
    try {
        $bytes = [System.IO.File]::ReadAllBytes($resolvedInput)
        $b64 = [Convert]::ToBase64String($bytes)
        
        if ($IncludeHeader) {
            $ext = [System.IO.Path]::GetExtension($resolvedInput).ToLower()
            $mime = switch ($ext) {
                ".png" { "image/png" }
                ".jpg" { "image/jpeg" }
                ".jpeg" { "image/jpeg" }
                ".gif" { "image/gif" }
                ".svg" { "image/svg+xml" }
                ".webp" { "image/webp" }
                Default { "application/octet-stream" }
            }
            $b64 = "data:$mime;base64,$b64"
        }
        
        if ($OutputFile) {
            Set-Content -Path $OutputFile -Value $b64 -Encoding UTF8
            Write-Verbose "Saved to file: $OutputFile"
        }

        # Handle Clipboard / Console Output
        if ($CopyToClipboard) {
            Set-Clipboard -Value $b64
            Write-Verbose "Copied to clipboard!"
        } 
        
        if (-not $OutputFile -and -not $CopyToClipboard) {
            Write-Verbose "`n--- Base64 Output ---"
            Write-Verbose $b64
            Write-Verbose "---------------------"
        } elseif (-not $OutputFile) {
            Write-Verbose "Length: $($b64.Length) chars"
        }

    } catch {
        Write-Error "PowerShell encoding failed: $_"
    }
}

}
