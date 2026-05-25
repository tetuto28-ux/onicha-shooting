@echo off
cd /d "%~dp0"
"%~dp0..\tools\rojo\rojo.exe" serve default.project.json --port 34872
