#Requires -Version 5.1
<#!
.SYNOPSIS
  Records active Codex/Claude Code turns and warns while a turn is running.

.DESCRIPTION
  UserPromptSubmit starts a turn and Stop ends it. The elapsed time is written
  only when Stop arrives, so time outside an agent turn is not accumulated.
#>
param(
  [Parameter(Mandatory = $true)][ValidateSet('Codex', 'ClaudeCode')][string]$Tool,
  [ValidateSet('Hook', 'Watch')][string]$Mode = 'Hook',
  [string]$StatePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-PropertyValue($Object, [string]$Name) {
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $null }
  return [string]$property.Value
}
function Get-StatePath([string]$ToolName, [string]$SessionId, [string]$TurnId) {
  $source = "$ToolName|$SessionId|$TurnId"
  $sha = [Security.Cryptography.SHA256]::Create()
  try { $hash = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($source))) -replace '-', '').ToLowerInvariant() }
  finally { $sha.Dispose() }
  $root = Join-Path $env:LOCALAPPDATA 'AIAgentGuardrails\turn-state'
  New-Item -ItemType Directory -Path $root -Force | Out-Null
  return (Join-Path $root "$hash.json")
}
function Get-TotalSeconds([string]$LogPath) {
  if (-not (Test-Path -LiteralPath $LogPath -PathType Leaf)) { return 0.0 }
  $sum = 0.0
  foreach ($row in @(Import-Csv -LiteralPath $LogPath)) {
    $value = 0.0
    if ([double]::TryParse([string]$row.ActiveSeconds, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$value)) { $sum += $value }
  }
  return $sum
}
function Save-State($State, [string]$Path) {
  $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
  $State | ConvertTo-Json -Compress | Set-Content -LiteralPath $temporary -Encoding utf8
  Move-Item -LiteralPath $temporary -Destination $Path -Force
}
function Show-Warning([int]$Threshold, [double]$Seconds) {
  $minutes = [math]::Round($Seconds / 60, 1)
  $message = "AI agent active-turn usage has reached $Threshold minutes (current total: $minutes minutes). Review whether to continue."
  try { $null = (New-Object -ComObject WScript.Shell).Popup($message, 30, 'AI Agent usage warning', 48) }
  catch { Write-Warning $message }
}

if ($Mode -eq 'Watch') {
  while (Test-Path -LiteralPath $StatePath -PathType Leaf) {
    try {
      $state = Get-Content -LiteralPath $StatePath -Raw -Encoding utf8 | ConvertFrom-Json
      $elapsed = [math]::Max(0, ([DateTime]::UtcNow - [DateTime]::Parse($state.StartedAtUtc)).TotalSeconds)
      $total = [double]$state.BaselineSeconds + $elapsed
      $threshold = [int]([math]::Floor($total / 1800) * 30)
      if ($threshold -gt [int]$state.LastWarnedThreshold) {
        $state.LastWarnedThreshold = $threshold
        Save-State $state $StatePath
        Show-Warning $threshold $total
      }
    } catch { }
    Start-Sleep -Seconds 5
  }
  exit 0
}

$inputText = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($inputText) -or [string]::IsNullOrWhiteSpace($env:AI_AGENT_AUDIT_ROOT)) { exit 0 }
$event = $inputText | ConvertFrom-Json
$eventName = Get-PropertyValue $event 'hook_event_name'
if ([string]::IsNullOrWhiteSpace($eventName)) { $eventName = Get-PropertyValue $event 'hookEventName' }
$sessionId = Get-PropertyValue $event 'session_id'
if ([string]::IsNullOrWhiteSpace($sessionId)) { $sessionId = Get-PropertyValue $event 'sessionId' }
$turnId = Get-PropertyValue $event 'turn_id'
if ([string]::IsNullOrWhiteSpace($turnId)) { $turnId = Get-PropertyValue $event 'turnId' }
if ([string]::IsNullOrWhiteSpace($sessionId)) { exit 0 }
if ([string]::IsNullOrWhiteSpace($turnId)) { $turnId = 'main' }
$path = Get-StatePath $Tool $sessionId $turnId
# Some Hook payload versions omit turn_id on Stop. In that case, finish the
# newest outstanding turn for this tool/session instead of leaving it running.
if ($eventName -eq 'Stop' -and -not (Test-Path -LiteralPath $path -PathType Leaf)) {
  $stateRoot = Join-Path $env:LOCALAPPDATA 'AIAgentGuardrails\turn-state'
  $candidate = Get-ChildItem -LiteralPath $stateRoot -Filter '*.json' -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTimeUtc -Descending |
    Where-Object {
      try {
        $pending = Get-Content -LiteralPath $_.FullName -Raw -Encoding utf8 | ConvertFrom-Json
        $pending.Tool -eq $Tool -and $pending.SessionId -eq $sessionId
      } catch { $false }
    } | Select-Object -First 1
  if ($candidate) { $path = $candidate.FullName }
}
$log = Join-Path $env:AI_AGENT_AUDIT_ROOT 'turn_usage.csv'

if ($eventName -eq 'UserPromptSubmit') {
  if (Test-Path -LiteralPath $path -PathType Leaf) { exit 0 }
  New-Item -ItemType Directory -Path $env:AI_AGENT_AUDIT_ROOT -Force | Out-Null
  $baseline = Get-TotalSeconds $log
  $state = [ordered]@{
    Tool = $Tool; SessionId = $sessionId; TurnId = $turnId; StartedAtUtc = [DateTime]::UtcNow.ToString('o')
    BaselineSeconds = $baseline; LastWarnedThreshold = [int]([math]::Floor($baseline / 1800) * 30)
  }
  Save-State $state $path
  Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-Tool', $Tool, '-Mode', 'Watch', '-StatePath', $path) | Out-Null
  exit 0
}

if ($eventName -eq 'Stop' -and (Test-Path -LiteralPath $path -PathType Leaf)) {
  $state = Get-Content -LiteralPath $path -Raw -Encoding utf8 | ConvertFrom-Json
  $ended = [DateTime]::UtcNow
  $activeSeconds = [math]::Max(0, [math]::Round(($ended - [DateTime]::Parse($state.StartedAtUtc)).TotalSeconds))
  $total = [double]$state.BaselineSeconds + $activeSeconds
  [PSCustomObject]@{
    Tool = $Tool; SessionId = $sessionId; TurnId = $turnId; StartedAtUtc = $state.StartedAtUtc; EndedAtUtc = $ended.ToString('o')
    ActiveSeconds = $activeSeconds; CumulativeSeconds = [math]::Round($total); CumulativeMinutes = [math]::Round($total / 60, 1)
  } | Export-Csv -LiteralPath $log -NoTypeInformation -Append
  Remove-Item -LiteralPath $path -Force
}
