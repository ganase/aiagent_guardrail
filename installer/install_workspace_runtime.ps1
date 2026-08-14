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
# saves its per-machine choice under the package root. Carry that choice into
# the installed launcher, whose scripts read <WorkspaceRoot>\config.
$sourceBoxConfig = Join-Path $PackageRoot 'config\box_mount.local.cmd'
if (Test-Path -LiteralPath $sourceBoxConfig -PathType Leaf) {
  Copy-Item -LiteralPath $sourceBoxConfig -Destination (Join-Path $configRoot 'box_mount.local.cmd') -Force
  Write-Output "Shared-drive configuration installed: $configRoot"
}
Write-Output "Workspace runtime installed: $WorkspaceRoot"