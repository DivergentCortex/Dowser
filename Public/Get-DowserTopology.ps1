#Requires -Version 5.1

# depth check must come first or recursion runs away
# InColor needs the DynamicParam block, do not remove it

function Get-DowserTopology {
    <#
    .SYNOPSIS
        Renders a provider-agnostic tree view of any PS provider path.

    .NOTES
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
        -  Author:        Curtis Leggett                                  -
        =  Copyright:     2026 Divergent Cortex                           =
        -  Organization:  Divergent Cortex                                -
        =  Version:       See docs/CHANGELOG.md                           =
        =-=-                       =-=-=-=-=-=-=-=                     -=-=
        -  it is not water they seek, but the truth beneath the trees     -
        =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

        Ported from: Get-TreeTopology.ps1 (standalone scripts)
        Aliases preserved: pstree, shtree

    .DESCRIPTION
        Displays a visual tree of containers and optionally items for any PSProvider
        (FileSystem, Registry, Cert:, etc.). Supports colorized output via ANSI escape
        codes when running on a FileSystem path with the InColor (alias -ansi) switch.

    .PARAMETER Path
        One or more paths to render. Accepts pipeline input. Defaults to current location.

    .PARAMETER LiteralPath
        Literal path(s), with no wildcard expansion.

    .PARAMETER Depth
        How many levels to display. Default is [int]::MaxValue (full depth).

    .PARAMETER IndentSize
        Characters per indent level. Default 3.

    .PARAMETER ShowItem
        Include non-container items (files) in the tree output.

    .PARAMETER ShowProperty
        Display item properties inline. Use * for all, or a comma-separated list.

    .PARAMETER InColor
        Dynamic, FileSystem only. Colorize output using PSAnsiFileMap ANSI codes.

    .EXAMPLE
        Get-DowserTopology -Path D:\Projects -Depth 3

    .EXAMPLE
        Get-DowserTopology -Path HKLM:\SOFTWARE -ShowItem

    .EXAMPLE
        Get-DowserTopology D:\Scripts -InColor -ShowItem

    .OUTPUTS
        String. Tree lines written to the output stream, one per container or item.
    #>

    [CmdletBinding(DefaultParameterSetName = "Path")]
    [Alias("pstree", "shtree")]

    param(
        [Parameter(
            Position = 0,
            ParameterSetName = "Path",
            ValueFromPipeline,
            ValueFromPipelineByPropertyName
        )]
        [ValidateNotNullOrEmpty()]
        [Alias("FullName")]
        [string[]]$Path = ".",

        [Parameter(
            Position = 0,
            ParameterSetName = "LiteralPath",
            ValueFromPipelineByPropertyName
        )]
        [ValidateNotNullOrEmpty()]
        [string[]]$LiteralPath,

        [Parameter(Position = 1)]
        [ValidateRange(0, 2147483647)]
        [int]$Depth = [int]::MaxValue,

        [Parameter()]
        [ValidateRange(1, 100)]
        [int]$IndentSize = 3,

        [Parameter()]
        [Alias("files")]
        [switch]$ShowItem,

        [Parameter(HelpMessage = "Display item properties. Use * to show all properties or specify a comma separated list.")]
        [Alias("properties")]
        [string[]]$ShowProperty
    )

    dynamicparam {
        if ($PSBoundParameters.ContainsKey("Path")) {
            $here = $PSBoundParameters["Path"]
        }
        elseif ($PSBoundParameters.ContainsKey("LiteralPath")) {
            $here = $PSBoundParameters["LiteralPath"]
        }
        else {
            $here = (Get-Location).path
        }
        if (
            ((Get-Item -Path $here -ErrorAction SilentlyContinue).PSprovider.Name -eq 'FileSystem') -or
            ((Get-Item -LiteralPath $here -ErrorAction SilentlyContinue).PSprovider.Name -eq 'FileSystem')
        ) {
            $attributes = New-Object System.Management.Automation.ParameterAttribute
            $attributes.HelpMessage = "Show tree and item colorized."
            $alias = [System.Management.Automation.AliasAttribute]::new("ansi")
            $attributeCollection = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
            $attributeCollection.Add($attributes)
            $attributeCollection.Add($alias)
            $dynParam1 = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("InColor", [Switch], $attributeCollection)
            $paramDictionary = New-Object -Type System.Management.Automation.RuntimeDefinedParameterDictionary
            $paramDictionary.Add("InColor", $dynParam1)
            return $paramDictionary
        }
    }

    begin {
        Write-Log "Starting Get-DowserTopology"
        if (-not $Path -and $PSCmdlet.ParameterSetName -eq "Path") {
            $Path = Get-Location
        }

        if ($PSBoundParameters.ContainsKey("InColor")) {
            # PSAnsiFileMap is ps7+ only, null on 5.1 and indexing null-refs
            if ($PSVersionTable.PSVersion.Major -ge 7) {
                $Colorize = $True
                $script:top = ($global:PSAnsiFileMap).where({ $_.description -eq 'TopContainer' }).Ansi
                $script:child = ($global:PSAnsiFileMap).where({ $_.description -eq 'ChildContainer' }).Ansi
            }
            else {
                Write-Log "Get-DowserTopology -InColor requires PowerShell 7+ (PSAnsiFileMap). Rendering without color." -Severity Warning
            }
        }

        function GetIndentString {
            [CmdletBinding()]
            param([bool[]]$IsLast)
            Write-Log "Starting $($MyInvocation.MyCommand)" -Severity Verbose
            $str = ''
            for ($i = 0; $i -lt $IsLast.Count - 1; $i++) {
                $sepChar = if ($IsLast[$i]) {
                    ' ' 
                }
                else {
                    '|' 
                }
                $str += "$sepChar"
                $str += " " * ($IndentSize - 1)
            }
            $teeChar = if ($IsLast[-1]) {
                '\' 
            }
            else {
                '+' 
            }
            $str += "$teeChar"
            $str += "-" * ($IndentSize - 1)
            $str
            Write-Log "Ending $($MyInvocation.MyCommand)" -Severity Verbose
        }

        function ShowProperty() {
            [cmdletbinding()]
            param(
                [string]$Name,
                [string]$Value,
                [bool[]]$IsLast
            )
            Write-Log "Starting $($MyInvocation.MyCommand)" -Severity Verbose
            $indentStr = GetIndentString $IsLast
            $propStr = "${indentStr} $Name = "
            $availableWidth = $host.UI.RawUI.BufferSize.Width - $propStr.Length - 1
            if ($Value.Length -gt $availableWidth) {
                $ellipsis = '...'
                $val = $Value.Substring(0, $availableWidth - $ellipsis.Length) + $ellipsis
            }
            else {
                $val = $Value
            }
            $propStr += $val
            $propStr
            Write-Log "Ending $($MyInvocation.MyCommand)" -Severity Verbose
        }

        function ShowItem {
            [CmdletBinding()]
            param(
                [string]$Path,
                [string]$Name,
                [bool[]]$IsLast,
                [bool]$HasChildItems = $false,
                [switch]$Color,
                [ValidateSet("topcontainer", "childcontainer", "file")]
                [string]$ItemType
            )
            Write-Log "Starting $($MyInvocation.MyCommand)" -Severity Verbose
            Write-Log ($PSBoundParameters | Out-String) -Severity Verbose
            if ($IsLast.Count -eq 0) {
                if ($Color) {
                    Write-Output "$($script:top)$("$(Resolve-Path $Path)")$([char]0x1b)[0m"
                }
                else {
                    "$(Resolve-Path $Path)"
                }
            }
            else {
                $indentStr = GetIndentString $IsLast
                if ($Color) {
                    switch ($ItemType) {
                        "topcontainer" {
                            Write-Output "$indentStr$($script:top)$($Name)$([char]0x1b)[0m"
                        }
                        "childcontainer" {
                            Write-Output "$indentStr$($script:child)$($Name)$([char]0x1b)[0m"
                        }
                        "file" {
                            foreach ($item in ($global:PSAnsiFileMap | Where-Object Pattern)) {
                                if ($name -match $item.pattern -and (-not $done)) {
                                    Write-Log "Detected a $($item.description) file" -Severity Verbose
                                    Write-Output "$indentStr$($item.ansi)$($Name)$([char]0x1b)[0m"
                                    $done = $True
                                }
                            }
                            if (-not $done) {
                                Write-Log "No ansi match for $Name" -Severity Verbose
                                Write-Output "$indentStr$Name$([char]0x1b)[0m"
                            }
                        }
                        default {
                            Write-Output "$indentStr$Name"
                        }
                    }
                }
                else {
                    "$indentStr$Name"
                }
            }

            if ($ShowProperty) {
                $IsLast += @($false)
                $excludedProviderNoteProps = 'PSChildName', 'PSDrive', 'PSParentPath', 'PSPath', 'PSProvider'
                $props = @(Get-ItemProperty $Path -ea 0)
                if ($props[0] -is [PSCustomObject]) {
                    if ($ShowProperty -eq "*") {
                        $props = @($props[0].PSObject.properties | Where-Object { $excludedProviderNoteProps -notcontains $_.Name })
                    }
                    else {
                        $props = @($props[0].PSObject.properties |
                                Where-Object { $excludedProviderNoteProps -notcontains $_.Name -and $showproperty -contains $_.name })
                    }
                }
                for ($i = 0; $i -lt $props.Count; $i++) {
                    $prop = $props[$i]
                    $IsLast[-1] = ($i -eq $props.count - 1) -and (-not $HasChildItems)
                    $showParams = @{
                        Name   = $prop.Name
                        Value  = $prop.Value
                        IsLast = $IsLast
                    }
                    ShowProperty @showParams
                }
            }
            Write-Log "Ending $($MyInvocation.MyCommand)" -Severity Verbose
        }

        function ShowContainer {
            [CmdletBinding()]
            param (
                [string]$Path,
                [string]$Name = $(Split-Path $Path -Leaf),
                [bool[]]$IsLast = @(),
                [switch]$IsTop,
                [switch]$Color
            )
            Write-Log "Starting $($MyInvocation.MyCommand) on $Path" -Severity Verbose
            Write-Log ($PSBoundParameters | Out-String) -Severity Verbose
            if ($IsLast.Count -gt $Depth) {
                return 
            }

            $childItems = @()
            if ($IsLast.Count -lt $Depth) {
                try {
                    $rPath = Resolve-Path -LiteralPath $Path -ErrorAction Stop
                }
                catch {
                    throw "Failed to resolve $path. This PSProvider and path may be incompatible with this command."
                    return
                }
                $childItems = @(Get-ChildItem $rPath -ErrorAction $ErrorActionPreference |
                        Where-Object { $ShowItem -or $_.PSIsContainer })
            }
            $hasChildItems = $childItems.Count -gt 0

            $sParams = @{
                path          = $Path
                name          = $Name
                IsLast        = $IsLast
                hasChildItems = $hasChildItems
                Color         = $Color
                ItemType      = if ($isTop) {
                    "topcontainer" 
                }
                else {
                    "childcontainer" 
                }
            }
            ShowItem @sParams

            $IsLast += @($false)
            for ($i = 0; $i -lt $childItems.count; $i++) {
                $childItem = $childItems[$i]
                $IsLast[-1] = ($i -eq $childItems.count - 1)
                if ($childItem.PSIsContainer) {
                    $iParams = @{
                        path   = $childItem.PSPath
                        name   = $childItem.PSChildName
                        isLast = $IsLast
                        Color  = $color
                    }
                    ShowContainer @iParams
                }
                elseif ($ShowItem) {
                    $unresolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($childItem.PSPath)
                    $name = Split-Path $unresolvedPath -Leaf
                    $iParams = @{
                        Path     = $childItem.PSPath
                        Name     = $name
                        IsLast   = $IsLast
                        Color    = $Color
                        ItemType = "File"
                    }
                    ShowItem @iParams
                }
            }
            Write-Log "Ending $($MyInvocation.MyCommand)" -Severity Verbose
        }
    }

    process {
        Write-Log "Get-DowserTopology detected parameter set '$($PSCmdlet.ParameterSetName)'"
        if ($PSCmdlet.ParameterSetName -eq "Path") {
            $resolvedPaths = @($Path | Resolve-Path | ForEach-Object { $_.Path })
        }
        else {
            $resolvedPaths = @($LiteralPath)
        }

        foreach ($rPath in $resolvedPaths) {
            Write-Log "Get-DowserTopology rendering '$rPath'"
            $showParams = @{
                Path  = $rPath
                Color = $colorize
                IsTop = $True
            }
            ShowContainer @showParams
        }
    }

    end {
        Write-Log "Ending Get-DowserTopology"
    }
}
