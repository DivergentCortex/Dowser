function ConvertTo-DowserBase64 {
    <#
.SYNOPSIS
    Encodes an image file to a Base64 string, or decodes a Base64 string back to an image file.

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
    Encode mode (default) reads an image file and returns its Base64 string. With
    -IncludeHeader the result is prefixed with a 'data:<mime>;base64,' header; the MIME
    type comes from the file extension (png, jpg, jpeg, gif, svg, webp, otherwise
    application/octet-stream). The result goes to -OutputFile, the clipboard
    (-CopyToClipboard), or the pipeline. If the clipboard is unavailable the function
    warns and emits the string instead.

    Decode mode (-Decode) reads -Path as a file when it resolves to one, otherwise as a
    literal Base64 string, strips any 'data:...;base64,' header, and writes the decoded
    bytes to -OutputFile, which is required.

.PARAMETER Path
    Path to the input image file when encoding, or a path to a text file (or a
    literal Base64 string) when decoding. Accepts pipeline input and carries the
    aliases ImagePath and FullName.

.PARAMETER OutputFile
    Path to write the result to. Optional when encoding (the string is emitted to
    the pipeline if omitted). Required when decoding.

.PARAMETER Decode
    Switch that decodes a Base64 string back into a binary file instead of encoding.

.PARAMETER IncludeHeader
    Switch that prefixes the encoded output with a 'data:<mime>;base64,' data URI
    header. Encode mode only.

.PARAMETER CopyToClipboard
    Switch that copies the encoded string to the clipboard. Falls back to the
    pipeline when the clipboard is unavailable. Encode mode only.

.EXAMPLE
    ConvertTo-DowserBase64 -Path 'C:\images\logo.png' -IncludeHeader

    Encodes logo.png and emits a data URI string to the pipeline.

.EXAMPLE
    ConvertTo-DowserBase64 -Path 'C:\images\logo.png' -OutputFile 'C:\images\logo.b64.txt'

    Encodes logo.png and writes the Base64 text to logo.b64.txt.

.EXAMPLE
    ConvertTo-DowserBase64 -Path 'C:\images\logo.b64.txt' -Decode -OutputFile 'C:\images\logo.png'

    Reads a Base64 text file and decodes it back to a binary PNG.

.INPUTS
    System.String
    You can pipe a file path to this function.

.OUTPUTS
    System.String
    When encoding without an output file, the Base64 (or data URI) string is
    emitted to the pipeline. Decode mode writes a file and returns nothing.
#>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('ImagePath', 'FullName')]
        [string]$Path,

        [Parameter(Position = 1)]
        [string]$OutputFile,

        [switch]$Decode,

        [switch]$IncludeHeader,

        [switch]$CopyToClipboard
    )

    Write-Log "Starting ConvertTo-DowserBase64"

    $resolvedInput = $Path
    if (Test-Path $Path) {
        $resolvedInput = (Resolve-Path $Path).Path
    }
    elseif (-not $Decode) {
        Write-Log "ConvertTo-DowserBase64: input file '$Path' not found." -Severity Error
        return
    }

    if ($OutputFile) {
        $OutputFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputFile)
    }

    if ($Decode) {
        if (-not $OutputFile) {
            Write-Log "ConvertTo-DowserBase64: output file is required for decoding." -Severity Error
            return
        }

        Write-Log "Decoding Base64 to image: '$resolvedInput'" -Severity Verbose

        try {
            if (Test-Path $resolvedInput) {
                $b64Str = Get-Content $resolvedInput -Raw
            }
            else {
                $b64Str = $Path
            }

            if ($b64Str -match "base64,") {
                $b64Str = $b64Str.Split(",")[1]
            }

            $b64Str = $b64Str.Trim()

            $bytes = [Convert]::FromBase64String($b64Str)
            [System.IO.File]::WriteAllBytes($OutputFile, $bytes)
            Write-Log "Decoded successfully to: '$OutputFile'" -Severity Verbose
        }
        catch {
            Write-Log "ConvertTo-DowserBase64 failed decoding '$resolvedInput' to '$OutputFile': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Error
        }
    }
    else {
        Write-Log "Encoding image to Base64: '$resolvedInput'" -Severity Verbose

        try {
            $bytes = [System.IO.File]::ReadAllBytes($resolvedInput)
            $b64 = [Convert]::ToBase64String($bytes)

            if ($IncludeHeader) {
                $ext = [System.IO.Path]::GetExtension($resolvedInput).ToLower()
                $mime = switch ($ext) {
                    ".png" {
                        "image/png"
                    }
                    ".jpg" {
                        "image/jpeg"
                    }
                    ".jpeg" {
                        "image/jpeg"
                    }
                    ".gif" {
                        "image/gif"
                    }
                    ".svg" {
                        "image/svg+xml"
                    }
                    ".webp" {
                        "image/webp"
                    }
                    default {
                        "application/octet-stream"
                    }
                }
                $b64 = "data:$mime;base64,$b64"
            }

            if ($OutputFile) {
                Set-Content -Path $OutputFile -Value $b64 -Encoding UTF8 -ErrorAction Stop
                Write-Log "Saved Base64 output to file: '$OutputFile'" -Severity Verbose
            }

            # set-clipboard is missing in headless sessions, so warn instead of throwing
            if ($CopyToClipboard) {
                $clipboardOk = $false
                if (Get-Command -Name Set-Clipboard -ErrorAction SilentlyContinue) {
                    try {
                        Set-Clipboard -Value $b64 -ErrorAction Stop
                        $clipboardOk = $true
                        Write-Log "Base64 copied to clipboard." -Severity Verbose
                    }
                    catch {
                        Write-Log "ConvertTo-DowserBase64 failed copying to clipboard: $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Warning
                    }
                }
                else {
                    Write-Log "Set-Clipboard is not available on this platform." -Severity Warning
                }
                if (-not $clipboardOk -and -not $OutputFile) {
                    Write-Log "Emitting Base64 to the pipeline as clipboard fallback." -Severity Verbose
                    Write-Output $b64
                }
            }

            if (-not $OutputFile -and -not $CopyToClipboard) {
                # nowhere else for it to go, so hand it to the pipeline
                Write-Output $b64
            }
            elseif (-not $OutputFile) {
                Write-Log "Base64 length: $($b64.Length) chars." -Severity Verbose
            }

        }
        catch {
            Write-Log "ConvertTo-DowserBase64 failed encoding '$resolvedInput': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Error
        }
    }

    Write-Log "Ending ConvertTo-DowserBase64"
}
