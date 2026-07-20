class_name TestBuildMode extends RefCounted
## EPIC 2 build-mode UX slice -- the player-facing input surface for placing the three Epic 2 placeables (crafting
## Station / storage Container / station Add-on). Where TestBuilder proves the headless place op and
## TestPlacementPersist proves the delta round-trip, THIS module proves the OPERABLE build loop a human drives:
## toggle build mode, cycle the selection across all three kinds, a GHOST that tracks a deterministic target and
## hides when off, an affordability query that matches Builder.can_place, and a CONFIRM that places THROUGH
## streaming_world.place_placeable (so the cost is deducted AND the placement persists) -- kind-agnostic across all
## three, since build mode only picks a scene and place_placeable reads its placement_kind()/capture_state().
## STRUCTURAL assertions driven via the component SEAM (components/build_mode.gd public methods), never raw key
## presses -- the seam is exactly what the InputMap maps onto, so this drives the same routing deterministically.
##
## Two legs, both self-contained at REMOTE coords clear of every other module's scans:
##   A (component, bare Player under a holder): build mode toggles on/off; the ghost appears/hides; the selection
##     cycles through Station -> Container -> Add-on and WRAPS; the ghost tracks the deterministic ghost_world_pos
##     (player + facing, snapped to the tile grid) and hides when off; affordable() EQUALS Builder.can_place in both
##     the affordable and un-affordable directions.
##   B (real flow, shipped streaming_world.tscn): CONFIRM while affordable places each of the three kinds THROUGH
##     place_placeable -- the node exists in its group, the exact cost is deducted, AND the placement is recorded as
##     a persistence delta of the right Kind on the owning chunk; CONFIRM while UNaffordable places NOTHING and
##     consumes NOTHING; the HUD reflects the selection + cost + affordability. All three ride the ONE path.
## Registered in tests/smoke_slash.gd after TestStationLeveling.

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const STREAMING_SCENE: PackedScene = preload("res://world/streaming_world.tscn")

## Remote regions clear of every other self-contained module (builder 120000, container_panel -140000, craft_menu
## 200000/-200000, station -90000, ...), so no placeable wanders into these scans and vice-versa.
const HOME: Vector2 = Vector2(250000.0, 250000.0)         # Leg A: bare-player component checks
const BUILD_SPOT: Vector2 = Vector2(-250000.0, 250000.0)  # Leg B: streamed-world confirm/place


func run(ctx: TestContext) -> void:
	print("[build-mode] --- Epic 2 build-mode UX: toggle + select 3 kinds + ghost tracking + affordability + confirm places through place_placeable ---")
	await _leg_component(ctx)
	await _leg_confirm(ctx)


## Leg A: the BuildMode component seam on a bare Player -- toggle, selection cycle across all 3 kinds, ghost
## tracking/hiding, and affordable() == Builder.can_place. No streaming needed (confirm is Leg B).
func _leg_component(ctx: TestContext) -> void:
	var holder: Node2D = Node2D.new()
	ctx.tree.root.add_child(holder)
	var player: Player = PLAYER_SCENE.instantiate() as Player
	player.pickup_radius = 0.0  # suppress the magnet before _ready (no drops out here anyway)
	holder.add_child(player)
	player.global_position = HOME
	await ctx.frame()
	await ctx.frame()
	var bm: BuildMode = player._build_mode

	# --- toggle on/off + ghost appears/hides ---
	var off_ok: bool = not bm.enabled() and not bm.ghost_visible()
	bm.set_enabled(true, player)
	await ctx.frame()
	var on_ok: bool = bm.enabled() and bm.ghost_visible()
	ctx.check(off_ok and on_ok,
		"build mode TOGGLES: off by default (no ghost), then ON creates + shows the ghost preview",
		"build-mode toggle wrong (off_ok=%s on_ok=%s)" % [str(off_ok), str(on_ok)])

	# --- selection cycles through ALL THREE placeable kinds and WRAPS ---
	var k0: int = _selected_kind(bm)               # index 0 -> Station
	bm.cycle(1)
	var k1: int = _selected_kind(bm)               # index 1 -> Container
	bm.cycle(1)
	var k2: int = _selected_kind(bm)               # index 2 -> Add-on
	bm.cycle(1)
	var k_wrap: int = _selected_kind(bm)           # wraps back to index 0 -> Station
	bm.cycle(-1)
	var k_back: int = _selected_kind(bm)           # -1 wraps to index 2 -> Add-on
	ctx.check(k0 == ChunkData.Kind.STATION and k1 == ChunkData.Kind.CONTAINER and k2 == ChunkData.Kind.ADDON
			and k_wrap == ChunkData.Kind.STATION and k_back == ChunkData.Kind.ADDON,
		"selection CYCLES through all 3 kinds (Station -> Container -> Add-on) and WRAPS both ways",
		"selection cycle wrong (k0=%d k1=%d k2=%d wrap=%d back=%d)" % [k0, k1, k2, k_wrap, k_back])

	# --- ghost tracks the deterministic target (player + facing, snapped) and hides when off ---
	while bm.selected_index() != 0:
		bm.cycle(1)  # back to Station for a clean, named readout later
	player.global_position = HOME
	player.facing = Vector2.RIGHT
	await ctx.frame()
	var expect1: Vector2 = _snap(HOME + Vector2.RIGHT * WorldScale.TILE * 2.0)
	var track1_ok: bool = bm.ghost_world_pos(player) == expect1 and bm.ghost_node().global_position == expect1
	player.global_position = HOME + Vector2(1200.0, 0.0)
	await ctx.frame()
	var expect2: Vector2 = _snap(player.global_position + Vector2.RIGHT * WorldScale.TILE * 2.0)
	var track2_ok: bool = bm.ghost_node().global_position == expect2 and expect2 != expect1
	bm.set_enabled(false, player)
	await ctx.frame()
	var hidden_ok: bool = not bm.ghost_visible()
	ctx.check(track1_ok and track2_ok and hidden_ok,
		"ghost TRACKS the deterministic target (2 tiles in front, snapped to grid) as the player moves, and HIDES when build mode is off",
		"ghost tracking wrong (track1=%s track2=%s hidden=%s)" % [str(track1_ok), str(track2_ok), str(hidden_ok)])

	# --- affordable() EXACTLY matches Builder.can_place, both directions ---
	var STONE: ItemData = load("res://data/stone.tres")
	var STICK: ItemData = load("res://data/stick.tres")
	player.inventory.add_item(STONE, 5)
	player.inventory.add_item(STICK, 4)  # enough for a Station (stone x3 + stick x2); NO wood -> Container/Add-on unaffordable
	bm.set_enabled(true, player)
	while bm.selected_index() != 0:
		bm.cycle(1)
	var builder: Builder = Builder.new()
	var afford_true: bool = bm.affordable(player)
	var can_true: bool = builder.can_place(bm.selected_scene(), player.inventory)
	bm.cycle(1)  # Container needs wood x4 -> not affordable
	var afford_false: bool = bm.affordable(player)
	var can_false: bool = builder.can_place(bm.selected_scene(), player.inventory)
	ctx.check(afford_true == can_true and afford_true
			and afford_false == can_false and not afford_false,
		"affordable() EQUALS Builder.can_place: TRUE for the Station the inventory can pay for, FALSE for the wood-less Container",
		"affordability mismatch (afford_true=%s can_true=%s afford_false=%s can_false=%s)" % [str(afford_true), str(can_true), str(afford_false), str(can_false)])

	holder.queue_free()
	await ctx.frame()
	await ctx.frame()


## Leg B: CONFIRM through the real streaming_world.place_placeable -- all 3 kinds place (cost deducted + delta
## recorded), an unaffordable confirm is a no-op, and the HUD reflects the build readout.
func _leg_confirm(ctx: TestContext) -> void:
	var sw: Node2D = STREAMING_SCENE.instantiate() as Node2D
	ctx.tree.root.add_child(sw)
	var player: Player = sw.get_node("Player") as Player
	player.set("pickup_radius", 0.0)
	var mgr: ChunkManager = sw.get_node("ChunkManager") as ChunkManager
	var hud: Hud = sw.get_node("HUD") as Hud

	player.global_position = BUILD_SPOT
	await ctx.frame()
	await ctx.frame()
	await ctx.frame()

	var STONE: ItemData = load("res://data/stone.tres")
	var STICK: ItemData = load("res://data/stick.tres")
	var WOOD: ItemData = load("res://data/wood.tres")
	player.inventory.add_item(STONE, 3)   # exactly one Station
	player.inventory.add_item(STICK, 2)
	player.inventory.add_item(WOOD, 6)     # one Container (x4) + one Add-on (x2)

	var bm: BuildMode = player._build_mode
	bm.set_enabled(true, player)

	# --- HUD readout reflects the selected placeable + cost + affordability (Station selected) ---
	while bm.selected_index() != 0:
		bm.cycle(1)
	player.facing = Vector2.RIGHT
	await ctx.settle_idle()
	var htext: String = hud.build_text()
	ctx.check(htext.contains("Station") and htext.contains("affordable") and not htext.is_empty(),
		"HUD build readout shows the selection + cost + affordability while in build mode (\"%s\")" % htext,
		"HUD build readout wrong (\"%s\")" % htext)

	# --- CONFIRM STATION (facing RIGHT) ---
	player.facing = Vector2.RIGHT
	await ctx.frame()
	var pos_s: Vector2 = bm.ghost_world_pos(player)
	var placed_s: Node = bm.confirm(player)
	await ctx.frame()
	var coord: Vector2i = WorldScale.world_to_chunk(pos_s)
	var station_ok: bool = placed_s is Station and (placed_s as Node2D).is_in_group(Station.GROUP) \
		and pos_s.distance_to((placed_s as Node2D).global_position) < 0.5 \
		and player.inventory.count_of(STONE) == 0 and player.inventory.count_of(STICK) == 0 \
		and _kind_count(mgr, coord, ChunkData.Kind.STATION) == 1
	ctx.check(station_ok,
		"CONFIRM (affordable) places a STATION through place_placeable: node in \"station\" group at the ghost pos, cost deducted (stone 3->0, stick 2->0), recorded as ONE STATION delta",
		"station confirm wrong (placed=%s stone=%d stick=%d delta=%d)" % [str(placed_s), player.inventory.count_of(STONE), player.inventory.count_of(STICK), _kind_count(mgr, coord, ChunkData.Kind.STATION)])

	# --- CONFIRM CONTAINER (facing DOWN) ---
	bm.cycle(1)
	player.facing = Vector2.DOWN
	await ctx.frame()
	var pos_c: Vector2 = bm.ghost_world_pos(player)
	var placed_c: Node = bm.confirm(player)
	await ctx.frame()
	var container_ok: bool = placed_c is StorageContainer and (placed_c as Node2D).is_in_group(StorageContainer.GROUP) \
		and pos_c.distance_to((placed_c as Node2D).global_position) < 0.5 \
		and player.inventory.count_of(WOOD) == 2 \
		and _kind_count(mgr, WorldScale.world_to_chunk(pos_c), ChunkData.Kind.CONTAINER) == 1
	ctx.check(container_ok,
		"CONFIRM (affordable) places a CONTAINER through the SAME path: node in \"container\" group at the ghost pos, wood 6->2, recorded as ONE CONTAINER delta",
		"container confirm wrong (placed=%s wood=%d delta=%d)" % [str(placed_c), player.inventory.count_of(WOOD), _kind_count(mgr, WorldScale.world_to_chunk(pos_c), ChunkData.Kind.CONTAINER)])

	# --- CONFIRM ADD-ON (facing LEFT) ---
	bm.cycle(1)
	player.facing = Vector2.LEFT
	await ctx.frame()
	var pos_a: Vector2 = bm.ghost_world_pos(player)
	var placed_a: Node = bm.confirm(player)
	await ctx.frame()
	var addon_ok: bool = placed_a is StationAddon and (placed_a as Node2D).is_in_group(StationAddon.GROUP) \
		and pos_a.distance_to((placed_a as Node2D).global_position) < 0.5 \
		and player.inventory.count_of(WOOD) == 0 \
		and _kind_count(mgr, WorldScale.world_to_chunk(pos_a), ChunkData.Kind.ADDON) == 1
	ctx.check(addon_ok,
		"CONFIRM (affordable) places an ADD-ON through the SAME path: node in \"station_addon\" group at the ghost pos, wood 2->0, recorded as ONE ADDON delta -- all 3 kinds shared ONE place_placeable path",
		"addon confirm wrong (placed=%s wood=%d delta=%d)" % [str(placed_a), player.inventory.count_of(WOOD), _kind_count(mgr, WorldScale.world_to_chunk(pos_a), ChunkData.Kind.ADDON)])

	# --- CONFIRM while UNAFFORDABLE places NOTHING, consumes NOTHING (Add-on still selected, wood now 0) ---
	player.facing = Vector2.UP
	await ctx.frame()
	var pos_u: Vector2 = bm.ghost_world_pos(player)
	var coord_u: Vector2i = WorldScale.world_to_chunk(pos_u)
	var addon_before: int = _kind_count(mgr, coord_u, ChunkData.Kind.ADDON)
	var wood_before: int = player.inventory.count_of(WOOD)
	var refused: Node = bm.confirm(player)
	await ctx.frame()
	var refuse_ok: bool = refused == null and not bm.affordable(player) \
		and player.inventory.count_of(WOOD) == wood_before \
		and _kind_count(mgr, coord_u, ChunkData.Kind.ADDON) == addon_before
	ctx.check(refuse_ok,
		"CONFIRM (UNaffordable, wood 0) is a NO-OP: places nothing, consumes nothing, records no new delta -- and build mode stays ON",
		"unaffordable confirm was not a no-op (refused=%s wood=%d/%d delta=%d/%d)" % [str(refused), player.inventory.count_of(WOOD), wood_before, _kind_count(mgr, coord_u, ChunkData.Kind.ADDON), addon_before])

	sw.queue_free()
	await ctx.frame()
	await ctx.frame()


## The placement_kind() of the currently selected placeable, read off a THROWAWAY instance (never entered the tree,
## freed immediately) -- proves the selection resolves to the right kind without placing anything.
func _selected_kind(bm: BuildMode) -> int:
	var probe: Placeable = bm.selected_scene().instantiate() as Placeable
	if probe == null:
		return -1
	var k: int = probe.placement_kind()
	probe.free()
	return k


## Count the ADDITION delta entries of a given Kind on the chunk that owns `coord` -- the persistence proof that a
## confirmed placement was recorded (or, when unaffordable, was NOT).
func _kind_count(mgr: ChunkManager, coord: Vector2i, kind: int) -> int:
	var cd: ChunkData = mgr.stored_data(coord)
	if cd == null:
		return 0
	var n: int = 0
	for e in cd.entries:
		if int(e["type"]) == kind:
			n += 1
	return n


## Snap a world position to the tile grid -- the INDEPENDENT mirror of BuildMode.ghost_world_pos's snapping, so the
## test verifies the deterministic target rather than trusting the SUT's own math.
func _snap(v: Vector2) -> Vector2:
	return Vector2(snappedf(v.x, WorldScale.TILE), snappedf(v.y, WorldScale.TILE))

# Verified against: Godot 4.7.1 (2026-07-20)
