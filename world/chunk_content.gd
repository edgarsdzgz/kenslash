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
## The three STANDALONE roster types a Kind.ENEMY entry may instead spawn as (encounter variety). One
## Kind.ENEMY still covers all four -- the specific type rides in the entry's state["enemy_type"]
## (ChunkData.EnemyType), derived deterministically by ChunkGenerator -- so the C3a census stays
## ENEMY-based and hp-capture still works through the shared base HealthComponent. The Tank reuses the
## existing tank.gd scene (enemy/dummy.tscn); a STREAMED tank is un-pinned (stationary=false, set at
## spawn) so it plays its GRAZE/ENRAGED/CALM AI in the world rather than standing as a training dummy.
const TANK_SCENE: PackedScene = preload("res://enemy/dummy.tscn")
const CHARGER_SCENE: PackedScene = preload("res://enemy/charger.tscn")
const SPITTER_SCENE: PackedScene = preload("res://enemy/spitter.tscn")
## The forageable bush scene (E4). A generated interactable (unlike DROP): spawned one-per
## BUSH entry, harvested by the player's Interaction subsystem, freed on harvest -> the
## deactivate is_instance_valid path flags its entry `gone`, so a harvested bush never respawns.
const BUSH_SCENE: PackedScene = preload("res://world/bush.tscn")
## The forageable pebble scene (E4). Like BUSH, a generated interactable spawned one-per PEBBLE
## entry, gathered by the player's Interaction subsystem, freed on gather -> the deactivate
## is_instance_valid path flags its entry `gone`, so a gathered pebble never respawns.
const PEBBLE_SCENE: PackedScene = preload("res://world/pebble.tscn")
## The Drop scene (E3c). Unlike the three above, a DROP entry is never generated -- it is a pure
## delta the ChunkManager snapshots from live Drop children on unload (drop_entry, below) and
## respawns here on reload, its item re-load()ed by resource_path and its aging RESUMED.
const DROP_SCENE: PackedScene = preload("res://world/drop.tscn")
## The UNMINEABLE boulder scene (Environment #2). Like BUSH/PEBBLE it is a generated Kind, but it is
## PERMANENT terrain: a solid StaticBody2D with NO Hurtbox/durability/drops, so it can never be destroyed
## or `gone`-flagged -- it simply respawns byte-identically every reload. Its coarse SIZE (rock/hill/
## mountain) rides in the entry's state["size"] and is applied at spawn, like the mineral's integrity.
const BOULDER_SCENE: PackedScene = preload("res://world/boulder.tscn")
## The crafting STATION scene (Epic 2 Part 1.2). Unlike the generated Kinds above, a STATION is a pure
## ADDITION delta -- never generated, recorded by ChunkManager.register_placement when the streamed-world
## build path (components/builder.gd) places one -- so it respawns here on reload EXACTLY like a DROP does,
## its station_tag re-applied from the entry's state before add_child so it re-joins the "station" group and
## gates crafting again. Its `state` carries ONLY serializable params (station_tag as a plain String), no Node.
const STATION_SCENE: PackedScene = preload("res://world/station.tscn")
## The storage CONTAINER scene (Epic 2 Phase 2 Part 2.1). The SECOND ADDITION delta, spawned identically to a
## STATION through the KIND-AGNOSTIC placeable contract (world/placeable.gd): _addition_scene() maps the entry's
## Kind to this scene, spawn() instances it and calls apply_state() from the entry's state before add_child. Part
## 2.1 round-trips an EMPTY container (identity only); its contents (Part 2.2) will ride the same state Dictionary.
const CONTAINER_SCENE: PackedScene = preload("res://world/container.tscn")

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
			# Encounter variety: the entry's state carries a deterministic enemy_type (ChunkData.
			# EnemyType) that selects WHICH roster scene to instance. All four extend Enemy and resolve
			# their target via the "player" group at runtime (the streaming_world Player is in that
			# group), so a streamed instance chases/kites/grazes with NO target wiring -- and a Tank
			# with no player near simply GRAZE-idles, a Charger/Spitter kite-idle, all no-ops. A missing
			# enemy_type (a pre-variety persisted chunk) falls back to the common Swordsman.
			var e_state: Dictionary = entry["state"]
			var e_type: int = int(e_state.get("enemy_type", ChunkData.EnemyType.SWORDSMAN))
			var enemy: Enemy
			match e_type:
				ChunkData.EnemyType.TANK:
					# The Tank scene (tank.gd on dummy.tscn) is authored `stationary = true` for the
					# durability-test dummy; un-pin a STREAMED tank so it plays its GRAZE/ENRAGED/CALM AI.
					var tank: Enemy = TANK_SCENE.instantiate()
					tank.stationary = false
					enemy = tank
				ChunkData.EnemyType.CHARGER:
					enemy = CHARGER_SCENE.instantiate()
				ChunkData.EnemyType.SPITTER:
					enemy = SPITTER_SCENE.instantiate()
				_:
					enemy = ENEMY_SCENE.instantiate()  # SWORDSMAN (default/common)
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
		ChunkData.Kind.BUSH:
			# A forageable bush (E4): no per-entry state to configure -- yields are authored on
			# the scene's exports. Positioned at local_pos by the caller like every other Kind.
			node = BUSH_SCENE.instantiate()
		ChunkData.Kind.PEBBLE:
			# A forageable pebble (E4): like BUSH, no per-entry state -- its single Stone yield is
			# authored on the scene's exports. Positioned at local_pos by the caller.
			node = PEBBLE_SCENE.instantiate()
		ChunkData.Kind.BOULDER:
			# A large UNMINEABLE terrain obstacle (Environment #2): set its coarse SIZE from the entry's
			# state BEFORE the caller add_child()s it, so boulder.gd._ready() builds the matching
			# silhouette + solid footprint (the same pre-add configure the MINERAL case uses for
			# integrity/hardness). A missing size (a pre-boulder persisted chunk) falls back to ROCK.
			var boulder: Boulder = BOULDER_SCENE.instantiate()
			var b_state: Dictionary = entry["state"]
			boulder.size = int(b_state.get("size", Boulder.Size.ROCK))
			node = boulder
		ChunkData.Kind.STATION, ChunkData.Kind.CONTAINER:
			# A placed ADDITION delta (Epic 2 -- Station or storage Container), re-created KIND-AGNOSTICALLY
			# through the placeable contract (world/placeable.gd): map the Kind to its scene, instance it, and
			# apply_state() the entry's recorded params BEFORE the caller add_child()s it -- so _ready() joins
			# the right group already configured (a Station carrying its station_tag). The same pre-add configure
			# the MINERAL/BOULDER cases use, generalized so ANY placement kind re-spawns with no new branch here.
			# The `state` holds ONLY serializable params (a Station's tag as a plain String; an empty {} for a
			# Part-2.1 container). Positioned at local_pos by the caller like every other Kind, so a reloaded
			# placement lands at the exact world position it was placed.
			var placeable: Placeable = _addition_scene(kind).instantiate() as Placeable
			placeable.apply_state(entry["state"])
			node = placeable
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
##   * TREE    -> an INTACT tree carries no partial state (nothing to capture). But a FELLED tree
##     stays a VALID, un-queued node for ~1s (fall + break-blink + linger, world/tree.gd) before it
##     frees; if its chunk unloads in THAT window it is still is_instance_valid, so this capture runs
##     while its Material.current_durability is already 0 -- flag the entry `gone` (mirrors the
##     MINERAL 0 path), else the tree would RESPAWN INTACT on reload. A fully-freed tree never
##     reaches here (the ChunkManager's is_instance_valid() path flags it `gone` instead).
static func capture(node: Node, entry: Dictionary) -> bool:
	var kind: int = int(entry["type"])
	var state: Dictionary = entry["state"]

	match kind:
		ChunkData.Kind.TREE:
			# A felled-but-not-yet-freed tree (chunk unloaded mid-fall): its Material durability is
			# already 0, so flag the entry `gone` -- it must never respawn. An intact tree (durability
			# > 0) has no partial state to persist, so nothing to capture (return false).
			var t_mat: DurabilityComponent = node.get_node("Material") as DurabilityComponent
			if t_mat.current_durability <= 0:
				state["gone"] = true
				return true
			return false
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
		ChunkData.Kind.BUSH:
			# A bush carries NO partial state: it is either intact (still a live node -> nothing to
			# capture) or harvested (queue_freed -> the ChunkManager's is_instance_valid path flags
			# the entry `gone`, exactly like a felled tree). So capture is always a no-op here.
			return false
		ChunkData.Kind.PEBBLE:
			# A pebble, like a bush, carries NO partial state: intact (a live node -> nothing to
			# capture) or gathered (queue_freed -> the ChunkManager's is_instance_valid path flags
			# the entry `gone`). So capture is always a no-op here too.
			return false
		ChunkData.Kind.BOULDER:
			# A boulder is UNMINEABLE, permanent terrain: it can never be damaged, yielded, or freed, so
			# there is NO durable delta to write back and it is never `gone` -- it respawns byte-identically
			# from the deterministic baseline every reload. So capture is always a no-op here.
			return false
		ChunkData.Kind.STATION, ChunkData.Kind.CONTAINER:
			# A placed ADDITION (Epic 2 -- Station or storage Container) carries NO durable per-node delta
			# captured HERE: the ChunkManager SKIPS every addition kind in its paired loop (ChunkData.
			# is_addition_kind), so this branch is never reached from deactivate -- it is defensive symmetry
			# with the other permanent Kinds. A Station's params live on the entry from register_placement and
			# never mutate; a Part-2.1 container is likewise identity-only. (Container CONTENTS write-back --
			# serializing the store back into the entry on unload -- is Part 2.2, and will live in THIS branch.)
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


## Map an ADDITION Kind (ChunkData.is_addition_kind) to the PackedScene spawn() instances for it -- the ONE
## place the kind -> placeable-scene decision lives, so spawn() re-creates every addition through the shared
## kind-agnostic path (instance + apply_state) with no per-kind branch. Append a case here the moment a new
## placement Kind is added (alongside its ChunkData.ADDITION_KINDS entry). Returns null for a non-addition kind
## (spawn only calls this from the STATION/CONTAINER arm, so that is unreachable there -- defensive).
static func _addition_scene(kind: int) -> PackedScene:
	match kind:
		ChunkData.Kind.STATION:
			return STATION_SCENE
		ChunkData.Kind.CONTAINER:
			return CONTAINER_SCENE
		_:
			return null

# Verified against: Godot 4.7.1 (2026-07-20)
