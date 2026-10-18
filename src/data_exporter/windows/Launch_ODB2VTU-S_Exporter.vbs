Option Explicit
Dim shell, fso, baseDir, wrapper, cmd
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

baseDir = fso.GetParentFolderName(WScript.ScriptFullName)

' Launch_Workbench.ps1 validates the UTF-8 BOM and PowerShell 5.1 syntax of
' every .ps1 and then runs the GUI in the same process, so startup spawns only
' one powershell.exe. Validation failures are reported by that script.
wrapper = fso.BuildPath(baseDir, "Launch_Workbench.ps1")
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & wrapper & """"
shell.Run cmd, 0, False
