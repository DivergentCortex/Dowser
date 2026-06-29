function ConvertTo-DowserExe {
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
    } else {
        Write-Warning "ConvertTo-DowserExe requires Windows PowerShell 5.1 (Add-Type -OutputType was removed in PowerShell 6+). Run this under powershell.exe."
        return $null
    }
}

function ConvertTo-DowserExeConfuserEx {
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
