@echo off
setlocal EnableExtensions
chcp 65001 >nul
set /p PVD=Paste the full path to the original PVD: 
if not exist "%PVD%" (
 echo [ERROR] PVD not found. Do not delete any rollback files.
 pause
 exit /b 1
)
for %%F in ("%PVD%") do set "DIR=%%~dpF"& set "STEM=%%~nF"
set "JOURNAL=%DIR%%STEM%_frames\_ODB2VTUS_INPLACE_JOURNAL.json"
if not exist "%JOURNAL%" (
 echo [INFO] No interrupted export journal exists for this PVD.
 pause
 exit /b 0
)
echo [WARNING] This will either roll back an incomplete update or clean a fully published update.
echo Journal: "%JOURNAL%"
choice /c YN /m "Proceed with recovery"
if errorlevel 2 exit /b 2
call abaqus python "%~dp0odb_inplace_transaction.py" --restore "%JOURNAL%"
if errorlevel 1 (
 echo [ERROR] Recovery failed. Preserve all .odb2vtus_rollback_* files and journal.
 pause
 exit /b 1
)
echo [OK] Recovery/cleanup complete.
pause
