#Requires -Version 5.1
param(
  [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
  [Parameter(Mandatory = $true)][string]$PackageRoot
)
$ErrorActionPreference = 'Stop'
$WorkspaceRoot = [IO.Path]::GetFullPath($WorkspaceRoot)
$launcherRoot = Join-Path $WorkspaceRoot 'launcher'
$maintenanceRoot = Join-Path $WorkspaceRoot 'maintenance'
$configRoot = Join-Path $WorkspaceRoot 'config'
New-Item -ItemType Directory -Force -Path $launcherRoot, $maintenanceRoot, $configRoot | Out-Null
$sourceInstaller = Join-Path $PackageRoot 'installer'
foreach ($name in @('launch_ai_workspace.bat', 'sync_ai_agent_logs.ps1', 'configure_box_mount.ps1', 'mount_box_drive.bat', 'mount_box_drive_silent.vbs', 'register_box_startup.ps1')) {
  Copy-Item -LiteralPath (Join-Path $sourceInstaller $name) -Destination (Join-Path $launcherRoot $name) -Force
}
foreach ($name in @('check_status.ps1', 'uninstall_standard.ps1', 'uninstall.bat')) {
  Copy-Item -LiteralPath (Join-Path $sourceInstaller $name) -Destination (Join-Path $maintenanceRoot $name) -Force
}
# The initial shared-drive dialog runs before the install location is known and
# saves its choice under the package root. Carry that choice into the
# installed launcher, whose scripts read <WorkspaceRoot>\config -- but only
# when it actually belongs to the user running this install. If the package
# root was copied from another Windows user's already-configured folder (e.g.
# a shared installer package), its TARGET_DIR points at that other user's
# Box path and must not be inherited; leaving the destination config absent
# makes launch_ai_workspace.bat run configure_box_mount.ps1 for this user on
# first launch instead.
$sourceBoxConfig = Join-Path $PackageRoot 'config\box_mount.local.cmd'
if (Test-Path -LiteralPath $sourceBoxConfig -PathType Leaf) {
  $boxEnabled = $null
  $boxTargetDir = $null
  Get-Content -LiteralPath $sourceBoxConfig | ForEach-Object {
    if ($_ -match '^\s*set\s+"BOX_ENABLED=(.*)"\s*$') { $boxEnabled = $Matches[1] }
    if ($_ -match '^\s*set\s+"TARGET_DIR=(.*)"\s*$') { $boxTargetDir = $Matches[1] }
  }
  $currentUserProfile = [System.IO.Path]::GetFullPath($env:USERPROFILE).TrimEnd('\')
  $ownedByCurrentUser = ($boxEnabled -eq '0') -or ($boxTargetDir -and (
      $boxTargetDir -eq $currentUserProfile -or
      $boxTargetDir.StartsWith(($currentUserProfile + '\'), [System.StringComparison]::OrdinalIgnoreCase)))
  if ($ownedByCurrentUser) {
    Copy-Item -LiteralPath $sourceBoxConfig -Destination (Join-Path $configRoot 'box_mount.local.cmd') -Force
    Write-Output "Shared-drive configuration installed: $configRoot"
  } else {
    Write-Output "Shared-drive configuration in the package belongs to a different Windows user; it will be configured on first launch instead."
  }
}
Write-Output "Workspace runtime installed: $WorkspaceRoot"