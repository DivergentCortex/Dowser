#Requires -Version 5.1

function Export-DowserJsonAssessment {
    <#
    .SYNOPSIS
        Exports a directory-level JSON assessment report.

    .DESCRIPTION
        Scans JSON and JSONL files once, then writes separate CSV reports for the directory
        summary, representative schemas, and every key-path coverage classification.

    .NOTES
        This is an assessment export. It writes metadata reports, not source documents or values.

    .PARAMETER Path
        Directory or JSON file to assess.

    .PARAMETER OutputDirectory
        Destination directory for the CSV report files.

    .PARAMETER ProfileLimit
        Maximum representative schema profiles to include.

    .PARAMETER ThreadCount
        Maximum concurrent JSON readers.

    .PARAMETER Force
        Replace existing report files.

    .EXAMPLE
        Export-DowserJsonAssessment -Path ./exports -OutputDirectory ./json-assessment

        Creates the output directory when needed and writes three CSV files.

    .OUTPUTS
        PSCustomObject with OutputDirectory, SummaryPath, SchemaProfilesPath,
        KeyValidationPath, and ValidationRows.

    .LINK
        Get-DowserJsonKey
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$OutputDirectory,

        [ValidateRange(1, 100)]
        [int]$ProfileLimit = 10,

        [int]$ThreadCount = [Math]::Min(8, [Environment]::ProcessorCount),

        [switch]$Force
    )

    $outputRoot = [System.IO.Path]::GetFullPath($OutputDirectory)
    $outputFiles = @(
        (Join-Path $outputRoot 'directory-summary.csv'),
        (Join-Path $outputRoot 'schema-profiles.csv'),
        (Join-Path $outputRoot 'key-validation.csv')
    )

    if ((Test-Path -LiteralPath $outputRoot) -and -not $Force -and @($outputFiles | Where-Object { Test-Path -LiteralPath $_ }).Count -gt 0) {
        Write-Log "Export-DowserJsonAssessment will not replace report files in '$outputRoot' without -Force" -Severity Error
        return
    }

    if (-not $PSCmdlet.ShouldProcess($outputRoot, "Export JSON assessment for '$Path'")) {
        return
    }

    try {
        if (-not (Test-Path -LiteralPath $outputRoot)) {
            New-Item -ItemType Directory -Path $outputRoot -Force -ErrorAction Stop | Out-Null
        }

        $comparison = @(Get-DowserJsonKey -Path $Path -Compare -ProfileLimit $ProfileLimit -ThreadCount $ThreadCount)
        $summary = @($comparison | Where-Object { $_.ResultType -eq 'DirectorySummary' })
        $profiles = @($comparison | Where-Object { $_.ResultType -eq 'SchemaProfile' })

        $summary | Export-Csv -LiteralPath $outputFiles[0] -NoTypeInformation -Encoding utf8 -Force
        $profiles | Export-Csv -LiteralPath $outputFiles[1] -NoTypeInformation -Encoding utf8 -Force
        $global:DowserJsonLastValidation | Export-Csv -LiteralPath $outputFiles[2] -NoTypeInformation -Encoding utf8 -Force
    }
    catch {
        Write-Log "Export-DowserJsonAssessment could not write '$outputRoot': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Error
        return
    }

    Write-Log "Export-DowserJsonAssessment wrote JSON assessment reports to '$outputRoot'" -Severity Info
    [pscustomobject]@{
        OutputDirectory = $outputRoot
        SummaryPath = $outputFiles[0]
        SchemaProfilesPath = $outputFiles[1]
        KeyValidationPath = $outputFiles[2]
        ValidationRows = $global:DowserJsonLastValidation.Count
    }
}
