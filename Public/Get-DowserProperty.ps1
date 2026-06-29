#Requires -Version 5.1

# deep file inspector. shell COM, VersionInfo, PE header, .NET assembly, optional signature.
# shell COM is slow on UNC, thats expected. IncludeSignature adds another 0.5-2s per file.

function Get-DowserProperty {
    <#
    .SYNOPSIS
        Gets detailed file metadata from any file including executables, DLLs, and other types.
    .NOTES
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
        -  Author:        Curtis Leggett                                  -
        =  Copyright:     2026 Divergent Cortex                           =
        -  Organization:  Divergent Cortex                                -
        =  Version:       See docs/CHANGELOG.md                           =
        =-=-                       =-=-=-=-=-=-=-=                     -=-=
        -  it is not water they seek, but the truth beneath the trees     -
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

        Ported from: Get-FilePropertyDetails.ps1 (standalone scripts)
        Uses: Private\Format-DowserSize for human-readable file sizes
    .DESCRIPTION
        Extracts all possible metadata, version information, extended properties, and file
        attributes from a given file using multiple methods: .NET classes, COM objects, and
        PowerShell cmdlets. Handles executables (PE header, .NET assembly info), regular files,
        and optionally directories.
    .PARAMETER FilePath
        Path to the file to analyze. Accepts pipeline input by value and by property name
        (FullName, Path).
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

        Returns full metadata for notepad.exe.
    .EXAMPLE
        Get-DowserProperty -FilePath "C:\Windows\System32\java.exe" -IncludeSignature -IncludeEmptyProperties

        Returns metadata including signature details and empty-valued properties.
    .EXAMPLE
        Get-ChildItem D:\Scripts -Filter *.ps1 | Get-DowserProperty

        Pipes every .ps1 file in D:\Scripts through the inspector.
    .INPUTS
        System.String
        You can pipe a file path to this function.
    .OUTPUTS
        PSCustomObject
        One object per file carrying metadata, version, extended, and attribute properties.
    #>
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
        Write-Log "Starting Get-DowserProperty"
    }

    process {
        if (-not (Test-Path -LiteralPath $FilePath)) {
            Write-Log "Get-DowserProperty path not found: '$FilePath'" -Severity Error
            return
        }

        try {
            $FileItem = Get-Item -LiteralPath $FilePath -ErrorAction Stop
        }
        catch {
            Write-Log "Get-DowserProperty failed accessing '$FilePath': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Error
            return
        }

        $ResolvedFilePath = $FileItem.FullName
        $IsDirectory = [bool]$FileItem.PSIsContainer

        if ($IsDirectory -and -not $IncludeDirectories) {
            Write-Log "Skipping directory input (use -IncludeDirectories to include): $ResolvedFilePath" -Severity Verbose
            return
        }
        Write-Log "Analyzing file: $ResolvedFilePath" -Severity Verbose

        $FileDetails = [PSCustomObject]@{
            FilePath         = $ResolvedFilePath
            FileName         = Split-Path $ResolvedFilePath -Leaf
            Directory        = Split-Path $ResolvedFilePath -Parent
            Extension        = [System.IO.Path]::GetExtension($ResolvedFilePath)
            BaseName         = [System.IO.Path]::GetFileNameWithoutExtension($ResolvedFilePath)
            ItemType         = if ($IsDirectory) {
                'Directory' 
            }
            else {
                'File' 
            }

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
            Write-Log "Getting basic file information..." -Severity Verbose

            if (-not $IsDirectory) {
                $FileDetails | Add-Member -MemberType NoteProperty -Name 'Size' -Value $FileItem.Length
                $FileDetails | Add-Member -MemberType NoteProperty -Name 'SizeFormatted' -Value (Format-DowserSize -DataValue $FileItem.Length)
            }
            $FileDetails | Add-Member -MemberType NoteProperty -Name 'CreationTime' -Value $FileItem.CreationTime
            $FileDetails | Add-Member -MemberType NoteProperty -Name 'LastWriteTime' -Value $FileItem.LastWriteTime
            $FileDetails | Add-Member -MemberType NoteProperty -Name 'LastAccessTime' -Value $FileItem.LastAccessTime
            $FileDetails | Add-Member -MemberType NoteProperty -Name 'Attributes' -Value $FileItem.Attributes
            $FileDetails | Add-Member -MemberType NoteProperty -Name 'IsReadOnly' -Value $FileItem.IsReadOnly
            $FileDetails | Add-Member -MemberType NoteProperty -Name 'IsHidden' -Value (($FileItem.Attributes -band [System.IO.FileAttributes]::Hidden) -eq [System.IO.FileAttributes]::Hidden)
            $FileDetails | Add-Member -MemberType NoteProperty -Name 'IsSystem' -Value (($FileItem.Attributes -band [System.IO.FileAttributes]::System) -eq [System.IO.FileAttributes]::System)

            Write-Log "Getting version information..." -Severity Verbose
            try {
                if ($IsDirectory) {
                    throw [System.InvalidOperationException]::new('Version information is not applicable to directories.') 
                }

                $VersionInfo = $FileItem.VersionInfo
                if (-not $VersionInfo) {
                    $VersionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($ResolvedFilePath)
                }

                if (![string]::IsNullOrWhiteSpace($VersionInfo.FileDescription) -or $IncludeEmptyProperties) {
                    $FileDetails.FileDescription = $VersionInfo.FileDescription 
                }
                if (![string]::IsNullOrWhiteSpace($VersionInfo.ProductName) -or $IncludeEmptyProperties) {
                    $FileDetails.ProductName = $VersionInfo.ProductName 
                }
                if (![string]::IsNullOrWhiteSpace($VersionInfo.ProductVersion) -or $IncludeEmptyProperties) {
                    $FileDetails.ProductVersion = $VersionInfo.ProductVersion 
                }
                if (![string]::IsNullOrWhiteSpace($VersionInfo.FileVersion) -or $IncludeEmptyProperties) {
                    $FileDetails.FileVersion = $VersionInfo.FileVersion 
                }
                if (![string]::IsNullOrWhiteSpace($VersionInfo.CompanyName) -or $IncludeEmptyProperties) {
                    $FileDetails.CompanyName = $VersionInfo.CompanyName 
                }
                if (![string]::IsNullOrWhiteSpace($VersionInfo.LegalCopyright) -or $IncludeEmptyProperties) {
                    $FileDetails.Copyright = $VersionInfo.LegalCopyright 
                }
                if (![string]::IsNullOrWhiteSpace($VersionInfo.OriginalFilename) -or $IncludeEmptyProperties) {
                    $FileDetails.OriginalFileName = $VersionInfo.OriginalFilename 
                }
                if (![string]::IsNullOrWhiteSpace($VersionInfo.InternalName) -or $IncludeEmptyProperties) {
                    $FileDetails.InternalName = $VersionInfo.InternalName 
                }
                if (![string]::IsNullOrWhiteSpace($VersionInfo.Language) -or $IncludeEmptyProperties) {
                    $FileDetails.Language = $VersionInfo.Language 
                }

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

                $FileDetails | Add-Member -MemberType NoteProperty -Name 'IsDebug' -Value $VersionInfo.IsDebug
                $FileDetails | Add-Member -MemberType NoteProperty -Name 'IsPatched' -Value $VersionInfo.IsPatched
                $FileDetails | Add-Member -MemberType NoteProperty -Name 'IsPreRelease' -Value $VersionInfo.IsPreRelease
                $FileDetails | Add-Member -MemberType NoteProperty -Name 'IsPrivateBuild' -Value $VersionInfo.IsPrivateBuild
                $FileDetails | Add-Member -MemberType NoteProperty -Name 'IsSpecialBuild' -Value $VersionInfo.IsSpecialBuild
            }
            catch {
                Write-Log "Version information not available or error: $($_.Exception.Message)" -Severity Verbose
            }

            # shell COM is windows only, $IsWindows null on 5.1 means windows
            if ($IsWindows -ne $false) {
                Write-Log "Getting extended properties using COM object..." -Severity Verbose
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
                        }
                        else {
                            Write-Log "Could not parse file name in folder: $FileName" -Severity Verbose
                        }
                        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($Folder) | Out-Null
                    }
                    else {
                        Write-Log "Could not access folder via Shell.Application: $FolderPath" -Severity Verbose
                    }
                    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($Shell) | Out-Null
                }
                catch {
                    Write-Log "Extended properties COM object error: $($_.Exception.Message)" -Severity Verbose
                }
            }
            else {
                Write-Log "Extended file properties via Shell.Application not available on this platform." -Severity Verbose
            }

            Write-Log "Calculating file hashes..." -Severity Verbose
            try {
                if ($IsDirectory) {
                    throw [System.InvalidOperationException]::new('Hash calculation is not applicable to directories.') 
                }
                $MD5Hash = Get-FileHash -LiteralPath $ResolvedFilePath -Algorithm MD5 -ErrorAction SilentlyContinue
                $SHA1Hash = Get-FileHash -LiteralPath $ResolvedFilePath -Algorithm SHA1 -ErrorAction SilentlyContinue
                $SHA256Hash = Get-FileHash -LiteralPath $ResolvedFilePath -Algorithm SHA256 -ErrorAction SilentlyContinue
                $FileDetails | Add-Member -MemberType NoteProperty -Name 'MD5Hash' -Value $MD5Hash.Hash
                $FileDetails | Add-Member -MemberType NoteProperty -Name 'SHA1Hash' -Value $SHA1Hash.Hash
                $FileDetails | Add-Member -MemberType NoteProperty -Name 'SHA256Hash' -Value $SHA256Hash.Hash
            }
            catch {
                Write-Log "Hash calculation error: $($_.Exception.Message)" -Severity Verbose
            }

            # opt-in, slow, windows only
            if (($IsWindows -ne $false) -and $IncludeSignature) {
                Write-Log "Getting digital signature information..." -Severity Verbose
                try {
                    if ($IsDirectory) {
                        throw [System.InvalidOperationException]::new('Digital signature is not applicable to directories.') 
                    }
                    $Signature = Get-AuthenticodeSignature -LiteralPath $ResolvedFilePath -ErrorAction SilentlyContinue
                    if ($Signature) {
                        $FileDetails | Add-Member -MemberType NoteProperty -Name 'SignatureStatus' -Value $Signature.Status
                        $FileDetails | Add-Member -MemberType NoteProperty -Name 'SignatureStatusMessage' -Value $Signature.StatusMessage
                        $FileDetails | Add-Member -MemberType NoteProperty -Name 'SignerCertificate' -Value $(if ($Signature.SignerCertificate) {
                                $Signature.SignerCertificate.Subject 
                            }
                            else {
                                $null 
                            })
                        $FileDetails | Add-Member -MemberType NoteProperty -Name 'TimeStamperCertificate' -Value $(if ($Signature.TimeStamperCertificate) {
                                $Signature.TimeStamperCertificate.Subject 
                            }
                            else {
                                $null 
                            })
                        $FileDetails | Add-Member -MemberType NoteProperty -Name 'SignatureType' -Value $Signature.SignatureType
                    }
                }
                catch {
                    Write-Log "Digital signature error: $($_.Exception.Message)" -Severity Verbose
                }
            }
            elseif ($IncludeSignature -and -not $IsWindows) {
                Write-Log "Authenticode signature inspection requires Windows." -Severity Verbose
            }

            if (-not $IsDirectory -and $ResolvedFilePath -match '\.(exe|dll)$') {
                Write-Log "Getting .NET assembly information..." -Severity Verbose
                try {
                    $Assembly = [System.Reflection.Assembly]::LoadFile($ResolvedFilePath)
                    $FileDetails | Add-Member -MemberType NoteProperty -Name 'DotNetVersion' -Value $Assembly.ImageRuntimeVersion
                    $FileDetails | Add-Member -MemberType NoteProperty -Name 'AssemblyFullName' -Value $Assembly.FullName
                    $FileDetails | Add-Member -MemberType NoteProperty -Name 'AssemblyLocation' -Value $Assembly.Location
                    $FileDetails | Add-Member -MemberType NoteProperty -Name 'AssemblyGAC' -Value $Assembly.GlobalAssemblyCache
                    $Attributes = $Assembly.GetCustomAttributes($false)
                    foreach ($attr in $Attributes) {
                        $attrName = $attr.GetType().Name -replace 'Attribute$', ''
                        if ($attr.GetType().GetProperty('Title')) {
                            $FileDetails | Add-Member -MemberType NoteProperty -Name "Assembly_$attrName" -Value $attr.Title -Force
                        }
                        elseif ($attr.GetType().GetProperty('Description')) {
                            $FileDetails | Add-Member -MemberType NoteProperty -Name "Assembly_$attrName" -Value $attr.Description -Force
                        }
                        elseif ($attr.GetType().GetProperty('Configuration')) {
                            $FileDetails | Add-Member -MemberType NoteProperty -Name "Assembly_$attrName" -Value $attr.Configuration -Force
                        }
                    }
                }
                catch {
                    Write-Log ".NET assembly information not available: $($_.Exception.Message)" -Severity Verbose
                }
            }

            if (-not $IsDirectory -and $ResolvedFilePath -match '\.(exe|dll)$') {
                Write-Log "Getting PE header information..." -Severity Verbose
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
                            $FileDetails | Add-Member -MemberType NoteProperty -Name 'MachineType' -Value $machine
                            $FileDetails | Add-Member -MemberType NoteProperty -Name 'Architecture' -Value $(
                                switch ($machine) {
                                    0x014c {
                                        "i386" 
                                    }
                                    0x0200 {
                                        "IA64" 
                                    }
                                    0x8664 {
                                        "x64" 
                                    }
                                    default {
                                        "Unknown ($machine)" 
                                    }
                                }
                            )
                        }
                    }
                    $BinaryReader.Close()
                    $FileStream.Close()
                }
                catch {
                    Write-Log "PE header analysis error: $($_.Exception.Message)" -Severity Verbose
                    if ($BinaryReader) {
                        $BinaryReader.Close() 
                    }
                    if ($FileStream) {
                        $FileStream.Close() 
                    }
                }
            }
        }
        catch {
            Write-Log "Get-DowserProperty failed analyzing '$FilePath': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Error
        }

        Write-Log "File analysis complete" -Severity Verbose
        return $FileDetails
    }

    end {
        Write-Log "Ending Get-DowserProperty"
    }
}
