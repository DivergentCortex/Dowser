# Scheduled cache retention

`dowser-cache-retention.service` runs `Invoke-DowserScheduledRetention.ps1 -Remove`, and `dowser-cache-retention.timer` starts it every six hours (00:17, 06:17, 12:17 and 18:17, plus up to five minutes of random delay). These are user units: they run as you, read `~/.claude` and `~/.codex`, and write `logs/dowser.cache.retention_YYYYMMDD.log` in the Dowser folder. Nothing in this repository installs or enables them.

## What a run does

It applies `Config/CacheRetentionRules.psd1`. For the Claude and Codex plugin caches it removes version folders that are not the installed version, are not held by a running process, are not the version a running seat started on (or the one before it), are not one of the newest two, are not symlinks or under a symlinked folder, and have had no file written in the last hour. A seat is a running `claude` (or `codex`) process: it keeps no plugin file open, so the version it loaded is worked out from its start time and the creation time of each version folder. A seat whose start time cannot be read, or a folder whose creation time cannot be read, keeps every version of that plugin.

Free space on `/` is only reported. When it is below 50 GB the run does not remove anything extra: the breach shows up as a failed unit (exit 112) and as a warning in `logs/dowser.cache.retention_YYYYMMDD.log`, and nothing else notifies anyone. The unit also fails (non-zero exit) when any removal or read failed, so `systemctl --user status dowser-cache-retention.service` and `journalctl --user -u dowser-cache-retention.service` show the last outcome.

Preview first, by hand, from the Dowser folder:

```powershell
pwsh -NoProfile -File ./Invoke-DowserScheduledRetention.ps1
```

Without `-Remove` the run deletes nothing and prints what a removal run would do.

## Install (operator step)

The units assume Dowser lives at `~/projects/Dowser` and PowerShell at `/opt/microsoft/powershell/7/pwsh`. Check with `command -v pwsh` (follow any link it prints) and edit the `ExecStart` and `Documentation` paths in the service before copying it; the systemd user manager does not search your shell `PATH`.

```bash
mkdir -p ~/.config/systemd/user
cp deploy/systemd/dowser-cache-retention.service deploy/systemd/dowser-cache-retention.timer ~/.config/systemd/user/
systemd-analyze --user verify dowser-cache-retention.service dowser-cache-retention.timer
systemctl --user daemon-reload
systemctl --user enable --now dowser-cache-retention.timer
systemctl --user list-timers dowser-cache-retention.timer
```

A user timer only runs while you are logged in. To keep it running when you are not, run `loginctl enable-linger $USER` once.

## Run once now (this is a real removal)

Starting the service runs `Invoke-DowserScheduledRetention.ps1 -Remove`, which deletes version folders. Read the preview from the section above first and start the service only when its Remove list is what you want deleted.

```bash
systemctl --user start dowser-cache-retention.service
journalctl --user -u dowser-cache-retention.service -n 50
```

## Remove

```bash
systemctl --user disable --now dowser-cache-retention.timer
rm ~/.config/systemd/user/dowser-cache-retention.service ~/.config/systemd/user/dowser-cache-retention.timer
systemctl --user daemon-reload
```

## Change a rule

Edit `Config/CacheRetentionRules.psd1`; the next run reads it. `KeepNewest`, `QuietMinutes`, the plugin names and the free-space minimum are all in that file.
