#Requires -Version 5.1
<#
.SYNOPSIS
    Gets comprehensive file details from any file including executables, DLLs, and other types.
.DESCRIPTION
    Extracts all possible metadata, version information, extended properties, and file
    attributes from a given file using multiple methods: .NET classes, COM objects, and
    PowerShell cmdlets. Handles executables (PE header, .NET assembly info), regular files,
    and optionally directories.
.PARAMETER FilePath
    Path to the file to analyze. Accepts pipeline input by value and by property name (FullName).
.PARAMETER IncludeEmptyProperties
    Include properties that exist but have empty values.
.PARAMETER IncludeSignature
    Include digital signature information (slower).
.PARAMETER IncludeDirectories
    When a directory path is provided (e.g., piping Get-ChildItem results), include it
    instead of skipping. File-only metadata (hashes, version info, signatures, PE/assembly
    parsing) will be skipped for directories.
.EXAMPLE
    Get-DowserProperty -FilePath "C:\Windows\System32\notepad.exe"
.EXAMPLE
    Get-DowserProperty -FilePath "C:\Windows\System32\java.exe" -IncludeSignature -IncludeEmptyProperties
.EXAMPLE
    Get-ChildItem D:\Scripts -Filter *.ps1 | Get-DowserProperty
.NOTES
    Author: Curtis Leggett / PowerShell Codesmith
    Ported from: Get-FilePropertyDetails.ps1 (General_Scripts)
    Uses: Private\Format-DowserSize for human-readable file sizes
#>

# deep file inspector. shell COM, VersionInfo, PE header, .NET assembly, optional signature.
# shell COM is slow on UNC -- that's expected. IncludeSignature adds another 0.5-2s per file.

function Get-DowserProperty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('FullName', 'Path')]
        [string]$FilePath,

        [switch]$IncludeEmptyProperties,

        [switch]$IncludeSignature,

        # When a directory path is provided (common when piping Get-ChildItem results),
        # include it instead of writing a "not found" error. File-only metadata (hashes,
        # version info, signatures, PE/assembly parsing) will be skipped for directories.
        [switch]$IncludeDirectories
    )

    begin {
        Write-Verbose "Starting comprehensive file analysis"
    }

    process {
        if (-not (Test-Path -LiteralPath $FilePath)) {
            Write-Error "Path not found: $FilePath"
            return
        }

        try {
            $FileItem = Get-Item -LiteralPath $FilePath -ErrorAction Stop
        }
        catch {
            Write-Error "Unable to access file: $FilePath. $($_.Exception.Message)"
            return
        }

        $ResolvedFilePath = $FileItem.FullName
        $IsDirectory = [bool]$FileItem.PSIsContainer

        if ($IsDirectory -and -not $IncludeDirectories) {
            Write-Verbose "Skipping directory input (use -IncludeDirectories to include): $ResolvedFilePath"
            return
        }
        Write-Verbose "Analyzing file: $ResolvedFilePath"

        $FileDetails = [PSCustomObject]@{
            FilePath         = $ResolvedFilePath
            FileName         = Split-Path $ResolvedFilePath -Leaf
            Directory        = Split-Path $ResolvedFilePath -Parent
            Extension        = [System.IO.Path]::GetExtension($ResolvedFilePath)
            BaseName         = [System.IO.Path]::GetFileNameWithoutExtension($ResolvedFilePath)
            ItemType         = if ($IsDirectory) { 'Directory' } else { 'File' }

            # Common file metadata (Details tab)
            FileDescription  = $null
            ProductName      = $null
            ProductVersion   = $null
            FileVersion      = $null
            CompanyName      = $null
            Copyright        = $null
            OriginalFileName = $null
            InternalName     = $null
            Language         = $null
        }

        try {
            Write-Verbose "Getting basic file information..."

            if (-not $IsDirectory) {
                $FileDetails | Add-Member -MemberType NoteProperty -Name 'Size' -Value $FileItem.Length
                $FileDetails | Add-Member -MemberType NoteProperty -Name 'SizeFormatted' -Value (Format-DowserSize -DataValue $FileItem.Length)
            }
            $FileDetails | Add-Member -MemberType NoteProperty -Name 'CreationTime'   -Value $FileItem.CreationTime
            $FileDetails | Add-Member -MemberType NoteProperty -Name 'LastWriteTime'  -Value $FileItem.LastWriteTime
            $FileDetails | Add-Member -MemberType NoteProperty -Name 'LastAccessTime' -Value $FileItem.LastAccessTime
            $FileDetails | Add-Member -MemberType NoteProperty -Name 'Attributes'     -Value $FileItem.Attributes
            $FileDetails | Add-Member -MemberType NoteProperty -Name 'IsReadOnly'     -Value $FileItem.IsReadOnly
            $FileDetails | Add-Member -MemberType NoteProperty -Name 'IsHidden'       -Value (($FileItem.Attributes -band [System.IO.FileAttributes]::Hidden) -eq [System.IO.FileAttributes]::Hidden)
            $FileDetails | Add-Member -MemberType NoteProperty -Name 'IsSystem'       -Value (($FileItem.Attributes -band [System.IO.FileAttributes]::System) -eq [System.IO.FileAttributes]::System)

            # 2. Version Information
            Write-Verbose "Getting version information..."
            try {
                if ($IsDirectory) { throw [System.InvalidOperationException]::new('Version information is not applicable to directories.') }

                $VersionInfo = $FileItem.VersionInfo
                if (-not $VersionInfo) {
                    $VersionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($ResolvedFilePath)
                }

                if (![string]::IsNullOrWhiteSpace($VersionInfo.FileDescription) -or $IncludeEmptyProperties) { $FileDetails.FileDescription = $VersionInfo.FileDescription }
                if (![string]::IsNullOrWhiteSpace($VersionInfo.ProductName) -or $IncludeEmptyProperties) { $FileDetails.ProductName = $VersionInfo.ProductName }
                if (![string]::IsNullOrWhiteSpace($VersionInfo.ProductVersion) -or $IncludeEmptyProperties) { $FileDetails.ProductVersion = $VersionInfo.ProductVersion }
                if (![string]::IsNullOrWhiteSpace($VersionInfo.FileVersion) -or $IncludeEmptyProperties) { $FileDetails.FileVersion = $VersionInfo.FileVersion }
                if (![string]::IsNullOrWhiteSpace($VersionInfo.CompanyName) -or $IncludeEmptyProperties) { $FileDetails.CompanyName = $VersionInfo.CompanyName }
                if (![string]::IsNullOrWhiteSpace($VersionInfo.LegalCopyright) -or $IncludeEmptyProperties) { $FileDetails.Copyright = $VersionInfo.LegalCopyright }
                if (![string]::IsNullOrWhiteSpace($VersionInfo.OriginalFilename) -or $IncludeEmptyProperties) { $FileDetails.OriginalFileName = $VersionInfo.OriginalFilename }
                if (![string]::IsNullOrWhiteSpace($VersionInfo.InternalName) -or $IncludeEmptyProperties) { $FileDetails.InternalName = $VersionInfo.InternalName }
                if (![string]::IsNullOrWhiteSpace($VersionInfo.Language) -or $IncludeEmptyProperties) { $FileDetails.Language = $VersionInfo.Language }

                if (($VersionInfo.FileMajorPart -ne 0 -or $VersionInfo.FileMinorPart -ne 0 -or $VersionInfo.FileBuildPart -ne 0 -or $VersionInfo.FilePrivatePart -ne 0) -or $IncludeEmptyProperties) {
                    $FileDetails | Add-Member -MemberType NoteProperty -Name 'FileVersionRaw' -Value ("{0}.{1}.{2}.{3}" -f $VersionInfo.FileMajorPart, $VersionInfo.FileMinorPart, $VersionInfo.FileBuildPart, $VersionInfo.FilePrivatePart)
                }
                if (($VersionInfo.ProductMajorPart -ne 0 -or $VersionInfo.ProductMinorPart -ne 0 -or $VersionInfo.ProductBuildPart -ne 0 -or $VersionInfo.ProductPrivatePart -ne 0) -or $IncludeEmptyProperties) {
                    $FileDetails | Add-Member -MemberType NoteProperty -Name 'ProductVersionRaw' -Value ("{0}.{1}.{2}.{3}" -f $VersionInfo.ProductMajorPart, $VersionInfo.ProductMinorPart, $VersionInfo.ProductBuildPart, $VersionInfo.ProductPrivatePart)
                }
                if (![string]::IsNullOrWhiteSpace($VersionInfo.LegalTrademarks) -or $IncludeEmptyProperties) {
                    $FileDetails | Add-Member -MemberType NoteProperty -Name 'LegalTrademarks' -Value $VersionInfo.LegalTrademarks
                }
                if (![string]::IsNullOrWhiteSpace($VersionInfo.Comments) -or $IncludeEmptyProperties) {
                    $FileDetails | Add-Member -MemberType NoteProperty -Name 'Comments' -Value $VersionInfo.Comments
                }
                if (![string]::IsNullOrWhiteSpace($VersionInfo.PrivateBuild) -or $IncludeEmptyProperties) {
                    $FileDetails | Add-Member -MemberType NoteProperty -Name 'PrivateBuild' -Value $VersionInfo.PrivateBuild
                }
                if (![string]::IsNullOrWhiteSpace($VersionInfo.SpecialBuild) -or $IncludeEmptyProperties) {
                    $FileDetails | Add-Member -MemberType NoteProperty -Name 'SpecialBuild' -Value $VersionInfo.SpecialBuild
                }

                $FileDetails | Add-Member -MemberType NoteProperty -Name 'IsDebug'        -Value $VersionInfo.IsDebug
                $FileDetails | Add-Member -MemberType NoteProperty -Name 'IsPatched'      -Value $VersionInfo.IsPatched
                $FileDetails | Add-Member -MemberType NoteProperty -Name 'IsPreRelease'   -Value $VersionInfo.IsPreRelease
                $FileDetails | Add-Member -MemberType NoteProperty -Name 'IsPrivateBuild' -Value $VersionInfo.IsPrivateBuild
                $FileDetails | Add-Member -MemberType NoteProperty -Name 'IsSpecialBuild' -Value $VersionInfo.IsSpecialBuild
            }
            catch {
                Write-Verbose "Version information not available or error: $($_.Exception.Message)"
            }

            # 3. Extended Properties via Shell.Application COM (Windows-only; $IsWindows is $null on 5.1)
            if ($IsWindows -ne $false) {
                Write-Verbose "Getting extended properties using COM object..."
                try {
                    $Shell = New-Object -ComObject Shell.Application
                $FolderPath = Split-Path $ResolvedFilePath
                $FileName = Split-Path $ResolvedFilePath -Leaf

                $Folder = $Shell.Namespace($FolderPath)
                if ($Folder) {
                    $File = $Folder.ParseName($FileName)
                    if ($File) {
                        $ExtendedProperties = @{}
                        for ($i = 0; $i -le 500; $i++) {
                            $PropertyName = $Folder.GetDetailsOf($null, $i)
                            if ($PropertyName) {
                                $PropertyValue = $Folder.GetDetailsOf($File, $i)
                                if ($PropertyValue -or $IncludeEmptyProperties) {
                                    $CleanPropertyName = $PropertyName -replace '[^\w]', ''
                                    if ($CleanPropertyName -and $CleanPropertyName -ne '') {
                                        $ExtendedProperties["Ext_$CleanPropertyName"] = $PropertyValue
                                    }
                                }
                            }
                        }
                        foreach ($prop in $ExtendedProperties.GetEnumerator()) {
                            if (-not (Get-Member -InputObject $FileDetails -Name $prop.Key -ErrorAction SilentlyContinue)) {
                                $FileDetails | Add-Member -MemberType NoteProperty -Name $prop.Key -Value $prop.Value
                            }
                        }
                        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($File) | Out-Null
                    } else {
                        Write-Verbose "Could not parse file name in folder: $FileName"
                    }
                    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($Folder) | Out-Null
                } else {
                    Write-Verbose "Could not access folder via Shell.Application: $FolderPath"
                }
                [System.Runtime.InteropServices.Marshal]::ReleaseComObject($Shell) | Out-Null
                }
                catch {
                    Write-Verbose "Extended properties COM object error: $($_.Exception.Message)"
                }
            } else {
                Write-Verbose "Extended file properties via Shell.Application not available on this platform."
            }

            # 4. Hash Information
            Write-Verbose "Calculating file hashes..."
            try {
                if ($IsDirectory) { throw [System.InvalidOperationException]::new('Hash calculation is not applicable to directories.') }
                $MD5Hash    = Get-FileHash -LiteralPath $ResolvedFilePath -Algorithm MD5    -ErrorAction SilentlyContinue
                $SHA1Hash   = Get-FileHash -LiteralPath $ResolvedFilePath -Algorithm SHA1   -ErrorAction SilentlyContinue
                $SHA256Hash = Get-FileHash -LiteralPath $ResolvedFilePath -Algorithm SHA256 -ErrorAction SilentlyContinue
                $FileDetails | Add-Member -MemberType NoteProperty -Name 'MD5Hash'    -Value $MD5Hash.Hash
                $FileDetails | Add-Member -MemberType NoteProperty -Name 'SHA1Hash'   -Value $SHA1Hash.Hash
                $FileDetails | Add-Member -MemberType NoteProperty -Name 'SHA256Hash' -Value $SHA256Hash.Hash
            }
            catch {
                Write-Verbose "Hash calculation error: $($_.Exception.Message)"
            }

            # 5. Digital Signature (opt-in -- slow, Windows-only; $IsWindows null on 5.1 = Windows)
            if (($IsWindows -ne $false) -and $IncludeSignature) {
                Write-Verbose "Getting digital signature information..."
                try {
                    if ($IsDirectory) { throw [System.InvalidOperationException]::new('Digital signature is not applicable to directories.') }
                    $Signature = Get-AuthenticodeSignature -LiteralPath $ResolvedFilePath -ErrorAction SilentlyContinue
                    if ($Signature) {
                        $FileDetails | Add-Member -MemberType NoteProperty -Name 'SignatureStatus'        -Value $Signature.Status
                        $FileDetails | Add-Member -MemberType NoteProperty -Name 'SignatureStatusMessage' -Value $Signature.StatusMessage
                        $FileDetails | Add-Member -MemberType NoteProperty -Name 'SignerCertificate'      -Value $(if ($Signature.SignerCertificate) { $Signature.SignerCertificate.Subject } else { $null })
                        $FileDetails | Add-Member -MemberType NoteProperty -Name 'TimeStamperCertificate' -Value $(if ($Signature.TimeStamperCertificate) { $Signature.TimeStamperCertificate.Subject } else { $null })
                        $FileDetails | Add-Member -MemberType NoteProperty -Name 'SignatureType'          -Value $Signature.SignatureType
                    }
                }
                catch {
                    Write-Verbose "Digital signature error: $($_.Exception.Message)"
                }
            } elseif ($IncludeSignature -and -not $IsWindows) {
                Write-Verbose "Authenticode signature inspection requires Windows."
            }

            # 6. .NET Assembly Information (exe/dll only)
            if (-not $IsDirectory -and $ResolvedFilePath -match '\.(exe|dll)$') {
                Write-Verbose "Getting .NET assembly information..."
                try {
                    $Assembly = [System.Reflection.Assembly]::LoadFile($ResolvedFilePath)
                    $FileDetails | Add-Member -MemberType NoteProperty -Name 'DotNetVersion'   -Value $Assembly.ImageRuntimeVersion
                    $FileDetails | Add-Member -MemberType NoteProperty -Name 'AssemblyFullName' -Value $Assembly.FullName
                    $FileDetails | Add-Member -MemberType NoteProperty -Name 'AssemblyLocation' -Value $Assembly.Location
                    $FileDetails | Add-Member -MemberType NoteProperty -Name 'AssemblyGAC'      -Value $Assembly.GlobalAssemblyCache
                    $Attributes = $Assembly.GetCustomAttributes($false)
                    foreach ($attr in $Attributes) {
                        $attrName = $attr.GetType().Name -replace 'Attribute$', ''
                        if ($attr.GetType().GetProperty('Title')) {
                            $FileDetails | Add-Member -MemberType NoteProperty -Name "Assembly_$attrName" -Value $attr.Title -Force
                        } elseif ($attr.GetType().GetProperty('Description')) {
                            $FileDetails | Add-Member -MemberType NoteProperty -Name "Assembly_$attrName" -Value $attr.Description -Force
                        } elseif ($attr.GetType().GetProperty('Configuration')) {
                            $FileDetails | Add-Member -MemberType NoteProperty -Name "Assembly_$attrName" -Value $attr.Configuration -Force
                        }
                    }
                }
                catch {
                    Write-Verbose ".NET assembly information not available: $($_.Exception.Message)"
                }
            }

            # 7. PE Header (exe/dll only)
            if (-not $IsDirectory -and $ResolvedFilePath -match '\.(exe|dll)$') {
                Write-Verbose "Getting PE header information..."
                try {
                    $FileStream = [System.IO.File]::OpenRead($ResolvedFilePath)
                    $BinaryReader = New-Object System.IO.BinaryReader($FileStream)
                    $dosHeader = $BinaryReader.ReadBytes(64)
                    if ($dosHeader[0] -eq 0x4D -and $dosHeader[1] -eq 0x5A) {
                        $peOffset = [BitConverter]::ToInt32($dosHeader, 60)
                        $FileStream.Seek($peOffset, [System.IO.SeekOrigin]::Begin) | Out-Null
                        $peSignature = $BinaryReader.ReadBytes(4)
                        if ($peSignature[0] -eq 0x50 -and $peSignature[1] -eq 0x45) {
                            $FileDetails | Add-Member -MemberType NoteProperty -Name 'IsPEFile' -Value $true
                            $machine = [BitConverter]::ToUInt16($BinaryReader.ReadBytes(2), 0)
                            $FileDetails | Add-Member -MemberType NoteProperty -Name 'MachineType'   -Value $machine
                            $FileDetails | Add-Member -MemberType NoteProperty -Name 'Architecture'  -Value $(
                                switch ($machine) {
                                    0x014c { "i386" }
                                    0x0200 { "IA64" }
                                    0x8664 { "x64" }
                                    default { "Unknown ($machine)" }
                                }
                            )
                        }
                    }
                    $BinaryReader.Close()
                    $FileStream.Close()
                }
                catch {
                    Write-Verbose "PE header analysis error: $($_.Exception.Message)"
                    if ($BinaryReader) { $BinaryReader.Close() }
                    if ($FileStream) { $FileStream.Close() }
                }
            }
        }
        catch {
            Write-Error "Error analyzing file: $($_.Exception.Message)"
        }

        Write-Verbose "File analysis complete"
        return $FileDetails
    }

    end {
        Write-Verbose "Function execution completed"
    }
}
