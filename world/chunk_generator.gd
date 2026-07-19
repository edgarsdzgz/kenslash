class_name ChunkGenerator
## The regenerable BASELINE for a chunk (Milestone C1, design-world-streaming.md).
## `generate(coord, world_seed)` is DETERMINISTIC: the same (coord, world_seed) always
## yields byte-identical entries, because the RNG seed is derived reproducibly from the
## coord + world_seed and NOTHING here touches the global RNG or Time/OS randomness.
## This is the "persist only the DELTA from a regenerable baseline" insight from
## patterns/persistent-world-scaling-pitfalls.md: the baseline is free to regenerate,
## so later we only ever save chunks the player CHANGED.
##
## A pure static-function holder -- never instantiated (no extends; defaults to
## RefCounted), same shape as CombatResolver / DurabilityResolver.

## Scatter counts per chunk (modest + tunable). randi_range is inclusive on both ends.
const TREES_MIN: int = 2
const TREES_MAX: int = 5
const MINERALS_MIN: int = 1
const MINERALS_MAX: int = 3
## Probability a chunk also seeds a single enemy spawn.
const ENEMY_CHANCE: float = 0.35
## Forageable bushes per chunk (E4, design-items.md "Interaction 'f'"). randi_range inclusive.
const BUSH_MIN: int = 1
const BUSH_MAX: int = 3
## Forageable pebbles per chunk (E4): small stones gathered without a pickaxe. randi_range inclusive.
const PEBBLE_MIN: int = 1
const PEBBLE_MAX: int = 4
## Starting integrity baked into a fresh mineral's mutable state.
const FRESH_MINERAL_INTEGRITY: int = 4


## Build the deterministic baseline ChunkData for one chunk. Same (coord, world_seed)
## in -> identical entries out; a different coord OR seed shifts the derived RNG seed
## and so (almost surely) yields different content.
static func generate(coord: Vector2i, world_seed: int) -> ChunkData:
	var cd: ChunkData = ChunkData.new()
	cd.coord = coord

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = _derive_seed(coord, world_seed)

	var tree_count: int = rng.randi_range(TREES_MIN, TREES_MAX)
	for _i in tree_count:
		cd.entries.append({
			"type": ChunkData.Kind.TREE,
			"local_pos": _rand_local(rng),
			"state": {},
		})

	var mineral_count: int = rng.randi_range(MINERALS_MIN, MINERALS_MAX)
	for _i in mineral_count:
		cd.entries.append({
			"type": ChunkData.Kind.MINERAL,
			"local_pos": _rand_local(rng),
			"state": {"integrity": FRESH_MINERAL_INTEGRITY},
		})

	if rng.randf() < ENEMY_CHANCE:
		cd.entries.append({
			"type": ChunkData.Kind.ENEMY,
			"local_pos": _rand_local(rng),
			"state": {},
		})

	# Bushes are drawn LAST (E4): appending after the enemy draw keeps every existing
	# TREE/MINERAL/ENEMY rng draw at the SAME position in the seeded sequence, so their
	# deterministic counts/positions are byte-unchanged -- only new draws are consumed here.
	var bush_count: int = rng.randi_range(BUSH_MIN, BUSH_MAX)
	for _i in bush_count:
		cd.entries.append({
			"type": ChunkData.Kind.BUSH,
			"local_pos": _rand_local(rng),
			"state": {},
		})

	# Pebbles are drawn LAST (E4), AFTER the bush loop: appending here keeps every existing
	# TREE/MINERAL/ENEMY/BUSH rng draw at the SAME position in the seeded sequence, so their
	# deterministic counts/positions are byte-unchanged -- only these new draws are consumed.
	var pebble_count: int = rng.randi_range(PEBBLE_MIN, PEBBLE_MAX)
	for _i in pebble_count:
		cd.entries.append({
			"type": ChunkData.Kind.PEBBLE,
			"local_pos": _rand_local(rng),
			"state": {},
		})

	return cd


## Reproducible spatial hash of (coord, world_seed) -> a seed for the local RNG.
## Integer XOR-mix with large odd constants; GDScript ints are 64-bit and wrap on
## overflow, so this is stable across runs and machines (no Time/OS input). Distinct
## coords/seeds diverge, which is what makes the scatter actually seeded, not constant.
static func _derive_seed(coord: Vector2i, world_seed: int) -> int:
	var h: int = world_seed * 83492791
	h ^= coord.x * 73856093
	h ^= coord.y * 19349663
	return h


## A random position strictly within the chunk's local box [0, CHUNK_PX).
static func _rand_local(rng: RandomNumberGenerator) -> Vector2:
	return Vector2(
		rng.randf_range(0.0, WorldScale.CHUNK_PX),
		rng.randf_range(0.0, WorldScale.CHUNK_PX),
	)

# Verified against: Godot 4.7.1 (2026-07-17)
