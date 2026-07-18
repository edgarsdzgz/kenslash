@echo off
REM Double-click this to play Sword Slash without opening the Godot editor.
REM It just runs play.ps1 (bypassing the PS execution-policy prompt).
REM Pass args through too, e.g.:  play.cmd -Test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0play.ps1" %*
