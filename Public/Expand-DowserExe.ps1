#Requires -Version 5.1
<#
.SYNOPSIS
    Extracts files from extractable EXE archives using 7-Zip.

.DESCRIPTION
    Runs Test-DowserExtractable first to verify the EXE contains extractable
    payloads, then uses 7-Zip to extract the contents to a destination folder.

    If the EXE is not extractable (compiled binary, ps2exe wrapper, etc.),
    a warning is emitted with the classification details and no extraction
    is attempted.

    Supports -WhatIf and -Confirm via ShouldProcess.

.PARAMETER Path
    Path to one or more EXE files to extract. Accepts pipeline input.
    Also accepts output from Test-DowserExtractable (pipes the Path property).

.PARAMETER Destination
    Target directory for extracted files. Defaults to a subfolder named
    "<ExeName>_extracted" in the same directory as the EXE.

.PARAMETER SevenZipPath
    Path to 7z executable. On Windows, defaults to the standard 7-Zip install path.
    On Linux/macOS, defaults to '7z' (expected on PATH via package manager).

.PARAMETER Force
    Overwrite existing destination directory contents without prompting.

.PARAMETER PassThru
    Return the extraction result object to the pipeline.

.EXAMPLE
    Expand-DowserExe -Path "D:\Downloads\Setup.exe"

.EXAMPLE
    Expand-DowserExe -Path "D:\Downloads\Setup.exe" -Destination "D:\Extracted\Setup"

.EXAMPLE
    Test-DowserExtractable -Path "D:\Downloads" -Recurse | Where-Object Extractable | Expand-DowserExe

.EXAMPLE
    Expand-DowserExe -Path "\\server\share\installer.exe" -Force

.NOTES
    Author: Curtis Leggett / Divergent Cortex
    Alias: dexpand, dextract
    Related: Test-DowserExtractable (detection without extraction)
    Requires: 7-Zip (mandatory for extraction)
#>

# extract payload from SFX/installer EXEs. runs Test-DowserExtractable first,
# then 7z x to pull files. skips non-extractable binaries with a warning.

function Expand-DowserExe {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('FullName')]
        [string[]]$Path,

        [Parameter(Position = 1)]
        [string]$Destination,

        [string]$SevenZipPath = $(if ($IsWindows -eq $false) { '7z' } else { Join-Path ${env:ProgramFiles} '7-Zip\7z.exe' }),

        [switch]$Force,

        [switch]$PassThru
    )

    begin {
        if (-not (Test-Path -LiteralPath $SevenZipPath)) {
            Write-Error "7-Zip not found at '$SevenZipPath'. Install 7-Zip or specify -SevenZipPath."
            return
        }
        Write-Verbose "Using 7-Zip: $SevenZipPath"
    }

    process {
        foreach ($inputPath in $Path) {
            # Resolve the file
            if (-not (Test-Path -LiteralPath $inputPath -PathType Leaf)) {
                Write-Warning "File not found: $inputPath"
                continue
            }

            $file = Get-Item -LiteralPath $inputPath -ErrorAction SilentlyContinue
            if (-not $file) {
                Write-Warning "Cannot access: $inputPath"
                continue
            }

            Write-Verbose "Checking: $($file.FullName)"

            # Run extractability test
            $testResult = Test-DowserExtractable -Path $file.FullName -SevenZipPath $SevenZipPath

            if (-not $testResult.Extractable) {
                Write-Warning "$($file.Name): Not extractable ($($testResult.Classification)). $($testResult.Details)"
                if ($PassThru) {
                    [PSCustomObject]@{
                        Path           = $file.FullName
                        Destination    = $null
                        Success        = $false
                        ExitCode       = $null
                        Classification = $testResult.Classification
                        FileCount      = 0
                        ArchiveType    = $testResult.ArchiveType
                        Details        = $testResult.Details
                    }
                }
                continue
            }

            # Determine destination folder
            $dest = if ($Destination) {
                $Destination
            }
            else {
                Join-Path $file.DirectoryName "$($file.BaseName)_extracted"
            }

            # Check existing destination
            if ((Test-Path -LiteralPath $dest) -and -not $Force) {
                Write-Warning "Destination already exists: $dest. Use -Force to overwrite."
                continue
            }

            if ($PSCmdlet.ShouldProcess($file.FullName, "Extract to '$dest'")) {
                # Create destination if needed
                if (-not (Test-Path -LiteralPath $dest)) {
                    New-Item -ItemType Directory -Path $dest -Force | Out-Null
                    Write-Verbose "Created destination: $dest"
                }

                Write-Verbose "Extracting $($file.Name) -> $dest"
                $7zArgs = @('x', $file.FullName, "-o$dest", '-y')
                if ($Force) { $7zArgs += '-aoa' }  # overwrite all

                $output = & $SevenZipPath @7zArgs 2>&1 | Out-String
                $exitCode = $LASTEXITCODE

                $success = ($exitCode -eq 0)
                if ($success) {
                    $extractedCount = (Get-ChildItem -LiteralPath $dest -Recurse -File -ErrorAction SilentlyContinue).Count
                    Write-Verbose "Extraction complete: $extractedCount files extracted to $dest"
                }
                else {
                    Write-Warning "7-Zip returned exit code $exitCode for $($file.Name)"
                }

                $extractResult = [PSCustomObject]@{
                    Path           = $file.FullName
                    Destination    = $dest
                    Success        = $success
                    ExitCode       = $exitCode
                    Classification = $testResult.Classification
                    FileCount      = if ($success) { $extractedCount } else { 0 }
                    ArchiveType    = $testResult.ArchiveType
                    Details        = if ($success) { "Extracted to $dest" } else { "7-Zip exit code: $exitCode" }
                }

                if ($PassThru) {
                    $extractResult
                }
                else {
                    Write-Verbose "$($file.Name): $($extractResult.Details)"
                }
            }
        }
    }
}
