@echo off
set ROOT=%~dp0
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%build.ps1" %*
exit /b %ERRORLEVEL%
