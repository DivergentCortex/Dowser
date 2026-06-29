function Get-DowserTemplate {
    <#
    .SYNOPSIS
        Retrieve Windows Explorer folder view settings: view mode and column definitions.

    .DESCRIPTION
        Uses Shell.Application COM to query a folder's current Explorer view mode
        (Details, Tiles, Icons, etc.) and the list of visible column definitions
        with their index numbers and names.

        Useful for understanding or cloning a folder's Explorer template when
        automating folder setup.

        Windows only -- Shell.Application COM is not available on Linux/macOS.

    .PARAMETER Path
        The folder path to inspect. Defaults to current directory.

    .EXAMPLE
        Get-DowserTemplate -Path D:\Projects

    .EXAMPLE
        Get-DowserTemplate

    .NOTES
        Alias: dtemplate
        Source: Get-FolderTemplate.ps1 (standalone scripts -- had live execution code outside function)
        Fixed: live execution code removed; -folderPath renamed to -Path; [CmdletBinding()] added.
        Shell.Application GetDetailsOf loop (0..500) can be slow -- Write-Progress included.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('FullName', 'folderPath')]
        [string]$Path = $PWD
    )

    # needs shell.application com, IsWindows null on 5.1 means windows
    if ($IsWindows -eq $false) {
        Write-Warning "Get-DowserTemplate requires Windows Shell.Application COM. Not available on this platform."
        return $null
    }

    process {
        if (-not (Test-Path $Path)) {
            Write-Warning "Path not found: $Path"
            return
        }

        $resolvedPath = (Resolve-Path $Path).ProviderPath

        try {
            $shell  = New-Object -ComObject Shell.Application
            $folder = $shell.Namespace($resolvedPath)

            if (-not $folder) {
                Write-Warning "Shell.Application could not open: $resolvedPath"
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

            [PSCustomObject]@{
                Path      = $resolvedPath
                ViewMode  = $viewMode
                Columns   = $columns.ToArray()
            }
        }
        catch {
            Write-Warning "Error querying folder template for '$Path': $_"
        }
    }
}
