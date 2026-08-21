#Requires -Version 5.1
<#
.SYNOPSIS
  Auto-approves requests defined in safe_approval_policy.json.

.DESCRIPTION
  The script makes no decision when the policy is absent, disabled, invalid, or
  does not match. The native Codex/Claude approval flow then remains in effect.
#>
param([Parameter(Mandatory = $true)][ValidateSet('Codex', 'ClaudeCode')][string]$Tool)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$policyPath = Join-Path $PSScriptRoot '..\config\safe_approval_policy.json'
try {
  $policy = Get-Content -LiteralPath $policyPath -Raw -Encoding utf8 | ConvertFrom-Json
  if (-not $policy.enabled -or -not $policy.read_only_tools -or -not $policy.safe_bash_patterns -or -not $policy.protected_path_patterns) { exit 0 }
} catch { exit 0 }

$inputText = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($inputText)) { exit 0 }
try { $event = $inputText | ConvertFrom-Json } catch { exit 0 }
$eventName = if ($event.hook_event_name) { [string]$event.hook_event_name } else { [string]$event.hookEventName }
if ($eventName -ne 'PermissionRequest') { exit 0 }
$toolName = [string]$event.tool_name

function Approve-Request {
  [PSCustomObject]@{ hookSpecificOutput = [PSCustomObject]@{ hookEventName = 'PermissionRequest'; decision = [PSCustomObject]@{ behavior = 'allow' } } } | ConvertTo-Json -Compress
}

if ($toolName -in @($policy.read_only_tools)) {
  $inputJson = ($event.tool_input | ConvertTo-Json -Compress -Depth 10).ToLowerInvariant()
  if (@($policy.protected_path_patterns | Where-Object { $inputJson -match $_ })) { exit 0 }
  Approve-Request
  exit 0
}

if ($toolName -ne 'Bash') { exit 0 }
$command = [string]$event.tool_input.command
if ([string]::IsNullOrWhiteSpace($command) -or $command -match '[;&|><`$]' -or $command -match '\r|\n') { exit 0 }
if (-not @($policy.safe_bash_patterns | Where-Object { $command -match $_ })) { exit 0 }
Approve-Request
