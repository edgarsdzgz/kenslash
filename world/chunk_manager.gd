class_name ChunkManager
extends Node2D
## The streaming ORCHESTRATOR (Milestone C, design-world-streaming.md) -- the single
## lifecycle chokepoint that makes "cost scales with PROXIMITY, not total content" true
## by construction (patterns/persistent-world-scaling-pitfalls.md, failure 1.1).
##
## Node2D so the per-chunk container Nodes it spawns live in world space as its children.
## Each physics tick it maps the target's world position to a chunk coord; when that coord
## CHANGES it recomputes the desired active set = the (2*load_radius+1)^2 square of chunks
## within Chebyshev distance load_radius, then ENTERs chunks that newly qualify and LEAVEs
## chunks that no longer do. The active-Node population is therefore bounded by load_radius
## ALONE -- never by how far the target has travelled or how many chunks the world contains.
##
## C3b scope (CLOSES Milestone C): a per-coord in-memory ChunkData STORE plus delta
## WRITE-BACK. _activate_chunk loads a coord's ChunkData FROM THE STORE (carrying any
## player-made deltas) else generates + stores the deterministic baseline, then spawns one
## Tree / Rock / Enemy per entry via ChunkContent.spawn() -- SKIPPING entries flagged `gone`.
## _deactivate_chunk WRITES BACK each live node's durable state into its entry (integrity /
## hp, or `gone` if it was mined out / chopped / killed) via ChunkContent.capture() before
## freeing the container, so a mined/damaged/destroyed thing STAYS changed across an
## unload/reload. The store holds DATA (RefCounted ChunkData), never resident Nodes, so it
## grows with explored-chunk COUNT as cold data -- the disk-offload that caps even that is a
## later milestone that swaps "generate" for "read disk else generate" at the SAME hook.
## Still single-player, in-memory only: NO disk, NO netcode here.

## Simulation distance in chunks. load_radius 2 -> a 5x5 = 25-chunk active set (the
## (2r+1)^2 square). Tunable; the bound is a function of THIS, not of world size.
@export var load_radius: int = 2
## World generation seed handed to ChunkGenerator.generate(). Deterministic baseline.
@export var world_seed: int = 1

## The entity whose chunk drives the active set (the player). Settable; null = idle.
var target: Node2D = null

## Active chunks: coord (Vector2i) -> container Node2D currently in the tree.
var _active: Dictionary = {}
## The PERSISTENT per-coord store: coord (Vector2i) -> ChunkData. Populated on first
## activation (generated baseline) and RETAINED across deactivation, carrying every
## player-made delta the write-back captured. This is the in-memory dormant world; the
## disk milestone later backs it with a read-disk-else-generate load at _activate_chunk.
## Grows with explored-chunk count as cold DATA (RefCounted records), never Nodes.
var _store: Dictionary = {}
## Active chunks only: coord (Vector2i) -> Array of spawned content nodes, INDEX-ALIGNED to
## that chunk's ChunkData.entries (a `null` slot marks a `gone` entry that was not spawned).
## Gives _deactivate_chunk the (entry -> live node) pairing it needs to write state back.
var _content: Dictionary = {}
## The target's last-known chunk coord, and whether we have one yet (first-tick guard).
var _center: Vector2i = Vector2i.ZERO
var _has_center: bool = false


## Boundary-crossing update: recompute the active set ONLY when the target crosses into a
## new chunk (the common case is an early-out -- cheap). Per-tick call, chunk-change gated.
func _physics_process(_delta: float) -> void:
	if target == null:
		return
	var center: Vector2i = WorldScale.world_to_chunk(target.global_position)
	if _has_center and center == _center:
		return
	_refresh(center)


## Force an immediate active-set recompute around the target (e.g. right after assigning
## target, before the first physics tick). No-op without a target.
func _refresh_now() -> void:
	if target == null:
		return
	_refresh(WorldScale.world_to_chunk(target.global_position))


## Diff the desired (2*load_radius+1)^2 square against the live set: LEAVE stale chunks,
## ENTER new ones. .keys() snapshots so erasing during the leave pass is safe.
func _refresh(center: Vector2i) -> void:
	var desired: Dictionary = {}
	for dx in range(-load_radius, load_radius + 1):
		for dy in range(-load_radius, load_radius + 1):
			desired[center + Vector2i(dx, dy)] = true

	for coord in _active.keys():
		if not desired.has(coord):
			_deactivate_chunk(coord)

	for coord in desired:
		if not _active.has(coord):
			_activate_chunk(coord)

	_center = center
	_has_center = true


## ENTER: the single place a chunk becomes live Nodes. Load the coord's ChunkData from the
## STORE (carrying deltas) else generate + store the deterministic baseline; build a container
## at the chunk's world origin; and instance one REAL content Node per entry via
## ChunkContent.spawn() (Kind -> Tree/Rock/Enemy, configured from the entry's state), SKIPPING
## any entry flagged `gone` (mined out / chopped / killed on a prior visit). The container sits
## at chunk_origin, so each child's local position IS its entry's local_pos. The parallel
## _content array records each entry's spawned node (null for a skipped `gone` entry) so
## _deactivate_chunk can write live state back. The disk milestone swaps the generate() branch
## for read-disk-else-generate HERE, unchanged otherwise.
func _activate_chunk(coord: Vector2i) -> void:
	var data: ChunkData = _store.get(coord) as ChunkData
	if data == null:
		data = ChunkGenerator.generate(coord, world_seed)
		_store[coord] = data
	var container: Node2D = Node2D.new()
	container.name = "Chunk_%d_%d" % [coord.x, coord.y]
	container.position = WorldScale.chunk_origin(coord)
	# Y-sort must be enabled on EVERY level from the y-sorted root down to the leaves
	# (root + ChunkManager + this container) so the player and this chunk's content
	# merge into one depth sort -- otherwise the player always draws over the trees.
	container.y_sort_enabled = true
	var nodes: Array = []
	for entry in data.entries:
		var state: Dictionary = entry["state"]
		if bool(state.get("gone", false)):
			nodes.append(null)  # skipped: keep index alignment with entries
			continue
		var node: Node2D = ChunkContent.spawn(entry)
		container.add_child(node)
		nodes.append(node)
	_active[coord] = container
	_content[coord] = nodes
	add_child(container)


## LEAVE: the single place a chunk stops being Nodes -- and where the C3b DELTA WRITE-BACK
## happens. For each entry paired with its recorded node: a node that is no longer valid (it
## was mined out / chopped / killed and queue_freed during play) flags the entry `gone` so it
## is never respawned; a still-live node has its durable state CAPTURED into the entry via
## ChunkContent.capture() (integrity / hp, or `gone` at 0). Any change flags the ChunkData
## dirty (the future save trigger). The ChunkData STAYS in _store (retained cold data); only
## the live Nodes are dropped and queue_freed, so the delta survives to the next activation.
## E3c: DROP entries are SKIPPED by the paired loop and instead REBUILT afterward -- every
## surviving Drop child is re-snapshotted into a fresh Kind.DROP entry (resuming its age), so a
## dropped item persists as cheap data when dormant and respawns on reload, bounded by the E3b cull.
func _deactivate_chunk(coord: Vector2i) -> void:
	var container: Node2D = _active[coord]
	var data: ChunkData = _store[coord]
	var nodes: Array = _content[coord]
	var changed: bool = false
	for i in range(data.entries.size()):
		var entry: Dictionary = data.entries[i]
		if int(entry["type"]) == ChunkData.Kind.DROP:
			continue  # drops are rebuilt from live nodes below, NOT captured per-index here
		if ChunkData.is_addition_kind(int(entry["type"])):
			# A placed ADDITION (Epic 2 -- STATION or CONTAINER, ChunkData.is_addition_kind) is a permanent
			# delta: it persists AS-IS across unload/reload and is NEVER `gone`-flagged. Skip EVERY addition
			# kind here (generalized from the former STATION-only branch) for two reasons. (1) Its params
			# already live on the entry from register_placement and never mutate, so there is nothing to
			# capture HERE (a container's CONTENTS write-back is a SEPARATE live-children scan below,
			# Part 2.2, not this paired loop). (2) An addition registered
			# while the chunk was ALREADY active was appended to data.entries AFTER _content was built, so its
			# index sits BEYOND nodes.size() -- without this skip the `i >= nodes.size()` guard below would
			# wrongly gone-flag it. The live placeable node is a child of the container (spawned by Builder
			# when active, or by spawn() on reload), so it is freed with the container and re-created from THIS
			# entry on the next activation -- no orphan, no double.
			continue
		var state: Dictionary = entry["state"]
		if bool(state.get("gone", false)):
			continue  # already gone -- nothing live to capture
		# Index nodes[i] DIRECTLY -- never bind it to a typed `Node` local first. A node
		# destroyed during play (mined out / chopped / killed) leaves a FREED reference in
		# the array, and assigning a freed instance to a typed variable raises "invalid
		# previously freed instance"; is_instance_valid() reads the raw element safely, and
		# capture() only ever receives a still-valid node (the elif branch).
		if i >= nodes.size() or not is_instance_valid(nodes[i]):
			state["gone"] = true  # destroyed during play -- never respawn this entry
			changed = true
		elif ChunkContent.capture(nodes[i], entry):
			changed = true
	# --- Epic 2 Part 2.2 CONTAINER contents write-back ------------------------------------
	# A live StorageContainer's `store` MUTATES during play (deposit/withdraw), so its CONTAINER
	# addition entry -- recorded EMPTY at register_placement time -- must be refreshed with the
	# CURRENT contents on unload, so they ride the delta through to the next reload. Like the DROP
	# rebuild below (and UNLIKE the paired capture loop above), this scans the container's LIVE
	# children and matches each StorageContainer to its CONTAINER entry by local_pos -- a placed
	# container never moves, so position is a stable key. Scanning children (not nodes[i]) is what
	# makes it work in BOTH index regimes: whether the entry sits IN _content (spawned on reload,
	# index-aligned) or BEYOND it (registered while the chunk was already active, appended past
	# _content -- the case the paired loop can only SKIP). capture_state() is the SAME serializer
	# register_placement used, so placement and write-back can never disagree.
	for child in container.get_children():
		if child is StorageContainer:
			var box: StorageContainer = child
			for c_entry in data.entries:
				if int(c_entry["type"]) == ChunkData.Kind.CONTAINER \
						and (c_entry["local_pos"] as Vector2).distance_to(box.position) < 0.5:
					c_entry["state"] = box.capture_state()
					changed = true
					break
	# --- E3c DROP rebuild -----------------------------------------------------------------
	# Drops are pure deltas: snapshot live Drop children into fresh Kind.DROP entries. This runs
	# ONLY AFTER the paired loop above, so nodes[i] stays aligned to entries[i] during capture --
	# we mutate data.entries (strip + append DROP) exclusively here, past that alignment window.
	# First drop every existing DROP entry (a persisted drop that was picked up or aged out is no
	# longer a live child, so it must NOT carry over); then re-derive from the surviving children,
	# resuming each drop's age/lifetime. A chunk that held or holds drops is a delta chunk (dirty).
	var had_drop_entries: bool = false
	var kept_entries: Array[Dictionary] = []
	for entry in data.entries:
		if int(entry["type"]) == ChunkData.Kind.DROP:
			had_drop_entries = true
		else:
			kept_entries.append(entry)
	if had_drop_entries:
		data.entries = kept_entries
	var swept_drop: bool = false
	for child in container.get_children():
		if child is Drop and is_instance_valid(child) and not child.is_queued_for_deletion():
			data.entries.append(ChunkContent.drop_entry(child))
			swept_drop = true
	if had_drop_entries or swept_drop:
		changed = true
	if changed:
		data.dirty = true
	_active.erase(coord)
	_content.erase(coord)
	container.queue_free()


## Register a placed object as a persistent ADDITION delta on the chunk that OWNS `world_pos` (Epic 2
## Part 1.2; generalized KIND-AGNOSTIC in Part 2.1). The mirror of the DROP write-back, but PUSHED by the
## build path instead of swept on unload: compute the owning coord + the position LOCAL to that chunk, ensure
## the coord's ChunkData exists in the store (generate + retain the deterministic baseline if this is its
## first touch -- IDENTICAL to what _activate_chunk would do, so the baseline is unshifted), then APPEND an
## entry of the given `kind` (an ADDITION Kind -- STATION / CONTAINER / future, from the placeable's
## placement_kind()) carrying the local_pos + a DEEP COPY of `params` (the placeable's capture_state(): a
## Station's station_tag, an empty {} for a Part-2.1 container). It records the DELTA only -- it does NOT spawn:
## when the chunk is active the live Station was already added by Builder (streamed-world flow); when the
## chunk later reactivates, _activate_chunk's spawn() re-creates it from THIS entry. Touches ZERO generator
## rng (an explicit delta, never a draw), so every per-Kind count stays byte-identical. Flags the chunk
## dirty (a delta chunk, the future save trigger). `params` is duplicated so the caller cannot alias the
## stored state. The local_pos matches the container-child convention every other Kind uses (the container
## sits at chunk_origin), so a station placed at world_pos re-spawns at exactly world_pos on reload.
func register_placement(world_pos: Vector2, kind: int, params: Dictionary) -> void:
	var coord: Vector2i = WorldScale.world_to_chunk(world_pos)
	var data: ChunkData = _store.get(coord) as ChunkData
	if data == null:
		data = ChunkGenerator.generate(coord, world_seed)
		_store[coord] = data
	data.entries.append({
		"type": kind,
		"local_pos": world_pos - WorldScale.chunk_origin(coord),
		"state": params.duplicate(true),
	})
	data.dirty = true


## Number of chunks currently active (live containers). Bounded by (2*load_radius+1)^2.
func active_chunk_count() -> int:
	return _active.size()


## The coords of every currently-active chunk (test-readable). Order is unspecified.
func active_coords() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for coord in _active:
		out.append(coord)
	return out


## The live container for an active chunk coord, or null if that coord is not active.
## Test hook: lets a test reach a specific chunk's spawned content by coord.
func active_container(coord: Vector2i) -> Node2D:
	return _active.get(coord) as Node2D


## True if the store retains a ChunkData for this coord (visited at least once). Test hook
## proving cold-data retention: a coord stays stored after its Nodes are freed.
func has_stored(coord: Vector2i) -> bool:
	return _store.has(coord)


## The retained ChunkData for a stored coord, or null if never visited. Test hook mirroring
## active_container(): lets a test inspect a chunk's persisted delta entries directly (e.g. the
## E3c DROP write-back -- item_path / count / resumed age) after its Nodes are freed.
func stored_data(coord: Vector2i) -> ChunkData:
	return _store.get(coord) as ChunkData


## How many chunks the store retains as dormant DATA (>= the active-Node count once the
## target has roamed). Test hook for the "store growth adds data, not resident Nodes" proof.
func stored_chunk_count() -> int:
	return _store.size()

# Verified against: Godot 4.7.1 (2026-07-20)
