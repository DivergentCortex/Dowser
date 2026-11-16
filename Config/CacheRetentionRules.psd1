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
#   SeatProcessNames  program names of the seats that load plugins from this cache. A seat reads
#                     its plugin files into memory when it starts and keeps none open, so the
#                     version it loaded is found from its start time: the newest version the
#                     cache held then, and the next older one, are kept. A seat whose start time
#                     cannot be read keeps every version.
#   RootAliases       other spellings of Root that a process may use (a link into it)
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
            RootAliases       = @('~/.claude/ravens/plugins/cache')
            SeatProcessNames  = @('claude')
            Marketplaces      = @('divergentcortex')
            Plugins           = @('myelindrite', 'cortex-toolbox', 'career-vulture')
            KeepNewest        = 2
            InstalledManifest = '~/.claude/plugins/installed_plugins.json'
            QuietMinutes      = 60
        }
        @{
            # Codex records only enabled flags per plugin in config.toml, never a version, so there is no
            # installed manifest and a seat's start time is the only evidence of what it loaded
            Name             = 'CodexPluginCache'
            Type             = 'VersionedCache'
            Root             = '~/.codex/plugins/cache'
            SeatProcessNames = @('codex')
            Marketplaces     = @('divergentcortex')
            Plugins          = @('myelindrite', 'cortex-toolbox', 'career-vulture')
            KeepNewest       = 2
            QuietMinutes     = 60
        }
        @{
            Name    = 'RootFilesystemFreeSpace'
            Type    = 'DiskThreshold'
            Path    = '/'
            MinFree = '50GB'
        }
    )
}
