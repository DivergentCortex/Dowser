#Requires -Version 5.1

function Invoke-DowserJsonKeyWorker {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Sync
    )

    $filePath = $null
    while ($Sync.Pending.TryDequeue([ref]$filePath)) {
        Read-DowserJsonKeyFile -FilePath $filePath -Sync $Sync
        $filePath = $null
    }
}
