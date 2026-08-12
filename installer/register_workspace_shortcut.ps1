#Requires -Version 5.1
<#
.SYNOPSIS
  AI Agent Workspace ランチャーのデスクトップショートカットを作成または更新する。
#>
param([Parameter(Mandatory = $true)][string]$WorkspaceRoot)

$ErrorActionPreference = "Stop"
$WorkspaceRoot = [IO.Path]::GetFullPath($WorkspaceRoot)
$launcherPath = Join-Path $WorkspaceRoot "launcher\launch_ai_workspace.bat"
if (-not (Test-Path -LiteralPath $launcherPath -PathType Leaf)) {
    throw "Workspace launcher was not found: $launcherPath"
}

$desktopPath = [Environment]::GetFolderPath("Desktop")
$shortcutPath = Join-Path $desktopPath "AI Agent Workspace.lnk"
$legacyShortcutPath = Join-Path $desktopPath "AI Coding Workspace.lnk"

# The shortcut was renamed. Remove the old one so a rerun does not leave two
# launchers on the desktop.
if (Test-Path -LiteralPath $legacyShortcutPath) {
    Remove-Item -LiteralPath $legacyShortcutPath -Force
}
$wsh = New-Object -ComObject WScript.Shell
$shortcut = $wsh.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $env:ComSpec
$shortcut.Arguments = '/k ""{0}""' -f $launcherPath
$shortcut.WorkingDirectory = $WorkspaceRoot
$shortcut.IconLocation = "$env:SystemRoot\System32\shell32.dll,135"
$shortcut.Description = "Box 上の AI Agent Workspace を開く"
$shortcut.Save()

# Versions before the unified workspace launcher created these two direct
# launchers from the setup wizard. Remove only those known legacy links so a
# rerun leaves one clear entry point and users reach the tool-selection menu.
foreach ($legacyName in @("Claude Code.lnk", "Codex.lnk")) {
    $legacyPath = Join-Path $desktopPath $legacyName
    if (Test-Path -LiteralPath $legacyPath -PathType Leaf) {
        Remove-Item -LiteralPath $legacyPath -Force
    }
}

Write-Output "デスクトップショートカットを作成しました: $shortcutPath"