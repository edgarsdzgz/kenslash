class_name ChunkData
extends RefCounted
## The DORMANT, Node-less form of one chunk (Milestone C1, design-world-streaming.md).
## The load-bearing rule from patterns/persistent-world-scaling-pitfalls.md: dormant
## world = plain serializable DATA, never a Node per dormant thing. A chunk far from
## the player costs one of these RefCounted records and ZERO Nodes / ZERO ticks; the
## ChunkManager (C2) turns this data into disposable Nodes only near the player.
##
## Kept deliberately plain and serializable: entries are bare Dictionaries of
## {type, local_pos, state}, NO Node references, NO Resource sub-objects that could
## carry code. to_dict()/from_dict() round-trip the whole chunk through a plain,
## store_var-/JSON-safe Dictionary (Vector2i/Vector2 flattened to [x, y] arrays) so
## disk/blob persistence later is a save/load CALL, not a redesign.

## Entry kinds. Small enum, extensible -- append new kinds (STRUCTURE, ...) as the world
## grows; never renumber existing values (they persist to disk later). DROP (E3c) is a pure
## DELTA kind: ChunkGenerator never emits one -- a dropped item becomes a DROP entry only on
## its chunk's unload (ChunkManager snapshots live Drop children), respawned on reload with its
## remaining lifetime. So drops are cheap serializable DATA when dormant, bounded by the E3b cull.
## BUSH (E4) IS generated (a forageable interactable); a harvested bush is queue_freed, so the
## deactivate is_instance_valid path flags its entry `gone` (never respawns), like a felled tree.
enum Kind { TREE, MINERAL, ENEMY, DROP, BUSH }

## This chunk's grid coordinate (WorldScale.world_to_chunk space).
var coord: Vector2i = Vector2i.ZERO
## The chunk's contents as plain records. Each entry:
##   { "type": int (Kind), "local_pos": Vector2 in [0, CHUNK_PX), "state": Dictionary }
## `state` is the small per-entry MUTABLE payload (e.g. a mineral's {"integrity": 4},
## an empty {} for a fresh tree). Everything here is value data -- no Nodes.
var entries: Array[Dictionary] = []
## Set true when a mutation diverges this chunk from its generated baseline -- the
## future save trigger ("persist only the DELTA from a regenerable baseline"). C1
## only defines it; C3 flips it on real mutations.
var dirty: bool = false


## Flatten this chunk to a plain, serializable Dictionary (the future disk/blob form).
## Vector2i/Vector2 are stored as [x, y] arrays so the result is store_var- AND
## JSON-safe. `state` dicts are deep-copied so the snapshot cannot alias live entries.
## Lossless: from_dict(to_dict(x)) reproduces x field-for-field.
func to_dict() -> Dictionary:
	var out_entries: Array = []
	for e in entries:
		var lp: Vector2 = e["local_pos"]
		out_entries.append({
			"type": int(e["type"]),
			"local_pos": [lp.x, lp.y],
			"state": (e["state"] as Dictionary).duplicate(true),
		})
	return {
		"coord": [coord.x, coord.y],
		"entries": out_entries,
		"dirty": dirty,
	}


## Rebuild a ChunkData from the plain Dictionary produced by to_dict(). Inverse of
## to_dict() -- reconstructs Vector2i/Vector2 from their [x, y] arrays and deep-copies
## each entry's state back out.
static func from_dict(d: Dictionary) -> ChunkData:
	var cd: ChunkData = ChunkData.new()
	var c: Array = d["coord"]
	cd.coord = Vector2i(int(c[0]), int(c[1]))
	cd.dirty = bool(d.get("dirty", false))
	var ents: Array = d.get("entries", [])
	for e in ents:
		var lp: Array = e["local_pos"]
		cd.entries.append({
			"type": int(e["type"]),
			"local_pos": Vector2(lp[0], lp[1]),
			"state": (e["state"] as Dictionary).duplicate(true),
		})
	return cd

# Verified against: Godot 4.7.1 (2026-07-17)
