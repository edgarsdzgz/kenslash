extends Node2D
## The streaming world scene root (Milestone C2, design-world-streaming.md) -- a SEPARATE
## scene from main.tscn (the combat/inventory test arena, which stays untouched). This is
## the future "real game" world; for C2 it just needs to instantiate and stream: a
## ChunkManager, a Player, and a Camera2D childed to the Player so the view follows it as
## it wanders a world larger than the screen.
##
## Wiring is done in code (no editor GUI): point the ChunkManager at the Player so its
## proximity-driven active set tracks the player's chunk. Camera follow needs no script --
## the Camera2D is a CHILD of the Player, so it tracks the player's transform automatically.

@onready var _manager: ChunkManager = $ChunkManager
@onready var _player: Player = $Player
## Minimal in-game HUD (design-playable-loop.md D2). Presentation only -- bound to the
## player below so it can READ live health/tool/durability/hotbar state without the player
## ever reaching into the UI (or growing a new signal for it).
@onready var _hud: Hud = $HUD


func _ready() -> void:
	_manager.target = _player
	# Playable loop D2: hand the HUD the live player so it can reflect its state. The HUD
	# subscribes to HealthComponent.damaged and per-frame-reads tool/durability/hotbar; it
	# adds NO signal to player.gd and mutates no game state.
	_hud.bind(_player)
	# Playable loop D1 (design-playable-loop.md): spawn = origin. A FINITE respawn_point
	# makes death respawn the player IN PLACE and KEEP the streamed world alive, instead of
	# reload_current_scene() (which would destroy the ChunkManager + its in-memory delta store).
	_player.respawn_point = Vector2.ZERO
	print("[streaming_world] ready -- streaming a %d-chunk set around the player" % [
		(2 * _manager.load_radius + 1) * (2 * _manager.load_radius + 1)])

# Verified against: Godot 4.7.1 (2026-07-17)
