@echo off

cd /d "%~dp0"
pwsh -ExecutionPolicy Bypass -File "%~dp0mkv_dut.ps1"
rem pwsh -ExecutionPolicy Bypass -Command ". %~dp0mkv_dut.ps1"
rem pwsh -ExecutionPolicy Bypass -NoLogo -NoProfile -Command "& { . '%~dp0mkv_dut.ps1' }"
pause
