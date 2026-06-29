#Requires -Version 5.1
<#
.SYNOPSIS
    Sorts strings or objects with embedded numbers in natural (human) order.

.DESCRIPTION
    Standard Sort-Object sorts "Item-10" before "Item-2" because it compares
    character codes, not numeric values. Invoke-DowserNumericSort pads all
    numeric segments before sorting so natural order is preserved:
    Item-1, Item-2 ... Item-9, Item-10.

    Delegates key generation to Get-DowserSortKey (Private\).

.PARAMETER InputObject
    Objects to sort. Accepts pipeline input. Required.

.PARAMETER Property
    Property name(s) to sort by. If omitted, sorts the object's string value directly.

.PARAMETER Descending
    Sort in descending order.

.PARAMETER CaseSensitive
    Case-sensitive sort comparison.

.PARAMETER Unique
    Return only unique results.

.PARAMETER Top
    Return only the top N results after sorting.

.EXAMPLE
    'Item-10','Item-2','Item-1' | Invoke-DowserNumericSort

.EXAMPLE
    Get-ChildItem | Invoke-DowserNumericSort -Property Name

.EXAMPLE
    $data | Invoke-DowserNumericSort -Property Version -Descending -Top 5

.NOTES
    Alias: dsort, dnsort
    Source: Invoke-NumericalSorting.ps1 (standalone scripts) - Sort-Numerical function
    Private helper: Get-DowserSortKey (extracted from source Get-SortKey)
    Related: Find-DowserFile, Find-DowserDuplicate
#>
function Invoke-DowserNumericSort {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object[]]$InputObject,

        [Parameter(Mandatory = $false)]
        [string[]]$Property,

        [Parameter(Mandatory = $false)]
        [switch]$Descending,

        [Parameter(Mandatory = $false)]
        [switch]$CaseSensitive,

        [Parameter(Mandatory = $false)]
        [switch]$Unique,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Top
    )

    begin {
        $inputArray = @()
    }

    process {
        $inputArray += $InputObject
    }

    end {
        if (-not $inputArray) {
            Write-Error "No input data provided - nothing to sort."
            return
        }

        try {
            $propertyScript = {
                if ($Property) {
                    $value = $_
                    foreach ($prop in $Property) {
                        $value = $value.$prop
                    }
                }
                else {
                    $value = $_
                }

                Get-DowserSortKey $value
            }

            $sortParams = @{
                Property   = $propertyScript
                Descending = $Descending.IsPresent
                Unique     = $Unique.IsPresent
            }

            if ($CaseSensitive -and (Get-Command Sort-Object).Parameters.ContainsKey('CaseSensitive')) {
                $sortParams.CaseSensitive = $true
            }

            $sortedArray = $inputArray | Sort-Object @sortParams

            if ($Top) {
                $sortedArray = $sortedArray | Select-Object -First $Top
            }

            $sortedArray
        }
        catch {
            Write-Error "Invoke-DowserNumericSort failed: $($_.Exception.Message)"
        }
    }
}

# tab-completion for -Property tries to infer available properties from whatever
# is flowing through the pipeline. falls back to generic suggestions if it can't.
Register-ArgumentCompleter -CommandName Invoke-DowserNumericSort -ParameterName Property -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    $inputObject = $null

    $pipelineAst = $commandAst.PipelineElements | Select-Object -First 1
    if ($pipelineAst -is [System.Management.Automation.Language.CommandAst]) {
        $variableAst = $pipelineAst.CommandElements |
            Where-Object { $_ -is [System.Management.Automation.Language.VariableExpressionAst] } |
            Select-Object -First 1
        if ($variableAst) {
            $variableName = $variableAst.VariablePath.UserPath
            $inputObject = Get-Variable -Name $variableName -ValueOnly -ErrorAction SilentlyContinue
        }
    }

    if ($inputObject) {
        $properties = $inputObject | Select-Object -First 1 | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name
        $properties | Where-Object { $_ -like ($wordToComplete + '*') }
    }
    else {
        @('Name', 'Age', 'Score')
    }
}
