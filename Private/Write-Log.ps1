# ===========================================================================
#  Write-Log.ps1 - canonical dot-source logging helper
#
#  This is the single-file dot-source form of the DivergentCortex.Witness module.
#  Same behavior, packaged as one file so it can be dot-sourced into scripts and
#  embedded inside other modules. Dot-source it, set a log path, then call Write-Log.
#
#  $script:WitnessIsWindows is set once with a 5.1-safe probe. PS 5.1 has no
#  $IsWindows automatic variable, its absence means Windows. Every function below
#  reads $script:WitnessIsWindows, raw $IsWindows is never used.
#
#  Set-StrictMode is intentionally not set at file scope. The module sets it in
#  isolated module scope. A dot-sourced file runs in the caller scope, so setting
#  it here would force strict mode onto the consuming script.
# ===========================================================================

# absence of $IsWindows means PS 5.1 on Windows
$script:WitnessIsWindows = if (Test-Path Variable:IsWindows) {
    $IsWindows
}
else {
    $true
}

# session state, set by Initialize-Log and the cleanup sentinel
$script:WitnessLogFilePath = $null
$script:WitnessCleanupRan = $false

# config defaults, consumers override with $Global: equivalents
$script:WitnessAutoCleanup = $true
$script:WitnessMaxSizeMB = 10
$script:WitnessMaxAgeDays = 7
$script:WitnessVerboseConsole = $false
$script:WitnessVerboseLogfile = $false
$script:WitnessDebugConsole = $false
$script:WitnessDebugLogfile = $false


function Resolve-WitnessLogPath {
    <#
    .SYNOPSIS
        Resolves the active log file path using a deterministic layered lookup.

    .DESCRIPTION
        Walks three layers in order and returns the first non-whitespace value:
          1. CallerResolved (explicit param or caller-scope value the caller checked).
          2. $script:WitnessLogFilePath (set by Initialize-Log).
          3. $Global:LogFilePath (dot-source back-compat).
        Returns $null when no layer yields a value.

    .PARAMETER CallerResolved
        The path the caller already resolved from its parameter and caller-scope check.

    .OUTPUTS
        System.String. The resolved path, or $null.
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$CallerResolved
    )

    if (-not [string]::IsNullOrWhiteSpace($CallerResolved)) {
        return $CallerResolved
    }

    if (-not [string]::IsNullOrWhiteSpace($script:WitnessLogFilePath)) {
        return $script:WitnessLogFilePath
    }

    if (Test-Path Variable:Global:LogFilePath) {
        $glbPath = $Global:LogFilePath
        if (-not [string]::IsNullOrWhiteSpace($glbPath)) {
            return $glbPath
        }
    }

    return $null
}


function Write-Log {
    <#
    .SYNOPSIS
        Write to a log file in CMTrace-compatible format with automatic log management.

    .DESCRIPTION
        Outputs strings to a log file formatted for CMTrace.exe and writes to console.

        Severity levels (CMTrace type codes):
            1 - Info/Information/Success (default)
            2 - Warning (yellow in CMTrace)
            3 - Error (red in CMTrace)
            4 - Verbose
            5 - Debug

        Features:
            - Automatic log rotation by size (default: 10MB)
            - Automatic cleanup of old logs (runs once per session)
            - Retry on file lock with contention logging
            - Granular control over console/logfile output per severity
            - Auto-detects calling function/script for Component field

        Tools to view logs:
            CM Trace - https://www.microsoft.com/en-us/download/details.aspx?id=50012

    .PARAMETER Message
        The message to log.

    .PARAMETER Severity
        Log level: Info, Information, Warning, Error, Verbose, Debug, Success

    .PARAMETER Color
        Optional console color override for the message text.

    .EXAMPLE
        Write-Log -Message "Operation completed" -Severity Info

    .EXAMPLE
        Write-Log -Message "Something might be wrong" -Severity Warning

    .EXAMPLE
        try {
            Get-Process -Name DoesNotExist -ErrorAction Stop
        } catch {
            Write-Log -Message $_.Exception.Message -Severity Error
        }

    .EXAMPLE
        Write-Log -Message "Detailed info" -Severity Verbose

    .EXAMPLE
        Write-Log -Message "Custom color message" -Severity Info -Color DarkGray

    .NOTES
        ===========================================================================
        Created on:                    4/23/2023 2:15 PM
        Modified heavily by:           Curtis Leggett & S.Henry
        Organization:                  Divergent Cortex
        Filename:                      Write-Log.ps1
        Version:                       2026.06.29.011
        ===========================================================================

        Backported from the DivergentCortex.Witness module: cross-platform context
        (Windows/Linux/macOS), native -Debug/-Verbose support, local-time timestamps,
        UTF-8 no-BOM writes, rotation-on-rename-success, layered log path resolution.

        SETUP - Add these variables BEFORE dot-sourcing Write-Log.ps1:

        ## FOR SCCM PACKAGES/APPLICATIONS:
            $ScriptName = $MyInvocation.MyCommand.Name -replace '\.ps1$'
            $logName = "$($ScriptName)_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
            $LogDir = Join-Path $env:PUBLIC "Documents\Logs"
            $LogFilePath = Join-Path $LogDir $logName

        ## FOR SCHEDULED TASKS / STANDALONE SCRIPTS:
            $ScriptName = $MyInvocation.MyCommand.Name -replace '\.ps1$'
            $logName = "$($ScriptName)_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
            $LogDir = Join-Path $PSScriptRoot "logs"
            $LogFilePath = Join-Path $LogDir $logName

        ## OPTIONAL - Granular Verbose/Debug Control (all default to $false):
            $Global:VerboseConsole = $true   # Verbose messages to console
            $Global:VerboseLogfile = $true   # Verbose messages to logfile
            $Global:DebugConsole   = $true   # Debug messages to console
            $Global:DebugLogfile   = $true   # Debug messages to logfile

        ## NOTE: -Debug or -Verbose on the calling function/script also turns these on.

        ## OPTIONAL - Auto Log Management (all have sensible defaults):
            $Global:WriteLogAutoCleanup   = $true   # Auto-cleanup on first call (default: $true)
            $Global:WriteLogMaxSizeMB     = 10      # Rotate log when exceeds MB (default: 10)
            $Global:WriteLogMaxAgeDays    = 7       # Delete logs older than N days (default: 7)

        ## STANDARD USAGE:
            Write-Log -Message "Your message here" -Severity Info
            Write-Log -Message "Warning message" -Severity Warning
            Write-Log -Message "Error occurred" -Severity Error
            Write-Log -Message "Verbose detail" -Severity Verbose
            Write-Log -Message "Debug info" -Severity Debug

        The function auto-detects the calling function/script name for the Component field.
        The $LogFilePath variable is read automatically - no parameter needed.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Message,

        [Parameter(Mandatory = $False)]
        [String]$Logfile,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Information', 'Warning', 'Error', 'Verbose', 'Debug', 'Success')]
        [Alias("LogLevel", "Type", "level")]
        [String]$Severity = "Info",

        [Parameter(Mandatory = $False)]
        [String]$Component,

        [Parameter(Mandatory = $False)]
        [bool]$WriteBackToHost = $True,

        [Parameter(Mandatory = $False)]
        [ValidateRange(0, 10)]
        [int]$MaxRetries = 3,

        [Parameter(Mandatory = $False)]
        [ValidateRange(0.0, 30.0)]
        [double]$RetryDelay = 0.5,

        [Parameter(Mandatory = $False)]
        [System.ConsoleColor]$Color
    )

    process {
        # resolve log path, layered lookup
        $callerCandidate = $null
        if ($PSBoundParameters.ContainsKey('Logfile') -and -not [string]::IsNullOrWhiteSpace($Logfile)) {
            $callerCandidate = $Logfile
        }
        else {
            $callerScopePath = $PSCmdlet.SessionState.PSVariable.GetValue('LogFilePath')
            if (-not [string]::IsNullOrWhiteSpace($callerScopePath)) {
                $callerCandidate = $callerScopePath
            }
        }
        $Logfile = Resolve-WitnessLogPath -CallerResolved $callerCandidate

        if ([string]::IsNullOrWhiteSpace($Logfile)) {
            throw "FATAL: No log file path set. Call Initialize-Log -LogFilePath first, or set `$LogFilePath in your script scope before calling Write-Log."
        }

        # settings from script defaults, overridden by $Global: equivalents
        $autoCleanup = $script:WitnessAutoCleanup
        if (Test-Path Variable:Global:WriteLogAutoCleanup) {
            $autoCleanup = $Global:WriteLogAutoCleanup 
        }

        $maxSizeMB = $script:WitnessMaxSizeMB
        if (Test-Path Variable:Global:WriteLogMaxSizeMB) {
            $maxSizeMB = $Global:WriteLogMaxSizeMB 
        }

        $maxAgeDays = $script:WitnessMaxAgeDays
        if (Test-Path Variable:Global:WriteLogMaxAgeDays) {
            $maxAgeDays = $Global:WriteLogMaxAgeDays 
        }

        # GetVariableValue crosses the module boundary, direct read cant
        $callerDebugPref = $PSCmdlet.GetVariableValue('DebugPreference')
        $callerVerbosePref = $PSCmdlet.GetVariableValue('VerbosePreference')
        $nativeDebugActive = ($null -ne $callerDebugPref) -and ($callerDebugPref -ne 'SilentlyContinue')
        $nativeVerboseActive = ($null -ne $callerVerbosePref) -and ($callerVerbosePref -ne 'SilentlyContinue')

        $verboseToConsole = $script:WitnessVerboseConsole
        if (Test-Path Variable:Global:VerboseConsole) {
            $verboseToConsole = $Global:VerboseConsole 
        }

        $verboseToLogfile = $script:WitnessVerboseLogfile
        if (Test-Path Variable:Global:VerboseLogfile) {
            $verboseToLogfile = $Global:VerboseLogfile 
        }

        $debugToConsole = $script:WitnessDebugConsole
        if (Test-Path Variable:Global:DebugConsole) {
            $debugToConsole = $Global:DebugConsole 
        }

        $debugToLogfile = $script:WitnessDebugLogfile
        if (Test-Path Variable:Global:DebugLogfile) {
            $debugToLogfile = $Global:DebugLogfile 
        }

        # native preference overrides per-surface flags
        if ($nativeVerboseActive) {
            $verboseToConsole = $true; $verboseToLogfile = $true 
        }
        if ($nativeDebugActive) {
            $debugToConsole = $true; $debugToLogfile = $true 
        }

        # map Information to Info
        if ($Severity -eq "Information") {
            $Severity = "Info"
        }

        if ($Severity -eq "Verbose" -and (-not $verboseToConsole) -and (-not $verboseToLogfile)) {
            return 
        }
        if ($Severity -eq "Debug" -and (-not $debugToConsole) -and (-not $debugToLogfile)) {
            return 
        }

        # CMSite provider breaks filesystem ops
        $originalLocation = Get-Location
        $isSCCMDrive = $false
        if ($script:WitnessIsWindows) {
            if ($null -ne $originalLocation.Provider -and $originalLocation.Provider.Name -eq 'CMSite') {
                $isSCCMDrive = $true
                Set-Location C:
            }
        }
    
        try {
            $callStack = Get-PSCallStack
        
            $Source = "Unknown"
            $callerFunctionName = "Unknown"
            $lineNumber = "?"
        
            if ($null -ne $callStack -and $callStack.Count -gt 1) {
                $callerInfo = $callStack[1]
            
                if ($callerInfo.Location) {
                    $Source = $callerInfo.Location
                }
            
                if ($callerInfo.ScriptLineNumber) {
                    $lineNumber = $callerInfo.ScriptLineNumber
                }
                if ($callerInfo.Command) {
                    $callerFunctionName = $callerInfo.Command
                    if ($callerFunctionName -like "*.ps1") {
                        $callerFunctionName = [System.IO.Path]::GetFileNameWithoutExtension($callerFunctionName)
                    }
                }
            }
            if ([string]::IsNullOrEmpty($Component)) {
                if ($callerFunctionName -ne "Unknown" -and $callerFunctionName -notlike "*.ps1") {
                    $Component = $callerFunctionName
                }
                else {
                    $callerComponent = $PSCmdlet.SessionState.PSVariable.GetValue('Component')
                    if (-not [string]::IsNullOrEmpty($callerComponent)) {
                        $Component = $callerComponent
                    }
                    else {
                        $Component = $callerFunctionName
                    }
                }
            }
        
            if ([string]::IsNullOrEmpty($Component) -or $Component -eq "Unknown") {
                if ($callStack.Count -gt 1 -and $null -ne $callStack[1].InvocationInfo -and $null -ne $callStack[1].InvocationInfo.MyCommand) {
                    $Component = $callStack[1].InvocationInfo.MyCommand.Name
                }
            
                if ([string]::IsNullOrEmpty($Component)) {
                    $Component = "Unknown"
                }
            }
        
            # local time, utc confuses operators
            $DateTime = Get-Date
            $LogDate = $DateTime.ToString('MM-dd-yyyy')
            $LogTime = $DateTime.ToString('HH:mm:ss.fff')

            # cmtrace expects integer type codes
            $severityType = "1"
            if ($Severity -eq "Error") {
                $severityType = "3" 
            }
            elseif ($Severity -eq "Warning") {
                $severityType = "2" 
            }
            elseif ($Severity -eq "Verbose") {
                $severityType = "4" 
            }
            elseif ($Severity -eq "Debug") {
                $severityType = "5" 
            }

            # re-resolve per write for impersonation changes
            if ($script:WitnessIsWindows) {
                $contextUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            }
            else {
                $contextUser = "$([System.Environment]::UserDomainName)\$([System.Environment]::UserName)"
            }

            $logline = "<![LOG[$Message]LOG]!>" +
            "<time=`"$LogTime`" " +
            "date=`"$LogDate`" " +
            "component=`"$Component`" " +
            "context=`"$contextUser`" " +
            "type=`"$severityType`" " +
            "thread=`"$PID`" " +
            "file=`"$Source`">"

            $logDir = Split-Path $Logfile
            if ($logDir -and !(Test-Path $logDir)) {
                New-Item -Path $logDir -ItemType Directory -Force | Out-Null
            }

            $shouldWriteConsole = switch ($Severity) {
                'Verbose' {
                    $verboseToConsole 
                }
                'Debug' {
                    $debugToConsole 
                }
                default {
                    $true 
                }
            }

            if ($WriteBackToHost -and $shouldWriteConsole) {
                $displayComponent = $Component
                if ($displayComponent.Length -gt 12) {
                    $displayComponent = $displayComponent.Substring(0, 10) + ".."
                }

                $severityConfig = @{
                    'Error'   = @{ Label = ' ERROR '; LabelColor = 'Red'; MessageColor = 'Red' }
                    'Warning' = @{ Label = ' WARNING '; LabelColor = 'Yellow'; MessageColor = 'Yellow' }
                    'Info'    = @{ Label = ' INFO '; LabelColor = 'Green'; MessageColor = 'White' }
                    'Success' = @{ Label = ' SUCCESS '; LabelColor = 'Green'; MessageColor = 'Green' }
                    'Verbose' = @{ Label = ' VERBOSE '; LabelColor = 'DarkGray'; MessageColor = 'DarkGray' }
                    'Debug'   = @{ Label = ' DEBUG '; LabelColor = 'Magenta'; MessageColor = 'Magenta' }
                }

                $config = $severityConfig[$Severity]

                $finalMessageColor = if ($PSBoundParameters.ContainsKey('Color')) {
                    $Color
                }
                else {
                    $config.MessageColor
                }

                Write-Host "[" -NoNewline -ForegroundColor Gray
                Write-Host $config.Label -NoNewline -ForegroundColor $config.LabelColor
                Write-Host "] [" -NoNewline -ForegroundColor Gray
                Write-Host "$displayComponent" -NoNewline -ForegroundColor Blue
                Write-Host "] [" -NoNewline -ForegroundColor Gray
                Write-Host "$lineNumber" -NoNewline -ForegroundColor Cyan
                Write-Host "]" -NoNewline -ForegroundColor Gray
                Write-Host ": " -NoNewline -ForegroundColor Magenta
                Write-Host "$Message" -ForegroundColor $finalMessageColor
            }

            $shouldWriteLogfile = switch ($Severity) {
                'Verbose' {
                    $verboseToLogfile 
                }
                'Debug' {
                    $debugToLogfile 
                }
                default {
                    $true 
                }
            }

            # rotate when size exceeds limit
            if ($shouldWriteLogfile -and (Test-Path $Logfile)) {
                $currentSize = (Get-Item $Logfile).Length / 1MB
                if ($currentSize -ge $maxSizeMB) {
                    $rotLogDir = Split-Path $Logfile
                    $logBase = [System.IO.Path]::GetFileNameWithoutExtension($Logfile)
                    $logExt = [System.IO.Path]::GetExtension($Logfile)
                    $rotationNum = 1
                    do {
                        $archiveName = "{0}_r{1:D2}{2}" -f $logBase, $rotationNum, $logExt
                        $archivePath = Join-Path $rotLogDir $archiveName
                        $rotationNum++
                    } while (Test-Path $archivePath)

                    $renamed = $false
                    try {
                        Rename-Item -Path $Logfile -NewName $archiveName -Force -ErrorAction Stop
                        $renamed = $true
                    }
                    catch {
                        Write-Warning "Write-Log: Could not rotate log to '$archiveName': $_"
                    }

                    if ($renamed) {
                        $rotationMsg = "<![LOG[LOG ROTATION: Previous log archived to $archiveName (exceeded ${maxSizeMB}MB)]LOG]!>" +
                        "<time=`"$LogTime`" date=`"$LogDate`" component=`"Write-Log`" " +
                        "context=`"$contextUser`" " +
                        "type=`"1`" thread=`"$PID`" file=`"Write-Log.ps1`">"

                        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
                        # cant use Write-Log here, file may not exist yet
                        try {
                            [System.IO.File]::WriteAllText($Logfile, "$rotationMsg$([System.Environment]::NewLine)", $utf8NoBom)
                        }
                        catch {
                            Write-Warning "Write-Log: Failed to write rotation notice to '$Logfile': $_"
                        }
                    }
                }
            }

            # sentinel before call prevents recursion
            if ($autoCleanup -and (-not $script:WitnessCleanupRan) -and (Test-Path $Logfile)) {
                $script:WitnessCleanupRan = $true
                $logFolder = Split-Path $Logfile
                if ($logFolder -and (Test-Path $logFolder)) {
                    try {
                        Clear-LogFile -LogFolder $logFolder -MaxAgeDays $maxAgeDays
                    }
                    catch {
                        Write-Warning "Auto-cleanup failed: $_"
                    }
                }
            }

            if ($shouldWriteLogfile) {
                $retryCount = 0
                $writeSucceeded = $false

                while (-not $writeSucceeded -and $retryCount -le $MaxRetries) {
                    $fileStream = $null
                    $streamWriter = $null

                    try {
                        $fileMode = [System.IO.FileMode]::Append
                        $fileAccess = [System.IO.FileAccess]::Write
                        $fileShare = [System.IO.FileShare]::ReadWrite
                        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)

                        $fileStream = New-Object System.IO.FileStream($Logfile, $fileMode, $fileAccess, $fileShare)
                        $streamWriter = New-Object System.IO.StreamWriter($fileStream, $utf8NoBom)
                        $streamWriter.NewLine = [System.Environment]::NewLine
                        $streamWriter.WriteLine($logline)
                        $writeSucceeded = $true

                        if ($retryCount -gt 0) {
                            $retryNote = "<![LOG[WRITE-LOG FILE CONTENTION: Previous entry required $retryCount retry attempt(s) due to file lock on $Logfile]LOG]!>" +
                            "<time=`"$LogTime`" date=`"$LogDate`" component=`"Write-Log`" " +
                            "context=`"$contextUser`" " +
                            "type=`"2`" thread=`"$PID`" file=`"Write-Log.ps1`">"
                            $streamWriter.WriteLine($retryNote)
                        }
                    }
                    catch [System.IO.IOException] {
                        $retryCount++
                        if ($retryCount -le $MaxRetries) {
                            Start-Sleep -Milliseconds ([int]($RetryDelay * 1000))
                        }
                        else {
                            Write-Warning "Failed to write to log after $MaxRetries retries (file locked): $Logfile"
                        }
                    }
                    catch {
                        Write-Warning "Failed to write to log file '$Logfile': $_"
                        break
                    }
                    finally {
                        try {
                            if ($null -ne $streamWriter) {
                                $streamWriter.Dispose() 
                            } 
                        }
                        catch { 
                        }
                        try {
                            if ($null -ne $fileStream) {
                                $fileStream.Dispose()   
                            } 
                        }
                        catch { 
                        }
                    }
                }
            }
        }
        finally {
            if ($isSCCMDrive) {
                try {
                    Set-Location $originalLocation -ErrorAction SilentlyContinue 
                }
                catch { 
                }
            }
        }
    }
}

function Clear-LogFile {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$LogFolder,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 365)]
        [int]$MaxAgeDays = 7
    )

    Write-Log "Starting log cleanup in: $LogFolder (keep last $MaxAgeDays days)" -Severity Debug

    $logFiles = Get-ChildItem -Path $LogFolder -Filter "*.log" -File -ErrorAction SilentlyContinue
    if (-not $logFiles) {
        Write-Log "No log files found in $LogFolder" -Severity Verbose
        return
    }

    $cutoff = (Get-Date).AddDays(-$MaxAgeDays)
    $expired = $logFiles | Where-Object { $_.LastWriteTime -lt $cutoff }

    if (-not $expired -or @($expired).Count -eq 0) {
        Write-Log "No logs older than $MaxAgeDays days - nothing to delete" -Severity Verbose
        return
    }

    Write-Log "Deleting $(@($expired).Count) log(s) older than $MaxAgeDays days" -Severity Info
    foreach ($file in $expired) {
        try {
            Remove-Item -Path $file.FullName -Force -ErrorAction Stop
            Write-Log "Deleted: $($file.Name)" -Severity Verbose
        }
        catch {
            Write-Log "Failed to delete '$($file.Name)': $($_.Exception.Message)" -Severity Warning
        }
    }

    Write-Log "Log cleanup completed for: $LogFolder" -Severity Debug
}

function Write-LogFinal {
    <#
    .SYNOPSIS
        Write a final log entry and trigger the session-end log cleanup pass.

    .DESCRIPTION
        Use as the last log call in a script. Writes the supplied message, then runs
        Clear-LogFile against the log directory to prune logs older than MaxAgeDays.
        The cleanup sentinel prevents cleanup from running twice. If Write-Log already
        triggered auto-cleanup earlier in the session, this skips it. Calling
        Initialize-Log resets the sentinel.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Information', 'Warning', 'Error', 'Verbose', 'Debug', 'Success')]
        [string]$Severity = 'Info'
    )

    Write-Log -Message $Message -Severity $Severity

    # dont run cleanup twice
    if ($script:WitnessCleanupRan) {
        return
    }

    $maxAgeDays = $script:WitnessMaxAgeDays
    if (Test-Path Variable:Global:WriteLogMaxAgeDays) {
        $maxAgeDays = $Global:WriteLogMaxAgeDays 
    }

    $callerScopePath = $PSCmdlet.SessionState.PSVariable.GetValue('LogFilePath')
    $resolvedPath = Resolve-WitnessLogPath -CallerResolved $callerScopePath

    if ([string]::IsNullOrWhiteSpace($resolvedPath)) {
        $script:WitnessCleanupRan = $true
        Write-Log -Message 'Write-LogFinal: Cannot determine log folder - skipping cleanup.' -Severity Warning
        return
    }

    $logFolder = Split-Path $resolvedPath
    if ([string]::IsNullOrWhiteSpace($logFolder) -or -not (Test-Path $logFolder)) {
        $script:WitnessCleanupRan = $true
        Write-Log -Message "Write-LogFinal: Log folder not found at '$logFolder' - skipping cleanup." -Severity Warning
        return
    }

    # sentinel before call prevents recursion
    $script:WitnessCleanupRan = $true
    try {
        Clear-LogFile -LogFolder $logFolder -MaxAgeDays $maxAgeDays
    }
    catch {
        Write-Log -Message "Log cleanup failed: $_" -Severity Error
    }
}

function Get-PlatformContext {
    <#
    .SYNOPSIS
        Returns a cross-platform identity and execution context object.

    .DESCRIPTION
        Detects platform (Windows/Linux/macOS), process identity, elevation, interactive
        user, session type, and hostname. Called once per session from Initialize-Log
        for the start banner. Windows uses WindowsIdentity; Linux/macOS use .NET
        Environment APIs with id(1) and loginctl fallbacks.

    .OUTPUTS
        PSCustomObject with Platform, IdentityName, LogonType, IsSystem, IsAdmin,
        UserDomainName, UserName, InteractiveUser, SessionType, HostName, ProcessId.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    # $IsMacOS missing on 5.1
    $platformStr = 'Linux'
    if ($script:WitnessIsWindows) {
        $platformStr = 'Windows'
    }
    elseif ((Test-Path Variable:IsMacOS) -and $IsMacOS) {
        $platformStr = 'macOS'
    }

    if ($script:WitnessIsWindows) {
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $identityName = $identity.Name
        $logonType = if ($identity.AuthenticationType) {
            $identity.AuthenticationType 
        }
        else {
            'N/A' 
        }
    }
    else {
        $identity = $null
        $identityName = "$([System.Environment]::UserDomainName)\$([System.Environment]::UserName)"
        $logonType = 'N/A'
    }

    # id -u must never run on windows
    if ($script:WitnessIsWindows) {
        $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
        $isAdmin = $principal.IsInRole(
            [System.Security.Principal.WindowsBuiltInRole]::Administrator
        )
    }
    else {
        # needs .NET 7+, missing on older builds
        $isAdmin = $false
        $privilegedProcessChecked = $false
        try {
            $isAdmin = [System.Environment]::IsPrivilegedProcess
            $privilegedProcessChecked = $true
        }
        catch [System.Management.Automation.RuntimeException] {
            $privilegedProcessChecked = $false
        }
        catch [System.MissingMemberException] {
            $privilegedProcessChecked = $false
        }
        if (-not $privilegedProcessChecked) {
            try {
                $idOutput = id -u 2>$null
                $isAdmin = ([int]$idOutput) -eq 0
            }
            catch {
                $isAdmin = $false
            }
        }
    }

    $isSystem = $false
    if ($script:WitnessIsWindows) {
        $isSystem = $identityName -eq 'NT AUTHORITY\SYSTEM'
    }

    $hostName = [System.Environment]::MachineName

    $interactiveUser = $null
    if ($script:WitnessIsWindows) {
        try {
            $explorer = Get-Process explorer -IncludeUserName -ErrorAction SilentlyContinue
            if ($explorer) {
                $interactiveUser = ($explorer | Select-Object -First 1).UserName
            }
        }
        catch {
        }
        if (-not $interactiveUser) {
            $interactiveUser = [System.Environment]::UserName
        }
    }
    else {
        # loginctl doesnt exist on macOS
        if ($platformStr -ne 'macOS') {
            try {
                $raw = loginctl list-sessions --no-legend 2>$null
                if ($LASTEXITCODE -eq 0 -and $raw) {
                    foreach ($line in ($raw -split "`n")) {
                        $fields = $line.Trim() -split '\s+'
                        if ($fields.Count -ge 3) {
                            $sessionId = $fields[0]
                            $sessionUser = $fields[2]
                            $sessionType = (loginctl show-session $sessionId -p Type --value 2>$null)
                            if ($null -ne $sessionType) {
                                $sessionType = $sessionType.Trim() 
                            }
                            if ($sessionType -in 'x11', 'wayland') {
                                $interactiveUser = $sessionUser
                                break
                            }
                        }
                    }
                }
            }
            catch {
            }
        }

        if (-not $interactiveUser) {
            try {
                $whoOutput = who 2>$null
                if ($LASTEXITCODE -eq 0 -and $whoOutput) {
                    $interactiveUser = ($whoOutput -split "`n" |
                            Where-Object { $_ -match '\S' } |
                            Select-Object -First 1) -split '\s+' |
                            Select-Object -First 1
                }
            }
            catch {
            }
        }

        if (-not $interactiveUser) {
            $interactiveUser = [System.Environment]::UserName
        }
    }

    $sessionType = $logonType
    if (-not $script:WitnessIsWindows) {
        $sshConn = [System.Environment]::GetEnvironmentVariable('SSH_CONNECTION')
        $xdgType = [System.Environment]::GetEnvironmentVariable('XDG_SESSION_TYPE')
        $xdgClass = [System.Environment]::GetEnvironmentVariable('XDG_SESSION_CLASS')

        if ($sshConn) {
            $sessionType = "ssh ($sshConn)"
        }
        elseif ($xdgType) {
            $sessionType = if ($xdgClass) {
                "$xdgType ($xdgClass)" 
            }
            else {
                $xdgType 
            }
        }
        else {
            $xdgSessionId = [System.Environment]::GetEnvironmentVariable('XDG_SESSION_ID')
            if ($xdgSessionId -and $platformStr -ne 'macOS') {
                try {
                    $lType = (loginctl show-session $xdgSessionId -p Type --value 2>$null)
                    $lClass = (loginctl show-session $xdgSessionId -p Class --value 2>$null)
                    if ($LASTEXITCODE -eq 0 -and $lType) {
                        $parts = @()
                        if ($lType) {
                            $parts += "type=$($lType.Trim())" 
                        }
                        if ($lClass) {
                            $parts += "class=$($lClass.Trim())" 
                        }
                        $sessionType = $parts -join '; '
                    }
                }
                catch {
                }
            }
            if ($sessionType -eq 'N/A') {
                $hasTty = -not [System.Console]::IsInputRedirected
                $sessionType = if ($hasTty) {
                    'local-interactive' 
                }
                else {
                    'non-interactive-or-unknown' 
                }
            }
        }
    }

    [pscustomobject]@{
        Platform        = $platformStr
        IdentityName    = $identityName
        LogonType       = $logonType
        IsSystem        = $isSystem
        IsAdmin         = $isAdmin
        UserDomainName  = [System.Environment]::UserDomainName
        UserName        = [System.Environment]::UserName
        InteractiveUser = $interactiveUser
        SessionType     = $sessionType
        HostName        = $hostName
        ProcessId       = $PID
    }
}


function Initialize-Log {
    <#
    .SYNOPSIS
        Initialize the log path and write a structured session-start banner.

    .DESCRIPTION
        Call once at the start of a script or session. Stores the resolved log file
        path in script scope so all subsequent Write-Log calls find it without an
        explicit -Logfile argument. The banner is written directly to the file
        bypassing the Verbose/Debug gate, and echoed to the console. Calling
        Initialize-Log a second time resets the auto-cleanup sentinel.

    .PARAMETER LogFilePath
        Full path to the log file. The parent directory is created if missing.

    .PARAMETER ScriptName
        Name of the calling script for the banner. Auto-detected when not supplied.

    .PARAMETER Version
        Version string written to the banner VERSION line.

    .OUTPUTS
        None. Sets $script:WitnessLogFilePath and writes the banner.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param (
        [Parameter(Mandatory = $false)]
        [string]$LogFilePath = (Get-Variable -Name LogFilePath -ErrorAction SilentlyContinue).Value,

        [Parameter(Mandatory = $false)]
        [string]$ScriptName,

        [Parameter(Mandatory = $false)]
        [string]$Version
    )

    $callerCandidate = $null
    if ($PSBoundParameters.ContainsKey('LogFilePath') -and -not [string]::IsNullOrWhiteSpace($LogFilePath)) {
        $callerCandidate = $LogFilePath
    }
    else {
        $callerScopePath = $PSCmdlet.SessionState.PSVariable.GetValue('LogFilePath')
        if (-not [string]::IsNullOrWhiteSpace($callerScopePath)) {
            $callerCandidate = $callerScopePath
        }
    }
    $LogFilePath = Resolve-WitnessLogPath -CallerResolved $callerCandidate

    if ([string]::IsNullOrWhiteSpace($LogFilePath)) {
        throw "Initialize-Log: No log file path provided. Pass -LogFilePath, set `$LogFilePath in your script scope, or set `$Global:LogFilePath before calling Initialize-Log."
    }

    $script:WitnessLogFilePath = $LogFilePath

    # new session, reset cleanup sentinel
    $script:WitnessCleanupRan = $false

    if ([string]::IsNullOrWhiteSpace($ScriptName)) {
        try {
            $callStack = Get-PSCallStack
            if ($callStack.Count -gt 1) {
                $ScriptName = $callStack[1].ScriptName | Split-Path -Leaf
            }
            if ([string]::IsNullOrWhiteSpace($ScriptName)) {
                $ScriptName = "Unknown Script" 
            }
        }
        catch {
            $ScriptName = "Unknown Script"
        }
    }

    $ctx = Get-PlatformContext

    # CMSite PSDrive breaks filesystem ops, same guard Write-Log uses
    $originalLocation = Get-Location
    $isSCCMDrive = $false
    if ($script:WitnessIsWindows) {
        if ($null -ne $originalLocation.Provider -and $originalLocation.Provider.Name -eq 'CMSite') {
            $isSCCMDrive = $true
            Set-Location C:
        }
    }

    $logDir = Split-Path $LogFilePath
    if ($logDir -and !(Test-Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }

    # bypass Write-Log so banner always appears regardless of gate settings
    $now = Get-Date
    $LogDate = $now.ToString('MM-dd-yyyy')
    $LogTime = $now.ToString('HH:mm:ss.fff')

    if ($script:WitnessIsWindows) {
        $contextUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    }
    else {
        $contextUser = "$([System.Environment]::UserDomainName)\$([System.Environment]::UserName)"
    }

    $bannerLines = @(
        "===============================================================================",
        "SCRIPT START: $ScriptName",
        "TIME:         $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "IDENTITY:     $($ctx.IdentityName)",
        "CONTEXT:      $(if ($ctx.IsSystem) { 'SYSTEM' } else { 'USER' }), Admin=$($ctx.IsAdmin)",
        "PLATFORM:     $($ctx.Platform)",
        "ENV USER:     $($ctx.UserDomainName)\$($ctx.UserName)",
        "INTERACTIVE:  $($ctx.InteractiveUser)",
        "SESSION:      $($ctx.SessionType)",
        "HOST:         $($ctx.HostName)",
        "PID:          $($ctx.ProcessId)",
        "LOG:          $LogFilePath",
        "VERSION:      $Version",
        "==============================================================================="
    )

    $fileStream = $null
    $streamWriter = $null
    try {
        $fileMode = [System.IO.FileMode]::Append
        $fileAccess = [System.IO.FileAccess]::Write
        $fileShare = [System.IO.FileShare]::ReadWrite
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)

        $fileStream = New-Object System.IO.FileStream($LogFilePath, $fileMode, $fileAccess, $fileShare)
        $streamWriter = New-Object System.IO.StreamWriter($fileStream, $utf8NoBom)
        $streamWriter.NewLine = [System.Environment]::NewLine

        foreach ($line in $bannerLines) {
            $entry = "<![LOG[$line]LOG]!>" +
            "<time=`"$LogTime`" " +
            "date=`"$LogDate`" " +
            "component=`"Initialize-Log`" " +
            "context=`"$contextUser`" " +
            "type=`"1`" " +
            "thread=`"$PID`" " +
            "file=`"Write-Log.ps1`">"
            $streamWriter.WriteLine($entry)
        }
    }
    catch {
        Write-Warning "Initialize-Log: Failed to write banner to '$LogFilePath': $_"
    }
    finally {
        try {
            if ($null -ne $streamWriter) {
                $streamWriter.Dispose() 
            } 
        }
        catch { 
        }
        try {
            if ($null -ne $fileStream) {
                $fileStream.Dispose()   
            } 
        }
        catch { 
        }
    }

    # banner to console unconditionally, session context must be visible on screen
    foreach ($line in $bannerLines) {
        Write-Host $line -ForegroundColor Cyan
    }

    if ($isSCCMDrive) {
        try {
            Set-Location $originalLocation -ErrorAction SilentlyContinue
        }
        catch {
            Write-Warning "Initialize-Log: Could not restore CMSite location: $_"
        }
    }
}
