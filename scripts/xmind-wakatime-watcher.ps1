param(
  [Parameter(Mandatory=$true)][string]$WatchPath,
  [string]$Project,
  [ValidateSet('coding','designing','building','researching','learning','writing','browsing')]
  [string]$Category = 'designing',
  [string]$Plugin = 'xmind/2025',
  [string]$WakaPath,
  [string]$Hostname = $env:COMPUTERNAME,
  [switch]$NoHostname,
  [string]$LogPath,
  [switch]$Truncate,
  [switch]$Append,
  [int]$RotateCount = 0,
  [int]$RotateKeep = 5,
  [switch]$Quiet,
  [int]$MinIntervalMs = 2000
)

$ErrorActionPreference = 'Stop'
$script:Quiet = $Quiet.IsPresent

if (-not (Test-Path $WatchPath)) { throw "Watch path not found: $WatchPath" }
if ([string]::IsNullOrWhiteSpace($Plugin)) { $Plugin = 'xmind/2025' }

function Resolve-WakaPath {
  param([string]$Preferred)
  if ($Preferred -and (Test-Path $Preferred)) { return $Preferred }
  if ($env:WAKATIME_CLI -and (Test-Path $env:WAKATIME_CLI)) { return $env:WAKATIME_CLI }
  $defaultLocal = Join-Path $env:LOCALAPPDATA 'WakaTime\wakatime-cli-windows-amd64.exe'
  if ($env:LOCALAPPDATA -and (Test-Path $defaultLocal)) { return $defaultLocal }
  foreach ($c in @('wakatime-cli','wakatime-cli.exe','wakatime','wakatime.exe','wakatime-cli-windows-amd64.exe')) {
    $cmd = (Get-Command $c -ErrorAction SilentlyContinue)
    if ($cmd -and $cmd.Path) { return $cmd.Path }
  }
  return $null
}

$waka = Resolve-WakaPath -Preferred $WakaPath
if (-not $waka) { throw 'WakaTime CLI not found.' }

if (-not $Project -or $Project.Trim() -eq '') {
  # derive from parent folder name of WatchPath
  $parent = Split-Path -Parent (Resolve-Path $WatchPath)
  $Project = Split-Path $parent -Leaf
}

if ($LogPath) {
  $dir = Split-Path -Parent $LogPath
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  if ($Truncate -and (Test-Path $LogPath)) { Remove-Item -Path $LogPath -Force }
}

$fsw = New-Object System.IO.FileSystemWatcher
$fsw.Path = $WatchPath
$fsw.Filter = '*.xmind'
$fsw.IncludeSubdirectories = $true
$fsw.NotifyFilter = [System.IO.NotifyFilters]'FileName, LastWrite'

# shared state on watcher
$fsw | Add-Member -NotePropertyName Waka -NotePropertyValue $waka -Force
$fsw | Add-Member -NotePropertyName Project -NotePropertyValue $Project -Force
$fsw | Add-Member -NotePropertyName Plugin -NotePropertyValue $Plugin -Force
$fsw | Add-Member -NotePropertyName Category -NotePropertyValue $Category -Force
$fsw | Add-Member -NotePropertyName Hostname -NotePropertyValue $Hostname -Force
$fsw | Add-Member -NotePropertyName NoHostname -NotePropertyValue $NoHostname.IsPresent -Force
$fsw | Add-Member -NotePropertyName LogPath -NotePropertyValue $LogPath -Force
$fsw | Add-Member -NotePropertyName RotateCount -NotePropertyValue $RotateCount -Force
$fsw | Add-Member -NotePropertyName RotateKeep -NotePropertyValue $RotateKeep -Force
$fsw | Add-Member -NotePropertyName CurrentCount -NotePropertyValue 0 -Force
$fsw | Add-Member -NotePropertyName MinIntervalMs -NotePropertyValue $MinIntervalMs -Force
$fsw | Add-Member -NotePropertyName LastBeat -NotePropertyValue ([System.Collections.Hashtable]::Synchronized((New-Object System.Collections.Hashtable))) -Force

$fsw.EnableRaisingEvents = $true

if ($LogPath) { Add-Content -Path $LogPath -Value "[$((Get-Date).ToString('u'))][INFO] Watcher starting. PID=$PID WatchPath=$WatchPath Project=$Project Category=$Category Plugin=$Plugin Hostname=$Hostname NoHostname=$($NoHostname.IsPresent) MinIntervalMs=$MinIntervalMs Mode=sync" }
if (-not $script:Quiet) { Write-Host "Watching: $WatchPath" -ForegroundColor Green }

$handlers = @()
$handlers += Register-ObjectEvent -InputObject $fsw -EventName Changed -SourceIdentifier 'XMindFSWChanged'
$handlers += Register-ObjectEvent -InputObject $fsw -EventName Renamed -SourceIdentifier 'XMindFSWRenamed'

try {
  while ($true) {
    $evt = Wait-Event -Timeout 1
    if ($null -eq $evt) { continue }
    try {
      $args = $evt.SourceEventArgs
      if ($null -eq $args) { Remove-Event -EventIdentifier $evt.EventIdentifier; continue }
      $file = $args.FullPath
      if (-not $file -or -not (Test-Path $file)) { Remove-Event -EventIdentifier $evt.EventIdentifier; continue }
      $key = try { [System.IO.Path]::GetFullPath($file).ToLowerInvariant() } catch { $file.ToLowerInvariant() }
      $shouldSend = $true
      $now = Get-Date
      try {
        [System.Threading.Monitor]::Enter($fsw)
        $last = $null
        if ($fsw.LastBeat.ContainsKey($key)) { $last = $fsw.LastBeat[$key] }
        if ($last) {
          $elapsed = ($now - $last).TotalMilliseconds
          if ($elapsed -le [double]$fsw.MinIntervalMs) { $shouldSend = $false }
        }
        if ($shouldSend) { $fsw.LastBeat[$key] = $now }
      } finally { [System.Threading.Monitor]::Exit($fsw) }
      if (-not $shouldSend) { Remove-Event -EventIdentifier $evt.EventIdentifier; continue }
      Start-Sleep -Milliseconds 500
      try {
        $cliArgs = @('--entity', $file, '--entity-type', 'file', '--project', $fsw.Project, '--plugin', $fsw.Plugin, '--category', $fsw.Category, '--write', '--alternate-project', $fsw.Project)
        if (-not $fsw.NoHostname -and $fsw.Hostname) { $cliArgs += @('--hostname', $fsw.Hostname) }
        & $fsw.Waka @cliArgs | Out-Null
        $ts = (Get-Date).ToString('u')
        $msg = "Heartbeat: $($args.ChangeType) -> $file"
        if (-not $script:Quiet) { Write-Host "[$ts] $msg" -ForegroundColor Cyan }
        if ($fsw.LogPath) { Add-Content -Path $fsw.LogPath -Value "[$ts][HEARTBEAT] $msg" }
        # drain queued for same file
        try {
          $drained = 0
          while ($true) {
            $peek = Get-Event -ErrorAction SilentlyContinue | Where-Object { try { $_.SourceEventArgs.FullPath } catch { $null } } | Where-Object { $_.SourceEventArgs.FullPath -eq $file } | Select-Object -First 1
            if ($null -eq $peek) { break }
            Remove-Event -EventIdentifier $peek.EventIdentifier -ErrorAction SilentlyContinue
            $drained++
          }
          if ($fsw.LogPath -and $drained -gt 0) { Add-Content -Path $fsw.LogPath -Value "[$((Get-Date).ToString('u'))][SKIP] Drained $drained queued events for -> $file" }
        } catch { }
      } catch {
        if ($fsw.LogPath) { Add-Content -Path $fsw.LogPath -Value "[$((Get-Date).ToString('u'))][ERROR] ${file} :: $($_.Exception.Message)" }
      }
    } finally {
      Remove-Event -EventIdentifier $evt.EventIdentifier -ErrorAction SilentlyContinue
    }
  }
} finally {
  foreach ($h in $handlers) { Unregister-Event -SourceIdentifier $h.Name -ErrorAction SilentlyContinue }
  $fsw.EnableRaisingEvents = $false
  $fsw.Dispose()
}
