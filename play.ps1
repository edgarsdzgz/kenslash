<#
.SYNOPSIS
    Launch the Sword Slash project without opening the Godot editor.

.DESCRIPTION
    Default (no args): imports if needed, then runs the game in a window so you
    can play-test immediately. Also supports running the headless smoke test,
    forcing a reimport, running a specific scene, or opening the editor GUI.

    If the Godot binary moves, edit $GodotCandidates below (add the new path).

.EXAMPLE
    .\play.ps1                 # play the game in a window (default)
    .\play.ps1 -Test           # run the headless smoke test, report pass/fail
    .\play.ps1 -Scene res://player/player.tscn   # run just one scene
    .\play.ps1 -Import         # force a reimport, then play
    .\play.ps1 -Editor         # open the editor GUI for this project
#>
[CmdletBinding()]
param(
    [switch]$Test,
    [switch]$Import,
    [switch]$Editor,
    [string]$Scene
)

$ErrorActionPreference = 'Stop'

# --- Locate the Godot binary (first existing candidate wins) -----------------
# Add new locations here if you move the exe out of Downloads.
$GodotCandidates = @(
    'C:\Users\ediaz\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64.exe',
    'C:\Tools\Godot\Godot_v4.7.1-stable_win64.exe',
    'C:\Program Files\Godot\Godot_v4.7.1-stable_win64.exe'
)

$GodotExe = $null
foreach ($c in $GodotCandidates) {
    if (Test-Path $c) { $GodotExe = $c; break }
}
if (-not $GodotExe) {
    Write-Host "[ERROR] Godot binary not found. Checked:" -ForegroundColor Red
    $GodotCandidates | ForEach-Object { Write-Host "  $_" }
    Write-Host "Edit `$GodotCandidates at the top of this script to point at your Godot exe."
    exit 1
}

# Console variant (blocks in PowerShell and returns a real exit code) for -Test.
$GodotConsole = $GodotExe -replace '_win64\.exe$', '_win64_console.exe'
if (-not (Test-Path $GodotConsole)) { $GodotConsole = $GodotExe }

# Project dir = the folder this script lives in.
$ProjectDir = $PSScriptRoot

Write-Host "Godot:   $GodotExe"
Write-Host "Project: $ProjectDir"
Write-Host ""

# --- Import first if requested or if .godot/ is missing ----------------------
$needsImport = $Import -or (-not (Test-Path (Join-Path $ProjectDir '.godot')))
if ($needsImport) {
    Write-Host "[import] Building import cache (--import)..." -ForegroundColor Cyan
    & $GodotConsole --headless --path $ProjectDir --import
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] Import failed (exit $LASTEXITCODE). Fix errors before running." -ForegroundColor Red
        exit $LASTEXITCODE
    }
    Write-Host "[import] OK" -ForegroundColor Green
    Write-Host ""
}

# --- Modes -------------------------------------------------------------------
if ($Test) {
    Write-Host "[test] Running headless smoke test..." -ForegroundColor Cyan
    & $GodotConsole --headless --path $ProjectDir -s "res://tests/smoke_slash.gd"
    $code = $LASTEXITCODE
    Write-Host ""
    if ($code -eq 0) {
        Write-Host "[test] PASS (exit 0)" -ForegroundColor Green
    } else {
        Write-Host "[test] FAIL (exit $code)" -ForegroundColor Red
    }
    exit $code
}

if ($Editor) {
    Write-Host "[editor] Opening the Godot editor GUI for this project..." -ForegroundColor Cyan
    & $GodotExe -e --path $ProjectDir
    exit $LASTEXITCODE
}

# Default: play the game in a window. -Scene runs a specific scene instead.
if ($Scene) {
    Write-Host "[play] Running scene: $Scene   (close the window to quit)" -ForegroundColor Cyan
    & $GodotExe --path $ProjectDir $Scene
} else {
    Write-Host "[play] Launching game -- WASD/arrows move, Space/J attack. Close window to quit." -ForegroundColor Cyan
    & $GodotExe --path $ProjectDir
}
exit $LASTEXITCODE
