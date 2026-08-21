param(
  [string]$InstallRoot,
  [string]$UserProfile,
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

function Find-PythonExe {
  function Test-PythonExe([string]$Candidate) {
    if (-not $Candidate -or -not (Test-Path -LiteralPath $Candidate -PathType Leaf)) { return $false }
    try {
      $version = & $Candidate --version 2>$null
      return ($LASTEXITCODE -eq 0 -and "$version" -match '^Python\s+\d+\.\d+')
    } catch { return $false }
  }
  foreach ($name in @('python', 'python3')) {
    $command = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    # App Execution Alias can exist as python.exe but only opens Microsoft Store.
    # Treat it as installed only when --version succeeds and identifies Python.
    if ($command -and (Test-PythonExe $command.Source)) {
      return (Resolve-Path -LiteralPath $command.Source).Path
    }
  }

  $pythonRoot = Join-Path $env:LOCALAPPDATA 'Programs\Python'
  if (Test-Path -LiteralPath $pythonRoot -PathType Container) {
    $candidates = @()
    foreach ($directory in Get-ChildItem -LiteralPath $pythonRoot -Directory -ErrorAction SilentlyContinue) {
      $candidate = Join-Path $directory.FullName 'python.exe'
      if ((Test-PythonExe $candidate) -and ($candidate -notmatch '(?i)[\\/](?:\.venv|venv)[\\/]')) { $candidates += $candidate }
    }
    if ($candidates.Count -gt 0) {
      $selected = $candidates | Sort-Object -Descending | Select-Object -First 1
      return (Resolve-Path -LiteralPath $selected).Path
    }
  }
  return $null
}

function Add-PathEntries {
  param(
    [Parameter(Mandatory = $true)][string[]]$Entries,
    [ValidateSet('User', 'Process')][string]$Scope
  )
  $currentPath = if ($Scope -eq 'User') { [Environment]::GetEnvironmentVariable('Path', 'User') } else { $env:Path }
  $parts = @($currentPath -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  $normalized = @{}
  foreach ($part in $parts) {
    $normalized[[Environment]::ExpandEnvironmentVariables($part).TrimEnd('\').ToLowerInvariant()] = $true
  }
  foreach ($entry in $Entries) {
    $key = $entry.TrimEnd('\').ToLowerInvariant()
    if (-not $normalized.ContainsKey($key)) { $parts += $entry; $normalized[$key] = $true }
  }
  $updatedPath = $parts -join ';'
  if ($Scope -eq 'User') { [Environment]::SetEnvironmentVariable('Path', $updatedPath, 'User') } else { $env:Path = $updatedPath }
}

function Add-PythonToUserPath {
  param([Parameter(Mandatory = $true)][string]$PythonExe)
  $pythonDir = Split-Path -Parent $PythonExe
  $scriptsDir = Join-Path $pythonDir 'Scripts'
  Add-PathEntries -Entries @($pythonDir, $scriptsDir) -Scope User
  Add-PathEntries -Entries @($pythonDir, $scriptsDir) -Scope Process
  Write-Host "Python User and process PATH entries configured: $pythonDir; $scriptsDir"
}

# Merge only the managed Codex [windows] settings, preserving auth/model settings.
function Set-CodexWindowsSection {
  param([Parameter(Mandatory = $true)][string]$ConfigPath, [Parameter(Mandatory = $true)][string]$TemplatePath)
  $marker = "# --- AI Agent Guardrail: sandbox settings (managed automatically, do not edit below) ---"
  $templateRaw = Get-Content $TemplatePath -Raw
  $windowsIdx = $templateRaw.IndexOf("[windows]")
  if ($windowsIdx -lt 0) { throw "Template does not contain a [windows] section: $TemplatePath" }
  $newBlock = "$marker
$($templateRaw.Substring($windowsIdx).TrimEnd())
"
  if (Test-Path $ConfigPath) {
    Copy-Item $ConfigPath "$ConfigPath.bak.$(Get-Date -Format yyyyMMddHHmmssfff)"
    $existing = Get-Content $ConfigPath -Raw
    if ($existing -match [regex]::Escape($marker)) {
      $existing = [regex]::Replace($existing, [regex]::Escape($marker) + '(?s).*?(?=\r?\n\[(?!windows\])|\z)', '')
    } else {
      $existing = [regex]::Replace($existing, '(?ms)^\[windows\].*?(?=^\[|\z)', '')
    }
    $existing = $existing.TrimEnd()
    $final = if ($existing) { "$existing

$newBlock" } else { $newBlock }
  } else { $final = $newBlock }
  Set-Content -Path $ConfigPath -Encoding UTF8 -Value $final -NoNewline
}
$IsAdmin = Test-IsAdmin
if (-not $UserProfile) { $UserProfile = $env:USERPROFILE }
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
    icacls $InstallRoot /inheritance:d /grant "BUILTIN\Administrators:(OI)(CI)F" /grant "NT AUTHORITY\SYSTEM:(OI)(CI)F" /grant "BUILTIN\Users:(OI)(CI)RX" /T /Q 2>&1 | Out-Null
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

$PythonExe = Find-PythonExe
if (-not $PythonExe) {
  throw "Python was not found. Install python/python3 on PATH or %LOCALAPPDATA%\Programs\Python\<version>\python.exe."
}
Add-PythonToUserPath -PythonExe $PythonExe

# Validate allowlist
& $PythonExe (Join-Path $InstallRoot "hooks\validate_allowlist.py") | Write-Host

# Keep operational logs outside the integrity manifest. The install record is
# intentionally appended on every installation and would otherwise make a
# freshly installed manifest appear tampered with.
$LogDir = Join-Path $InstallRoot "logs"
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$Log = Join-Path $LogDir "install_log.csv"
if (-not (Test-Path $Log)) { "timestamp,user,install_root,admin,configure_claude,configure_codex,protected" | Set-Content -Encoding UTF8 $Log }
"$(Get-Date -Format o),$env:USERNAME,`"$InstallRoot`",$IsAdmin,$ConfigureClaude,$ConfigureCodex,$Protected" | Add-Content -Encoding UTF8 $Log

# Hash recording
$HashFile = Join-Path $InstallRoot "config\installed_hashes.csv"
"file,sha256" | Set-Content -Encoding UTF8 $HashFile
Get-ChildItem -Path $InstallRoot -Recurse -File | Where-Object {
  $_.FullName -notlike "*installed_hashes.csv" -and
  $_.FullName -notlike "$LogDir\*"
} | ForEach-Object {
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
  $CodexDir = Join-Path $UserProfile ".codex"
  New-Item -ItemType Directory -Path $CodexDir -Force | Out-Null
  $configTarget = Join-Path $CodexDir "config.toml"
  Set-CodexWindowsSection -ConfigPath $configTarget -TemplatePath (Join-Path $InstallRoot "config\codex_config.template.toml")
  $reqTarget = Join-Path $CodexDir "requirements.toml"
  if (Test-Path $reqTarget) { Copy-Item $reqTarget "$reqTarget.bak.$(Get-Date -Format yyyyMMddHHmmss)" }
  Copy-Item (Join-Path $InstallRoot "config\codex_requirements.template.toml") $reqTarget -Force
  Write-Host "Codex config を配置しました: $CodexDir"
}

if ($AddWrappersToUserPath) {
  $bin = Join-Path $InstallRoot "bin"
  Add-PathEntries -Entries @($bin) -Scope User
  Add-PathEntries -Entries @($bin) -Scope Process
  Write-Host "User and process PATH entries configured: $bin"
}

Write-Host ""
Write-Host "AI Agent Guardrails v0.2 installed."
Write-Host "InstallRoot : $InstallRoot"
Write-Host "ACL保護    : $Protected"
Write-Host "Python      : $PythonExe"
Write-Host "Restart Claude Code completely before use so its Hook receives the updated User PATH."
if (-not $IsAdmin) {
  Write-Warning "非 admin 導入です。ACL保護なし。運用は管理者による正式導入を推奨します。"
}
Write-Host "Next: .\installer\check_status.ps1 -InstallRoot `"$InstallRoot`""
