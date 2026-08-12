#Requires -Version 5.1
<#
.SYNOPSIS
  Box ドライブ自動マウント(mount_box_drive.bat)を Windows スタートアップに登録する。
  admin 不要（ユーザーのスタートアップフォルダにショートカットを配置するだけ）。
  再実行しても重複登録しない（冪等）。
#>
param()

$ErrorActionPreference = "Stop"

# Shared-drive mount is opt-in (installer\box_mount.local.cmd, written by
# configure_box_mount.ps1). If it is absent or disabled, there is nothing to
# register at startup.
$localConfigPath = Join-Path (Split-Path -Parent $PSScriptRoot) "config\box_mount.local.cmd"
if (-not (Test-Path -LiteralPath $localConfigPath -PathType Leaf)) {
    Write-Output "INFO: box_mount.local.cmd が見つかりません。共有ドライブのスタートアップ登録をスキップします。"
    exit 0
}
$boxEnabled = $false
Get-Content -LiteralPath $localConfigPath | ForEach-Object {
    if ($_ -match '^\s*set\s+"BOX_ENABLED=(\d)"') { $boxEnabled = ($Matches[1] -eq '1') }
}
if (-not $boxEnabled) {
    Write-Output "INFO: 共有ドライブの自動マウントは無効化されています。スタートアップ登録をスキップします。"
    exit 0
}

$vbsPath = Join-Path $PSScriptRoot "mount_box_drive_silent.vbs"
if (-not (Test-Path $vbsPath)) {
    Write-Output "ERROR: $vbsPath が見つかりません。installer フォルダから実行してください。"
    exit 1
}

$startupDir   = [Environment]::GetFolderPath("Startup")
$shortcutPath = Join-Path $startupDir "AIAgent_Workspace_BoxDriveMount.lnk"
$wscriptExe   = Join-Path $env:WINDIR "System32\wscript.exe"
$expectedArgs = "`"$vbsPath`""

$needsUpdate = $true
if (Test-Path $shortcutPath) {
    try {
        $wsh = New-Object -ComObject WScript.Shell
        $existing = $wsh.CreateShortcut($shortcutPath)
        if ($existing.TargetPath -ieq $wscriptExe -and $existing.Arguments -ieq $expectedArgs) {
            $needsUpdate = $false
        }
    } catch {
        # Corrupt or unreadable shortcut: fall through and recreate it.
    }
}

if ($needsUpdate) {
    $wsh = New-Object -ComObject WScript.Shell
    $shortcut = $wsh.CreateShortcut($shortcutPath)
    $shortcut.TargetPath       = $wscriptExe
    $shortcut.Arguments        = $expectedArgs
    $shortcut.WorkingDirectory = $PSScriptRoot
    $shortcut.WindowStyle      = 7  # Minimized (defensive; the .vbs itself already runs hidden)
    $shortcut.Description      = "AI Agent Guardrail: Box drive auto-mount at logon"
    $shortcut.Save()
    Write-Output "スタートアップに登録しました: $shortcutPath"
} else {
    Write-Output "スタートアップ登録は既に最新です（スキップ）: $shortcutPath"
}
