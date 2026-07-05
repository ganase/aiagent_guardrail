param(
  [string]$InstallRoot
)
$ErrorActionPreference = "Stop"
if (-not $InstallRoot) {
  $InstallRoot = $env:AIAGENT_GUARDRAIL_HOME
  if (-not $InstallRoot) { $InstallRoot = Join-Path $env:ProgramFiles "AIAgentGuardrails" }
}
Write-Host "Uninstall target: $InstallRoot"
if (Test-Path $InstallRoot) {
  Remove-Item -Path $InstallRoot -Recurse -Force
  Write-Host "Removed: $InstallRoot"
}
[Environment]::SetEnvironmentVariable("AIAGENT_GUARDRAIL_HOME", $null, "User")
Write-Host "User environment AIAGENT_GUARDRAIL_HOME removed."
Write-Host "Claude/Codex側の既存設定は安全のため自動削除しません。必要に応じてバックアップを確認して手動で戻してください。"
