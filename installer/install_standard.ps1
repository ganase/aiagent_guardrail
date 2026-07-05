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

[Environment]::SetEnvironmentVariable("AIAGENT_GUARDRAIL_HOME", $InstallRoot, "User")
$env:AIAGENT_GUARDRAIL_HOME = $InstallRoot

# 検証
python (Join-Path $InstallRoot "hooks\validate_allowlist.py") | Write-Host

# ハッシュ記録
$HashFile = Join-Path $InstallRoot "config\installed_hashes.csv"
"file,sha256" | Set-Content -Encoding UTF8 $HashFile
Get-ChildItem -Path $InstallRoot -Recurse -File | Where-Object { $_.FullName -notlike "*$HashFile" } | ForEach-Object {
  $hash = Get-FileHash -Algorithm SHA256 $_.FullName
  $rel = $_.FullName.Substring($InstallRoot.Length).TrimStart('\\')
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
    $content = $content.Replace("%AIAGENT_GUARDRAIL_HOME%", $InstallRoot.Replace("\", "\\"))
    Set-Content -Path $target -Encoding UTF8 -Value $content
    Write-Host "Claude Code managed-settings を配置しました: $target"
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
  $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
  if ($currentPath -notlike "*$bin*") {
    [Environment]::SetEnvironmentVariable("Path", "$currentPath;$bin", "User")
    Write-Host "User PATH に追加しました: $bin"
  }
}

$LogDir = Join-Path $InstallRoot "logs"
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$Log = Join-Path $LogDir "install_log.csv"
if (-not (Test-Path $Log)) { "timestamp,user,install_root,admin,configure_claude,configure_codex" | Set-Content -Encoding UTF8 $Log }
"$(Get-Date -Format o),$env:USERNAME,`"$InstallRoot`",$IsAdmin,$ConfigureClaude,$ConfigureCodex" | Add-Content -Encoding UTF8 $Log

Write-Host ""
Write-Host "AI Agent Guardrails installed."
Write-Host "InstallRoot: $InstallRoot"
Write-Host "Next: .\installer\check_status.ps1 -InstallRoot `"$InstallRoot`""
