class_name BuildMode
extends RefCounted
## The player-facing BUILD-MODE UX (Epic 2 build-mode slice; design-crafting.md "Track B -- Building"). Turns the
## headless-only placement path (components/builder.gd + world/streaming_world.gd place_placeable) into an OPERABLE
## in-game loop: a toggle, a selection among the three placeable kinds, a GHOST preview that follows a deterministic
## target in front of the player, an affordability tint, and a CONFIRM that rides streaming_world.place_placeable so
## the placement is COST-DEDUCTED and PERSISTED exactly as the headless tests already prove. It adds NOTHING to the
## placement/persistence LOGIC -- it only DRIVES it (picks a scene, computes a position, calls place_placeable).
##
## KIND-AGNOSTIC BY CONSTRUCTION. The three placeable kinds (Station / StorageContainer / StationAddon) all place
## through the ONE path: build mode picks a PackedScene and hands it to place_placeable(), which reads the instance's
## placement_kind()/capture_state() (world/placeable.gd) -- there is NO per-kind branch here or downstream (Part 2.1
## already generalized the reviewer-flagged place_station hardcoding; ADDITION_KINDS = [STATION, CONTAINER, ADDON]).
## So delivering build mode ALSO delivers "all 3 kinds share one placement path": cycling the selection is the only
## per-kind knowledge, and it is pure data (SCENES/NAMES).
##
## RefCounted (NOT a Node), exactly like components/interaction.gd / pickup.gd -- so the controller itself perturbs no
## streaming node-count / orphan baseline and the player "calls down" into process() each physics frame. The GHOST it
## owns IS a Node (a Polygon2D lives in the scene tree), created LAZILY on the first enable and parented UNDER THE
## PLAYER (never the streamed chunk path) so streaming baselines stay undisturbed; a build session that never toggles
## on (every existing test) adds no node at all.
##
## Input is read DIRECTLY from the InputMap (Input.is_action_just_pressed), NOT via the networked FrameInput seam --
## the SAME rationale as components/interaction.gd / equipment.gd: placement is a LOCAL build action (put a workbench
## in front of me), not gameplay-simulation state a networked peer / AI would replay. The seam methods below
## (set_enabled / cycle / confirm + the queries) are PUBLIC so a headless test drives the exact same routing without
## a real key press, and process() is a thin wrapper mapping the InputMap onto them.
##
## DETERMINISM: the ghost target position, affordability, and placement are pure (no Time/OS/RNG) -- ghost_world_pos()
## is the single source of truth (player position + facing, snapped to the tile grid), so the ghost, the confirm, and
## the test all read the SAME position. The ghost's tint is presentation-only. Placement persistence is UNCHANGED (it
## rides place_placeable). Every query is exactly headless-assertable.

## The three placeable scenes cycled among, in a FIXED deterministic order (station -> container -> add-on -> wrap).
## preload() results are constant expressions, so this const array is authored data, not runtime lookup.
const SCENES: Array[PackedScene] = [
	preload("res://world/station.tscn"),
	preload("res://world/container.tscn"),
	preload("res://world/station_addon.tscn"),
]
## Human-readable name PARALLEL to SCENES (SCENES[i] is NAMES[i]) for the HUD readout -- named without instantiating
## the scene just to label it. Kept in lockstep with SCENES above.
const NAMES: Array[String] = ["Station", "Storage Container", "Station Add-on"]

## How far in front of the player (px) the ghost/target sits: two tiles (WorldScale.TILE 40), matching the
## build-beside-you reach of a station/container. Snapped to the tile grid so placements land on a coarse build grid.
const BUILD_REACH: float = WorldScale.TILE * 2.0

## Ghost tints (semi-transparent): green when the selected placeable is affordable RIGHT NOW, red when not -- the
## visual mirror of affordable() / Builder.can_place. Presentation only.
const GHOST_OK: Color = Color(0.4, 1.0, 0.45, 0.5)
const GHOST_NO: Color = Color(1.0, 0.35, 0.3, 0.5)
## Half-extent (px) of the ghost marker footprint -- a ~1-tile square, filled translucent in the affordability tint.
## A generic placeholder shape shared by all three kinds (built at runtime in _make_ghost -- a PackedVector2Array is
## not a constant expression): the readout names WHICH kind; the ghost only shows WHERE + WHETHER it is affordable.
const GHOST_HALF: float = 16.0

## Whether build mode is currently ON. Off by default -- the ghost is hidden (and not even created) until the first
## enable, so a player who never builds pays nothing and every non-build test is undisturbed.
var _enabled: bool = false
## Index into SCENES/NAMES of the currently selected placeable (0 station / 1 container / 2 add-on). cycle() wraps it.
var _index: int = 0
## The lazily-created ghost preview node (a Polygon2D, which IS a Node2D), parented under the player on first enable.
## Null until then. Positioned + tinted each frame by _update_ghost while build mode is on; hidden when off.
var _ghost: Polygon2D = null
## Stateless placement helper (RefCounted) -- one instance serves every affordability query + the confirm precheck,
## exactly like the tests / streaming_world instantiate it. The actual cost-deducting place rides place_placeable.
var _builder: Builder = Builder.new()


## Per-frame LOCAL-input pass (called from player._physics_process). Reads the InputMap DIRECTLY -- placement is a
## LOCAL build action, NOT networked sim, so it does NOT route through FrameInput (same rationale as interaction.gd).
## Maps the build keys onto the public seam: `build_toggle` flips build mode; while ON, `build_prev`/`build_next`
## cycle the selection and `build_confirm` places the selected placeable. The ghost is refreshed every frame last so
## it tracks the player + the live affordability. Build mode STAYS ON after a confirm (repeated placing).
func process(player: Node2D) -> void:
	if Input.is_action_just_pressed("build_toggle"):
		set_enabled(not _enabled, player)
	if _enabled:
		if Input.is_action_just_pressed("build_prev"):
			cycle(-1)
		if Input.is_action_just_pressed("build_next"):
			cycle(1)
		if Input.is_action_just_pressed("build_confirm"):
			confirm(player)
	_update_ghost(player)


## Turn build mode ON/OFF (the seam `build_toggle` drives, and a test calls directly). Enabling for the FIRST time
## lazily creates + parents the ghost under the player; the ghost is then shown/hidden by _update_ghost. Idempotent.
func set_enabled(on: bool, player: Node2D) -> void:
	_enabled = on
	if _enabled and _ghost == null:
		_make_ghost(player)
	_update_ghost(player)


## Whether build mode is currently ON. Pure read (the HUD polls this each frame to show/hide its build readout).
func enabled() -> bool:
	return _enabled


## Advance the selection by `dir` (+1 next / -1 prev), WRAPPING across the three kinds (wrapi). Pure integer step --
## no Input/Time/OS/RNG -- so a test cycles the exact same selection the `build_next`/`build_prev` keys would.
func cycle(dir: int) -> void:
	_index = wrapi(_index + dir, 0, SCENES.size())


## The selected placeable's index into SCENES/NAMES (0..2). Pure read for the test.
func selected_index() -> int:
	return _index


## The selected placeable's PackedScene -- the ONE scene build mode hands to place_placeable (and Builder.can_place).
func selected_scene() -> PackedScene:
	return SCENES[_index]


## The selected placeable's human-readable name (for the HUD readout).
func selected_name() -> String:
	return NAMES[_index]


## The DETERMINISTIC ghost/target world position: BUILD_REACH in front of the player (its `facing`, or RIGHT when the
## player has never moved), SNAPPED to the tile grid so placements land on a coarse build grid. The SINGLE source of
## truth -- the ghost node, confirm(), and the test all read this one pure function, so they can never disagree. No
## Time/OS/RNG. `player` is typed Node2D and its `facing` is read dynamically (the established component idiom, see
## combat.gd) to avoid a circular BuildMode<->Player class dependency.
func ghost_world_pos(player: Node2D) -> Vector2:
	var face: Vector2 = player.facing if player.facing != Vector2.ZERO else Vector2.RIGHT
	var raw: Vector2 = player.global_position + face.normalized() * BUILD_REACH
	return Vector2(snappedf(raw.x, WorldScale.TILE), snappedf(raw.y, WorldScale.TILE))


## Whether the selected placeable is affordable RIGHT NOW -- a thin, pure forward to Builder.can_place against the
## player's inventory, so affordable() and the ghost tint and place()'s accept/refuse all agree by construction. The
## HUD + the ghost read this each frame while build mode is on.
func affordable(player: Node2D) -> bool:
	return _builder.can_place(SCENES[_index], player.inventory)


## The selected placeable's build cost as a readable "Stone x3 + Stick x2" string (for the HUD). Reads the cost off a
## THROWAWAY instance (never entered the tree -> no _ready, no group join -> freed immediately), the same probe idiom
## Builder.can_place uses. An empty cost reads "free". Pure -- no game state touched.
func cost_text() -> String:
	var probe: Placeable = SCENES[_index].instantiate() as Placeable
	if probe == null:
		return ""
	var parts: PackedStringArray = []
	for i in range(probe.build_items.size()):
		var item: ItemData = probe.build_items[i]
		var n: int = probe.build_counts[i] if i < probe.build_counts.size() else 0
		if item != null and n > 0:
			parts.append("%s x%d" % [item.display_name, n])
	probe.free()
	return " + ".join(parts) if parts.size() > 0 else "free"


## CONFIRM a placement (the seam `build_confirm` drives, and a test calls directly). Places the selected placeable at
## the ghost position THROUGH streaming_world.place_placeable so the cost is deducted AND the placement PERSISTS as a
## chunk delta. Guards: build mode must be ON; the owning world (the player's parent) must expose place_placeable (so
## a confirm in the non-streamed arena is a safe no-op); and the cost must be AFFORDABLE -- an unaffordable confirm
## places NOTHING and consumes NOTHING (place_placeable would refuse atomically anyway, but the guard makes "do
## nothing" explicit + avoids touching the world). Returns the placed node, or null on any guard/refusal. Build mode
## stays ON for repeated placing. The SAME kind-agnostic path for all three kinds -- the only difference is which
## SCENES[_index] scene is handed to place_placeable.
func confirm(player: Node2D) -> Node:
	if not _enabled:
		return null
	var world: Node = player.get_parent()
	if world == null or not world.has_method("place_placeable"):
		return null
	if not _builder.can_place(SCENES[_index], player.inventory):
		return null  # unaffordable -- place nothing, consume nothing (atomic, an explicit no-op)
	return world.call("place_placeable", SCENES[_index], ghost_world_pos(player), player.inventory)


## Whether the ghost preview is currently VISIBLE (created AND shown). False before the first enable and while build
## mode is off. Pure read for the test (the ghost tracks + hides deterministically).
func ghost_visible() -> bool:
	return _ghost != null and _ghost.visible


## The live ghost preview node, or null before the first enable. For a test that wants to read the ghost's actual
## global_position / color (the rendered WHERE + affordability tint), not just the computed target.
func ghost_node() -> Polygon2D:
	return _ghost


## Lazily build the ghost preview: a translucent square Polygon2D drawn above the world, parented UNDER THE PLAYER
## (never the streamed chunk path) so it rides the player and frees WITH it. Starts hidden; _update_ghost shows +
## positions + tints it. Created only on the first enable, so a player who never builds adds no node.
func _make_ghost(player: Node2D) -> void:
	_ghost = Polygon2D.new()
	_ghost.polygon = PackedVector2Array([
		Vector2(-GHOST_HALF, -GHOST_HALF), Vector2(GHOST_HALF, -GHOST_HALF),
		Vector2(GHOST_HALF, GHOST_HALF), Vector2(-GHOST_HALF, GHOST_HALF),
	])
	_ghost.color = GHOST_OK
	_ghost.z_index = 5  # above the streamed world entities, so the preview reads clearly
	_ghost.visible = false
	player.add_child(_ghost)


## Refresh the ghost each frame: hidden when build mode is off (or before it exists); else moved to the deterministic
## ghost_world_pos and tinted green/red by live affordability. Pure presentation -- no game state touched.
func _update_ghost(player: Node2D) -> void:
	if _ghost == null:
		return
	_ghost.visible = _enabled
	if not _enabled:
		return
	_ghost.global_position = ghost_world_pos(player)
	_ghost.color = GHOST_OK if affordable(player) else GHOST_NO

# Verified against: Godot 4.7.1 (2026-07-20)
