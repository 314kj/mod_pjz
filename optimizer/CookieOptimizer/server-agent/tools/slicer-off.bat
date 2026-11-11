@echo off
rem Cookie Slicer OFF (the server runs the game's own way). Writes CookieSlicer.mode next to this file;
rem the agent reads it within 5 s. Does NOT start, stop or restart the server. In game (admin): !offslice
cd /d "%~dp0"
>"%~dp0CookieSlicer.mode" echo(off
echo Cookie Slicer: OFF requested (takes up to 5 s)
timeout /t 7 /nobreak >nul
call "%~dp0slicer-status.bat" nopause
pause
