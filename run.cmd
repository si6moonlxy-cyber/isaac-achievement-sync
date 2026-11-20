@echo off
setlocal
chcp 65001 >nul
set "PSEXE=%SystemRoot%\SysWOW64\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PSEXE%" set "PSEXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PSEXE%" (
    echo Windows PowerShell was not found.
    pause
    exit /b 1
)
"%PSEXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0IsaacAchievements.ps1" %*
set "RESULT=%ERRORLEVEL%"
echo.
if not "%RESULT%"=="0" echo The tool failed. See the error above.
echo Press any key to close this window...
pause >nul
exit /b %RESULT%
