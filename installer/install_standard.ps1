param(
  [string]$InstallRoot,
  [switch]$ConfigureClaude,
  [switch]$ConfigureCodex,
  [switch]$AddWrappersToUserPath
)
$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PackageRoot = Split-Path -Parent $ScriptDir

function Test-IsAdmin {
  $current = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($current)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

$IsAdmin = Test-IsAdmin
if (-not $InstallRoot) {
  if ($IsAdmin) { $InstallRoot = Join-Path $env:ProgramFiles "AIAgentGuardrails" }
  else { $InstallRoot = Join-Path $env:LOCALAPPDATA "AIAgentGuardrails" }
}

New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
Copy-Item -Path (Join-Path $PackageRoot "guardrails\*") -Destination $InstallRoot -Recurse -Force

# C. ACL protection: Users get ReadAndExecute only; Administrators/SYSTEM get FullControl.
# This prevents users from replacing guardrail_policy.json or package_allowlist.json.
$Protected = $false
if ($IsAdmin) {
  try {
    icacls $InstallRoot /inheritance:d /grant "BUILTIN\Administrators:(OI)(CI)F" /grant "NT AUTHORITY\SYSTEM:(OI)(CI)F" /deny "BUILTIN\Users:(OI)(CI)W" /T /Q 2>&1 | Out-Null
    $Protected = $true
    Write-Host "ACL設定完了: Users の書込権限を制限しました ($InstallRoot)"
  } catch {
    Write-Warning "ACL設定に失敗しました（スキップ）: $_"
  }
} else {
  Write-Warning "管理者権限がないためACL保護を設定できません。非 admin 導入は評価用途限定です。設定ファイルはユーザーが変更可能な状態です。"
}

[Environment]::SetEnvironmentVariable('AIAGENT_GUARDRAIL_HOME', $InstallRoot, 'User')
$env:AIAGENT_GUARDRAIL_HOME = $InstallRoot

# Validate allowlist
python (Join-Path $InstallRoot "hooks\validate_allowlist.py") | Write-Host

# Hash recording
$HashFile = Join-Path $InstallRoot "config\installed_hashes.csv"
"file,sha256" | Set-Content -Encoding UTF8 $HashFile
Get-ChildItem -Path $InstallRoot -Recurse -File | Where-Object { $_.FullName -notlike "*installed_hashes.csv" } | ForEach-Object {
  $hash = Get-FileHash -Algorithm SHA256 $_.FullName
  $rel = $_.FullName.Substring($InstallRoot.Length).TrimStart('\')
  "`"$rel`",$($hash.Hash)" | Add-Content -Encoding UTF8 $HashFile
}

if ($ConfigureClaude) {
  $ClaudeDir = Join-Path $env:ProgramFiles "ClaudeCode"
  if (-not $IsAdmin) {
    Write-Warning "管理者権限がないため、Claude Code managed-settings のシステム配置はスキップします。"
  } else {
    New-Item -ItemType Directory -Path $ClaudeDir -Force | Out-Null
    $template = Join-Path $InstallRoot "config\claude_managed_settings.template.json"
    $target = Join-Path $ClaudeDir "managed-settings.json"
    if (Test-Path $target) {
      Copy-Item $target "$target.bak.$(Get-Date -Format yyyyMMddHHmmss)"
    }
    $content = Get-Content $template -Raw
    # Replace placeholder with JSON-escaped path (backslash -> double backslash for JSON)
    $escapedRoot = $InstallRoot.Replace("\", "\\")
    $content = $content.Replace("%AIAGENT_GUARDRAIL_HOME%", $escapedRoot)
    Set-Content -Path $target -Encoding UTF8 -Value $content
    Write-Host "Claude Code managed-settings を配置しました: $target"
    Write-Host "Hook コマンドは run_guardrail_hook.cmd 経由（fail-closed）に変更済みです。"
  }
}

if ($ConfigureCodex) {
  $CodexDir = Join-Path $env:USERPROFILE ".codex"
  New-Item -ItemType Directory -Path $CodexDir -Force | Out-Null
  $configTarget = Join-Path $CodexDir "config.toml"
  if (Test-Path $configTarget) { Copy-Item $configTarget "$configTarget.bak.$(Get-Date -Format yyyyMMddHHmmss)" }
  Copy-Item (Join-Path $InstallRoot "config\codex_config.template.toml") $configTarget -Force
  $reqTarget = Join-Path $CodexDir "requirements.toml"
  if (Test-Path $reqTarget) { Copy-Item $reqTarget "$reqTarget.bak.$(Get-Date -Format yyyyMMddHHmmss)" }
  Copy-Item (Join-Path $InstallRoot "config\codex_requirements.template.toml") $reqTarget -Force
  Write-Host "Codex config を配置しました: $CodexDir"
}

if ($AddWrappersToUserPath) {
  $bin = Join-Path $InstallRoot "bin"
  $currentPath = [Environment]::GetEnvironmentVariable('Path', 'User')
  if ($currentPath -notlike "*$bin*") {
    [Environment]::SetEnvironmentVariable('Path', "$currentPath;$bin", 'User')
    Write-Host "User PATH に追加しました: $bin"
  }
}

$LogDir = Join-Path $InstallRoot "logs"
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$Log = Join-Path $LogDir "install_log.csv"
if (-not (Test-Path $Log)) { "timestamp,user,install_root,admin,configure_claude,configure_codex,protected" | Set-Content -Encoding UTF8 $Log }
"$(Get-Date -Format o),$env:USERNAME,`"$InstallRoot`",$IsAdmin,$ConfigureClaude,$ConfigureCodex,$Protected" | Add-Content -Encoding UTF8 $Log

Write-Host ""
Write-Host "AI Agent Guardrails v0.2 installed."
Write-Host "InstallRoot : $InstallRoot"
Write-Host "ACL保護    : $Protected"
if (-not $IsAdmin) {
  Write-Warning "非 admin 導入です。ACL保護なし。運用は管理者による正式導入を推奨します。"
}
Write-Host "Next: .\installer\check_status.ps1 -InstallRoot `"$InstallRoot`""
