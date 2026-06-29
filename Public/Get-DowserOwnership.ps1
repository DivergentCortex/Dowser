#Requires -Version 5.1

# ownership + shell metadata reader. scans dir, pipes file paths to Get-FileMetaData.
# Format-DowserSize replaces the old inline Get-FileSize inner function.

function Get-DowserOwnership {
    <#
    .SYNOPSIS
        Gets file ownership and extended metadata for files in a directory.
    .NOTES
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
        -  Author:        Curtis Leggett                                  -
        =  Copyright:     2026 Divergent Cortex                           =
        -  Organization:  Divergent Cortex                                -
        =  Version:       See docs/CHANGELOG.md                           =
        =-=-                       =-=-=-=-=-=-=-=                     -=-=
        -  it is not water they seek, but the truth beneath the trees     -
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

        Ported from: Get-FileOwnership.ps1 (standalone scripts)
        Uses: Private\Format-DowserSize for human-readable sizes
    .DESCRIPTION
        Scans a directory for files matching an extension filter and returns metadata
        including name, full path, size (human-readable via Format-DowserSize), read-only
        status, last-write time, and all Shell.Application extended properties.
    .PARAMETER Directory
        Target directory to scan. Accepts pipeline input by value and by property name
        (Path, FullName). Defaults to the current location.
    .PARAMETER Extension
        Extension filter (wildcard). Default is "*" (all files).
    .EXAMPLE
        Get-DowserOwnership -Directory "D:\Projects" -Extension "*.ps1"

        Returns ownership and extended metadata for every .ps1 file under D:\Projects.
    .EXAMPLE
        Get-DowserOwnership -Directory "C:\Logs"

        Returns metadata for every file under C:\Logs.
    .INPUTS
        System.String
        You can pipe a directory path to this function.
    .OUTPUTS
        PSCustomObject
        One object per file carrying ownership and extended metadata.
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('Path', 'FullName')]
        [string]$Directory = $PWD,
        [string]$Extension = "*"
    )

    Write-Log "Starting Get-DowserOwnership"

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
        Gets metadata information from a file, similar to what Explorer shows.
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
        process {
            foreach ($F in $File) {
                $MetaDataObject = [ordered] @{}
                if ($F -is [string]) {
                    if ($F -and (Test-Path -LiteralPath $F)) {
                        $FileInformation = Get-ItemProperty -Path $F
                        if ($FileInformation -is [System.IO.DirectoryInfo]) {
                            continue 
                        }
                    }
                    else {
                        Write-Log "Get-FileMetaData - path does not exist, skipping: $F" -Severity Warning
                        continue
                    }
                }
                elseif ($F -is [System.IO.DirectoryInfo]) {
                    continue
                }
                elseif ($F -is [System.IO.FileInfo]) {
                    $FileInformation = $F
                }
                else {
                    Write-Log "Get-FileMetaData - only files are supported, skipping: $F" -Severity Warning
                    continue
                }

                # com metadata is windows only, fall back to unix fileinfo elsewhere
                # $IsWindows is null on 5.1 so -ne $false means windows
                $ShellApplication = $null
                $ShellFolder = $null
                $ShellFile = $null
                if ($IsWindows -ne $false) {
                    try {
                        $ShellApplication = New-Object -ComObject Shell.Application -ErrorAction Stop
                        $ShellFolder = $ShellApplication.Namespace($FileInformation.Directory.FullName)
                        $ShellFile = $ShellFolder.ParseName($FileInformation.Name)
                    }
                    catch {
                        Write-Log "Shell.Application COM not available on this platform; skipping extended metadata." -Severity Verbose
                    }
                }
                if ($IsWindows -eq $false) {
                    # user/group/unixmode come from get-item on pwsh core unix
                    $MetaDataObject['Owner'] = $FileInformation.User
                    $MetaDataObject['Group'] = $FileInformation.Group
                    $MetaDataObject['UnixMode'] = $FileInformation.UnixMode
                    $MetaDataObject['PlatformNote'] = 'Unix ownership via .NET FileInfo; Shell.Application extended metadata is Windows-only and was skipped.'
                }
                if ($null -eq $ShellFolder) {
                    $MetaDataObject["Attributes"] = $FileInformation.Attributes
                    $MetaDataObject['IsReadOnly'] = $FileInformation.IsReadOnly
                    $MetaDataObject['IsHidden'] = $FileInformation.Attributes -like '*Hidden*'
                    $MetaDataObject['IsSystem'] = $FileInformation.Attributes -like '*System*'
                    if ($AsHashTable) {
                        $MetaDataObject 
                    }
                    else {
                        [PSCustomObject]$MetaDataObject 
                    }
                    continue
                }
                $MetaDataProperties = [ordered] @{}
                0..400 | ForEach-Object -Process {
                    $DataValue = $ShellFolder.GetDetailsOf($null, $_)
                    $PropertyValue = (Get-Culture).TextInfo.ToTitleCase($DataValue.Trim()).Replace(' ', '')
                    if ($PropertyValue -ne '') {
                        $MetaDataProperties["$_"] = $PropertyValue 
                    }
                }
                foreach ($Key in $MetaDataProperties.Keys) {
                    $Property = $MetaDataProperties[$Key]
                    $Value = $ShellFolder.GetDetailsOf($ShellFile, [int] $Key)
                    if ($Property -in 'Attributes', 'Folder', 'Type', 'SpaceFree', 'TotalSize', 'SpaceUsed') {
                        continue 
                    }
                    if (($null -ne $Value) -and ($Value -ne '')) {
                        $MetaDataObject["$Property"] = $Value 
                    }
                }
                if ($FileInformation.VersionInfo) {
                    $SplitInfo = ([string] $FileInformation.VersionInfo).Split([char]13)
                    foreach ($Item in $SplitInfo) {
                        $Property = $Item.Split(":").Trim()
                        if ($Property[0] -and $Property[1] -ne '') {
                            if ($Property[1] -in 'False', 'True') {
                                $MetaDataObject["$($Property[0])"] = [bool] $Property[1]
                            }
                            else {
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
                if ($AsHashTable) {
                    $MetaDataObject 
                }
                else {
                    [PSCustomObject] $MetaDataObject 
                }
            }
        }
    }

    Write-Log "Get-DowserOwnership scanning '$Directory' for extension '$Extension'"
    try {
        $DirectoryFiles = Get-ChildItem $Directory -Recurse -Force -ErrorAction Stop
        Write-Log "Get-DowserOwnership scan complete: $(@($DirectoryFiles).Count) items found"
    }
    catch {
        Write-Log "Get-DowserOwnership failed scanning '$Directory': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Error
        Write-Log "Ending Get-DowserOwnership"
        return
    }

    $List = $DirectoryFiles | Where-Object { $_.extension -like $Extension }
    $List.FullName | Get-FileMetaData
    Write-Log "Ending Get-DowserOwnership"
}
