@echo off
rem Cookie Slicer ON. Writes CookieSlicer.mode next to this file; the agent reads it within 5 s.
rem Does NOT start, stop or restart the server. In game (admin): !onslice
cd /d "%~dp0"
>"%~dp0CookieSlicer.mode" echo(on
echo Cookie Slicer: ON requested (takes up to 5 s)
if exist "%~dp0CookieSlicer.off" echo NOTE: CookieSlicer.off exists and keeps it OFF. Delete that file to turn it on.
timeout /t 7 /nobreak >nul
call "%~dp0slicer-status.bat" nopause
pause
