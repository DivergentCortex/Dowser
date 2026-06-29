function ConvertTo-DowserExe {
    <#
    .SYNOPSIS
        Wraps a PowerShell script in a compiled console EXE that runs the script via powershell.exe.
    .NOTES
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
        -  Author:        Curtis Leggett                                  -
        =  Copyright:     2026 Divergent Cortex                           =
        -  Organization:  Divergent Cortex                                -
        =  Version:       See docs/CHANGELOG.md                           =
        =-=-                       =-=-=-=-=-=-=-=                     -=-=
        -  it is not water they seek, but the truth beneath the trees     -
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
    .DESCRIPTION
        Reads the target script, embeds its contents as a string literal inside a
        generated C# console program, and compiles that program to a PE executable
        using Add-Type. At runtime the EXE writes the embedded script to a temp .ps1
        file, launches powershell.exe with -ExecutionPolicy Bypass against it,
        captures stdout and stderr, prints them, then deletes the temp file.

        Compilation depends on Add-Type -OutputType, which exists only in Windows
        PowerShell 5.1. On PowerShell 6+ the function warns and returns $null without
        producing an EXE. The function also requires Windows; on other platforms it
        warns and returns $null. The output EXE is named after the input script with
        a .exe extension and is written to the current working directory.
    .PARAMETER ScriptPath
        Path to the PowerShell .ps1 script to wrap into an executable.
    .EXAMPLE
        ConvertTo-DowserExe -ScriptPath 'C:\scripts\Deploy.ps1'

        Produces Deploy.exe in the current directory when run under Windows PowerShell 5.1.
    .OUTPUTS
        None. Writes an .exe file to disk. Returns $null when the platform or
        PowerShell version is unsupported.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath
    )

    Write-Log "Starting ConvertTo-DowserExe"

    # eq false not -not, $IsWindows is null on 5.1
    if ($IsWindows -eq $false) {
        Write-Log "ConvertTo-DowserExe requires Windows. Not available on this platform." -Severity Warning
        return $null
    }

    try {
        $scriptContent = Get-Content -Path $ScriptPath -Raw -ErrorAction Stop
    }
    catch {
        Write-Log "ConvertTo-DowserExe failed reading script '$ScriptPath': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Error
        return $null
    }

    $codeTemplate = @"
using System;
using System.IO;
using System.Diagnostics;
using System.Text;

namespace PowerShellWrapper
{
    class Program
    {
        static void Main(string[] args)
        {
            string scriptContent = @"$($scriptContent -replace '"', '""')";

            string tempScriptPath = Path.GetTempFileName() + ".ps1";
            File.WriteAllText(tempScriptPath, scriptContent);

            ProcessStartInfo startInfo = new ProcessStartInfo();
            startInfo.FileName = "powershell.exe";
            startInfo.Arguments = "-ExecutionPolicy Bypass -File "" + tempScriptPath + """;
            startInfo.UseShellExecute = false;
            startInfo.RedirectStandardOutput = true;
            startInfo.RedirectStandardError = true;
            startInfo.CreateNoWindow = true;

            Process process = new Process();
            process.StartInfo = startInfo;
            process.Start();

            string output = process.StandardOutput.ReadToEnd();
            string error = process.StandardError.ReadToEnd();

            process.WaitForExit();

            Console.WriteLine(output);
            Console.WriteLine(error);

            File.Delete(tempScriptPath);
        }
    }
}
"@

    $outputFile = [System.IO.Path]::GetFileNameWithoutExtension($ScriptPath) + ".exe"
    # Add-Type -OutputType was removed in PS 6+
    if ($PSVersionTable.PSVersion.Major -lt 6) {
        Write-Log "Compiling '$ScriptPath' to '$outputFile'."
        try {
            Add-Type -TypeDefinition $codeTemplate -Language CSharp -OutputAssembly $outputFile -OutputType ConsoleApplication -ErrorAction Stop
            Write-Log "Compiled '$outputFile' successfully."
        }
        catch {
            Write-Log "ConvertTo-DowserExe failed compiling '$outputFile': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Error
        }
    }
    else {
        Write-Log "ConvertTo-DowserExe requires Windows PowerShell 5.1 (Add-Type -OutputType removed in PS 6+). Run under powershell.exe." -Severity Warning
        return $null
    }

    Write-Log "Ending ConvertTo-DowserExe"
}

function ConvertTo-DowserExeConfuserEx {
    <#
    .SYNOPSIS
        Wraps a PowerShell script in a console EXE and obfuscates it with ConfuserEx.
    .NOTES
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
        -  Author:        Curtis Leggett                                  -
        =  Copyright:     2026 Divergent Cortex                           =
        -  Organization:  Divergent Cortex                                -
        =  Version:       See docs/CHANGELOG.md                           =
        =-=-                       =-=-=-=-=-=-=-=                     -=-=
        -  it is not water they seek, but the truth beneath the trees     -
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
    .DESCRIPTION
        Builds the same powershell.exe-wrapping console EXE as ConvertTo-DowserExe,
        then runs ConfuserEx against the resulting binary to obfuscate it in place.
        Compilation uses Add-Type -OutputType, which exists only in Windows
        PowerShell 5.1; on PowerShell 6+ the function warns and returns $null. The
        function also requires Windows; on other platforms it warns and returns $null.
        After compilation it invokes Confuser.CLI.exe from -ConfuserExPath using the
        ConfuserEx.crproj project file found in the same directory, overwriting the
        output EXE with the obfuscated build.
    .PARAMETER ScriptPath
        Path to the PowerShell .ps1 script to wrap into an executable.
    .PARAMETER ConfuserExPath
        Path to the directory holding Confuser.CLI.exe and ConfuserEx.crproj.
    .EXAMPLE
        ConvertTo-DowserExeConfuserEx -ScriptPath 'C:\scripts\Deploy.ps1' -ConfuserExPath 'C:\Tools\ConfuserEx'

        Compiles Deploy.exe and obfuscates it using the ConfuserEx CLI in C:\Tools\ConfuserEx.
    .OUTPUTS
        None. Writes an obfuscated .exe file to disk. Returns $null when the platform
        or PowerShell version is unsupported.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,
        [Parameter(Mandatory = $true)]
        [string]$ConfuserExPath
    )

    Write-Log "Starting ConvertTo-DowserExeConfuserEx"

    # eq false not -not, $IsWindows is null on 5.1
    if ($IsWindows -eq $false) {
        Write-Log "ConvertTo-DowserExeConfuserEx requires Windows. Not available on this platform." -Severity Warning
        return $null
    }

    try {
        $scriptContent = Get-Content -Path $ScriptPath -Raw -ErrorAction Stop
    }
    catch {
        Write-Log "ConvertTo-DowserExeConfuserEx failed reading script '$ScriptPath': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Error
        return $null
    }

    $codeTemplate = @"
using System;
using System.IO;
using System.Diagnostics;
using System.Text;

namespace PowerShellWrapper
{
    class Program
    {
        static void Main(string[] args)
        {
            string scriptContent = @"$($scriptContent -replace '"', '""')";

            string tempScriptPath = Path.GetTempFileName() + ".ps1";
            File.WriteAllText(tempScriptPath, scriptContent);

            ProcessStartInfo startInfo = new ProcessStartInfo();
            startInfo.FileName = "powershell.exe";
            startInfo.Arguments = "-ExecutionPolicy Bypass -File "" + tempScriptPath + """;
            startInfo.UseShellExecute = false;
            startInfo.RedirectStandardOutput = true;
            startInfo.RedirectStandardError = true;
            startInfo.CreateNoWindow = true;

            Process process = new Process();
            process.StartInfo = startInfo;
            process.Start();

            string output = process.StandardOutput.ReadToEnd();
            string error = process.StandardError.ReadToEnd();

            process.WaitForExit();

            Console.WriteLine(output);
            Console.WriteLine(error);

            File.Delete(tempScriptPath);
        }
    }
}
"@

    $outputFile = [System.IO.Path]::GetFileNameWithoutExtension($ScriptPath) + ".exe"
    # Add-Type -OutputType was removed in PS 6+
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        Write-Log "ConvertTo-DowserExeConfuserEx requires Windows PowerShell 5.1 (Add-Type -OutputType removed in PS 6+). Run under powershell.exe." -Severity Warning
        return $null
    }

    Write-Log "Compiling '$ScriptPath' to '$outputFile'."
    try {
        Add-Type -TypeDefinition $codeTemplate -Language CSharp -OutputAssembly $outputFile -OutputType ConsoleApplication -ErrorAction Stop
        Write-Log "Compiled '$outputFile' successfully."
    }
    catch {
        Write-Log "ConvertTo-DowserExeConfuserEx failed compiling '$outputFile': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Error
        return $null
    }

    $confuserCliExe = Join-Path -Path $ConfuserExPath -ChildPath "Confuser.CLI.exe"
    $confuserExConfig = Join-Path -Path $ConfuserExPath -ChildPath "ConfuserEx.crproj"
    Write-Log "Running ConfuserEx on '$outputFile'."
    try {
        & $confuserCliExe -n $outputFile -o $outputFile --project $confuserExConfig
        if ($LASTEXITCODE -ne 0) {
            Write-Log "ConvertTo-DowserExeConfuserEx: ConfuserEx exited with code $LASTEXITCODE for '$outputFile'." -Severity Warning
        }
        else {
            Write-Log "ConfuserEx obfuscation complete for '$outputFile'."
        }
    }
    catch {
        Write-Log "ConvertTo-DowserExeConfuserEx failed running ConfuserEx on '$outputFile': $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity Error
    }

    Write-Log "Ending ConvertTo-DowserExeConfuserEx"
}
