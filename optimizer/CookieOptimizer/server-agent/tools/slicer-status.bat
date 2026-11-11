@echo off
rem Cookie Slicer status: state + last minute's numbers + last log lines. Changes nothing.
rem In game (admin): !slice
cd /d "%~dp0"
echo.
if exist "%~dp0CookieSlicer_status.txt" (
    type "%~dp0CookieSlicer_status.txt"
) else (
    echo No status file yet - it comes with agent v4. Mode file says:
    if exist "%~dp0CookieSlicer.mode" (type "%~dp0CookieSlicer.mode") else (echo   no mode file = ON)
)
if exist "%~dp0CookieSlicer.off" echo CookieSlicer.off exists = always OFF
echo.
echo --- last lines of CookieSlicer.log ---
powershell -NoProfile -Command "Get-Content -LiteralPath '%~dp0CookieSlicer.log' -Tail 3 -Encoding UTF8" 2>nul
echo.
if /i not "%~1"=="nopause" pause
