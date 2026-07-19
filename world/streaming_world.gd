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
## Meadow ground (design-environment.md #1). A full-screen ColorRect on a LOW CanvasLayer
## (layer -100 -> draws BEHIND the streamed world + entities) running world/meadow_ground.gdshader.
## Its ShaderMaterial samples world-space noise to paint a splotchy meadow; the camera pair below
## is what keeps the pattern anchored to WORLD space instead of sliding with the screen.
@onready var _ground_mat: ShaderMaterial = ($GroundLayer/Ground as ColorRect).material as ShaderMaterial
@onready var _camera: Camera2D = $Player/Camera2D


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


## Meadow ground world-anchoring feed (design-environment.md #1). Each frame, hand the ground
## shader the camera's screen-center (in WORLD pixels), zoom, and viewport size so it can
## reconstruct the world position under every fragment. THIS is the world-anchored invariant:
## as the Camera2D follows the player, the meadow noise scrolls WITH the world rather than
## staying fixed to the screen (which would shimmer). A few cheap uniform writes, no game state.
func _process(_delta: float) -> void:
	if _ground_mat == null:
		return
	_ground_mat.set_shader_parameter("cam_center", _camera.get_screen_center_position())
	_ground_mat.set_shader_parameter("cam_zoom", _camera.zoom)
	_ground_mat.set_shader_parameter("viewport_size", get_viewport_rect().size)

# Verified against: Godot 4.7.1 (2026-07-19)
