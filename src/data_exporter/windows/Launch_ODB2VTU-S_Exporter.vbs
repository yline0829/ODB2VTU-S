Option Explicit
Dim shell, fso, baseDir, ps1, cmd, check, status
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

baseDir = fso.GetParentFolderName(WScript.ScriptFullName)
ps1 = fso.BuildPath(baseDir, "ODB2VTU-S_Exporter.ps1")

check = fso.BuildPath(baseDir, "Check_PS51_Syntax.ps1")
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & check & """"
status = shell.Run(cmd, 0, True)
If status <> 0 Then
    MsgBox "Startup validation failed. Please run Launch_ODB2VTU-S_Exporter_Debug.cmd and share the displayed error.", vbCritical, "ODB2VTU-S Startup Check"
    WScript.Quit status
End If
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & ps1 & """"
shell.Run cmd, 0, False
