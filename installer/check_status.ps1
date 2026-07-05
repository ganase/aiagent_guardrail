param(
  [string]$InstallRoot
)
$ErrorActionPreference = "Continue"
if (-not $InstallRoot) {
  $InstallRoot = $env:AIAGENT_GUARDRAIL_HOME
  if (-not $InstallRoot) { $InstallRoot = Join-Path $env:ProgramFiles "AIAgentGuardrails" }
}
Write-Host "AI Agent Guardrail status"
Write-Host "InstallRoot: $InstallRoot"
$paths = @(
  "config\manifest.json",
  "config\guardrail_policy.json",
  "config\package_allowlist.json",
  "config\runtime_policy.json",
  "hooks\aiagent_guardrail_check.py",
  "hooks\validate_allowlist.py",
  "bin\ai-pip.ps1",
  "bin\ai-npm.ps1"
)
foreach ($p in $paths) {
  $full = Join-Path $InstallRoot $p
  if (Test-Path $full) { Write-Host "OK   $p" }
  else { Write-Host "NG   $p" -ForegroundColor Red }
}
Write-Host ""
Write-Host "Allowlist validation:"
python (Join-Path $InstallRoot "hooks\validate_allowlist.py")
Write-Host ""
Write-Host "Guardrail sample checks:"
python (Join-Path $InstallRoot "hooks\aiagent_guardrail_check.py") --command "pip install pandas"
python (Join-Path $InstallRoot "hooks\aiagent_guardrail_check.py") --command "pip install unknown-package-for-test"
Write-Host ""
$claude = Join-Path $env:ProgramFiles "ClaudeCode\managed-settings.json"
if (Test-Path $claude) { Write-Host "OK   Claude managed-settings: $claude" } else { Write-Host "INFO Claude managed-settings not found: $claude" }
$codex = Join-Path $env:USERPROFILE ".codex\config.toml"
if (Test-Path $codex) { Write-Host "OK   Codex config: $codex" } else { Write-Host "INFO Codex config not found: $codex" }
