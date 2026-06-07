function ConvertTo-DowserExe {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath
    )

    # Platform guard: produces Windows PE binaries, requires Windows
    if (-not $IsWindows) {
        Write-Warning "ConvertTo-DowserExe produces Windows PE executables and requires Windows. Not available on this platform."
        return $null
    }

    # Read the content of the PowerShell script
    $scriptContent = Get-Content -Path $ScriptPath -Raw

    # Generate the C# code to wrap the PowerShell script
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

    # Compile the C# code into an executable
    $outputFile = [System.IO.Path]::GetFileNameWithoutExtension($ScriptPath) + ".exe"
    Add-Type -TypeDefinition $codeTemplate -Language CSharp -OutputAssembly $outputFile -OutputType ConsoleApplication
}

function ConvertTo-DowserExeConfuserEx {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,
        [Parameter(Mandatory = $true)]
        [string]$ConfuserExPath
    )

    # Read the content of the PowerShell script
    $scriptContent = Get-Content -Path $ScriptPath -Raw

    # Generate the C# code to wrap the PowerShell script
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

    # Compile the C# code into an executable
    $outputFile = [System.IO.Path]::GetFileNameWithoutExtension($ScriptPath) + ".exe"
    Add-Type -TypeDefinition $codeTemplate -Language CSharp -OutputAssembly $outputFile -OutputType ConsoleApplication

    # Obfuscate the compiled executable using ConfuserEx
    $confuserExPath = Join-Path -Path $ConfuserExPath -ChildPath "Confuser.CLI.exe"
    $confuserExConfig = Join-Path -Path $ConfuserExPath -ChildPath "ConfuserEx.crproj"
    & $confuserExPath -n $outputFile -o $outputFile --project $confuserExConfig
}
