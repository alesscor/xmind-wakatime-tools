param(
  [string]$TaskName = 'XMind WakaTime Watcher',
  [Parameter(Mandatory=$true)][string]$WatchPath,
  [string]$Project,
  [string]$Category = 'designing',
  [string]$Plugin = 'xmind/2025',
  [string]$LogPath = "$env:LOCALAPPDATA\WakaTime\xmind-watcher.log",
  [int]$RotateCount = 1000,
  [int]$RotateKeep = 5,
  [int]$MinIntervalMs = 2000,
  [switch]$NoHostname,
  [switch]$Truncate,
  [switch]$Hidden
)

$ErrorActionPreference = 'Stop'

$script = Join-Path $PSScriptRoot 'xmind-wakatime-watcher.ps1'
if (!(Test-Path $script)) { throw "Watcher script not found: $script" }

$logDir = Split-Path -Parent $LogPath
if ($logDir -and -not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

$escapedScript = '"' + $script + '"'
$psFlags = if ($Hidden) { '-WindowStyle Hidden -NoLogo -NoProfile -NonInteractive' } else { '-NoLogo' }
$args = "$psFlags -ExecutionPolicy Bypass -File $escapedScript -WatchPath '$WatchPath' -Category '$Category' -Plugin '$Plugin' -LogPath '$LogPath' -RotateCount $RotateCount -RotateKeep $RotateKeep -MinIntervalMs $MinIntervalMs"
if ($Project) { $args += " -Project '$Project'" }
if ($NoHostname) { $args += ' -NoHostname' }
if ($Truncate) { $args += ' -Truncate' }

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $args
$trigger = New-ScheduledTaskTrigger -AtLogOn
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -Hidden -MultipleInstances IgnoreNew
$task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'Start XMind WakaTime watcher on user logon'

Register-ScheduledTask -TaskName $TaskName -InputObject $task -Force | Out-Null
Write-Host "Registered task '$TaskName' to start watcher at logon." -ForegroundColor Green
