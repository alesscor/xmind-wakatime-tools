param(
  [string]$WatchPath,
  [string]$LogPath,
  [switch]$WhatIf,
  [switch]$List
)

$ErrorActionPreference = 'Stop'

$scriptName = 'xmind-wakatime-watcher.ps1'
$patternName = [Regex]::Escape($scriptName)

if ($LogPath) {
  $LogPath = [Environment]::ExpandEnvironmentVariables($LogPath)
}

function Write-Log {
  param([string]$Level='INFO',[string]$Message)
  $ts = (Get-Date).ToString('u')
  $line = "[$ts][$Level] $Message"
  Write-Host $line
  if ($LogPath) {
    $dir = Split-Path -Parent $LogPath
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Add-Content -Path $LogPath -Value $line
  }
}

try {
  $procs = Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" |
    Where-Object { $_.CommandLine -and ($_.CommandLine -match $patternName) }

  if ($WatchPath) {
    $watchEsc = [Regex]::Escape((Resolve-Path $WatchPath).Path)
    $procs = $procs | Where-Object { $_.CommandLine -match $watchEsc }
  }

  if ($List) {
    $all = Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" | Where-Object { $_.CommandLine }
    Write-Log -Level 'INFO' -Message 'Listing candidate shell processes:'
    foreach ($p in $all) { Write-Log -Level 'INFO' -Message ("{0} PID={1} :: {2}" -f $p.Name, $p.ProcessId, $p.CommandLine) }
  }

  if (-not $procs) { Write-Log -Level 'INFO' -Message 'No watcher process found.'; exit 0 }

  $pids = @($procs | Select-Object -ExpandProperty ProcessId)
  if ($WhatIf) { Write-Log -Level 'INFO' -Message ("Would stop PIDs: {0}" -f ($pids -join ', ')); exit 0 }

  foreach ($procId in $pids) {
    try {
      Stop-Process -Id $procId -Force -ErrorAction Stop
      Write-Log -Level 'INFO' -Message ("Stopped PID {0}" -f $procId)
    } catch { Write-Log -Level 'ERROR' -Message ("Failed to stop PID {0}: {1}" -f $procId, $_.Exception.Message) }
  }
  exit 0
} catch {
  Write-Log -Level 'ERROR' -Message $_.Exception.Message
  exit 1
}
