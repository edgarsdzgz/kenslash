# Milestone C -- The Streaming Biome (chunked, dormant, single-player)

Decided 2026-07-17. The spatial foundation the whole open world rides on. Enforces
the ONE law from the research (patterns/persistent-world-scaling-pitfalls.md):
**cost scales with PROXIMITY, not with total built content.** Built single-player,
in-memory (NO disk persistence, NO netcode yet) -- both of those layer onto this
exact lifecycle later without a rewrite.

## The law, made mechanical

- **Dormant world = plain serializable DATA** (chunk-addressable, Node-less).
- **Active, near-player world = instantiated Nodes.**
- Node instantiation is the cost gated behind proximity. A chunk 50 tiles away with
  20 trees and 3 enemies costs a small data record and ZERO Nodes / ZERO ticks.

## Chunk model (on WorldScale.TILE = 40px)

- `CHUNK_TILES = 16` -> `CHUNK_PX = 640` (Minecraft's 16 convention; tunable).
- `chunk_key = Vector2i(cx, cy)`. `world_to_chunk(pos)` = floor(pos / CHUNK_PX)
  (must floor correctly for NEGATIVE coords -- the world extends all directions).
- `chunk_origin(coord)` = coord * CHUNK_PX (top-left world pos of the chunk).
- `LOAD_RADIUS = 2` -> active set = the (2*2+1)^2 = 25 chunks around the player's
  chunk (5x5). Tunable; this is the "simulation distance." (A larger "view
  distance" for far-but-visible content can come later; not needed for C.)

## ChunkData -- the dormant form (Node-less)

`class_name ChunkData` (RefCounted): the contents of one chunk as plain records --
an array of `{type, local_pos, state}` entries (tree / mineral / enemy spawn, its
position within the chunk, and any mutated state e.g. a rock's remaining integrity).
Plus a `dirty: bool` flag. Serializes to/from a plain `Dictionary` (the future
disk/blob form -- built now so persistence is a save/load call later, not a
redesign). NEVER holds Nodes.

## Generator -- the regenerable baseline

`class_name ChunkGenerator`: `static generate(coord, world_seed) -> ChunkData`,
DETERMINISTIC -- same coord + seed always yields identical content (seeded RNG
scatter of trees/minerals/enemies per chunk). This is the "persist only the DELTA
from a regenerable baseline" insight from persistent-world-at-scale.md: the baseline
is free to regenerate, so later we only ever save chunks the player CHANGED.

## ChunkManager -- the orchestrator (THE lifecycle chokepoint)

Tracks the player's chunk each frame; maintains the active set = chunks within
LOAD_RADIUS. Single chokepoint everything hooks:
- **Chunk ENTERS active set**: get its ChunkData (generate baseline now; read
  disk-else-generate later), instantiate its content as Nodes under the world.
- **Chunk LEAVES active set**: write any changed state back into its ChunkData
  (dormancy; set dirty if changed -- the future save trigger), then FREE its Nodes.
- Enemies in a dormant chunk do not exist as Nodes and do not tick -> the PZ
  "everything simulates forever" failure mode is impossible by construction.

## Camera

Player needs a following Camera2D (currently the arena camera is static) so the
player can actually wander a world larger than the screen.

## Build sub-sequence (each headless-verified; keeps existing 80 tests green)

IMPORTANT: do NOT convert main.tscn (the combat/inventory/durability test arena) --
the existing 80-assertion suite loads it. Streaming is a NEW world scene + NEW tests;
entity-level combat logic is unchanged. The arena stays as the combat fixture; the
streaming world becomes the "real game" main scene later.

- **C1 -- pure data foundation** (no scene, fully unit-testable): chunk-coord math
  (incl. negatives), `ChunkData` (+ Dictionary round-trip), `ChunkGenerator`
  (determinism). Unit tests only.
- **C2 -- streaming orchestrator + camera**: `ChunkManager` active-set by proximity,
  instantiate/free on enter/leave, camera follow. THE anti-PZ test: drive the player
  across a large (e.g. 100x100-chunk) world and assert (a) active Node count stays
  <= the LOAD_RADIUS bound REGARDLESS of world size, and (b) leaving chunks frees
  their Nodes with ZERO orphans (get_orphan_node_count or explicit child counts).
- **C3 -- content + dormancy + delta write-back**: real trees/minerals/enemies
  spawned from ChunkData; enemy dormancy (only active-chunk enemies tick); changed
  state persists in ChunkData (mine a rock, walk away, come back -> still mined --
  the delta concept, still in-memory). Test the round-trip.

## How this serves the 200-player target (foundation, not implementation)

We can't support N players until netcode (the co-op-online milestone,
patterns/multiplayer-architecture.md). But this foundation is what makes 100-200
ACHIEVABLE instead of fantasy: server cost ~= Sum over players of (their load-radius
active set), NOT total world content. Buildings/item-hoards far from ALL players are
cold data (dormant ChunkData, later on disk), never resident Nodes. When netcode
arrives, the same active-set becomes the network interest set (one grid, three
consumers: render, replicate, persist), and per-world player caps / sharding are
tuning on top -- exactly the OSRS/WoW shape. Hard cap 200, comfortable ~100, typical
20-80: all a function of load-radius x average density x server hardware, all bounded
by construction here.

## Guardrails applied by construction (from the pitfalls research)

1. Never a Node per dormant thing -- ChunkData is Node-less. [C1]
2. Every world mutation is chunk-addressable serializable data behind a dirty flag. [C1/C3]
3. One mutation/lifecycle chokepoint -- the ChunkManager. [C2]
4. Sim/presentation separable -- the Node is always disposable, the data survives. [C2/C3]
5. Bounded active set independent of total content -- the C2 test proves it. [C2]

## Depth sorting in the streamed world (2026-07-18 -- bug fix)

Y-sort (design-world-scale.md, design-durability.md tree-depth) must be enabled on
EVERY node from the y-sorted root down to the content leaves, or it does not cross
container boundaries. In `streaming_world.tscn` the player is a sibling of the
ChunkManager, and trees live at `root -> ChunkManager -> Chunk_x_y container -> tree`,
so all THREE must set `y_sort_enabled = true`: the StreamingWorld root, the ChunkManager
node (both in the .tscn), AND each per-chunk container (set in
`chunk_manager.gd _activate_chunk` when the container Node2D is created). With the chain
enabled, player and content merge into one depth sort keyed by each node's origin.y
(feet/base) -- the player draws behind a tree when north of its base, in front when
south. Missing any level => the player always draws over the trees. Verified by a
structural assertion in test_streaming (root + manager + a live container all y-sorted).

*Verified against: Godot 4.7.1. Last updated: 2026-07-18*
