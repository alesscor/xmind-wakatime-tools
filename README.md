# XMind WakaTime Tools

Standalone scripts to track time spent editing XMind files using the WakaTime CLI on Windows.

Features
- Watch any folder for `*.xmind` changes (recursive)
- Sends WakaTime heartbeats with project/category/plugin metadata
- Works with Windows PowerShell 5.1 and PowerShell 7+
- Hidden startup via Task Scheduler or VBScript launcher
- Single-instance guard
- Logging with optional rotation, throttle, and queue draining to avoid duplicates

Quick start
1) Install wakatime-cli and configure your API key (`%USERPROFILE%\.wakatime.cfg` or `WAKATIME_API_KEY`).
2) Copy scripts to any folder (or use this repo as-is).
3) Run the watcher:
   - `powershell.exe -ExecutionPolicy Bypass -File .\scripts\xmind-wakatime-watcher.ps1 -WatchPath "C:\\path\\to\\_mindmaps" -Project "MyProject" -LogPath "$env:LOCALAPPDATA\\WakaTime\\xmind-watcher.log"`
4) Optional: register a Task Scheduler entry using the helper script.

Git repo notes
- A .gitignore is included to avoid committing logs and editor artifacts.
- Typical first commit:
   - git add .
   - git commit -m "xmind-wakatime-tools: initial commit with watcher, launcher, task helper, stopper"
   - git branch -M main
   - git remote add origin <your-remote-url>
   - git push -u origin main

Scripts
- scripts/xmind-wakatime-watcher.ps1 — main watcher
- scripts/register-watcher-task.ps1 — Task Scheduler helper
- scripts/run-watcher-hidden.vbs — VBScript launcher (fully hidden)
- scripts/stop-watcher.ps1 — stop all matching watcher processes

Notes
- Requires WakaTime CLI (`wakatime-cli.exe`).
- By default logs append; use `-Truncate` to start fresh.
- VBScript writes a bootstrap log to `%LOCALAPPDATA%\WakaTime\watcher-bootstrap.log` for troubleshooting hidden launches.
