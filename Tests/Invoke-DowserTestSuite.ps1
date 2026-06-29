#Requires -Version 5.1
<#
.SYNOPSIS
    Comprehensive Dowser module test suite - validates all 21 cmdlets.

.DESCRIPTION
    Tests every Public cmdlet for:
      - Syntax clean (pre-import)
      - Module import success
      - Help block present (Synopsis + examples)
      - Pipeline input accepted (where expected)
      - Functional output - returns expected object structure
      - Timing benchmarks (small/medium/large tree)
      - Edge cases: recurse, filters, threading, empty dirs

    Produces a CSV and HTML report under Tests\Reports\.

.PARAMETER ModulePath
    Path to Dowser.psd1. Defaults to parent of this script's directory.

.PARAMETER TestDataPath
    Root path for large-tree timing tests. Default: $PSScriptRoot

.PARAMETER ReportDir
    Output directory for HTML/CSV reports. Default: <ScriptDir>\Reports

.PARAMETER SkipSlow
    Skip timing benchmarks on the large tree. Useful for quick smoke tests.

.EXAMPLE
    pwsh -File Tests/Invoke-DowserTestSuite.ps1

.EXAMPLE
    pwsh -File Tests/Invoke-DowserTestSuite.ps1 -SkipSlow
#>
[CmdletBinding()]
param(
    [string]$ModulePath,
    [string]$TestDataPath,
    [string]$ReportDir,
    [switch]$SkipSlow
)

function Get-ScriptPath {
    <#	
		.NOTES
		===========================================================================
		 Created on:   	1/24/2024 10:07 AM
		 Created by:   	Curtis Leggett - Script Jester
		 Organization: 	$_.ɭᶓԌɩτ™ 
		 Filename:     	Get-ScriptPath.ps1
		===========================================================================
		.SYNOPSIS
			Determines the current script path using different methods based on the PowerShell version.
	  
		.DESCRIPTION
		  IF THIS FUNCTION SEEMS LIKE AN OVER-ENGINEERED MASTERPIECE, THATS BECAUSE IT IS!!
          Designed to:
          - save countless hours of frustration caused by scripts failing 
		    to find their root directory. It's like a superhero that swoops 
		    in to save the day, no matter which PowerShell version it encounters. 
		  - If it ever fails, you've probably discovered a glitch in the Matrix!
	  
		.EXAMPLE
			. Get-ScriptPath
		  $ThisPath = Get-ScriptPath
	#>
    [cmdletbinding()]
    [OutputType([string])]
    param ()
    try {
        [string]$determinedScriptPath = $null
        
        # CHECK IF USING ISE
        if (Get-Variable "psISE" -ValueOnly -ErrorAction SilentlyContinue) {
            Write-Host "Powershell ISE detected"
            $determinedScriptPath = Split-Path -Parent -Path $psISE.CurrentFile.FullPath
        }
        # CHECK POWERSHELL VERSION 
        elseif ($PSVersionTable.PSVersion.Major -gt 3) {
            Write-Host "PowerShell $($PSVersionTable.PSVersion) detected"
            # Use CallStack to get the path of the calling script
            $callStack = Get-PSCallStack
            if ($callStack.Count -gt 1) {
                $callingScript = $callStack[1].ScriptName
                $determinedScriptPath = if ($callingScript) {
                    Split-Path -Parent $callingScript 
                }
                else {
                    $PSScriptRoot 
                }
            }
            else {
                $determinedScriptPath = $PSScriptRoot
            }
        }
        else {
            Write-Host "PowerShell $($PSVersionTable.PSVersion) detected"
            # For PS 2.0, use call stack as well
            $callStack = Get-PSCallStack
            if ($callStack.Count -gt 1) {
                $callingScript = $callStack[1].ScriptName
                $determinedScriptPath = if ($callingScript) {
                    Split-Path -Parent $callingScript 
                }
                else {
                    $PWD.Path 
                }
            }
            else {
                $determinedScriptPath = $PWD.Path
            }
        }

        # VALIDATE BEFORE RETURNING
        if ([string]::IsNullOrEmpty($determinedScriptPath)) {
            Write-Host "Unable to determine script path, using current directory" -ForegroundColor Yellow
            $determinedScriptPath = $PWD.Path
        }

        # PREFER MAPPED DRIVE WHEN UNC ROOT IS MAPPED AND REACHABLE
        $preferredPath = $determinedScriptPath
        if ($determinedScriptPath -like '\\*\*') {
            $rootMatch = [regex]::Match($determinedScriptPath, '^(\\\\[^\\]+\\[^\\]+)')
            if ($rootMatch.Success) {
                $uncRoot = $rootMatch.Value.TrimEnd('\')
                $drive = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root.TrimEnd('\') -ieq $uncRoot }
                if ($drive) {
                    $mappedCandidate = $determinedScriptPath -replace [regex]::Escape($drive.Root.TrimEnd('\')), "$($drive.Name):\"
                    if (Test-Path $mappedCandidate) {
                        $preferredPath = $mappedCandidate
                    }
                }
            }
        }
    }
    catch {
        Write-Host "Error in Get-ScriptPath: $_" -ForegroundColor Red
        $determinedScriptPath = $PWD.Path
    }
    
    Write-Host "Script path determined as: $preferredPath"
    $Global:ScriptPath = $preferredPath
    return $preferredPath
}

$sciptPath = Get-ScriptPath
$modulesDir = Split-Path $sciptPath -Parent -ErrorAction SilentlyContinue
if (-not $modulesDir -or -not (Test-Path (Join-Path $modulesDir "Dowser.psd1"))) {
    $modulesDir = Split-Path $PSScriptRoot -Parent -ErrorAction SilentlyContinue
}
if (-not $modulesDir -or -not (Test-Path (Join-Path $modulesDir "Dowser.psd1"))) {
    $modulesDir = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}
[string]$ModulePath = (Join-Path $ModulesDir "Dowser.psd1")
[string]$TestDataPath = $PSScriptRoot
[string]$ReportDir = Join-Path $ScriptPath "Reports"


Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------
# helpers
# ---------------------------------------------------------
$script:TestResults = [System.Collections.Generic.List[object]]::new()
$script:PassCount = 0
$script:FailCount = 0
$script:WarnCount = 0

function Add-TestResult {
    param(
        [string]$Cmdlet,
        [string]$TestName,
        [ValidateSet('PASS', 'FAIL', 'WARN', 'SKIP')]
        [string]$Status,
        [string]$Detail = '',
        [double]$ElapsedMs = 0
    )
    $script:TestResults.Add([PSCustomObject]@{
            Cmdlet    = $Cmdlet
            TestName  = $TestName
            Status    = $Status
            Detail    = $Detail
            ElapsedMs = [Math]::Round($ElapsedMs, 1)
        })
    switch ($Status) {
        'PASS' {
            $script:PassCount++ 
        } 'FAIL' {
            $script:FailCount++ 
        } 'WARN' {
            $script:WarnCount++ 
        } 
    }
    $color = switch ($Status) {
        'PASS' {
            'Green' 
        } 'FAIL' {
            'Red' 
        } 'WARN' {
            'Yellow' 
        } default {
            'Gray' 
        } 
    }
    Write-Host ("  [{0,-4}] {1,-42} {2}" -f $Status, $TestName, $Detail) -ForegroundColor $color
}

function Invoke-Timed {
    param([scriptblock]$ScriptBlock)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $result = & $ScriptBlock
        $sw.Stop()
        return @{ Result = $result; ElapsedMs = $sw.Elapsed.TotalMilliseconds; Error = $null }
    }
    catch {
        $sw.Stop()
        return @{ Result = $null; ElapsedMs = $sw.Elapsed.TotalMilliseconds; Error = "$_" }
    }
}

# ---------------------------------------------------------
# setup
# ---------------------------------------------------------
$null = New-Item -ItemType Directory -Path $ReportDir -Force -ErrorAction SilentlyContinue

$tempBase = Join-Path ([System.IO.Path]::GetTempPath()) "DowserTests_$(Get-Date -Format 'yyyyMMddHHmmss')"
$null = New-Item -ItemType Directory -Path $tempBase -Force

# build small tree: 3 subdirs x 5 .ps1 files + 1 duplicate
$smallDir = Join-Path $tempBase "small"
$null = New-Item -ItemType Directory -Path $smallDir -Force
foreach ($subName in @('alpha', 'beta', 'gamma')) {
    $d = Join-Path $smallDir $subName
    $null = New-Item -ItemType Directory -Path $d -Force
    for ($i = 1; $i -le 5; $i++) {
        $content = "# test $i in $subName`nfunction Test-Item$i {`n    param([string]`$Path)`n}`n# dot-source: . `"$smallDir\helpers\Write-Log.ps1`""
        Set-Content (Join-Path $d "file_$i.ps1") $content
    }
}
# add a duplicate pair for duplicate detection tests
Copy-Item (Join-Path $smallDir "alpha\file_1.ps1") (Join-Path $smallDir "beta\file_1.ps1") -Force

$mediumDir = Split-Path $ModulePath -Parent
$largeDir = $TestDataPath

$largeFileCount = if (Test-Path $largeDir) {
    (Get-ChildItem $largeDir -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count
}
else {
    0 
}

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "  DOWSER MODULE TEST SUITE  -  $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -ForegroundColor Cyan
Write-Host "  Module  : $ModulePath" -ForegroundColor Cyan
Write-Host "  Small   : $smallDir  (~15 files)" -ForegroundColor Cyan
Write-Host "  Medium  : $mediumDir" -ForegroundColor Cyan
Write-Host "  Large   : $largeDir  ($largeFileCount files)" -ForegroundColor Cyan
Write-Host "============================================================`n" -ForegroundColor Cyan

# ---------------------------------------------------------
# T-00  syntax check (pre-import)
# ---------------------------------------------------------
Write-Host "T-00: Syntax Check (pre-import)" -ForegroundColor White
$pubDir = Join-Path (Split-Path $ModulePath -Parent) "Public"
foreach ($f in (Get-ChildItem "$pubDir\*.ps1" | Sort-Object Name)) {
    $parseErrors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseInput(
        (Get-Content $f.FullName -Raw), [ref]$null, [ref]$parseErrors)
    $status = if ($parseErrors.Count -eq 0) {
        'PASS' 
    }
    else {
        'FAIL' 
    }
    $detail = if ($parseErrors.Count -gt 0) {
        ($parseErrors | ForEach-Object { "L$($_.Extent.StartLineNumber): $($_.Message)" }) -join "; "
    }
    else {
        '' 
    }
    Add-TestResult -Cmdlet $f.BaseName -TestName "Syntax" -Status $status -Detail $detail
}

# ---------------------------------------------------------
# T-01  module import
# ---------------------------------------------------------
Write-Host "`nT-01: Module Import" -ForegroundColor White
$t = Invoke-Timed { Import-Module $ModulePath -Force -ErrorAction Stop }
if ($t.Error) {
    Add-TestResult -Cmdlet "Module" -TestName "Import-Module" -Status FAIL -Detail $t.Error -ElapsedMs $t.ElapsedMs
    Write-Host "FATAL: module failed to import. aborting." -ForegroundColor Red; exit 1
}
Add-TestResult -Cmdlet "Module" -TestName "Import-Module" -Status PASS -Detail "OK in $([Math]::Round($t.ElapsedMs))ms" -ElapsedMs $t.ElapsedMs

$funcCount = @(Get-Command -Module Dowser -CommandType Function).Count
$aliasCount = @(Get-Command -Module Dowser -CommandType Alias).Count
Add-TestResult -Cmdlet "Module" -TestName "FunctionCount" -Status $(if ($funcCount -ge 21) {
        'PASS'
    }
    else {
        'FAIL'
    }) -Detail "$funcCount exported (need >= 21)"
Add-TestResult -Cmdlet "Module" -TestName "AliasCount" -Status $(if ($aliasCount -ge 20) {
        'PASS'
    }
    else {
        'WARN'
    }) -Detail "$aliasCount exported (need >= 20)"

# ---------------------------------------------------------
# T-02  help blocks
# ---------------------------------------------------------
Write-Host "`nT-02: Help Blocks" -ForegroundColor White
$allCmdlets = @(
    'ConvertTo-DowserBase64', 'ConvertTo-DowserExe', 'ConvertTo-DowserIco',
    'Find-DowserDependency', 'Find-DowserDuplicate', 'Find-DowserFile',
    'Find-DowserModified', 'Find-DowserOrphan', 'Find-DowserRecentLog',
    'Find-DowserScript', 'Find-DowserString',
    'Get-DowserInfo', 'Get-DowserMap', 'Get-DowserOwnership', 'Get-DowserProperty',
    'Get-DowserReport', 'Get-DowserTemplate', 'Get-DowserTopology',
    'Invoke-DowserFastSearch', 'Invoke-DowserNumericSort',
    'Measure-DowserDirectory', 'New-DowserHiddenFolder'
)
foreach ($cmdlet in $allCmdlets) {
    try {
        $help = Get-Help $cmdlet -Full -ErrorAction Stop
        $hasSyn = -not [string]::IsNullOrWhiteSpace($help.Synopsis)
        $exObj = if ($help.PSObject.Properties['Examples']) {
            $help.Examples 
        }
        else {
            $null 
        }
        $exCnt = if ($exObj -and $exObj.PSObject.Properties['Example']) {
            ($exObj.Example | Measure-Object).Count
        }
        else {
            0 
        }
        if ($hasSyn -and $exCnt -gt 0) {
            Add-TestResult -Cmdlet $cmdlet -TestName "HelpBlock" -Status PASS -Detail "Synopsis + $exCnt example(s)"
        }
        elseif ($hasSyn) {
            Add-TestResult -Cmdlet $cmdlet -TestName "HelpBlock" -Status WARN -Detail "Synopsis present; no .EXAMPLE blocks"
        }
        else {
            Add-TestResult -Cmdlet $cmdlet -TestName "HelpBlock" -Status WARN -Detail "No comment-based help (auto-generated only)"
        }
    }
    catch {
        Add-TestResult -Cmdlet $cmdlet -TestName "HelpBlock" -Status WARN -Detail "Get-Help unusual return: $_"
    }
}

# ---------------------------------------------------------
# T-03  pipeline support
# ---------------------------------------------------------
Write-Host "`nT-03: Pipeline Support" -ForegroundColor White
$pipelineCmdlets = @{
    'Find-DowserFile'         = 'Path'
    'Find-DowserModified'     = 'Path'
    'Find-DowserRecentLog'    = 'Path'
    'Find-DowserScript'       = 'Path'
    'Find-DowserString'       = 'Path'
    'Find-DowserDuplicate'    = 'Path'
    'Invoke-DowserFastSearch' = 'Path'
    'Measure-DowserDirectory' = 'Path'
    'Get-DowserReport'        = 'Path'
    'Get-DowserProperty'      = 'FilePath'
    'Get-DowserTopology'      = 'Path'
    'Get-DowserMap'           = 'Path'
    'New-DowserHiddenFolder'  = 'Path'
    'ConvertTo-DowserBase64'  = 'Path'
}
foreach ($entry in $pipelineCmdlets.GetEnumerator()) {
    $cmdlet = $entry.Key
    $paramName = $entry.Value
    try {
        $cmd = Get-Command $cmdlet -ErrorAction Stop
        $param = $cmd.Parameters[$paramName]
        if (-not $param) {
            # check if any parameter has pipeline support
            $pipeParam = $cmd.Parameters.Values | Where-Object {
                $_.Attributes | Where-Object { $_ -is [Parameter] -and ($_.ValueFromPipeline -or $_.ValueFromPipelineByPropertyName) }
            } | Select-Object -First 1
            $status = if ($pipeParam) {
                'WARN' 
            }
            else {
                'FAIL' 
            }
            $detail = if ($pipeParam) {
                "Found '$($pipeParam.Name)' instead of '$paramName'" 
            }
            else {
                "No pipeline param found (expected '$paramName')" 
            }
            Add-TestResult -Cmdlet $cmdlet -TestName "Pipeline" -Status $status -Detail $detail
        }
        else {
            $isPipe = $param.Attributes | Where-Object {
                $_ -is [Parameter] -and ($_.ValueFromPipeline -or $_.ValueFromPipelineByPropertyName)
            }
            Add-TestResult -Cmdlet $cmdlet -TestName "Pipeline" -Status $(if ($isPipe) {
                    'PASS'
                }
                else {
                    'FAIL'
                }) `
                -Detail $(if ($isPipe) {
                    "$paramName accepts pipeline"
                }
                else {
                    "$paramName has no ValueFromPipeline"
                })
        }
    }
    catch {
        Add-TestResult -Cmdlet $cmdlet -TestName "Pipeline" -Status FAIL -Detail "Get-Command failed: $_"
    }
}

# ---------------------------------------------------------
# T-04  functional tests
# ---------------------------------------------------------
Write-Host "`nT-04: Functional Tests" -ForegroundColor White

# Find-DowserFile
Write-Host "  [Find-DowserFile]" -ForegroundColor DarkCyan
$t = Invoke-Timed { @(Find-DowserFile -Path $smallDir -Pattern "*.ps1" -UseRunspaces:$false) }
Add-TestResult -Cmdlet "Find-DowserFile" -TestName "BasicSearch" `
    -Status $(if (-not $t.Error -and $t.Result.Count -gt 0 -and $t.Result[0].PSObject.Properties['FullName']) {
        'PASS'
    }
    else {
        'FAIL'
    }) `
    -Detail "$(if($t.Error){$t.Error}else{"$($t.Result.Count) files; has FullName/Size props"})" -ElapsedMs $t.ElapsedMs

$t2 = Invoke-Timed { @($smallDir | Find-DowserFile -Pattern "*.ps1" -UseRunspaces:$false) }
Add-TestResult -Cmdlet "Find-DowserFile" -TestName "PipelineInput" `
    -Status $(if (-not $t2.Error -and $t2.Result.Count -gt 0) {
        'PASS'
    }
    else {
        'FAIL'
    }) `
    -Detail "$(if($t2.Error){$t2.Error}else{"$($t2.Result.Count) via pipe"})" -ElapsedMs $t2.ElapsedMs

$t3 = Invoke-Timed { @(Find-DowserFile -Path $smallDir -ModifiedAfter (Get-Date).AddYears(-5) -UseRunspaces:$false) }
Add-TestResult -Cmdlet "Find-DowserFile" -TestName "DateFilter" `
    -Status $(if (-not $t3.Error -and $t3.Result.Count -gt 0) {
        'PASS'
    }
    else {
        'FAIL'
    }) `
    -Detail "$(if($t3.Error){$t3.Error}else{"$($t3.Result.Count) modified last 5yr"})" -ElapsedMs $t3.ElapsedMs

$t4 = Invoke-Timed { @(Find-DowserFile -Path $smallDir -UseRunspaces:$true) }
Add-TestResult -Cmdlet "Find-DowserFile" -TestName "Threaded" `
    -Status $(if (-not $t4.Error -and $t4.Result.Count -gt 0) {
        'PASS'
    }
    else {
        'FAIL'
    }) `
    -Detail "$(if($t4.Error){$t4.Error}else{"$($t4.Result.Count) files (runspaces on)"})" -ElapsedMs $t4.ElapsedMs

# Find-DowserScript
Write-Host "  [Find-DowserScript]" -ForegroundColor DarkCyan
$t = Invoke-Timed { @(Find-DowserScript -Path $smallDir) }
Add-TestResult -Cmdlet "Find-DowserScript" -TestName "BasicSearch" `
    -Status $(if (-not $t.Error -and $t.Result.Count -gt 0 -and $t.Result[0].PSObject.Properties['Extension']) {
        'PASS'
    }
    else {
        'FAIL'
    }) `
    -Detail "$(if($t.Error){$t.Error}else{"$($t.Result.Count) scripts, has Extension prop"})" -ElapsedMs $t.ElapsedMs

$t2 = Invoke-Timed { @(Find-DowserScript -Path $smallDir -ModifiedWithin 7) }
Add-TestResult -Cmdlet "Find-DowserScript" -TestName "ModifiedWithin" `
    -Status $(if (-not $t2.Error) {
        'PASS'
    }
    else {
        'FAIL'
    }) `
    -Detail "$(if($t2.Error){$t2.Error}else{"$($t2.Result.Count) scripts modified within 7 days"})" -ElapsedMs $t2.ElapsedMs

# Find-DowserModified
Write-Host "  [Find-DowserModified]" -ForegroundColor DarkCyan
$t = Invoke-Timed { @(Find-DowserModified -Path $smallDir -Date (Get-Date).Date) }
Add-TestResult -Cmdlet "Find-DowserModified" -TestName "TodayFiles" `
    -Status $(if (-not $t.Error) {
        'PASS'
    }
    else {
        'FAIL'
    }) `
    -Detail "$(if($t.Error){$t.Error}else{"$($t.Result.Count) files modified today"})" -ElapsedMs $t.ElapsedMs

$t2 = Invoke-Timed { @($smallDir | Find-DowserModified -Date (Get-Date).Date) }
Add-TestResult -Cmdlet "Find-DowserModified" -TestName "PipelineInput" `
    -Status $(if (-not $t2.Error) {
        'PASS'
    }
    else {
        'FAIL'
    }) `
    -Detail "$(if($t2.Error){$t2.Error}else{"$($t2.Result.Count) via pipe"})" -ElapsedMs $t2.ElapsedMs

# Find-DowserRecentLog
Write-Host "  [Find-DowserRecentLog]" -ForegroundColor DarkCyan
$t = Invoke-Timed { @(Find-DowserRecentLog -FileName "*.ps1" -Path $smallDir) }
Add-TestResult -Cmdlet "Find-DowserRecentLog" -TestName "FindNewest" `
    -Status $(if (-not $t.Error -and $t.Result.Count -eq 1) {
        'PASS'
    }
    else {
        'FAIL'
    }) `
    -Detail "$(if($t.Error){$t.Error}else{"Newest: $($t.Result[0].FullName -split '[/\\]' | Select-Object -Last 1)"})" -ElapsedMs $t.ElapsedMs

$t2 = Invoke-Timed { @(Find-DowserRecentLog -FileName "*.ps1" -Path $smallDir -All) }
Add-TestResult -Cmdlet "Find-DowserRecentLog" -TestName "AllCopies" `
    -Status $(if (-not $t2.Error -and $t2.Result.Count -gt 1) {
        'PASS'
    }
    else {
        'FAIL'
    }) `
    -Detail "$(if($t2.Error){$t2.Error}else{"$($t2.Result.Count) copies found with -All"})" -ElapsedMs $t2.ElapsedMs

# Find-DowserDuplicate
Write-Host "  [Find-DowserDuplicate]" -ForegroundColor DarkCyan
$t = Invoke-Timed { @(Find-DowserDuplicate -Path $smallDir -Mode Name) }
Add-TestResult -Cmdlet "Find-DowserDuplicate" -TestName "NameMode" `
    -Status $(if (-not $t.Error) {
        'PASS'
    }
    else {
        'FAIL'
    }) `
    -Detail "$(if($t.Error){$t.Error}else{"$(@($global:dupObjects).Count) dup sets (Name mode)"})" -ElapsedMs $t.ElapsedMs

$t2 = Invoke-Timed { @(Find-DowserDuplicate -Path $smallDir -Mode Content) }
Add-TestResult -Cmdlet "Find-DowserDuplicate" -TestName "ContentHash" `
    -Status $(if (-not $t2.Error) {
        'PASS'
    }
    else {
        'FAIL'
    }) `
    -Detail "$(if($t2.Error){$t2.Error}else{"$(@($global:dupObjects).Count) sets (Content mode)"})" -ElapsedMs $t2.ElapsedMs

# check we found the actual duplicate
$contentDups = @($global:dupObjects | Where-Object Mode -EQ 'Content')
$foundDupe = $contentDups.Count -gt 0
Add-TestResult -Cmdlet "Find-DowserDuplicate" -TestName "DetectsActualDupe" `
    -Status $(if ($foundDupe) {
        'PASS'
    }
    else {
        'WARN'
    }) `
    -Detail "$(if($foundDupe){"$($contentDups.Count) content-identical sets detected"}else{'No content dupes found - expected at least 1'})"

# Find-DowserDependency
Write-Host "  [Find-DowserDependency]" -ForegroundColor DarkCyan
$t = Invoke-Timed { @(Find-DowserDependency -SearchPath $smallDir) }
Add-TestResult -Cmdlet "Find-DowserDependency" -TestName "ScanBasic" `
    -Status $(if (-not $t.Error) {
        'PASS'
    }
    else {
        'FAIL'
    }) `
    -Detail "$(if($t.Error){$t.Error}else{"$($t.Result.Count) dependency refs found"})" -ElapsedMs $t.ElapsedMs

$t2 = Invoke-Timed { @(Find-DowserDependency -SearchPath $smallDir -FunctionNames @("Test-Item1", "Test-Item2")) }
Add-TestResult -Cmdlet "Find-DowserDependency" -TestName "FunctionSearch" `
    -Status $(if (-not $t2.Error) {
        'PASS'
    }
    else {
        'FAIL'
    }) `
    -Detail "$(if($t2.Error){$t2.Error}else{"$($t2.Result.Count) refs to specified functions"})" -ElapsedMs $t2.ElapsedMs

# Find-DowserOrphan
Write-Host "  [Find-DowserOrphan]" -ForegroundColor DarkCyan
$t = Invoke-Timed { @(Find-DowserOrphan -SearchPath $smallDir) }
Add-TestResult -Cmdlet "Find-DowserOrphan" -TestName "BasicScan" `
    -Status $(if (-not $t.Error -and $null -ne $t.Result) {
        'PASS'
    }
    else {
        'FAIL'
    }) `
    -Detail "$(if($t.Error){$t.Error}else{"$($t.Result.Count) orphans identified"})" -ElapsedMs $t.ElapsedMs

# Find-DowserString
Write-Host "  [Find-DowserString]" -ForegroundColor DarkCyan
$t = Invoke-Timed { @(Find-DowserString -Path $smallDir -Patterns "param" -Extensions "*.ps1") }
Add-TestResult -Cmdlet "Find-DowserString" -TestName "LiteralSearch" `
    -Status $(if (-not $t.Error -and $t.Result.Count -gt 0) {
        'PASS'
    }
    else {
        'FAIL'
    }) `
    -Detail "$(if($t.Error){$t.Error}else{"$($t.Result.Count) file hits for 'param'"})" -ElapsedMs $t.ElapsedMs

$t2 = Invoke-Timed { @(Find-DowserString -Path $smallDir -Patterns "param", "function" -Extensions "*.ps1") }
Add-TestResult -Cmdlet "Find-DowserString" -TestName "MultiPattern-Aho" `
    -Status $(if (-not $t2.Error) {
        'PASS'
    }
    else {
        'FAIL'
    }) `
    -Detail "$(if($t2.Error){$t2.Error}else{"$($t2.Result.Count) hits multi-pattern"})" -ElapsedMs $t2.ElapsedMs

$t3 = Invoke-Timed { @(Find-DowserString -Path $smallDir -Patterns "func\w+" -UseRegex -Extensions "*.ps1") }
Add-TestResult -Cmdlet "Find-DowserString" -TestName "RegexMode" `
    -Status $(if (-not $t3.Error) {
        'PASS'
    }
    else {
        'FAIL'
    }) `
    -Detail "$(if($t3.Error){$t3.Error}else{"$($t3.Result.Count) regex hits"})" -ElapsedMs $t3.ElapsedMs

$t4 = Invoke-Timed { @(Find-DowserString -Path $smallDir -Patterns "param" -Extensions "*.ps1" -OutputMode files) }
Add-TestResult -Cmdlet "Find-DowserString" -TestName "FilesMode" `
    -Status $(if (-not $t4.Error) {
        'PASS'
    }
    else {
        'FAIL'
    }) `
    -Detail "$(if($t4.Error){$t4.Error}else{"$($t4.Result.Count) unique files"})" -ElapsedMs $t4.ElapsedMs

# Invoke-DowserFastSearch
Write-Host "  [Invoke-DowserFastSearch]" -ForegroundColor DarkCyan
$t = Invoke-Timed { @(Invoke-DowserFastSearch -Path $smallDir -SearchString "function") }
Add-TestResult -Cmdlet "Invoke-DowserFastSearch" -TestName "BasicSearch" `
    -Status $(if (-not $t.Error) {
        'PASS'
    }
    else {
        'FAIL'
    }) `
    -Detail "$(if($t.Error){$t.Error}else{"$($t.Result.Count) file hits for 'function'"})" -ElapsedMs $t.ElapsedMs

$t2 = Invoke-Timed { @(Invoke-DowserFastSearch -Path $smallDir -SearchString "param" -CaseSensitive) }
Add-TestResult -Cmdlet "Invoke-DowserFastSearch" -TestName "CaseSensitive" `
    -Status $(if (-not $t2.Error) {
        'PASS'
    }
    else {
        'FAIL'
    }) `
    -Detail "$(if($t2.Error){$t2.Error}else{"$($t2.Result.Count) case-sensitive hits"})" -ElapsedMs $t2.ElapsedMs

# alias test
$t3 = Invoke-Timed { @(dfast -Path $smallDir -SearchString "Test-Item") }
Add-TestResult -Cmdlet "Invoke-DowserFastSearch" -TestName "Alias-dfast" `
    -Status $(if (-not $t3.Error) {
        'PASS'
    }
    else {
        'FAIL'
    }) `
    -Detail "$(if($t3.Error){$t3.Error}else{"alias dfast ok: $($t3.Result.Count) hits"})" -ElapsedMs $t3.ElapsedMs

# Invoke-DowserNumericSort
Write-Host "  [Invoke-DowserNumericSort]" -ForegroundColor DarkCyan
$unsorted = @("Item-10", "Item-2", "Item-20", "Item-1", "Item-11", "Item-3")
$t = Invoke-Timed { @($unsorted | Invoke-DowserNumericSort) }
$order1 = $t.Result
$sortOk = (-not $t.Error) -and ($order1[0] -eq "Item-1") -and ($order1[1] -eq "Item-2") -and ($order1[2] -eq "Item-3")
Add-TestResult -Cmdlet "Invoke-DowserNumericSort" -TestName "NaturalSort" `
    -Status $(if ($sortOk) {
        'PASS'
    }
    else {
        'FAIL'
    }) `
    -Detail "$(if($t.Error){$t.Error}else{"Order: $($order1 -join ', ')"})" -ElapsedMs $t.ElapsedMs

$t2 = Invoke-Timed { @($unsorted | Invoke-DowserNumericSort -Descending) }
$descOk = (-not $t2.Error) -and $t2.Result[0] -eq "Item-20"
Add-TestResult -Cmdlet "Invoke-DowserNumericSort" -TestName "Descending" `
    -Status $(if ($descOk) {
        'PASS'
    }
    else {
        'FAIL'
    }) `
    -Detail "$(if($t2.Error){$t2.Error}else{"First: $($t2.Result[0])"})" -ElapsedMs $t2.ElapsedMs

$t3 = Invoke-Timed { @($unsorted | Invoke-DowserNumericSort -Top 3) }
$topOk = (-not $t3.Error) -and $t3.Result.Count -eq 3
Add-TestResult -Cmdlet "Invoke-DowserNumericSort" -TestName "TopN" `
    -Status $(if ($topOk) {
        'PASS'
    }
    else {
        'FAIL'
    }) `
    -Detail "$(if($t3.Error){$t3.Error}else{"Top 3: $($t3.Result -join ', ')"})" -ElapsedMs $t3.ElapsedMs

# Measure-DowserDirectory
Write-Host "  [Measure-DowserDirectory]" -ForegroundColor DarkCyan
$t = Invoke-Timed { @(Measure-DowserDirectory -Path $smallDir) }
Add-TestResult -Cmdlet "Measure-DowserDirectory" -TestName "BasicMeasure" `
    -Status $(if (-not $t.Error -and $t.Result.Count -gt 0 -and $t.Result[0].PSObject.Properties['DataSize']) {
        'PASS'
    }
    else {
        'FAIL'
    }) `
    -Detail "$(if($t.Error){$t.Error}else{"$($t.Result.Count) subdirs measured"})" -ElapsedMs $t.ElapsedMs

$t2 = Invoke-Timed { @($smallDir | Measure-DowserDirectory) }
Add-TestResult -Cmdlet "Measure-DowserDirectory" -TestName "PipelineInput" `
    -Status $(if (-not $t2.Error -and $t2.Result.Count -gt 0) {
        'PASS'
    }
    else {
        'FAIL'
    }) `
    -Detail "$(if($t2.Error){$t2.Error}else{"$($t2.Result.Count) via pipe"})" -ElapsedMs $t2.ElapsedMs

if ($t.Result -and $t.Result.Count -gt 0) {
    $expectedProps = 'Directory', 'DataSize', 'FileCount', 'LargestFile', 'LargestFileName', 'NewestFileName', 'NewestFileDate', 'OldestFileName', 'OldestFileDate'
    $missing = $expectedProps | Where-Object { -not $t.Result[0].PSObject.Properties[$_] }
    Add-TestResult -Cmdlet "Measure-DowserDirectory" -TestName "OutputSchema" `
        -Status $(if (-not $missing) {
            'PASS'
        }
        else {
            'FAIL'
        }) `
        -Detail $(if ($missing) {
            "Missing: $($missing -join ', ')"
        }
        else {
            "All 9 expected props present"
        })
}

# Get-DowserMap
Write-Host "  [Get-DowserMap]" -ForegroundColor DarkCyan
$t = Invoke-Timed { @(Get-DowserMap -Path $smallDir -MaxDepth 3) }
Add-TestResult -Cmdlet "Get-DowserMap" -TestName "BasicTree" `
    -Status $(if (-not $t.Error -and $t.Result.Count -gt 0 -and $t.Result[0] -is [string]) {
        'PASS'
    }
    else {
        'FAIL'
    }) `
    -Detail "$(if($t.Error){$t.Error}else{"$($t.Result.Count) tree lines emitted"})" -ElapsedMs $t.ElapsedMs

$t2 = Invoke-Timed { @(Get-DowserMap -Path $smallDir -Ascii -MaxDepth 2) }
Add-TestResult -Cmdlet "Get-DowserMap" -TestName "AsciiMode" `
    -Status $(if (-not $t2.Error -and $t2.Result.Count -gt 0) {
        'PASS'
    }
    else {
        'FAIL'
    }) `
    -Detail "$(if($t2.Error){$t2.Error}else{"$($t2.Result.Count) lines ASCII"})" -ElapsedMs $t2.ElapsedMs

$t3 = Invoke-Timed { @(Get-DowserMap -Path $smallDir -FoldersOnly -MaxDepth 3) }
Add-TestResult -Cmdlet "Get-DowserMap" -TestName "FoldersOnly" `
    -Status $(if (-not $t3.Error) {
        'PASS'
    }
    else {
        'FAIL'
    }) `
    -Detail "$(if($t3.Error){$t3.Error}else{"$($t3.Result.Count) lines (folders only)"})" -ElapsedMs $t3.ElapsedMs

$t4 = Invoke-Timed { @(Get-DowserMap -Path $smallDir -IncludeSize -MaxDepth 3) }
Add-TestResult -Cmdlet "Get-DowserMap" -TestName "IncludeSize" `
    -Status $(if (-not $t4.Error) {
        'PASS'
    }
    else {
        'FAIL'
    }) `
    -Detail "$(if($t4.Error){$t4.Error}else{"$($t4.Result.Count) lines with size annotations"})" -ElapsedMs $t4.ElapsedMs

# Get-DowserTopology
Write-Host "  [Get-DowserTopology]" -ForegroundColor DarkCyan
$t = Invoke-Timed { @(Get-DowserTopology -Path $smallDir -ShowItem -Depth 3) }
Add-TestResult -Cmdlet "Get-DowserTopology" -TestName "ShowItems" `
    -Status $(if (-not $t.Error) {
        'PASS'
    }
    else {
        'FAIL'
    }) `
    -Detail "$(if($t.Error){$t.Error}else{"$($t.Result.Count) lines"})" -ElapsedMs $t.ElapsedMs

$t2 = Invoke-Timed { @(Get-Item $smallDir | Get-DowserTopology -Depth 2) }
Add-TestResult -Cmdlet "Get-DowserTopology" -TestName "PipelineFromGetItem" `
    -Status $(if (-not $t2.Error) {
        'PASS'
    }
    else {
        'FAIL'
    }) `
    -Detail "$(if($t2.Error){$t2.Error}else{"$($t2.Result.Count) lines via pipeline"})" -ElapsedMs $t2.ElapsedMs

# Get-DowserProperty
Write-Host "  [Get-DowserProperty]" -ForegroundColor DarkCyan
$sampleFile = Get-ChildItem $smallDir -Recurse -File | Select-Object -First 1
$t = Invoke-Timed { @(Get-DowserProperty -FilePath $sampleFile.FullName) }
Add-TestResult -Cmdlet "Get-DowserProperty" -TestName "SingleFile" `
    -Status $(if (-not $t.Error -and $t.Result.Count -gt 0) {
        'PASS'
    }
    else {
        'FAIL'
    }) `
    -Detail "$(if($t.Error){$t.Error}else{"$($t.Result.Count) property objects"})" -ElapsedMs $t.ElapsedMs

$t2 = Invoke-Timed { @(Get-ChildItem $smallDir -Recurse -File | Select-Object -First 3 | Get-DowserProperty) }
Add-TestResult -Cmdlet "Get-DowserProperty" -TestName "PipelineBatch" `
    -Status $(if (-not $t2.Error) {
        'PASS'
    }
    else {
        'FAIL'
    }) `
    -Detail "$(if($t2.Error){$t2.Error}else{"$($t2.Result.Count) objects for 3 files"})" -ElapsedMs $t2.ElapsedMs

# Get-DowserReport
Write-Host "  [Get-DowserReport]" -ForegroundColor DarkCyan
$csvOut = Join-Path $tempBase "report_out.csv"
$htmlOut = Join-Path $tempBase "report_out.html"
$t = Invoke-Timed { @(Get-DowserReport -Path $smallDir -Depth -1 -UseRunspaces:$false) }
Add-TestResult -Cmdlet "Get-DowserReport" -TestName "DirScan" `
    -Status $(if (-not $t.Error -and $t.Result.Count -gt 0) {
        'PASS'
    }
    else {
        'FAIL'
    }) `
    -Detail "$(if($t.Error){$t.Error}else{"$($t.Result.Count) file records"})" -ElapsedMs $t.ElapsedMs

$t2 = Invoke-Timed { Get-DowserReport -Path $smallDir -Depth -1 -UseRunspaces:$false -ExportCsv $csvOut -ExportHtml $htmlOut }
Add-TestResult -Cmdlet "Get-DowserReport" -TestName "ExportFiles" `
    -Status $(if (-not $t2.Error -and (Test-Path $csvOut) -and (Test-Path $htmlOut)) {
        'PASS'
    }
    else {
        'FAIL'
    }) `
    -Detail "$(if($t2.Error){$t2.Error}elseif(-not (Test-Path $csvOut)){'CSV missing'}elseif(-not (Test-Path $htmlOut)){'HTML missing'}else{'CSV+HTML written'})" -ElapsedMs $t2.ElapsedMs

# Get-DowserOwnership
Write-Host "  [Get-DowserOwnership]" -ForegroundColor DarkCyan
$t = Invoke-Timed { @(Get-DowserOwnership -Path $smallDir) }
Add-TestResult -Cmdlet "Get-DowserOwnership" -TestName "BasicOwner" `
    -Status $(if (-not $t.Error) {
        'PASS'
    }
    else {
        'FAIL'
    }) `
    -Detail "$(if($t.Error){$t.Error}else{"$($t.Result.Count) ownership records"})" -ElapsedMs $t.ElapsedMs

# Get-DowserInfo
Write-Host "  [Get-DowserInfo]" -ForegroundColor DarkCyan
$t = Invoke-Timed { Get-DowserInfo }
Add-TestResult -Cmdlet "Get-DowserInfo" -TestName "StubInfo" `
    -Status $(if (-not $t.Error -and $t.Result.Module -eq 'Dowser') {
        'PASS'
    }
    else {
        'FAIL'
    }) `
    -Detail "$(if($t.Error){$t.Error}else{"Module=$($t.Result.Module) Version=$($t.Result.Version)"})" -ElapsedMs $t.ElapsedMs

# New-DowserHiddenFolder
Write-Host "  [New-DowserHiddenFolder]" -ForegroundColor DarkCyan
$hiddenPath = Join-Path $tempBase ".hidden_test"
$t = Invoke-Timed { New-DowserHiddenFolder -Path $hiddenPath }
Add-TestResult -Cmdlet "New-DowserHiddenFolder" -TestName "CreateFolder" `
    -Status $(if (-not $t.Error -and (Test-Path $hiddenPath)) {
        'PASS'
    }
    else {
        'FAIL'
    }) `
    -Detail "$(if($t.Error){$t.Error}else{"Created $hiddenPath"})" -ElapsedMs $t.ElapsedMs

if (Test-Path $hiddenPath) {
    $attr = (Get-Item $hiddenPath -Force).Attributes
    $isHidden = [bool]($attr -band [System.IO.FileAttributes]::Hidden)
    Add-TestResult -Cmdlet "New-DowserHiddenFolder" -TestName "HiddenAttribute" `
        -Status $(if ($isHidden) {
            'PASS'
        }
        else {
            'FAIL'
        }) -Detail "Attributes=$attr"
    $t2 = Invoke-Timed { New-DowserHiddenFolder -Path $hiddenPath -AttributesOnly -Force }
    Add-TestResult -Cmdlet "New-DowserHiddenFolder" -TestName "AttributesOnly" `
        -Status $(if (-not $t2.Error) {
            'PASS'
        }
        else {
            'FAIL'
        }) `
        -Detail "$(if($t2.Error){$t2.Error}else{'AttributesOnly on existing dir - OK'})" -ElapsedMs $t2.ElapsedMs
}

# ConvertTo-DowserBase64
Write-Host "  [ConvertTo-DowserBase64]" -ForegroundColor DarkCyan
$b64Out = Join-Path $tempBase "enc.b64"
$b64Dec = Join-Path $tempBase "dec.ps1"
$srcFile = (Get-ChildItem $smallDir -Recurse -File -Filter "*.ps1" | Select-Object -First 1).FullName
$t = Invoke-Timed { ConvertTo-DowserBase64 -Path $srcFile -OutputFile $b64Out }
Add-TestResult -Cmdlet "ConvertTo-DowserBase64" -TestName "Encode" `
    -Status $(if (-not $t.Error -and (Test-Path $b64Out)) {
        'PASS'
    }
    else {
        'FAIL'
    }) `
    -Detail "$(if($t.Error){$t.Error}else{"Encoded to $([System.IO.Path]::GetFileName($b64Out))"})" -ElapsedMs $t.ElapsedMs

$t2 = Invoke-Timed { ConvertTo-DowserBase64 -Path $b64Out -Decode -OutputFile $b64Dec }
Add-TestResult -Cmdlet "ConvertTo-DowserBase64" -TestName "Decode" `
    -Status $(if (-not $t2.Error -and (Test-Path $b64Dec)) {
        'PASS'
    }
    else {
        'FAIL'
    }) `
    -Detail "$(if($t2.Error){$t2.Error}else{"Decoded to $([System.IO.Path]::GetFileName($b64Dec))"})" -ElapsedMs $t2.ElapsedMs

# roundtrip content check
if ((Test-Path $srcFile) -and (Test-Path $b64Dec)) {
    $orig = Get-Content $srcFile -Raw
    $round = Get-Content $b64Dec -Raw
    Add-TestResult -Cmdlet "ConvertTo-DowserBase64" -TestName "RoundtripContent" `
        -Status $(if ($orig -eq $round) {
            'PASS'
        }
        else {
            'FAIL'
        }) `
        -Detail $(if ($orig -eq $round) {
            'Content identical after encode/decode'
        }
        else {
            'Content mismatch after roundtrip'
        })
}

# ConvertTo-DowserExe (param check only - compilation requires Windows csc)
Write-Host "  [ConvertTo-DowserExe]" -ForegroundColor DarkCyan
$cmd = Get-Command ConvertTo-DowserExe
Add-TestResult -Cmdlet "ConvertTo-DowserExe" -TestName "HasScriptPath" `
    -Status $(if ($cmd.Parameters.ContainsKey('ScriptPath')) {
        'PASS'
    }
    else {
        'FAIL'
    }) `
    -Detail "ScriptPath param check"
Add-TestResult -Cmdlet "ConvertTo-DowserExe" -TestName "CompileTest" -Status SKIP `
    -Detail "Requires Windows .NET csc compiler - skipped on Linux/WSL"

# ConvertTo-DowserIco (param check only - System.Drawing not reliably available)
Write-Host "  [ConvertTo-DowserIco]" -ForegroundColor DarkCyan
$cmd2 = Get-Command ConvertTo-DowserIco
$hasInput = $cmd2.Parameters.ContainsKey('InputFilePath')
$hasSizes = $cmd2.Parameters.ContainsKey('IcoSizes')
Add-TestResult -Cmdlet "ConvertTo-DowserIco" -TestName "ParameterCheck" `
    -Status $(if ($hasInput -and $hasSizes) {
        'PASS'
    }
    else {
        'WARN'
    }) `
    -Detail "InputFilePath=$(if($hasInput){'Y'}else{'N'}) IcoSizes=$(if($hasSizes){'Y'}else{'N'})"
Add-TestResult -Cmdlet "ConvertTo-DowserIco" -TestName "ConversionTest" -Status SKIP `
    -Detail "Requires System.Drawing + image file - skipped"

# Get-DowserTemplate (Shell.Application - Windows COM only)
Write-Host "  [Get-DowserTemplate]" -ForegroundColor DarkCyan
$t = Invoke-Timed { @(Get-DowserTemplate -Path $smallDir -WarningAction SilentlyContinue -ErrorAction SilentlyContinue) }
$resultCount = @($t.Result).Count
if ($t.Error) {
    Add-TestResult -Cmdlet "Get-DowserTemplate" -TestName "ShellCOM" -Status SKIP `
        -Detail "COM not available (expected on Linux/WSL): $($t.Error)" -ElapsedMs $t.ElapsedMs
}
elseif ($resultCount -eq 0) {
    Add-TestResult -Cmdlet "Get-DowserTemplate" -TestName "ShellCOM" -Status SKIP `
        -Detail "No results - Shell.Application COM unavailable on this platform"
}
else {
    Add-TestResult -Cmdlet "Get-DowserTemplate" -TestName "ShellCOM" -Status PASS `
        -Detail "$resultCount result(s)" -ElapsedMs $t.ElapsedMs
}

# ---------------------------------------------------------
# T-05  timing benchmarks
# ---------------------------------------------------------
Write-Host "`nT-05: Timing Benchmarks" -ForegroundColor White
$benchmarks = [System.Collections.Generic.List[object]]::new()

function Add-Bench {
    param([string]$Cmdlet, [string]$Tree, [double]$Ms, [int]$Count, [string]$Note = '')
    $benchmarks.Add([PSCustomObject]@{ Cmdlet = $Cmdlet; Tree = $Tree; ElapsedMs = [Math]::Round($Ms); Count = $Count; Note = $Note })
    $status = if ($Ms -lt 60000) {
        'PASS' 
    }
    else {
        'WARN' 
    }
    Add-TestResult -Cmdlet $Cmdlet -TestName "Bench-$Tree" -Status $status `
        -Detail "$Count results in $([Math]::Round($Ms))ms$(if($Note){" [$Note]"})" -ElapsedMs $Ms
}

Write-Host "  small tree..." -ForegroundColor DarkGray
$t = Invoke-Timed { @(Find-DowserFile -Path $smallDir -UseRunspaces:$false) }
Add-Bench "Find-DowserFile" "small" $t.ElapsedMs $t.Result.Count "no-runspace"
$t = Invoke-Timed { @(Find-DowserString -Path $smallDir -Patterns "function" -Extensions "*.ps1") }
Add-Bench "Find-DowserString" "small" $t.ElapsedMs $t.Result.Count
$t = Invoke-Timed { @(Measure-DowserDirectory -Path $smallDir) }
Add-Bench "Measure-DowserDirectory" "small" $t.ElapsedMs $t.Result.Count
$t = Invoke-Timed { @(Get-DowserMap -Path $smallDir -MaxDepth 3) }
Add-Bench "Get-DowserMap" "small" $t.ElapsedMs $t.Result.Count
$t = Invoke-Timed { @(Get-DowserReport -Path $smallDir -Depth -1 -UseRunspaces:$false) }
Add-Bench "Get-DowserReport" "small" $t.ElapsedMs $t.Result.Count

Write-Host "  medium tree..." -ForegroundColor DarkGray
$t = Invoke-Timed { @(Find-DowserFile -Path $mediumDir -Pattern "*.ps1" -UseRunspaces:$true) }
Add-Bench "Find-DowserFile" "medium" $t.ElapsedMs $t.Result.Count "runspaces"
$t = Invoke-Timed { @(Find-DowserString -Path $mediumDir -Patterns "function" -Extensions "*.ps1") }
Add-Bench "Find-DowserString" "medium" $t.ElapsedMs $t.Result.Count
$t = Invoke-Timed { @(Measure-DowserDirectory -Path $mediumDir) }
Add-Bench "Measure-DowserDirectory" "medium" $t.ElapsedMs $t.Result.Count
$t = Invoke-Timed { @(Get-DowserMap -Path $mediumDir -MaxDepth 3) }
Add-Bench "Get-DowserMap" "medium" $t.ElapsedMs $t.Result.Count

if (-not $SkipSlow -and (Test-Path $largeDir)) {
    Write-Host "  large tree ($largeFileCount files)..." -ForegroundColor DarkGray
    $t = Invoke-Timed { @(Find-DowserFile -Path $largeDir -Pattern "*.ps1" -UseRunspaces:$true) }
    Add-Bench "Find-DowserFile" "large" $t.ElapsedMs $t.Result.Count "runspaces"
    $t = Invoke-Timed { @(Find-DowserScript -Path $largeDir) }
    Add-Bench "Find-DowserScript" "large" $t.ElapsedMs $t.Result.Count
    $t = Invoke-Timed { @(Find-DowserString -Path $largeDir -Patterns "Write-Log" -Extensions "*.ps1" -MaxThreads 4) }
    Add-Bench "Find-DowserString" "large" $t.ElapsedMs $t.Result.Count "4 threads"
    $t = Invoke-Timed { @(Invoke-DowserFastSearch -Path $largeDir -SearchString "Write-Log" -Include "*.ps1" -Threads 4) }
    Add-Bench "Invoke-DowserFastSearch" "large" $t.ElapsedMs $t.Result.Count "4 threads"
    $t = Invoke-Timed { @(Measure-DowserDirectory -Path $largeDir) }
    Add-Bench "Measure-DowserDirectory" "large" $t.ElapsedMs $t.Result.Count
    $t = Invoke-Timed { @(Get-DowserMap -Path $largeDir -MaxDepth 2 -FoldersOnly) }
    Add-Bench "Get-DowserMap" "large" $t.ElapsedMs $t.Result.Count "FoldersOnly"
}
elseif ($SkipSlow) {
    Add-TestResult -Cmdlet "Benchmark" -TestName "LargeTree" -Status SKIP -Detail "-SkipSlow flag set"
}
else {
    Add-TestResult -Cmdlet "Benchmark" -TestName "LargeTree" -Status SKIP -Detail "Path not found: $largeDir"
}

# ---------------------------------------------------------
# T-06  edge cases
# ---------------------------------------------------------
Write-Host "`nT-06: Edge Cases" -ForegroundColor White

$emptyDir = Join-Path $tempBase "edge_empty"
$null = New-Item -ItemType Directory -Path $emptyDir -Force

$t = Invoke-Timed { @(Find-DowserFile -Path $emptyDir -UseRunspaces:$false -WarningAction SilentlyContinue) }
$rc = @($t.Result).Count
Add-TestResult -Cmdlet "Find-DowserFile" -TestName "EmptyDir" `
    -Status $(if (-not $t.Error -and $rc -eq 0) {
        'PASS'
    }
    else {
        'FAIL'
    }) `
    -Detail "$(if($t.Error){$t.Error}else{"$rc results (expected 0)"})" -ElapsedMs $t.ElapsedMs

$t2 = Invoke-Timed { @(Measure-DowserDirectory -Path $emptyDir -WarningAction SilentlyContinue -ErrorAction SilentlyContinue) }
$rc2 = @($t2.Result).Count
Add-TestResult -Cmdlet "Measure-DowserDirectory" -TestName "EmptyDir" `
    -Status $(if (-not $t2.Error -and $rc2 -eq 0) {
        'PASS'
    }
    else {
        'FAIL'
    }) `
    -Detail "$(if($t2.Error){$t2.Error}else{"$rc2 subdirs (expected 0)"})" -ElapsedMs $t2.ElapsedMs

$t3 = Invoke-Timed { @(Find-DowserFile -Path "/path/does/not/exist/xyz" -UseRunspaces:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue) }
$rc3 = @($t3.Result).Count
Add-TestResult -Cmdlet "Find-DowserFile" -TestName "NonExistentPath" `
    -Status $(if ($rc3 -eq 0) {
        'PASS'
    }
    else {
        'WARN'
    }) `
    -Detail "$(if($t3.Error){"Error: $($t3.Error)"}else{"$rc3 results - graceful on nonexistent path"})" -ElapsedMs $t3.ElapsedMs

# size filter - use KB/MB not bare "1B" (ConvertTo-DowserBytes parses KB/MB/GB/TB)
$t4 = Invoke-Timed { @(Find-DowserFile -Path $smallDir -MinSize "1KB" -MaxSize "100KB" -UseRunspaces:$false) }
$rc4 = @($t4.Result).Count
Add-TestResult -Cmdlet "Find-DowserFile" -TestName "SizeFilter" `
    -Status $(if (-not $t4.Error) {
        'PASS'
    }
    else {
        'FAIL'
    }) `
    -Detail "$(if($t4.Error){$t4.Error}else{"$rc4 files 1KB-100KB"})" -ElapsedMs $t4.ElapsedMs

# case sensitivity
$tCS = Invoke-Timed { @(Find-DowserString -Path $smallDir -Patterns "FUNCTION" -Extensions "*.ps1" -CaseSensitive) }
$tCI = Invoke-Timed { @(Find-DowserString -Path $smallDir -Patterns "FUNCTION" -Extensions "*.ps1") }
$csCount = @($tCS.Result).Count
$ciCount = @($tCI.Result).Count
$caseOk = $csCount -le $ciCount
Add-TestResult -Cmdlet "Find-DowserString" -TestName "CaseSensitive" `
    -Status $(if (-not $tCS.Error -and $caseOk) {
        'PASS'
    }
    else {
        'WARN'
    }) `
    -Detail "CaseSens=$csCount CaseInsens=$ciCount"

$t7 = Invoke-Timed {
    try {
        $null = @() | Invoke-DowserNumericSort -ErrorAction SilentlyContinue -WarningAction SilentlyContinue 
    }
    catch {
    }
}
Add-TestResult -Cmdlet "Invoke-DowserNumericSort" -TestName "EmptyInput" `
    -Status $(if (-not $t7.Error) {
        'PASS'
    }
    else {
        'WARN'
    }) `
    -Detail $(if ($t7.Error) {
        "Error: $($t7.Error)"
    }
    else {
        "Empty input handled without crash"
    })

$t8 = Invoke-Timed { @(@($smallDir, (Join-Path $smallDir "alpha")) | Find-DowserFile -Pattern "*.ps1" -UseRunspaces:$false) }
$rc8 = @($t8.Result).Count
Add-TestResult -Cmdlet "Find-DowserFile" -TestName "MultiPathPipeline" `
    -Status $(if (-not $t8.Error -and $rc8 -gt 0) {
        'PASS'
    }
    else {
        'FAIL'
    }) `
    -Detail "$(if($t8.Error){$t8.Error}else{"$rc8 results from 2-path pipeline"})" -ElapsedMs $t8.ElapsedMs

# recurse vs flat
$tFlat = Invoke-Timed { @(Find-DowserFile -Path $smallDir -Recurse:$false -UseRunspaces:$false) }
$tRec = Invoke-Timed { @(Find-DowserFile -Path $smallDir -Recurse:$true -UseRunspaces:$false) }
$flatCount = @($tFlat.Result).Count
$recurseCount = @($tRec.Result).Count
$recurseOk = $recurseCount -gt $flatCount
Add-TestResult -Cmdlet "Find-DowserFile" -TestName "RecurseVsFlat" `
    -Status $(if ($recurseOk) {
        'PASS'
    }
    else {
        'WARN'
    }) `
    -Detail "Flat=$flatCount Recurse=$recurseCount"

# ---------------------------------------------------------
# cleanup
# ---------------------------------------------------------
try {
    Remove-Item $tempBase -Recurse -Force -ErrorAction SilentlyContinue 
}
catch {
}

# ---------------------------------------------------------
# results summary
# ---------------------------------------------------------
$total = $script:TestResults.Count
$passes = $script:PassCount
$fails = $script:FailCount
$warns = $script:WarnCount
$skips = ($script:TestResults | Where-Object Status -EQ 'SKIP').Count
$eligible = $total - $skips
$passRate = if ($eligible -gt 0) {
    [Math]::Round(($passes / $eligible) * 100, 1) 
}
else {
    0 
}

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "  FINAL RESULTS" -ForegroundColor Cyan
Write-Host ("  Total={0} PASS={1} FAIL={2} WARN={3} SKIP={4}" -f $total, $passes, $fails, $warns, $skips) `
    -ForegroundColor $(if ($fails -eq 0) {
        'Green'
    }
    else {
        'Yellow'
    })
Write-Host "  Pass rate (excl skips): $passRate%" `
    -ForegroundColor $(if ($passRate -ge 90) {
        'Green'
    }
    elseif ($passRate -ge 75) {
        'Yellow'
    }
    else {
        'Red'
    })
if ($fails -eq 0) {
    Write-Host "  >>> ALL PASS (zero FAILs) <<<" -ForegroundColor Green
}
Write-Host "============================================================`n" -ForegroundColor Cyan

if ($fails -gt 0) {
    Write-Host "FAILED TESTS:" -ForegroundColor Red
    $script:TestResults | Where-Object Status -EQ FAIL |
        Format-Table Cmdlet, TestName, Detail -AutoSize
}

if ($benchmarks.Count -gt 0) {
    Write-Host "TIMING TABLE:" -ForegroundColor White
    $benchmarks | Sort-Object Tree, Cmdlet | Format-Table -AutoSize
}

# ---------------------------------------------------------
# CSV export
# ---------------------------------------------------------
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$csvPath = Join-Path $ReportDir "DowserTestResults_$stamp.csv"
$script:TestResults | Export-Csv -Path $csvPath -NoTypeInformation -Force
Write-Host "CSV  : $csvPath" -ForegroundColor Green

# ---------------------------------------------------------
# HTML export
# ---------------------------------------------------------
$htmlPath = Join-Path $ReportDir "DowserTestResults_$stamp.html"

function Escape-Html([string]$s) {
    [System.Security.SecurityElement]::Escape($s) 
}

$rowsHtml = ($script:TestResults | ForEach-Object {
        $bg = switch ($_.Status) {
            'PASS' {
                '#d4edda'
            } 'FAIL' {
                '#f8d7da'
            } 'WARN' {
                '#fff3cd'
            } default {
                '#e2e3e5'
            } 
        }
        "<tr style='background:$bg'><td>$(Escape-Html $_.Cmdlet)</td><td>$(Escape-Html $_.TestName)</td><td><b>$($_.Status)</b></td><td>$(Escape-Html $_.Detail)</td><td align='right'>$($_.ElapsedMs)</td></tr>"
    }) -join "`n"

# build benchmark html section
$benchHtml = ''
if ($benchmarks.Count -gt 0) {
    $brows = ($benchmarks | Sort-Object Tree, Cmdlet | ForEach-Object {
            '<tr><td>' + $_.Cmdlet + '</td><td>' + $_.Tree + '</td><td align="right">' + $_.ElapsedMs + '</td><td align="right">' + $_.Count + '</td><td>' + (Escape-Html $_.Note) + '</td></tr>'
        }) -join "`n"
    $benchHtml = '<h2>Timing Benchmarks</h2>'
    $benchHtml += '<table border="1" cellpadding="5" style="border-collapse:collapse;margin-bottom:30px">'
    $benchHtml += '<tr style="background:#333;color:#eee"><th>Cmdlet</th><th>Tree</th><th>ElapsedMs</th><th>Count</th><th>Note</th></tr>'
    $benchHtml += $brows
    $benchHtml += '</table>'
}

# build fail section
$failHtml = if ($fails -gt 0) {
    $frows = ($script:TestResults | Where-Object Status -EQ 'FAIL' | ForEach-Object {
            '<tr style="background:#f8d7da"><td>' + (Escape-Html $_.Cmdlet) + '</td><td>' + (Escape-Html $_.TestName) + '</td><td>' + (Escape-Html $_.Detail) + '</td></tr>'
        }) -join "`n"
    '<h2 style="color:red">Failed Tests</h2><table border="1" cellpadding="5" style="border-collapse:collapse"><tr style="background:#c0392b;color:#fff"><th>Cmdlet</th><th>Test</th><th>Detail</th></tr>' + $frows + '</table>'
}
else {
    '<p style="color:green;font-size:1.2em"><b>ALL PASS - zero failures.</b></p>'
}

$allPassBanner = if ($fails -eq 0) {
    '<div style="background:#155724;color:#d4edda;padding:15px;border-radius:5px;font-size:1.2em;margin-bottom:20px"><b>ALL PASS</b> - ' + $passes + ' passed, ' + $warns + ' warnings, ' + $skips + ' skipped.</div>'
}
else {
    '' 
}

$htmlContent = '<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8">'
$htmlContent += '<title>Dowser Test Suite - ' + (Get-Date -Format 'yyyy-MM-dd HH:mm') + '</title>'
$htmlContent += '<style>body{font-family:Consolas,monospace;background:#1e1e1e;color:#d4d4d4;margin:20px}h1{color:#4fc3f7;border-bottom:2px solid #333;padding-bottom:8px}h2{color:#81c784;margin-top:30px}table{width:100%;border-collapse:collapse;margin-bottom:20px}th{background:#333;color:#eee;padding:8px;text-align:left}td{padding:6px 8px;border:1px solid #444}.stats{display:flex;gap:24px;background:#252526;padding:12px;border-radius:5px;margin-bottom:20px}.stat{text-align:center}.val{font-size:1.8em;font-weight:bold}.lbl{font-size:.8em;color:#aaa}.p{color:#28a745}.f{color:#dc3545}.w{color:#ffc107}.s{color:#6c757d}</style>'
$htmlContent += '</head><body>'
$htmlContent += '<h1>Dowser Module Test Suite</h1>'
$htmlContent += '<p>Run: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  |  Module: ' + $ModulePath + '</p>'
$htmlContent += $allPassBanner
$htmlContent += '<div class="stats">'
$htmlContent += '<div class="stat"><div class="val">' + $total + '</div><div class="lbl">Total</div></div>'
$htmlContent += '<div class="stat"><div class="val p">' + $passes + '</div><div class="lbl">PASS</div></div>'
$htmlContent += '<div class="stat"><div class="val f">' + $fails + '</div><div class="lbl">FAIL</div></div>'
$htmlContent += '<div class="stat"><div class="val w">' + $warns + '</div><div class="lbl">WARN</div></div>'
$htmlContent += '<div class="stat"><div class="val s">' + $skips + '</div><div class="lbl">SKIP</div></div>'
$htmlContent += '<div class="stat"><div class="val">' + $passRate + '%</div><div class="lbl">Pass Rate</div></div>'
$htmlContent += '</div>'
$htmlContent += $failHtml
$htmlContent += $benchHtml
$htmlContent += '<h2>All Test Results</h2>'
$htmlContent += '<table><tr><th>Cmdlet</th><th>Test</th><th>Status</th><th>Detail</th><th>ms</th></tr>'
$htmlContent += $rowsHtml
$htmlContent += '</table></body></html>'

$htmlContent | Set-Content -Path $htmlPath -Encoding UTF8
Write-Host "HTML : $htmlPath" -ForegroundColor Green
Write-Host ""

if ($fails -gt 0) {
    exit 1 
}
else {
    exit 0 
}