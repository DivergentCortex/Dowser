# Aliases\Aliases.ps1
# all Dowser short aliases. none defined inside function files.

# ConvertTo-Dowser*
Set-Alias -Name db64      -Value ConvertTo-DowserBase64
Set-Alias -Name dexe      -Value ConvertTo-DowserExe
Set-Alias -Name dico      -Value ConvertTo-DowserIco

# Find-Dowser*
Set-Alias -Name ddupe     -Value Find-DowserDuplicate
Set-Alias -Name dfile     -Value Find-DowserFile
Set-Alias -Name dfind     -Value Find-DowserFile
Set-Alias -Name dmod      -Value Find-DowserModified
Set-Alias -Name dlog      -Value Find-DowserRecentLog
Set-Alias -Name dorphan   -Value Find-DowserOrphan
Set-Alias -Name ddep      -Value Find-DowserDependency
Set-Alias -Name dscript   -Value Find-DowserScript
Set-Alias -Name dstr      -Value Find-DowserString
Set-Alias -Name dgrep     -Value Find-DowserString

# Get-Dowser*
Set-Alias -Name dmap      -Value Get-DowserMap
Set-Alias -Name dtree     -Value Get-DowserTopology
Set-Alias -Name down      -Value Get-DowserOwnership
Set-Alias -Name dprop     -Value Get-DowserProperty
Set-Alias -Name dreport   -Value Get-DowserReport
Set-Alias -Name dtemplate -Value Get-DowserTemplate
Set-Alias -Name dtopo     -Value Get-DowserTopology
Set-Alias -Name pstree    -Value Get-DowserTopology
Set-Alias -Name shtree    -Value Get-DowserTopology

# Measure-Dowser*
Set-Alias -Name dsize     -Value Measure-DowserDirectory
Set-Alias -Name ddu       -Value Measure-DowserDiskUsage

# Invoke-Dowser*
Set-Alias -Name dfast     -Value Invoke-DowserFastSearch
Set-Alias -Name dsort     -Value Invoke-DowserNumericSort
Set-Alias -Name dnsort    -Value Invoke-DowserNumericSort

# Test-Dowser*
Set-Alias -Name dtest       -Value Test-DowserExtractable
Set-Alias -Name dtestexe    -Value Test-DowserExtractable
Set-Alias -Name dintegrity  -Value Test-DowserIntegrity
Set-Alias -Name dinteg      -Value Test-DowserIntegrity

# Expand-Dowser*
Set-Alias -Name dexpand   -Value Expand-DowserExe
Set-Alias -Name dextract  -Value Expand-DowserExe
