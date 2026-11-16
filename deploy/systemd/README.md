# Scheduled cache retention

`dowser-cache-retention.service` runs `Invoke-DowserScheduledRetention.ps1 -Remove`, and `dowser-cache-retention.timer` starts it every six hours (00:17, 06:17, 12:17 and 18:17, plus up to five minutes of random delay). These are user units: they run as you, read `~/.claude` and `~/.codex`, and write `logs/dowser.cache.retention_YYYYMMDD.log` in the Dowser folder. Nothing in this repository installs or enables them.

## What a run does

It applies `Config/CacheRetentionRules.psd1`. For the Claude and Codex plugin caches it removes version folders that are not the installed version, are not held by a running process, are not one of the newest two, are not symlinks, and have had no file written in the last hour. It also reports when free space on `/` is below 50 GB. The unit fails (non-zero exit) when anything failed or the threshold is breached, so `systemctl --user status dowser-cache-retention.service` and `journalctl --user -u dowser-cache-retention.service` show the last outcome.

Preview first, by hand, from the Dowser folder:

```powershell
pwsh -NoProfile -File ./Invoke-DowserScheduledRetention.ps1
```

Without `-Remove` the run deletes nothing and prints what a removal run would do.

## Install (operator step)

The units assume Dowser lives at `~/projects/Dowser`. If it lives elsewhere, edit the `ExecStart` and `Documentation` paths in the service before copying it.

```bash
mkdir -p ~/.config/systemd/user
cp deploy/systemd/dowser-cache-retention.service deploy/systemd/dowser-cache-retention.timer ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now dowser-cache-retention.timer
systemctl --user list-timers dowser-cache-retention.timer
```

A user timer only runs while you are logged in. To keep it running when you are not, run `loginctl enable-linger $USER` once.

## Run once now

```bash
systemctl --user start dowser-cache-retention.service
```

## Remove

```bash
systemctl --user disable --now dowser-cache-retention.timer
rm ~/.config/systemd/user/dowser-cache-retention.service ~/.config/systemd/user/dowser-cache-retention.timer
systemctl --user daemon-reload
```

## Change a rule

Edit `Config/CacheRetentionRules.psd1`; the next run reads it. `KeepNewest`, `QuietMinutes`, the plugin names and the free-space minimum are all in that file.
