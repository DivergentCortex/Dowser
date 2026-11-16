#
# Rule set for Invoke-DowserCacheRetention.
#
# VersionedCache rules prune <Root>/<marketplace>/<plugin>/<version> folders:
#   Marketplaces      marketplace folder names under Root
#   Plugins           plugin folder names under each marketplace
#   KeepNewest        newest versions kept per plugin, by dotted version number
#   InstalledManifest installed_plugins.json whose installPath values are always kept
#                     (omit when the cache has no such manifest)
#   QuietMinutes      a version with a file written inside this window is left alone
#
# DiskThreshold rules report when free space on the filesystem holding Path drops below MinFree.
#   MinFree           size string such as 20GB
#
# A leading ~ in Root, InstalledManifest or Path expands to the current user's home folder.
#
@{
    Rules = @(
        @{
            Name              = 'ClaudePluginCache'
            Type              = 'VersionedCache'
            Root              = '~/.claude/plugins/cache'
            Marketplaces      = @('divergentcortex')
            Plugins           = @('myelindrite', 'cortex-toolbox', 'career-vulture')
            KeepNewest        = 2
            InstalledManifest = '~/.claude/plugins/installed_plugins.json'
            QuietMinutes      = 60
        }
        @{
            Name         = 'CodexPluginCache'
            Type         = 'VersionedCache'
            Root         = '~/.codex/plugins/cache'
            Marketplaces = @('divergentcortex')
            Plugins      = @('myelindrite', 'cortex-toolbox', 'career-vulture')
            KeepNewest   = 2
            QuietMinutes = 60
        }
        @{
            Name    = 'RootFilesystemFreeSpace'
            Type    = 'DiskThreshold'
            Path    = '/'
            MinFree = '50GB'
        }
    )
}
