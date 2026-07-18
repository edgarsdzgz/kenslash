class_name TestDropPersist extends RefCounted
## Milestone E3c chunk-ownership + persistence (design-items.md "Drops" ->
## "Chunk-ownership + persistence"): a Drop is CHUNK CONTENT that survives unload/reload by
## reusing the C3b delta store. On unload the ChunkManager snapshots each live Drop child into
## a Kind.DROP ChunkData entry (item id + count + REMAINING lifetime); on reload spawn() rebuilds
## it, RESUMING its age rather than resetting. So a dropped item is cheap serializable DATA when
## its chunk is dormant, bounded by the E3b cull -- never a resident node accumulating without end.
##
## Self-contained: drives a FRESH ChunkManager directly (load_radius 1 -> a 3x3 = 9 active set, so
## a short hop moves the focus chunk out of range and back) with a bare Node2D target -- never a
## player, so NO magnet can eat the drops we are persisting (E3a pickup stays out of this). Two
## REMOTE focus chunks, far from every other module's content, keep the scenarios isolated and
## from co-activating each other (Chebyshev distance well past the 3x3 neighborhood). Mirrors the
## C3b delta-persistence leg of test_streaming.gd (hand-driven manager, hop-away/hop-back reload).

const WOOD: ItemData = preload("res://data/wood.tres")
const DROP_SCENE: PackedScene = preload("res://world/drop.tscn")

## A remote focus chunk for the persist/respawn scenario, and a second (far enough that its 3x3
## never co-activates with the first) for the freed-drop-does-not-persist scenario.
const FOCUS: Vector2i = Vector2i(9000, -9000)
const FOCUS_FREED: Vector2i = Vector2i(9000, -9040)

## A non-zero starting age injected into the test drop BEFORE unload. Large enough that a reloaded
## drop reading ~this value proves aging RESUMED, while a reset-to-0 regression would read ~0.
const INJECT_AGE: float = 50.0
## The drop's local position within its chunk container (arbitrary, distinct from origin), so the
## respawned drop's position round-trips through the DROP entry's local_pos.
const DROP_LOCAL: Vector2 = Vector2(33.0, 44.0)


func run(ctx: TestContext) -> void:
	print("[drop-persist] --- E3c: drops persist across unload/reload, resume aging, cull-bounded ---")
	var dm: ChunkManager = ChunkManager.new()
	dm.load_radius = 1
	dm.world_seed = 7
	ctx.tree.root.add_child(dm)
	var dmover: Node2D = Node2D.new()
	ctx.tree.root.add_child(dmover)
	dm.target = dmover

	# --- Activate the focus chunk, then inject a live Drop (Wood x3) as chunk content ----------
	dmover.global_position = WorldScale.chunk_origin(FOCUS) + Vector2(20.0, 20.0)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	var container: Node2D = dm.active_container(FOCUS)
	var have_container: bool = container != null
	var drop: Drop = DROP_SCENE.instantiate()
	drop.setup(WOOD, 3)
	drop.lifetime = 300.0  # far above INJECT_AGE, so the E3b cull never fires during this test
	if have_container:
		container.add_child(drop)
		drop.position = DROP_LOCAL
		drop._age = INJECT_AGE  # non-zero, so a reloaded drop reading ~this proves RESUME not reset
	await ctx.tree.physics_frame  # settle _ready + let it age a hair past INJECT_AGE
	ctx.check(have_container,
		"E3c setup: focus chunk " + str(FOCUS) + " activated and a live Wood x3 Drop was injected as its content",
		"could not activate focus chunk to inject a drop")

	# --- Persist across unload: hop away so FOCUS leaves the 3x3 set (write-back) --------------
	dmover.global_position = WorldScale.chunk_origin(FOCUS + Vector2i(20, 20)) + Vector2(20.0, 20.0)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	var stored: ChunkData = dm.stored_data(FOCUS)
	var drop_entries: Array = _drop_entries(stored)
	var persisted_ok: bool = drop_entries.size() == 1
	var persisted_age: float = -1.0
	var persisted_lifetime: float = -1.0
	if persisted_ok:
		var st: Dictionary = drop_entries[0]["state"]
		persisted_ok = String(st.get("item_path", "")) == WOOD.resource_path \
			and int(st.get("count", -1)) == 3
		persisted_age = float(st.get("age", -1.0))
		persisted_lifetime = float(st.get("lifetime", -1.0))
	ctx.check(persisted_ok,
		"E3c persist-across-unload: the unloaded chunk's stored ChunkData holds exactly ONE Kind.DROP entry (item_path == wood, count == 3) -- the live drop became cheap delta data",
		"drop did not persist as a DROP delta entry on unload (entries=" + str(drop_entries.size()) + ")")
	ctx.check(persisted_age >= INJECT_AGE and persisted_lifetime == 300.0 and stored != null and stored.dirty,
		"E3c persist carries REMAINING lifetime: the DROP entry stored age >= injected " + str(INJECT_AGE) + " (accrued, not reset) and lifetime 300, and the chunk is now dirty (a delta chunk)",
		"DROP entry lost its age/lifetime or the chunk was not flagged dirty (age=" + str(persisted_age) + ")")

	# --- Respawn on reload: hop back so FOCUS reactivates and spawn() rebuilds the drop --------
	dmover.global_position = WorldScale.chunk_origin(FOCUS) + Vector2(20.0, 20.0)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	var reloaded: Array = _drops_in(dm.active_container(FOCUS))
	var respawn_ok: bool = reloaded.size() == 1
	var re_drop: Drop = reloaded[0] if respawn_ok else null
	ctx.check(respawn_ok and re_drop.count == 3 and re_drop.position == DROP_LOCAL,
		"E3c respawn-on-reload: a live Drop respawned carrying Wood x3 at its persisted local_pos " + str(DROP_LOCAL) + " -- dormant data became a node again",
		"drop did not respawn correctly on reload (count/pos, drops=" + str(reloaded.size()) + ")")
	ctx.check(respawn_ok and re_drop._age >= persisted_age and re_drop.lifetime == 300.0,
		"E3c aging RESUMES: the respawned drop's _age (" + str(re_drop._age if respawn_ok else -1.0) + ") >= the persisted age (" + str(persisted_age) + ") -- it continued toward the cull, NOT reset to 0, lifetime preserved",
		"respawned drop reset its age instead of resuming (age=" + str(re_drop._age if respawn_ok else -1.0) + " vs persisted " + str(persisted_age) + ")")
	ctx.check(respawn_ok and re_drop.item != null and re_drop.item.resource_path == WOOD.resource_path,
		"E3c round-trip item identity: the respawned drop's item.resource_path == wood -- load() rebuilt the SAME ItemData from the stored id",
		"respawned drop's item identity was lost across unload/reload")

	# --- Aged-out / picked-up drop does NOT persist -------------------------------------------
	# In a SEPARATE remote chunk, inject a drop then free it BEFORE unload (a picked-up / aged-out
	# drop is no longer a live child). After deactivate the store must hold NO DROP entry for it.
	dmover.global_position = WorldScale.chunk_origin(FOCUS_FREED) + Vector2(20.0, 20.0)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	var container_f: Node2D = dm.active_container(FOCUS_FREED)
	if container_f != null:
		var ghost: Drop = DROP_SCENE.instantiate()
		ghost.setup(WOOD, 1)
		container_f.add_child(ghost)
		ghost.position = DROP_LOCAL
		ghost.queue_free()  # freed before unload -- stands in for a picked-up / aged-out drop
	await ctx.tree.physics_frame  # let the queue_free resolve (no longer a live child)
	dmover.global_position = WorldScale.chunk_origin(FOCUS_FREED + Vector2i(20, 20)) + Vector2(20.0, 20.0)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	ctx.check(_drop_entries(dm.stored_data(FOCUS_FREED)).size() == 0,
		"E3c freed-drop-does-not-persist: a drop freed before unload leaves NO DROP entry -- a picked-up / aged-out drop correctly vanishes, not resurrected on reload",
		"a freed drop was wrongly persisted as a DROP entry")

	# --- Teardown: free the manager + target so nothing leaks downstream -----------------------
	dm.queue_free()
	dmover.queue_free()
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame


## The live Drop instances directly under a chunk container (empty if the container is null).
func _drops_in(container: Node2D) -> Array:
	var out: Array = []
	if container == null:
		return out
	for child in container.get_children():
		if child is Drop:
			out.append(child)
	return out


## The Kind.DROP entries of a stored ChunkData (empty if the data is null). Lets a test assert
## how many drop deltas a dormant chunk carries, and read their persisted item_path / count / age.
func _drop_entries(cd: ChunkData) -> Array:
	var out: Array = []
	if cd == null:
		return out
	for e in cd.entries:
		if int(e["type"]) == ChunkData.Kind.DROP:
			out.append(e)
	return out

# Verified against: Godot 4.7.1 (2026-07-18)
