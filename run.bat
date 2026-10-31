@echo off
:: run.bat — launch Las Tormentas from the correct working directory.
:: Double-click this file (or run it from any terminal) to start an instance.
:: The default build runs without Steam. See docs/STEAMWORKS.md for co-op setup.
cd /d "%~dp0"
start "" bin\tormentas.exe
