' Silent launcher for mount_box_drive.bat (used from the Windows Startup folder).
' Runs the batch file with a hidden window so no console flashes at logon.
' Error dialogs from mount_box_drive.bat (msg *) still display, since those are
' shown by a separate process (msg.exe), not the hidden console window itself.

Dim objFSO, objShell, scriptDir, batPath

Set objFSO = CreateObject("Scripting.FileSystemObject")
scriptDir = objFSO.GetParentFolderName(WScript.ScriptFullName)
batPath = objFSO.BuildPath(scriptDir, "mount_box_drive.bat")

Set objShell = CreateObject("WScript.Shell")
objShell.Run """" & batPath & """", 0, True
