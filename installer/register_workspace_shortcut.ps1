#Requires -Version 5.1
<#
.SYNOPSIS
  Coding Agent for IT ランチャーのショートカットをデスクトップとスタートメニューに作成または
  更新し、タスクバーへのピン留めを試みる。
#>
param([Parameter(Mandatory = $true)][string]$WorkspaceRoot, [string]$DesktopPath)

$ErrorActionPreference = "Stop"
$WorkspaceRoot = [IO.Path]::GetFullPath($WorkspaceRoot)
$launcherPath = Join-Path $WorkspaceRoot "launcher\launch_ai_workspace.bat"
if (-not (Test-Path -LiteralPath $launcherPath -PathType Leaf)) {
    throw "Workspace launcher was not found: $launcherPath"
}

$shortcutName = "Coding Agent for IT.lnk"
$legacyShortcutNames = @("AI Coding Workspace.lnk", "AI Agent Workspace.lnk", "Coding Agent@IT.lnk")

$desktopPath   = if ($DesktopPath) { [IO.Path]::GetFullPath($DesktopPath) } else { [Environment]::GetFolderPath("Desktop") }
$startMenuPath = [Environment]::GetFolderPath("StartMenu")

function New-WorkspaceShortcut {
    param([Parameter(Mandatory = $true)][string]$Directory)
    New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    $path = Join-Path $Directory $shortcutName
    $wsh = New-Object -ComObject WScript.Shell
    $shortcut = $wsh.CreateShortcut($path)
    $shortcut.TargetPath = $env:ComSpec
    $shortcut.Arguments = '/k ""{0}""' -f $launcherPath
    $shortcut.WorkingDirectory = $WorkspaceRoot
    $shortcut.IconLocation = "$env:SystemRoot\System32\shell32.dll,135"
    $shortcut.Description = "Coding Agent for IT を開く"
    $shortcut.Save()
    return $path
}

# The shortcut was renamed (possibly more than once). Remove old names from
# both locations so a rerun does not leave stale launchers behind.
foreach ($dir in @($desktopPath, $startMenuPath)) {
    foreach ($legacyName in $legacyShortcutNames) {
        $legacyPath = Join-Path $dir $legacyName
        if (Test-Path -LiteralPath $legacyPath) {
            Remove-Item -LiteralPath $legacyPath -Force
        }
    }
}

$desktopShortcutPath = New-WorkspaceShortcut -Directory $desktopPath
Write-Output "デスクトップショートカットを作成しました: $desktopShortcutPath"

$startMenuShortcutPath = New-WorkspaceShortcut -Directory $startMenuPath
Write-Output "スタートメニューショートカットを作成しました: $startMenuShortcutPath"

# Versions before the unified workspace launcher created these two direct
# launchers from the setup wizard. Remove only those known legacy links so a
# rerun leaves one clear entry point and users reach the tool-selection menu.
foreach ($legacyName in @("Claude Code.lnk", "Codex.lnk")) {
    foreach ($dir in @($desktopPath, $startMenuPath)) {
        $legacyPath = Join-Path $dir $legacyName
        if (Test-Path -LiteralPath $legacyPath -PathType Leaf) {
            Remove-Item -LiteralPath $legacyPath -Force
        }
    }
}

# Best-effort taskbar pin. Windows has no supported public API for this, and
# recent Windows 11 builds have progressively removed the underlying shell
# verb entirely (to stop adware from auto-pinning), so this can silently do
# nothing on newer builds. A failure here must never fail the whole setup.
try {
    $shellApp = New-Object -ComObject Shell.Application
    $folder = $shellApp.Namespace((Split-Path -Parent $desktopShortcutPath))
    $item = $folder.ParseName((Split-Path -Leaf $desktopShortcutPath))
    $item.InvokeVerb("taskbarpin")
    Write-Output "タスクバーへのピン留めを実行しました（反映されない場合はお手数ですが手動でピン留めしてください）。"
} catch {
    Write-Output "WARNING: タスクバーへの自動ピン留めに失敗しました。この Windows のバージョンでは対応していない可能性があります。お手数ですが手動でピン留めしてください（$($_.Exception.Message)）。"
}
