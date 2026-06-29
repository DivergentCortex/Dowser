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

    # eq false not -not, $IsWindows is null on 5.1
    if ($IsWindows -eq $false) {
        Write-Warning "ConvertTo-DowserExe produces Windows PE executables and requires Windows. Not available on this platform."
        return $null
    }

    $scriptContent = Get-Content -Path $ScriptPath -Raw

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
        Add-Type -TypeDefinition $codeTemplate -Language CSharp -OutputAssembly $outputFile -OutputType ConsoleApplication
    }
    else {
        Write-Warning "ConvertTo-DowserExe requires Windows PowerShell 5.1 (Add-Type -OutputType was removed in PowerShell 6+). Run this under powershell.exe."
        return $null
    }
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

    # eq false not -not, $IsWindows is null on 5.1
    if ($IsWindows -eq $false) {
        Write-Warning "ConvertTo-DowserExeConfuserEx produces Windows PE executables and requires Windows. Not available on this platform."
        return $null
    }

    $scriptContent = Get-Content -Path $ScriptPath -Raw

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
        Write-Warning "ConvertTo-DowserExeConfuserEx requires Windows PowerShell 5.1 (Add-Type -OutputType was removed in PowerShell 6+). Run this under powershell.exe."
        return $null
    }
    Add-Type -TypeDefinition $codeTemplate -Language CSharp -OutputAssembly $outputFile -OutputType ConsoleApplication

    $confuserExPath = Join-Path -Path $ConfuserExPath -ChildPath "Confuser.CLI.exe"
    $confuserExConfig = Join-Path -Path $ConfuserExPath -ChildPath "ConfuserEx.crproj"
    & $confuserExPath -n $outputFile -o $outputFile --project $confuserExConfig
}
