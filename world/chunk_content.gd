class_name ChunkContent
## Maps ONE dormant ChunkData entry -> ONE live content Node2D (Milestone C3a,
## design-world-streaming.md, the "content" half of C3). Pure static factory, no state --
## the single place the entry-Kind -> scene decision lives, so the ChunkManager stays a
## pure lifecycle orchestrator and this file owns "what a tree/mineral/enemy IS."
##
## Split out (rather than inlined into chunk_manager.gd) for single-responsibility per
## CONVENTIONS.md Rule 1: activation/deactivation lifecycle is one job, the entry->Node
## mapping + per-instance config is another. Both stay small.
##
## spawn(): instance the real scene for each Kind and position it at the entry's local_pos
## (its parent container already sits at chunk_origin, so a child's LOCAL position IS the
## entry's local_pos), configured from the entry's state (a mineral's integrity, an enemy's
## stored hp). capture() is its C3b inverse: write a live node's durable state BACK into its
## entry on unload (the delta write-back), keeping the per-Kind "what state matters" knowledge
## in THIS file, not the ChunkManager (Rule 1). Enemy dormancy ticking remains later work.

## The three content scenes, preloaded once as consts (loaded at class-load, not per
## spawn). Tree has no class_name (its native-class clash is documented in world/tree.gd),
## so it is typed as its base StaticBody2D at the call site; Rock/Enemy carry class_names.
const TREE_SCENE: PackedScene = preload("res://world/tree.tscn")
const ROCK_SCENE: PackedScene = preload("res://world/rock.tscn")
const ENEMY_SCENE: PackedScene = preload("res://enemy/enemy.tscn")
## The Drop scene (E3c). Unlike the three above, a DROP entry is never generated -- it is a pure
## delta the ChunkManager snapshots from live Drop children on unload (drop_entry, below) and
## respawns here on reload, its item re-load()ed by resource_path and its aging RESUMED.
const DROP_SCENE: PackedScene = preload("res://world/drop.tscn")

## Hardness of a streamed mineral. The soft, mineable-with-the-pickaxe stone (matches
## world/rock.tscn's default): over = 6 - pickaxe.power 7 <= 0 -> Band A, so it chips.
## Obsidian / harder variety is later content-variety work, not C3a.
const MINERAL_HARDNESS: int = 6
## Integrity used when an entry's state omits it. Mirrors ChunkGenerator's fresh baseline
## so a generated mineral and a defaulted one agree; a partially-mined entry (C3b's
## write-back) will instead carry its own reduced integrity in state.
const DEFAULT_MINERAL_INTEGRITY: int = 4


## Instance the scene for one ChunkData entry, configure it from the entry, and set its
## LOCAL position to the entry's local_pos. The caller (ChunkManager._activate_chunk)
## simply add_child()s the returned node under the chunk container. Never returns null --
## an unknown Kind yields a bare Node2D so a future enum value cannot crash streaming.
static func spawn(entry: Dictionary) -> Node2D:
	var kind: int = int(entry["type"])
	var node: Node2D

	match kind:
		ChunkData.Kind.TREE:
			node = TREE_SCENE.instantiate()
		ChunkData.Kind.MINERAL:
			var rock: Rock = ROCK_SCENE.instantiate()
			# Set the ROOT exports BEFORE add_child: rock.gd._ready() reads integrity/
			# hardness and pushes them down onto its Material/Hurtbox children (same path
			# main.tscn uses to author a soft rock vs obsidian by instance override).
			var state: Dictionary = entry["state"]
			rock.integrity = int(state.get("integrity", DEFAULT_MINERAL_INTEGRITY))
			rock.hardness = MINERAL_HARDNESS
			node = rock
		ChunkData.Kind.ENEMY:
			# Bare flesh enemy; enemy.gd resolves its target via the "player" group at
			# runtime (the streaming_world Player is in that group).
			var enemy: Enemy = ENEMY_SCENE.instantiate()
			var e_state: Dictionary = entry["state"]
			if e_state.has("hp"):
				# HealthComponent._ready() resets current_health to max on tree-entry, so a
				# stored (reduced) hp must be re-applied AFTER that -- on the enemy's `ready`
				# signal (fires once, after all children _ready). One-shot so it self-cleans.
				var stored_hp: int = int(e_state["hp"])
				var apply_hp: Callable = func() -> void:
					var hc: HealthComponent = enemy.get_node("HealthComponent") as HealthComponent
					hc.current_health = stored_hp
				enemy.ready.connect(apply_hp, CONNECT_ONE_SHOT)
			node = enemy
		ChunkData.Kind.DROP:
			# A persisted drop: rebuild the same Drop from its serialized state. load() the
			# ItemData by its stable resource_path (the item id), restore item+count via setup(),
			# then RESUME aging -- re-apply the stored lifetime and _age so the reloaded drop
			# continues toward its E3b cull rather than resetting to a fresh 300s. The caller
			# positions it at local_pos, same as every other Kind.
			var d_state: Dictionary = entry["state"]
			var drop: Drop = DROP_SCENE.instantiate()
			var item: ItemData = load(d_state["item_path"]) as ItemData
			drop.setup(item, int(d_state["count"]))
			drop.lifetime = float(d_state.get("lifetime", 300.0))
			drop._age = float(d_state.get("age", 0.0))
			node = drop
		_:
			node = Node2D.new()

	node.position = entry["local_pos"]
	return node


## Mirror of spawn(): WRITE one live content node's durable state BACK into its ChunkData
## entry, so a mutation survives the chunk's unload (Milestone C3b delta write-back). The
## per-Kind "what state is durable" knowledge lives HERE next to spawn() (Rule 1), not in the
## ChunkManager. Returns true iff it changed the entry (the caller flags the ChunkData dirty).
##   * MINERAL -> entry.state.integrity = the rock's Material.current_durability; a rock at 0
##     integrity (mined out but not yet freed) flags the entry `gone` instead (never respawns).
##   * ENEMY   -> entry.state.hp = the HealthComponent.current_health; hp <= 0 flags `gone`.
##   * TREE    -> intact trees carry no partial state; nothing to capture (a felled tree is
##     freed, so the ChunkManager's is_instance_valid() path flags it `gone`, not this).
static func capture(node: Node, entry: Dictionary) -> bool:
	var kind: int = int(entry["type"])
	var state: Dictionary = entry["state"]

	match kind:
		ChunkData.Kind.MINERAL:
			var mat: DurabilityComponent = node.get_node("Material") as DurabilityComponent
			var integrity: int = mat.current_durability
			if integrity <= 0:
				state["gone"] = true
				return true
			if int(state.get("integrity", -1)) != integrity:
				state["integrity"] = integrity
				return true
			return false
		ChunkData.Kind.ENEMY:
			var hc: HealthComponent = node.get_node("HealthComponent") as HealthComponent
			var hp: int = hc.current_health
			if hp <= 0:
				state["gone"] = true
				return true
			if int(state.get("hp", hc.max_health)) != hp:
				state["hp"] = hp
				return true
			return false
		ChunkData.Kind.DROP:
			# Drops are NOT captured through this paired integrity/hp loop -- the ChunkManager
			# REBUILDS drop entries wholesale from live Drop children on unload (drop_entry, so a
			# picked-up/aged-out drop simply is not swept and vanishes). Never touch the entry here.
			return false
		_:
			return false


## Snapshot ONE live Drop into a fresh Kind.DROP ChunkData entry (E3c write-back). Called by the
## ChunkManager per surviving Drop child on unload -- NOT by the paired capture() loop. Keeping
## "what a drop entry IS" here (next to spawn's DROP case) preserves this file's single job: the
## per-Kind data<->node mapping. local_pos is the drop's LOCAL position: it is a child of the
## container that sits at chunk_origin, the same convention spawn() reads back. The stored `age`
## + `lifetime` let spawn() RESUME the E3b cull instead of resetting it.
static func drop_entry(drop: Drop) -> Dictionary:
	return {
		"type": ChunkData.Kind.DROP,
		"local_pos": drop.position,
		"state": {
			"item_path": drop.item.resource_path,
			"count": drop.count,
			"age": drop._age,
			"lifetime": drop.lifetime,
		},
	}

# Verified against: Godot 4.7.1 (2026-07-18)
