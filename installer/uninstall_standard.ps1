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
  try {
    Remove-Item -Path $InstallRoot -Recurse -Force
    Write-Host "Removed: $InstallRoot"
  } catch {
    Write-Warning "削除に失敗しました: $_"
    Write-Warning "ACL保護が残っている場合は、管理者権限で次を実行してから再試行してください: icacls `"$InstallRoot`" /reset /T /Q"
    throw
  }
}
[Environment]::SetEnvironmentVariable("AIAGENT_GUARDRAIL_HOME", $null, "User")
Write-Host "User environment AIAGENT_GUARDRAIL_HOME removed."
Write-Host "Claude/Codex側の既存設定は安全のため自動削除しません。必要に応じてバックアップを確認して手動で戻してください。"
