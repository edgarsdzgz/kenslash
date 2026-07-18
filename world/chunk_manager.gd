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
func _deactivate_chunk(coord: Vector2i) -> void:
	var container: Node2D = _active[coord]
	var data: ChunkData = _store[coord]
	var nodes: Array = _content[coord]
	var changed: bool = false
	for i in range(data.entries.size()):
		var entry: Dictionary = data.entries[i]
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
	if changed:
		data.dirty = true
	_active.erase(coord)
	_content.erase(coord)
	container.queue_free()


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


## How many chunks the store retains as dormant DATA (>= the active-Node count once the
## target has roamed). Test hook for the "store growth adds data, not resident Nodes" proof.
func stored_chunk_count() -> int:
	return _store.size()

# Verified against: Godot 4.7.1 (2026-07-17)
