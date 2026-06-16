#Requires -Version 5.1
<#
.SYNOPSIS
    Gets file ownership and extended metadata for files in a directory.
.DESCRIPTION
    Scans a directory for files matching an extension filter and returns metadata
    including name, full path, size (human-readable via Format-DowserSize), read-only
    status, last-write time, and all Shell.Application extended properties.
.PARAMETER Directory
    Target directory to scan.
.PARAMETER Extension
    Extension filter (wildcard). Default is "*" (all files).
.EXAMPLE
    Get-DowserOwnership -Directory "D:\Projects" -Extension "*.ps1"
.EXAMPLE
    Get-DowserOwnership -Directory "C:\Logs"
.NOTES
    Author: Curtis Leggett / PowerShell Codesmith
    Ported from: Get-FileOwnership.ps1 (General_Scripts)
    Uses: Private\Format-DowserSize for human-readable sizes
#>

# ownership + shell metadata reader. scans dir, pipes file paths to Get-FileMetaData.
# Format-DowserSize replaces the old inline Get-FileSize inner function.

function Get-DowserOwnership {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('Path', 'FullName')]
        [string]$Directory = $PWD,
        [string]$Extension = "*"
    )

    function Get-FileInformation {
        [CmdletBinding()]
        param([string] $File)
        if (Test-Path $File) {
            return Get-Item $File | Select-Object Name, FullName,
                @{N = 'Size'; E = { Format-DowserSize -DataValue $_.Length } },
                IsReadOnly, LastWriteTime
        }
        return
    }

    function Get-FileMetaData {
        <#
        .SYNOPSIS
        Gets metadata information from a file -- similar to what Explorer shows.
        .PARAMETER File
        FileName or FileObject
        .PARAMETER HashAlgorithm
        Optional hash algorithm to compute.
        .PARAMETER Signature
        Include authenticode signature info.
        .PARAMETER AsHashTable
        Return as hashtable instead of PSCustomObject.
        #>
        [CmdletBinding()]
        param (
            [Parameter(Position = 0, ValueFromPipeline)]
            [Object] $File,
            [ValidateSet('None', 'MACTripleDES', 'MD5', 'RIPEMD160', 'SHA1', 'SHA256', 'SHA384', 'SHA512')]
            [string] $HashAlgorithm = 'None',
            [switch] $Signature,
            [switch] $AsHashTable
        )
        Process {
            foreach ($F in $File) {
                $MetaDataObject = [ordered] @{}
                if ($F -is [string]) {
                    if ($F -and (Test-Path -LiteralPath $F)) {
                        $FileInformation = Get-ItemProperty -Path $F
                        if ($FileInformation -is [System.IO.DirectoryInfo]) { continue }
                    } else {
                        Write-Warning "Get-FileMetaData - Doesn't exists. Skipping $F."
                        continue
                    }
                } elseif ($F -is [System.IO.DirectoryInfo]) {
                    continue
                } elseif ($F -is [System.IO.FileInfo]) {
                    $FileInformation = $F
                } else {
                    Write-Warning "Get-FileMetaData - Only files are supported. Skipping $F."
                    continue
                }

                # COM metadata is Windows-only. On non-Windows, populate real Unix
                # ownership from the .NET FileInfo instead of returning an empty object.
                # ($IsWindows is $null on PS 5.1, so -ne $false means Windows.)
                $ShellApplication = $null
                $ShellFolder      = $null
                $ShellFile        = $null
                if ($IsWindows -ne $false) {
                    try {
                        $ShellApplication = New-Object -ComObject Shell.Application -ErrorAction Stop
                        $ShellFolder = $ShellApplication.Namespace($FileInformation.Directory.FullName)
                        $ShellFile   = $ShellFolder.ParseName($FileInformation.Name)
                    } catch {
                        Write-Verbose "Shell.Application COM not available on this platform; skipping extended metadata."
                    }
                }
                if ($IsWindows -eq $false) {
                    # Unix ownership: User/Group/UnixMode are exposed by Get-Item on
                    # PowerShell Core for Unix filesystems.
                    $MetaDataObject['Owner']    = $FileInformation.User
                    $MetaDataObject['Group']    = $FileInformation.Group
                    $MetaDataObject['UnixMode'] = $FileInformation.UnixMode
                    $MetaDataObject['PlatformNote'] = 'Unix ownership via .NET FileInfo; Shell.Application extended metadata is Windows-only and was skipped.'
                }
                if ($null -eq $ShellFolder) {
                    $MetaDataObject["Attributes"] = $FileInformation.Attributes
                    $MetaDataObject['IsReadOnly'] = $FileInformation.IsReadOnly
                    $MetaDataObject['IsHidden'] = $FileInformation.Attributes -like '*Hidden*'
                    $MetaDataObject['IsSystem'] = $FileInformation.Attributes -like '*System*'
                    if ($AsHashTable) { $MetaDataObject } else { [PSCustomObject]$MetaDataObject }
                    continue
                }
                $MetaDataProperties = [ordered] @{}
                0..400 | ForEach-Object -Process {
                    $DataValue = $ShellFolder.GetDetailsOf($null, $_)
                    $PropertyValue = (Get-Culture).TextInfo.ToTitleCase($DataValue.Trim()).Replace(' ', '')
                    if ($PropertyValue -ne '') { $MetaDataProperties["$_"] = $PropertyValue }
                }
                foreach ($Key in $MetaDataProperties.Keys) {
                    $Property = $MetaDataProperties[$Key]
                    $Value = $ShellFolder.GetDetailsOf($ShellFile, [int] $Key)
                    if ($Property -in 'Attributes', 'Folder', 'Type', 'SpaceFree', 'TotalSize', 'SpaceUsed') { continue }
                    If (($null -ne $Value) -and ($Value -ne '')) { $MetaDataObject["$Property"] = $Value }
                }
                if ($FileInformation.VersionInfo) {
                    $SplitInfo = ([string] $FileInformation.VersionInfo).Split([char]13)
                    foreach ($Item in $SplitInfo) {
                        $Property = $Item.Split(":").Trim()
                        if ($Property[0] -and $Property[1] -ne '') {
                            if ($Property[1] -in 'False', 'True') {
                                $MetaDataObject["$($Property[0])"] = [bool] $Property[1]
                            } else {
                                $MetaDataObject["$($Property[0])"] = $Property[1]
                            }
                        }
                    }
                }
                $MetaDataObject["Attributes"] = $FileInformation.Attributes
                $MetaDataObject['IsReadOnly'] = $FileInformation.IsReadOnly
                $MetaDataObject['IsHidden'] = $FileInformation.Attributes -like '*Hidden*'
                $MetaDataObject['IsSystem'] = $FileInformation.Attributes -like '*System*'
                if ($Signature) {
                    $DigitalSignature = Get-AuthenticodeSignature -FilePath $FileInformation.Fullname
                    $MetaDataObject['SignatureCertificateSubject'] = $DigitalSignature.SignerCertificate.Subject
                    $MetaDataObject['SignatureCertificateIssuer'] = $DigitalSignature.SignerCertificate.Issuer
                    $MetaDataObject['SignatureCertificateSerialNumber'] = $DigitalSignature.SignerCertificate.SerialNumber
                    $MetaDataObject['SignatureCertificateNotBefore'] = $DigitalSignature.SignerCertificate.NotBefore
                    $MetaDataObject['SignatureCertificateNotAfter'] = $DigitalSignature.SignerCertificate.NotAfter
                    $MetaDataObject['SignatureCertificateThumbprint'] = $DigitalSignature.SignerCertificate.Thumbprint
                    $MetaDataObject['SignatureStatus'] = $DigitalSignature.Status
                    $MetaDataObject['IsOSBinary'] = $DigitalSignature.IsOSBinary
                }
                if ($HashAlgorithm -ne 'None') {
                    $MetaDataObject[$HashAlgorithm] = (Get-FileHash -LiteralPath $FileInformation.FullName -Algorithm $HashAlgorithm).Hash
                }
                if ($AsHashTable) { $MetaDataObject } else { [PSCustomObject] $MetaDataObject }
            }
        }
    }

    $DirectoryFiles = Get-ChildItem $Directory -Recurse -Force
    $List = $DirectoryFiles | Where-Object { $_.extension -like $Extension }
    $List.FullName | Get-FileMetaData
}
