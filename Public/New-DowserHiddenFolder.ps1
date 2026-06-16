function New-DowserHiddenFolder {
    <#
    .SYNOPSIS
        Create a new folder and mark it Hidden+System, or apply those attributes to an existing folder.

    .DESCRIPTION
        Creates a hidden/system folder that won't appear in normal directory listings.
        Useful for storing module-private data, config caches, or temporary work dirs
        that should stay out of sight in Windows Explorer.

        If -Path already exists, attributes are applied without creating a new folder.
        Use -Force to suppress the "already exists" warning.

    .PARAMETER Path
        Full path of the folder to create or modify. Required.

    .PARAMETER Force
        Suppress warning when folder already exists; just apply attributes and continue.

    .PARAMETER AttributesOnly
        Skip folder creation entirely -- only apply Hidden+System to an existing folder.
        Errors if the path doesn't exist.

    .EXAMPLE
        New-DowserHiddenFolder -Path 'D:\Projects\.cache'

    .EXAMPLE
        New-DowserHiddenFolder -Path 'C:\Temp\.dowserwork' -Force

    .EXAMPLE
        New-DowserHiddenFolder -Path 'D:\Existing\.config' -AttributesOnly

    .NOTES
        Source: create-hiddenfolder (General_Scripts -- was hardcoded to X:\synapse-sql-v3.3\.$svcconf)
        Rewritten to accept -Path parameter; no hardcoded paths.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('FullName')]
        [string]$Path,

        [switch]$Force,

        [switch]$AttributesOnly
    )

    process {
        $alreadyExists = Test-Path -LiteralPath $Path

        if ($AttributesOnly -and -not $alreadyExists) {
            Write-Error "-AttributesOnly specified but '$Path' does not exist."
            return
        }

        if (-not $alreadyExists -and -not $AttributesOnly) {
            if ($PSCmdlet.ShouldProcess($Path, 'New-Item -ItemType Directory')) {
                $null = New-Item -ItemType Directory -Path $Path -ErrorAction Stop
                Write-Verbose "Created directory: $Path"
            }
        }
        elseif ($alreadyExists -and -not $Force -and -not $AttributesOnly) {
            Write-Warning "Folder already exists: $Path (use -Force to suppress this warning)"
        }

        if (Test-Path -LiteralPath $Path) {
            if ($PSCmdlet.ShouldProcess($Path, 'Set hidden attributes')) {
                $folder = Get-Item -LiteralPath $Path -Force -ErrorAction Stop

                # Canonical platform guard: $IsWindows is $null on PS 5.1, so -ne $false
                # means Windows and -eq $false means a non-Windows pwsh runtime.
                if ($IsWindows -ne $false) {
                    # Windows: NTFS Hidden+System attributes hide the folder in Explorer.
                    $folder.Attributes = [System.IO.FileAttributes]'Hidden,System,Directory'
                    Write-Verbose "Applied Hidden+System attributes to: $Path"

                    [PSCustomObject]@{
                        Path       = $folder.FullName
                        Attributes = $folder.Attributes
                    }
                }
                else {
                    # Linux/macOS have no NTFS Hidden/System attributes. True hiding is a
                    # leading dot on the folder name. Under -AttributesOnly we must not
                    # rename (that would move the path out from under the caller), so we
                    # warn honestly instead of silently doing nothing.
                    Write-Verbose 'NTFS Hidden/System attributes are Windows-only; on this platform a folder is hidden by a leading dot in its name.'
                    $leafName = $folder.Name

                    if ($AttributesOnly) {
                        if (-not $leafName.StartsWith('.')) {
                            Write-Warning "Cannot apply NTFS Hidden/System attributes on this platform, and -AttributesOnly forbids renaming '$Path' to a dot-prefixed name. The folder is NOT hidden."
                        }
                    }
                    elseif (-not $leafName.StartsWith('.')) {
                        $dottedName = '.' + $leafName
                        $parent     = Split-Path -Path $folder.FullName -Parent
                        $dottedPath = Join-Path $parent $dottedName
                        if (Test-Path -LiteralPath $dottedPath) {
                            Write-Warning "Cannot dot-prefix '$Path' for hiding: '$dottedPath' already exists. The folder is NOT hidden."
                        }
                        else {
                            Rename-Item -LiteralPath $folder.FullName -NewName $dottedName -ErrorAction Stop
                            $folder = Get-Item -LiteralPath $dottedPath -Force -ErrorAction Stop
                            Write-Verbose "Renamed to dot-prefixed (hidden on this platform): $dottedPath"
                        }
                    }

                    # Re-read so the returned Attributes reflect the real on-disk state,
                    # never a claimed Hidden,System value.
                    $folder = Get-Item -LiteralPath $folder.FullName -Force -ErrorAction Stop
                    [PSCustomObject]@{
                        Path         = $folder.FullName
                        Attributes   = $folder.Attributes
                        PlatformNote = 'NTFS Hidden/System attributes are Windows-only; on this platform hidden state is conveyed by a leading dot in the folder name.'
                    }
                }
            }
        }
    }
}
