#Requires -Version 5.1

function Read-DowserJsonKeyFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [hashtable]$Sync
    )

    $keyCounts = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::Ordinal)
    $documentCount = 0
    $stream = $null
    $reader = $null
    $readSucceeded = $true

    try {
        $stream = [System.IO.File]::OpenRead($FilePath)
        $textReader = [System.IO.StreamReader]::new($stream)
        $reader = [Newtonsoft.Json.JsonTextReader]::new($textReader)
        $reader.SupportMultipleContent = $true
    }
    catch {
        $readSucceeded = $false
        $Sync.LogQueue.Enqueue([pscustomobject]@{
            Severity = 'Warning'
            Message = "Get-DowserJsonKey could not open '$FilePath': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"
        })
    }

    if ($readSucceeded) {
        try {
            while ($reader.Read()) {
                if (($reader.TokenType -eq [Newtonsoft.Json.JsonToken]::StartObject -or
                     $reader.TokenType -eq [Newtonsoft.Json.JsonToken]::StartArray) -and
                    $reader.Depth -eq 0) {
                    $documentCount++
                }

                if ($reader.TokenType -ne [Newtonsoft.Json.JsonToken]::PropertyName) {
                    continue
                }

                $keyPath = '$.' + ($reader.Path -replace '\[\d+\]', '[]')
                if ($keyCounts.ContainsKey($keyPath)) {
                    $keyCounts[$keyPath] = $keyCounts[$keyPath] + 1
                }
                else {
                    $keyCounts.Add($keyPath, 1)
                }
            }
        }
        catch {
            $readSucceeded = $false
            $Sync.LogQueue.Enqueue([pscustomobject]@{
                Severity = 'Warning'
                Message = "Get-DowserJsonKey could not parse '$FilePath': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"
            })
        }
        finally {
            $reader.Close()
        }
    }

    $Sync.Results.Enqueue([pscustomobject]@{
        FilePath = $FilePath
        Format = [System.IO.Path]::GetExtension($FilePath).TrimStart('.').ToUpperInvariant()
        Documents = $documentCount
        KeyCounts = $keyCounts
        ReadSucceeded = $readSucceeded
    })
    $Sync.Progress.Enqueue(1)
}
