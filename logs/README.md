# Dowser logs

Every Dowser log is written by `DivergentCortex.Witness` in CMTrace format, one file per day, directly in this folder. Witness rotates a file beside itself when it reaches its size limit and prunes aged files. Nothing but this README is tracked by git.

| File | Component | Written by |
| --- | --- | --- |
| `dowser.module_YYYYMMDD.log` | The module and every public command | `Dowser.psm1` at import, then each command through `Write-Log` |
| `dowser.cache.retention_YYYYMMDD.log` | Scheduled and manual cache retention runs | `Invoke-DowserScheduledRetention.ps1`, which points Witness at this file before it calls `Invoke-DowserCacheRetention` |

Verbose and Debug records are written only when troubleshooting turns them on (`$Global:VerboseLogfile`, `$Global:DebugLogfile`, or `-Verbose` on a command).
