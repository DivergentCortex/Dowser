function Get-DowserTemplate {
    <#
    .SYNOPSIS
        Retrieve Windows Explorer folder view settings: view mode and column definitions.

    .NOTES
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
        -  Author:        Curtis Leggett                                  -
        =  Copyright:     2026 Divergent Cortex                           =
        -  Organization:  Divergent Cortex                                -
        =  Version:       See docs/CHANGELOG.md                           =
        =-=-                       =-=-=-=-=-=-=-=                     -=-=
        -  it is not water they seek, but the truth beneath the trees     -
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

        Alias: dtemplate
        Source: Get-FolderTemplate.ps1 (standalone scripts, had live execution code outside function)
        Fixed: live execution code removed; -folderPath renamed to -Path; [CmdletBinding()] added.
        Shell.Application GetDetailsOf loop (0..500) can be slow, so Write-Progress is included.

    .DESCRIPTION
        Uses Shell.Application COM to query a folder's current Explorer view mode
        (Details, Tiles, Icons, etc.) and the list of visible column definitions
        with their index numbers and names.

        Useful for understanding or cloning a folder's Explorer template when
        automating folder setup.

        Windows only. Shell.Application COM is not available on Linux or macOS.

    .PARAMETER Path
        The folder path to inspect. Defaults to current directory.

    .EXAMPLE
        Get-DowserTemplate -Path D:\Projects

    .EXAMPLE
        Get-DowserTemplate

    .OUTPUTS
        PSCustomObject with Path, ViewMode, and Columns (array of Index/Name pairs).
    #>
    [CmdletBinding()]
    param (
        [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('FullName', 'folderPath')]
        [string]$Path = $PWD
    )

    begin {
        Write-Log "Starting Get-DowserTemplate"
        # needs shell.application com, IsWindows null on 5.1 means windows
        $unsupported = $IsWindows -eq $false
        if ($unsupported) {
            Write-Log "Get-DowserTemplate requires Windows Shell.Application COM. Not available on this platform." -Severity Warning
        }
    }

    process {
        if ($unsupported) { return }

        if (-not (Test-Path $Path)) {
            Write-Log "Get-DowserTemplate path not found: '$Path'" -Severity Warning
            return
        }

        $resolvedPath = (Resolve-Path $Path).ProviderPath

        $shell = $null
        try {
            Write-Log "Get-DowserTemplate querying Shell.Application for '$resolvedPath'"
            $shell = New-Object -ComObject Shell.Application
            $folder = $shell.Namespace($resolvedPath)

            if (-not $folder) {
                Write-Log "Get-DowserTemplate Shell.Application could not open namespace: '$resolvedPath'" -Severity Warning
                return
            }

            $viewMode = $folder.CurrentViewMode

            $columns = [System.Collections.Generic.List[object]]::new()
            for ($i = 0; $i -le 500; $i++) {
                if ($i % 50 -eq 0) {
                    Write-Progress -Activity "Get-DowserTemplate" -Status "Reading column $i / 500" -PercentComplete ($i / 5)
                }
                $name = $folder.GetDetailsOf($folder.Items(), $i)
                if ($name) {
                    $columns.Add([PSCustomObject]@{
                            Index = $i
                            Name  = $name
                        })
                }
            }
            Write-Progress -Activity "Get-DowserTemplate" -Completed
            Write-Log "Get-DowserTemplate found $($columns.Count) column(s) for '$resolvedPath'"

            [PSCustomObject]@{
                Path     = $resolvedPath
                ViewMode = $viewMode
                Columns  = $columns.ToArray()
            }
        }
        catch {
            Write-Log "Get-DowserTemplate failed querying Shell.Application for '$resolvedPath': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Error
        }
        finally {
            if ($null -ne $shell) {
                [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
            }
        }
    }

    end {
        Write-Log "Ending Get-DowserTemplate"
    }
}
