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
## The build path (Epic 2 Part 1.1/1.2). Stateless RefCounted -- one instance serves every placement, exactly
## like the tests instantiate it. place_station() below drives it, then records the placement as a streaming
## delta so it survives chunk unload/reload (Part 1.2). Kept off player.gd (it stays under its line cap).
var _builder: Builder = Builder.new()


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


## Place a crafting Station into the streamed world AND persist it as a chunk ADDITION delta (Epic 2 Part
## 1.2 -- the placement FLOW that wires Builder to the streaming persistence). Two decoupled steps:
##   (1) Builder.place() does the ATOMIC build-cost placement (Part 1.1): it verifies + consumes the cost from
##       `inventory` and spawns the Station under the OWNING chunk's live container. Builder never knows about
##       chunks -- it just takes the `parent` we hand it. Parenting under the container (not the world root) is
##       what makes the placement leak-free: the station is freed WITH its chunk on unload, so there is no
##       stray root child to double up when the chunk reloads.
##   (2) On success, ChunkManager.register_placement() records the placement as a STATION delta on that same
##       chunk, so when the chunk later unloads + reloads, spawn() re-creates the station from the delta at
##       the same position + tag. The build-cost live node and the reloaded node are never both alive.
## Returns the placed Station, or null if the owning chunk is not active (can only build into a live chunk)
## or the build cost was not met (Builder refused -> nothing placed, nothing recorded -- atomic + no stray
## delta). Deterministic: no Input/Time/OS/RNG -- a headless test calls this directly, same as Builder's test.
func place_station(station_scene: PackedScene, world_pos: Vector2, inventory: Inventory) -> Node:
	var coord: Vector2i = WorldScale.world_to_chunk(world_pos)
	var container: Node2D = _manager.active_container(coord)
	if container == null:
		return null  # the target chunk is not streamed in -- nothing to parent the placement under
	var placed: Node = _builder.place(station_scene, world_pos, inventory, container)
	if placed == null:
		return null  # build cost not met -- Builder consumed nothing; record no delta
	var station: Station = placed as Station
	_manager.register_placement(world_pos, {"station_tag": String(station.station_tag)})
	return placed


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

# Verified against: Godot 4.7.1 (2026-07-20)
