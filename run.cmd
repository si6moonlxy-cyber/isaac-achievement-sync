@echo off
setlocal
chcp 65001 >nul
set "PSEXE=%SystemRoot%\SysWOW64\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PSEXE%" set "PSEXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PSEXE%" (
    echo 找不到 Windows PowerShell。
    pause
    exit /b 1
)
"%PSEXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0IsaacAchievements.ps1" %*
set "RESULT=%ERRORLEVEL%"
echo.
if not "%RESULT%"=="0" echo 运行失败，请查看上方错误。
echo 按任意键关闭窗口...
pause >nul
exit /b %RESULT%
