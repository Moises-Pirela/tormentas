@echo off
:: run.bat — launch Las Tormentas from the correct working directory.
:: Double-click this file (or run it from any terminal) to start an instance.
:: For local P2P testing, open two File Explorer windows and double-click
:: this file in each — the first becomes the host (click HOST GAME),
:: the second becomes the joiner (click JOIN GAME, enter 127.0.0.1).
cd /d "%~dp0"
start "" bin\tormentas.exe
