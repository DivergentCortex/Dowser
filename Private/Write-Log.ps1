function Get-SafeLogIdentity {
    # Returns current user identity string, cross-platform safe.
    # Used in CMTrace log format context field.
    if ($IsWindows) {
        try {
            return [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        } catch {
            return $env:USERNAME
        }
    }
    # Linux/macOS: use environment variables
    if ($env:USER) { return $env:USER }
    if ($env:LOGNAME) { return $env:LOGNAME }
    return 'unknown'
}

Function Write-Log {
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
        Version:                       2026.03.24.010
        ===========================================================================

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

        ## OPTIONAL - Granular Verbose/Debug Control (all default to $true):
            $Global:VerboseConsole = $true   # Verbose messages to console
            $Global:VerboseLogfile = $true   # Verbose messages to logfile
            $Global:DebugConsole   = $true   # Debug messages to console
            $Global:DebugLogfile   = $true   # Debug messages to logfile

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
    Param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Message,

        [Parameter(Mandatory = $False)]
        [String]$Logfile = $LogFilePath,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Information', 'Warning', 'Error', 'Verbose', 'Debug', 'Success')]
        [Alias("LogLevel", "Type", "level")]
        [String]$Severity = "Info",

        [Parameter(Mandatory = $False)]
        [String]$Component,

        [Parameter(Mandatory = $False)]
        [switch]$WriteBackToHost = $True,

        [Parameter(Mandatory = $False)]
        [int]$MaxRetries = 3,

        [Parameter(Mandatory = $False)]
        [double]$RetryDelay = 0.5,

        [Parameter(Mandatory = $False)]
        [System.ConsoleColor]$Color
    )

    # ==================== AUTO LOG MANAGEMENT ====================
    # Global settings (set before dot-sourcing to override defaults):
    #   $Global:WriteLogAutoCleanup    = $true   # Enable auto-cleanup (default: $true)
    #   $Global:WriteLogMaxSizeMB      = 10      # Max log size before rotation (default: 10MB)
    #   $Global:WriteLogMaxAgeDays     = 7       # Delete logs older than N days (default: 7)

    # Get settings from globals or use defaults
    $autoCleanup    = if (Test-Path Variable:Global:WriteLogAutoCleanup) { $Global:WriteLogAutoCleanup } else { $true }
    $maxSizeMB      = if (Test-Path Variable:Global:WriteLogMaxSizeMB) { $Global:WriteLogMaxSizeMB } else { 10 }
    $maxAgeDays     = if (Test-Path Variable:Global:WriteLogMaxAgeDays) { $Global:WriteLogMaxAgeDays } else { 7 }

    # REQUIRE $LogFilePath to be set - no TEMP fallback ever
    # caller must set $LogFilePath before dot-sourcing Write-Log.ps1
    if ([string]::IsNullOrWhiteSpace($Logfile)) {
        throw "FATAL: `$LogFilePath is not set. You must define `$LogFilePath BEFORE dot-sourcing Write-Log.ps1. Example:`n`$LogFilePath = Join-Path `$PSScriptRoot 'logs\MyScript_`$(Get-Date -Format 'yyyyMMdd').log'"
    }

    # Resolve tilde/PS-drive paths; log file may not exist yet so use unresolved provider path
    $Logfile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Logfile)

    # Map "Information" to "Info" for internal processing
    if ($Severity -eq "Information") {
        $Severity = "Info"
    }

    # Granular output control via global variables (all default to $true if not defined)
    $verboseToConsole = if (Test-Path Variable:Global:VerboseConsole) { $Global:VerboseConsole } else { $true }
    $verboseToLogfile = if (Test-Path Variable:Global:VerboseLogfile) { $Global:VerboseLogfile } else { $true }
    $debugToConsole   = if (Test-Path Variable:Global:DebugConsole) { $Global:DebugConsole } else { $true }
    $debugToLogfile   = if (Test-Path Variable:Global:DebugLogfile) { $Global:DebugLogfile } else { $true }

    # Early return if both outputs disabled for this severity (performance optimization)
    if ($Severity -eq "Verbose" -and (-not $verboseToConsole) -and (-not $verboseToLogfile)) { return }
    if ($Severity -eq "Debug" -and (-not $debugToConsole) -and (-not $debugToLogfile)) { return }

    # Store original location
    $originalLocation = Get-Location
    $isSCCMDrive = $false    # PS 2.0 compatible check for CMSite provider
    if ($null -ne $originalLocation.Provider -and $originalLocation.Provider.Name -eq 'CMSite') {
        $isSCCMDrive = $true
        # Switch to C: drive temporarily
        Set-Location C:
    }
    
    try {        # Get caller information more reliably
        # First, get the call stack
        $callStack = Get-PSCallStack
        
        # Default values if we can't determine them
        $Source = "Unknown"
        $callerFunctionName = "Unknown"
        $lineNumber = "?"
        
        # If we have a call stack with at least 2 entries (current function and caller)
        if ($null -ne $callStack -and $callStack.Count -gt 1) {
            $callerInfo = $callStack[1]
            
            # Get the source file location
            if ($callerInfo.Location) {
                $Source = $callerInfo.Location
            }
            
            # Get line number for console output
            if ($callerInfo.ScriptLineNumber) {
                $lineNumber = $callerInfo.ScriptLineNumber
            }
              # Determine the calling function name
            if ($callerInfo.Command) {
                $callerFunctionName = $callerInfo.Command
                
                # If it looks like a script path rather than a function name, extract just the script name
                if ($callerFunctionName -like "*.ps1") {
                    $callerFunctionName = [System.IO.Path]::GetFileNameWithoutExtension($callerFunctionName)
                    Write-Verbose "Call from script body: $callerFunctionName"
                } else {
                    Write-Verbose "Call from function: $callerFunctionName"
                }
            }
        }
          # Component resolution priority:
        # 1. Explicitly provided Component parameter
        # 2. Caller function name from call stack (prioritized over Script:Component)
        # 3. Script:Component if defined in the calling script
        # 4. "Unknown" as last resort
        if ([string]::IsNullOrEmpty($Component)) {
            # PRIORITIZE function name from call stack over Script:Component
            if ($callerFunctionName -ne "Unknown" -and $callerFunctionName -notlike "*ps1") {
                # Use the function name from the call stack if it's a proper function
                $Component = $callerFunctionName
            }
            # Only fall back to Script:Component if we couldn't get a function name
            elseif (Test-Path Variable:Script:Component) {
                $Component = $Script:Component
            }
            else {
                # Use whatever we could get from the call stack
                $Component = $callerFunctionName
            }
        }
        
        # Final check - make sure Component isn't empty
        if ([string]::IsNullOrEmpty($Component) -or $Component -eq "Unknown") {            # One last attempt - try to get it from MyInvocation of the caller
            if ($callStack.Count -gt 1 -and $null -ne $callStack[1].InvocationInfo -and $null -ne $callStack[1].InvocationInfo.MyCommand) {
                $Component = $callStack[1].InvocationInfo.MyCommand.Name
            }
            
            # If still empty, use a default
            if ([string]::IsNullOrEmpty($Component)) {
                $Component = "Unknown"
            }
        }
        
        # Format dates EXACTLY as CMTrace expects them
        $DateTime = Get-Date
        # Date must be MM-dd-yyyy format
        $LogDate = $DateTime.ToString('MM-dd-yyyy')
        # Time must be HH:mm:ss.fff format with direct UTC offset in minutes
        $UtcOffset = [TimeZoneInfo]::Local.GetUtcOffset($DateTime).TotalMinutes
        $LogTime = "$($DateTime.ToString('HH:mm:ss.fff'))$UtcOffset"

        # Get correct severity type mapping for CMTrace - numeric codes
        $severityType = "1" # Default to Info
        if ($Severity -eq "Error") { $severityType = "3" }
        elseif ($Severity -eq "Warning") { $severityType = "2" }
        elseif ($Severity -eq "Info") { $severityType = "1" }
        elseif ($Severity -eq "Success") { $severityType = "1" } # Map to Info for CMTrace
        elseif ($Severity -eq "Verbose") { $severityType = "4" }
        elseif ($Severity -eq "Debug") { $severityType = "5" }

        # Build CMTrace compatible log line - NO SPACES between attributes
        $logline = "<![LOG[$Message]LOG]!>" + 
            "<time=`"$LogTime`" " + 
            "date=`"$LogDate`" " + 
            "component=`"$Component`" " + 
            "context=`"$(Get-SafeLogIdentity)`" " + 
            "type=`"$severityType`" " + 
            "thread=`"$PID`" " + 
            "file=`"$Source`">"

        # Create log directory if needed
        $logDir = Split-Path (Get-Variable -Name logfilepath -ValueOnly)
        if (!(Test-Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        }

        # Check if console output is enabled for this severity
        $shouldWriteConsole = switch ($Severity) {
            'Verbose' { $verboseToConsole }
            'Debug'   { $debugToConsole }
            default   { $true }
        }

        # Write to console if enabled
        if ($WriteBackToHost -and $shouldWriteConsole) {
            # Truncate component name for display if too long
            $displayComponent = $Component
            if ($displayComponent.Length -gt 12) {
                $displayComponent = $displayComponent.Substring(0, 10) + ".."
            }

            # Define severity label and color mappings
            $severityConfig = @{
                'Error'   = @{ Label = ' ERROR '; LabelColor = 'Red'; MessageColor = 'Red' }
                'Warning' = @{ Label = ' WARNING '; LabelColor = 'Yellow'; MessageColor = 'Yellow' }
                'Info'    = @{ Label = ' INFO '; LabelColor = 'Green'; MessageColor = 'White' }
                'Success' = @{ Label = ' SUCCESS '; LabelColor = 'Green'; MessageColor = 'Green' }
                'Verbose' = @{ Label = ' VERBOSE '; LabelColor = 'DarkGray'; MessageColor = 'DarkGray' }
                'Debug'   = @{ Label = ' DEBUG '; LabelColor = 'Magenta'; MessageColor = 'Magenta' }
            }

            # Get configuration for current severity
            $config = $severityConfig[$Severity]

            # Determine final message color (use -Color parameter if specified, otherwise default)
            $finalMessageColor = if ($PSBoundParameters.ContainsKey('Color')) {
                $Color
            } else {
                $config.MessageColor
            }

            # Write formatted output: [ SEVERITY ] [Component..] [LineNum]: Message
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

        # Check if logfile output is enabled for this severity
        $shouldWriteLogfile = switch ($Severity) {
            'Verbose' { $verboseToLogfile }
            'Debug'   { $debugToLogfile }
            default   { $true }
        }

        # ==================== SIZE-BASED LOG ROTATION ====================
        # If current log exceeds max size, rotate (rename) old file and start fresh
        if ($shouldWriteLogfile -and (Test-Path $Logfile)) {
            $currentSize = (Get-Item $Logfile).Length / 1MB
            if ($currentSize -ge $maxSizeMB) {
                $logDir = Split-Path $Logfile
                $logBase = [System.IO.Path]::GetFileNameWithoutExtension($Logfile)
                $logExt = [System.IO.Path]::GetExtension($Logfile)

                # Find next available rotation number for the ARCHIVE name
                $rotationNum = 1
                do {
                    $archiveName = "{0}_r{1:D2}{2}" -f $logBase, $rotationNum, $logExt
                    $archivePath = Join-Path $logDir $archiveName
                    $rotationNum++
                } while (Test-Path $archivePath)

                # RENAME old file to archive name (removes it from original path)
                try {
                    Rename-Item -Path $Logfile -NewName $archiveName -Force
                } catch {
                    # If rename fails, continue writing to current file
                }

                # $Logfile path now doesn't exist - will be created fresh
                # Log rotation event as first entry in new log
                $rotationMsg = "<![LOG[LOG ROTATION: Previous log archived to $archiveName (exceeded ${maxSizeMB}MB)]LOG]!>" +
                    "<time=`"$LogTime`" date=`"$LogDate`" component=`"Write-Log`" " +
                    "context=`"$(Get-SafeLogIdentity)`" " +
                    "type=`"1`" thread=`"$PID`" file=`"Write-Log.ps1`">"

                try {
                    [System.IO.File]::WriteAllText($Logfile, "$rotationMsg`r`n")
                } catch { }
            }
        }

        # ==================== AUTO-CLEANUP (ONCE PER SESSION) ====================
        # Run cleanup once on first Write-Log call in this session
        $cleanupAlreadyRan = if (Test-Path Variable:Script:WriteLogCleanupRan) { $Script:WriteLogCleanupRan } else { $false }
        if ($autoCleanup -and (-not $cleanupAlreadyRan) -and (Test-Path $Logfile)) {
            $Script:WriteLogCleanupRan = $true  # Set BEFORE cleanup to prevent recursion
            $logFolder = Split-Path $Logfile
            if (Test-Path $logFolder) {
                try {
                    Cleanup-LogFiles -LogFolder $logFolder -MaxAgeDays $maxAgeDays
                } catch {
                    # Cleanup failure shouldn't break logging
                    Write-Warning "Auto-cleanup failed: $_"
                }
            }
        }

        # Write to logfile if enabled
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

                    $fileStream = New-Object System.IO.FileStream($Logfile, $fileMode, $fileAccess, $fileShare)
                    $streamWriter = New-Object System.IO.StreamWriter($fileStream)
                    $streamWriter.WriteLine($logline)
                    $writeSucceeded = $true

                    # If we had to retry, log that fact for visibility into file contention
                    if ($retryCount -gt 0) {
                        $retryNote = "<![LOG[WRITE-LOG FILE CONTENTION: Previous entry required $retryCount retry attempt(s) due to file lock on $Logfile]LOG]!>" +
                            "<time=`"$LogTime`" date=`"$LogDate`" component=`"Write-Log`" " +
                            "context=`"$(Get-SafeLogIdentity)`" " +
                            "type=`"2`" thread=`"$PID`" file=`"Write-Log.ps1`">"
                        $streamWriter.WriteLine($retryNote)
                    }
                }
                catch [System.IO.IOException] {
                    # File is locked - retry if we have attempts left
                    $retryCount++
                    if ($retryCount -le $MaxRetries) {
                        Start-Sleep -Milliseconds ([int]($RetryDelay * 1000))
                    } else {
                        Write-Warning "Failed to write to log after $MaxRetries retries (file locked): $Logfile"
                    }
                }
                catch {
                    # Non-lock error - don't retry
                    Write-Warning "Failed to write to log file: $_"
                    break
                }
                finally {
                    if ($null -ne $streamWriter) { $streamWriter.Close() }
                    if ($null -ne $fileStream) { $fileStream.Close() }
                }
            }
        }
    }
    finally {
        # Return to original location if possible (SCCM drive may have disconnected)
        if ($isSCCMDrive) {
            try { Set-Location $originalLocation -ErrorAction SilentlyContinue } catch { }
        }
    }
}

Function Cleanup-LogFiles {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [string]$LogFolder,

        # delete all logs older than this many days - no count-based logic
        [Parameter()]
        [int]$MaxAgeDays = 7,

        # optional: scope cleanup to a specific script name prefix
        [Parameter()]
        [string]$ScriptFilter = $null
    )

    Write-Log "Starting log cleanup in: $LogFolder (keep last $MaxAgeDays days)" -Severity Debug

    $logFiles = Get-ChildItem -Path $LogFolder -Filter "*.log" -File -ErrorAction SilentlyContinue
    if (-not $logFiles) {
        Write-Log "No log files found in $LogFolder" -Severity Verbose
        return
    }

    if ($ScriptFilter) {
        $logFiles = $logFiles | Where-Object { $_.BaseName -like "$ScriptFilter*" }
        if (-not $logFiles) {
            Write-Log "No log files matched filter: $ScriptFilter" -Severity Verbose
            return
        }
    }

    $cutoff  = (Get-Date).AddDays(-$MaxAgeDays)
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
    .DESCRIPTION
      Writes a final log message and triggers the log cleanup routine.
      Use this function only as your final log entry in the script
      (for example, in Remove-HpAdminLocal.ps1) so that cleanup only occurs once.
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Warning', 'Error', 'Verbose', 'Debug')]
        [string]$Severity = 'Info'
    )
    
    # Write the final log message using your existing Write-Log function.
    Write-Log -Message $Message -Severity $Severity
    
    # Write another log message indicating that the cleanup routine is triggered.
    Write-Log -Message "Final log entry: Triggering log cleanup." -Severity 'Verbose'
    
    # Determine the log folder—assuming your global $LogFile variable holds the current log file path.
    $logFolder = Split-Path $LogFile
    
    try {
        Cleanup-LogFiles -LogFolder $logFolder
    }
    catch {
        Write-Log -Message "Log cleanup failed: $_" -Severity 'Error'
    }
}

function Get-ExecutionContextInfo {
    [CmdletBinding()]
    param()

    if (-not $IsWindows) {
        return [PSCustomObject]@{
            UserName    = Get-SafeLogIdentity
            IsAdmin     = ($env:USER -eq 'root')
            IsSystem    = $false
            SessionType = 'NonWindows'
        }
    }

    # Original Windows code continues unchanged below...
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)

    $isSystem   = $identity.Name -eq 'NT AUTHORITY\SYSTEM'
    $isAdmin    = $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)

    # Best-effort “interactive” guess: has a non-empty USERNAME and explorer.exe for that user
    $interactiveUser = $null
    try {
        $explorer = Get-Process explorer -IncludeUserName -ErrorAction SilentlyContinue
        if ($explorer) {
            $interactiveUser = ($explorer | Select-Object -First 1).UserName
        }
    } catch {}

    [pscustomobject]@{
        IdentityName    = $identity.Name
        LogonType       = $identity.AuthenticationType
        IsSystem        = $isSystem
        IsAdmin         = $isAdmin
        UserDomainUser  = if ($env:USERDOMAIN -and $env:USERNAME) { "$($env:USERDOMAIN)\$($env:USERNAME)" } else { $null }
        InteractiveUser = $interactiveUser
        ProcessId       = $PID
        HostName        = $env:COMPUTERNAME
    }
}


Function Initialize-Log {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $false)]
        [string]$LogFilePath = (Get-Variable -Name logfilepath -ValueOnly),

        [string]$ScriptName,

        [string]$Version
    )

    if ([string]::IsNullOrWhiteSpace($ScriptName)) {
        try {
            $callStack = Get-PSCallStack
            if ($callStack.Count -gt 1) {
                $ScriptName = $callStack[1].ScriptName | Split-Path -Leaf
            }
            if ([string]::IsNullOrWhiteSpace($ScriptName)) {
                $ScriptName = "Unknown Script"
            }
        } catch {
            $ScriptName = "Unknown Script"
        }
    }

    $ctx = Get-ExecutionContextInfo

    Write-Log -Message "===============================================================================" -Severity Verbose
    Write-Log -Message "SCRIPT START: $ScriptName" -Severity Debug
    Write-Log -Message "TIME:         $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Severity Debug
    Write-Log -Message "IDENTITY:     $($ctx.IdentityName)" -Severity Debug
    Write-Log -Message "CONTEXT:      $(if ($ctx.IsSystem) { 'SYSTEM' } else { 'USER' }), Admin=$($ctx.IsAdmin)" -Severity Debug
    Write-Log -Message "ENV USER:     $($ctx.UserDomainUser)" -Severity Debug
    if ($ctx.InteractiveUser) {
        Write-Log -Message "INTERACTIVE:  $($ctx.InteractiveUser)" -Severity Debug
    }
    Write-Log -Message "HOST:         $($ctx.HostName)" -Severity Debug
    Write-Log -Message "PID:          $($ctx.ProcessId)" -Severity Debug
    Write-Log -Message "LOG:          $LogFilePath" -Severity Debug
    Write-Log -Message "VERSION:      $Version" -Severity Debug
    Write-Log -Message "===============================================================================" -Severity Verbose
}

##############################################################
##############################################################
