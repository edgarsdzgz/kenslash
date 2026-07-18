#!/usr/bin/env bash
# Launch the Sword Slash project without opening the Godot editor.
#   play.sh            play the game in a window (default)
#   play.sh --test     run the headless smoke test, report pass/fail
#   play.sh --import   force a reimport, then play
#   play.sh --editor   open the editor GUI for this project
#   play.sh --scene res://player/player.tscn   run just one scene
# If the Godot binary moves, add its path to GODOT_CANDIDATES below.
set -uo pipefail

GODOT_CANDIDATES=(
  "/c/Users/ediaz/Downloads/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64.exe"
  "/c/Tools/Godot/Godot_v4.7.1-stable_win64.exe"
  "/c/Program Files/Godot/Godot_v4.7.1-stable_win64.exe"
)
GODOT=""
for c in "${GODOT_CANDIDATES[@]}"; do
  if [[ -f "$c" ]]; then GODOT="$c"; break; fi
done
if [[ -z "$GODOT" ]]; then
  echo "[ERROR] Godot binary not found. Edit GODOT_CANDIDATES in play.sh." >&2
  exit 1
fi
# console variant blocks and returns a real exit code (used for --test)
GODOT_CONSOLE="${GODOT/_win64.exe/_win64_console.exe}"
[[ -f "$GODOT_CONSOLE" ]] || GODOT_CONSOLE="$GODOT"

PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "Godot:   $GODOT"
echo "Project: $PROJ"
echo

# Import if the cache is missing, or if explicitly asked.
if [[ ! -d "$PROJ/.godot" || "${1:-}" == "--import" ]]; then
  echo "[import] Building import cache (--import)..."
  if ! "$GODOT_CONSOLE" --headless --path "$PROJ" --import; then
    echo "[ERROR] Import failed. Fix errors before running." >&2
    exit 1
  fi
  echo "[import] OK"; echo
  [[ "${1:-}" == "--import" ]] && shift
fi

case "${1:-}" in
  --test)
    echo "[test] Running headless smoke test..."
    code=0
    "$GODOT_CONSOLE" --headless --path "$PROJ" -s "res://tests/smoke_slash.gd" || code=$?
    echo
    if [[ $code -eq 0 ]]; then echo "[test] PASS (exit 0)"; else echo "[test] FAIL (exit $code)"; fi
    exit $code
    ;;
  --editor)
    echo "[editor] Opening the Godot editor GUI for this project..."
    exec "$GODOT" -e --path "$PROJ"
    ;;
  --scene)
    echo "[play] Running scene: ${2:-}   (close the window to quit)"
    exec "$GODOT" --path "$PROJ" "${2:-}"
    ;;
  *)
    echo "[play] Launching game -- WASD/arrows move, Space/J attack. Close the window to quit."
    exec "$GODOT" --path "$PROJ" "$@"
    ;;
esac
