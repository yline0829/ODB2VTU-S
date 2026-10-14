@echo off
setlocal
title ODB2VTU-S Exporter - Debug Launcher
echo ============================================================
echo ODB2VTU-S v0.2.0 - Windows Debug Launcher
echo ============================================================
echo Status: STARTING GUI via PowerShell...
echo If the GUI takes time to appear, leave this window open.
echo Export jobs open a separate CMD window with progress messages.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0ODB2VTU-S_Exporter.ps1"
set "EXITCODE=%errorlevel%"
echo.
if not "%EXITCODE%"=="0" (
 echo GUI exited with error code %EXITCODE%.
) else (
 echo GUI closed normally.
)
echo Press any key to close this debug window...
pause >nul
endlocal
