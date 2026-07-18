# Sword Slash -- Design Notes

Working title: TBD. A top-down hack-and-slash: move around, slash enemies with a sword.

## Vision (the game we're eventually building toward)

Top-down (Zelda / Hades-style) hack-and-slash. The player wields a sword, slashing in a
facing direction to damage enemies. Combat is the core: it must feel weighty and responsive
-- hit feedback (flash, screen shake, knockback, brief hit-stop), readable enemy telegraphs,
i-frames on the player. Scope beyond combat (rooms, progression, story) is deliberately
undecided until the combat loop feels good.

## Core pillars

1. The slash must feel good before anything else exists. Feel > content.
2. Readable combat: the player should always understand why they got hit.
3. Code-first: built per ../../LLM_GUIDE.md, verified headlessly, GUI only when unavoidable.

## Decisions (2026-07-17)

- Perspective: top-down, 8-direction movement
- Art: placeholder primitives (ColorRect / Polygon2D) until mechanics feel good; swap real art later
- Engine: Godot 4.7.1-stable, GDScript, statically typed

## Milestone A -- First slice: "one slash, one enemy" `[COMPLETE]` (2026-07-17)

Built code-first, verified headless (smoke test exit 0). Build log in NOTES.md.

The smallest thing that proves the core loop.

- Player: CharacterBody2D, primitive body, 8-dir movement (topdown-movement recipe),
  tracks a facing direction
- Attack: press attack -> a sword Hitbox (Area2D) appears in the facing direction for a
  short window, then disappears (Hitbox/Hurtbox pattern from health-and-damage recipe)
- Enemy: a stationary dummy CharacterBody2D with a HealthComponent + Hurtbox; takes damage
  when the sword overlaps it, flashes on hit, dies (queue_free) at 0 HP
- Collision layers deliberate, per the health-and-damage recipe scheme (no default layers)
- Verified: headless smoke test positions the enemy in range, triggers an attack, asserts
  the enemy took damage and died, exits with code 0

## Recipes this slice exercises (and will stress-test)

- recipes/topdown-movement.md -- player movement + facing
- recipes/health-and-damage.md -- HealthComponent, Hitbox/Hurtbox, layer discipline, hit flash
- patterns/scene-composition.md -- components as child scenes
- patterns/state-machines.md -- (light; a real enemy FSM comes in Milestone B)

Anything that turns out wrong or awkward in practice gets fixed in the source recipe, same session.

## Milestone B -- Combat feel `[IN PROGRESS]` (started 2026-07-17)

- B1 `[COMPLETE]` (2026-07-17): enemy AI -- idle/chase/attack state machine (enum+match,
  right-sized per the state-machines recipe); enemy attacks back, so the player gained a
  HealthComponent + Hurtbox and a death->restart loop. New layers: enemy_hitbox (32),
  player_hurtbox (64). Tuning: detection 180, attack_range 34, enemy speed 70 (half player),
  enemy HP 6 / dmg 1, player HP 5 / i-frames 0.5. Verified headless (smoke exit 0).
- B2 (next): knockback, screen shake on hit, hit-stop, tuned player i-frames -> "juice"

## Inventory & hotbar -- DECIDED (2026-07-17), full spec in design-inventory.md

One array (`Inventory.slots`, default 6, grows later); hotbar is a WINDOW onto it
(hotbar_size = min(slots.size(), 10)), keyed 1,2,3,4,5,6,7,8,9,0 -> indices 0-9.
Number keys always jump directly to their slot. Scroll wheel + Q/E cycle the
`equipped_index` through the key-ring order, wrapping within the hotbar when LOCKED
(default) or the whole inventory when UNLOCKED ('g' toggle) -- unlock never rebinds
number keys, only widens the scroll/Q/E range. Auto-populate fills empty slots with
tools in priority order (sword/axe/pickaxe); `sort()` explicitly deferred. Empty/
non-tool equip = unarmed (low flat ATK, no durability/harvest interaction). No visual
UI this slice -- data model + input logic only, headless-verified.

## Durability & hardness -- DECIDED (2026-07-17), full spec in design-durability.md

Two DECOUPLED systems (the key decision): combat HP damage is predictable ATK vs DEF
(`max(0, ATK-DEF)` -- DEF can FULLY block to 0 HP); durability WEAR is a separate number
from `power` vs `hardness` (three-band model). HP and wear never share a value. BOTH the
weapon AND the struck armor/material lose durability. Durability does NOT scale
effectiveness -- armor/weapon/tool works the SAME at 1% as 100%, until it BREAKS (binary);
never punish the player for wear. Enemies always take ATK/DEF HP (DEF handles mitigation,
even to 0); hardness's "too hard" (Band C) gates only mineable MATERIALS (rock). Emergent:
0-HP vs heavy armor, but grind armor durability -> it breaks -> DEF drops -> HP gets through.
Split rule: HealthComponent = combat HP; DurabilityComponent = wear. Building the slice now.

## Milestone E -- items, harvesting & pickup -- STARTED (2026-07-18), spec in design-items.md

Harvest by attacking (existing); magnetic-pull auto-pickup; drops persist as chunk data,
age while loaded, despawn at 5 real-min (the anti-sprawl cull). Sub-sequence: E1a extract
an Equipment component out of player.gd (551, over cap -- pure refactor, pays the debt) ->
E1b ItemData/ItemStack + generalized stacking inventory (Wood/Stone) -> E2 harvest yield
(tree-on-fell, mineral-per-hit spawning drops) -> E3 Drop entity + magnetic pickup +
lifetime cull + chunk-persist. E4 (later) 'f' interaction framework once doors/chests exist.

## Milestone D -- the playable loop -- COMPLETE (2026-07-18), spec in design-playable-loop.md

DONE, 141/141 headless. D1: boots into streaming_world.tscn; world-preserving respawn
(ChunkManager+store survive death -- proven by instance identity; harvested stays
harvested; death repeatable). D2: minimal HUD (health, equipped tool+durability, hotbar
w/ active highlight) as presentation-only Control nodes reading live state (player.gd NOT
grown -- HUD per-frame reads state). The game is now a real loop: boot into the biome,
wander, fight, harvest, die, respawn with the world kept. Open debt: player.gd at 549 is
over the 500 cap (CONVENTIONS Rule 1 refactor candidate).

Boot into the biome as the real game. D1: main_scene -> streaming_world.tscn (main.tscn
kept as test fixture); death/respawn that PRESERVES the world (player.respawn_point set ->
respawn in place keeping the ChunkManager+delta store; unset -> arena reload as before) --
the concrete first instance of the decided checkpoint respawn (spawn=origin now). D2:
minimal HUD (health, equipped tool+durability, hotbar) as presentation-only Control nodes
reading live state via signals. Neither touches main.tscn contents or the combat suite.

## Open world -- Milestone C: the streaming biome -- COMPLETE (2026-07-17), spec in design-world-streaming.md

DONE end-to-end, 118/118 headless: C1 (Node-less ChunkData + deterministic generator) ->
C2 (ChunkManager bounded 25-chunk streaming, zero-orphan-leak proven) -> C3a (real
tree/mineral/enemy content) -> C3b (per-coord in-memory store + delta write-back:
mined-stays-mined, destroyed-stays-gone, enemy-HP-persists, killed-stays-gone; store is
DATA not Nodes -- live set bounded 9 while store holds 36 coords). The disk-persistence
and netcode milestones hook the SAME _activate/_deactivate chokepoint + dirty flag +
store with no rewrite. Runs as world/streaming_world.tscn (main.tscn arena untouched, its
combat/inventory/durability suite still green within the 118).

The spatial foundation everything rides on. Chunked world (16 tiles = 640px/chunk),
DORMANT = Node-less data (ChunkData), ACTIVE near-player = Nodes, freed on leave.
Single-player + in-memory first (no disk, no netcode -- both layer onto this exact
load/unload lifecycle later). Enforces the research law: cost scales with proximity,
not total built content -- the thing that makes 100-200 players achievable (server
cost ~= players x load-radius, not world size) and prevents the Project Zomboid
overload. Sub-sequence C1 (chunk data + generator, unit-tested) -> C2 (ChunkManager
streaming + camera, proves bounded active-set + zero-orphan-leak headless) -> C3
(content + enemy dormancy + delta write-back). Does NOT touch main.tscn (keeps the
80-assertion combat arena green); streaming is a new world scene + new tests.

## Multiplayer intent -- DECIDED (2026-07-17): architecture-aware now, netcode later

Goal: the game is SOLO-playable OR live ONLINE multiplayer, designing for headroom
toward 36+ players in an open world (initial target 11+). This is ambitious (MMO-lite:
real-time action netcode + replication across a large streamed world).

Scaling note (11 -> 36+): does NOT change the present guardrails -- both need server
authority + interest management + dedicated server + spatial grid. What 36+ escalates
(all in the LATER netcode phase): interest management becomes mandatory/aggressive
(naive replication is O(N^2) fan-out); replication must be optimized (delta + value
quantization + per-client bandwidth budgets); and topology may need SERVER SHARDING
(world split across server processes by region) -- the point where Godot's high-level
API is likely outgrown toward custom netcode / a backend. KEY: in an open world, local
DENSITY (players in one spot -- boss fights, hub towns, world events) sets the real
ceiling, not total count. 36 spread out w/ interest management can beat 11 in one arena.
Congregation density is a DESIGN lever (spread content, cap instance density), not only
a netcode one.

Approach: do NOT build netcode now (it would slow finding the fun). Instead adopt
cheap "multiplayer-ready guardrails" during single-player dev, and reserve real
netcode for a dedicated phase after the combat slice is fun. Solo stays the default
mode; MP = "the same simulation, driven by networked input, with a server authority."

Guardrails to hold now (mostly already true via patterns/game-code-organization.md):
- Input-STRUCT-driven controller [ADOPTED 2026-07-17]: player consumes a FrameInput
  (components/frame_input.gd); `_simulate()` reads NO Input globals; `input_override`
  is the injection point for networked peer / AI / test input. Enemies are already
  AI-driven (no Input reads), so they need no change. Verified headless (smoke leg i).
- Simulation separated from presentation (server-authority seam). [already]
- NO hardcoded "one local player": the enemy target lookup uses
  `get_first_node_in_group("player")` (one player) -- keep it easy to make
  multi-target-aware. Watch for any "the player" singletons.
- Keep gameplay server-drivable / deterministic-friendly; route state through systems.

Big synergy: the open-world CHUNK STREAMING system (load/unload by proximity) is the
SAME spatial-partition problem as network INTEREST MANAGEMENT (what to replicate to
whom). Design the spatial grid ONCE to drive both. So the phase order is:
prove combat fun -> build open-world streaming (interest-management-shaped grid) ->
layer networked input + server authority + synchronizers on that grid.

Full research + current-Godot specifics filed in
`R:\Godot_Knowledge\patterns\multiplayer-architecture.md`.

PvE vs PvP: undecided (2026-07-17). Architect for CO-OP PvE first (the forgiving
baseline -- simpler authority, easier to scale to 11+) while keeping a door open for
PvP later. Server-authoritative structure serves both, so this is not blocking.

## Vision update (2026-07-17): explorable levels + streaming + death/respawn

The game is a SERIES OF LEVELS the player walks around and explores (Metroidvania /
top-down Zelda flavor), not single arenas. This introduces three systems to design
deliberately, later, once combat feel is solid:

### Two SEPARATE loading concerns (do not conflate)
1. **Processing activation** -- "don't run AI/physics for far-away enemies."
   - Godot node: `VisibleOnScreenEnabler2D` (auto-disables a node's process/physics
     when it leaves an on-screen rect that can be enlarged past the actual screen;
     re-enables on approach). This is the cheap CPU win.
   - ALSO already handled by the enemy FSM `detection_range`: an enemy far from the
     player stays IDLE and never chases. So the "enemy walks across the whole map to
     ambush" fear is a non-issue by design -- aggro is local, gated on proximity.
2. **Memory / instantiation** -- "don't even load much outside the screen."
   - Godot has NO built-in open-world streaming; you build it from primitives.
   - Pattern to adopt: cheap **spawner markers** placed throughout a level hold only
     data; the actual enemy/prop node is instanced when the player enters a LOAD
     radius (larger than the screen) and freed past an UNLOAD radius. Threaded load
     via `ResourceLoader.load_threaded_request` for bigger chunks (see
     tooling/headless-workflow.md + 2d/ notes). This is the "load when near, not on
     enter-screen" behavior requested.
   - For discrete rooms: load a room scene on approach / at a doorway, free the
     previous one. For a contiguous map: chunk it and stream neighbors.

### Death / respawn / checkpoints -- CURRENTLY A PLACEHOLDER
- B1 death loop (CURRENT, placeholder) = player HP hits 0 -> print -> `reload_current_scene()`
  after ~1 s. A full-round restart, NOT the target system.
- DECIDED (2026-07-17): **checkpoint-based respawn** -- die -> respawn at the last checkpoint
  reached. Drives a `GameState` autoload (patterns/autoloads-and-singletons.md) holding
  current level + last checkpoint; persistence via patterns/save-systems.md.
- STILL TO DECIDE (later): what persists on death (do killed enemies stay dead? items kept?),
  lives vs infinite respawn, checkpoint placement (markers vs auto at chunk boundaries).

### Combat: assetless sword + 3-hit combo -- DECIDED (2026-07-17)

Assetless: the visible blade IS the hitbox (no separate debug overlay). Narrower
blade (~30 long x 6 wide) on a pivot at the player; it sweeps/thrusts and whatever
it crosses is hit (cleaves multiple enemies, one hit each via i-frames).

Three-hit combo, chained by pressing attack within a 0.5 s window of the last swing
(miss the window -> reset to Hit 1; after Hit 3 -> back to Hit 1):
- Hit 1: 120-degree arc sweep, direction A
- Hit 2: 120-degree arc sweep, direction B (opposite)
- Hit 3: straight LUNGE -- blade thrusts along facing, player nudges forward slightly

Attack-speed / gating rules (DECIDED 2026-07-17):
- Swing is HARD-GATED: a swing must fully complete before another can start; presses
  during an active swing are DROPPED (no input buffer). Mash 3x in one animation ->
  only one swing fires.
- `swing_duration` IS the attack-speed stat -- lower = faster; upgradeable for power
  escalation. Default snappy (~0.12 s) so it feels light, not heavy.
- The 0.5 s combo continue-window starts at the END of the swing animation, never the
  start, so a slow animation never eats the window or punishes the player.

### Enemy silhouette: directional "D" shape -- DECIDED (2026-07-17)

Enemy Body is a half-square / half-circle "D": the FRONT half (facing direction) is
a rounded semicircle (the "face"), the BACK half is a flat square edge. Built as a
single Polygon2D pointing +x: back-flat edge at x=-r, straight sides for the back
half, semicircular arc (radius r, ~10-12 segments) for the front half. The Body
Polygon2D rotates to `_facing.angle()` each frame so the rounded face points where
the enemy is headed -- so the player can always read enemy facing. Collision/hurtbox
stay circular (visual-only shape change). Stationary dummy keeps a fixed facing.
This is the visual foundation for a future enemy VISION CONE (front = line of sight).
Applies to both enemy.tscn (r~14) and dummy.tscn (r~20).

### Enemy death animation -- DECIDED (2026-07-17)

On enemy death: disable body collision (player passes THROUGH the corpse), apply a
hard knockback LURCH in the direction of the killing blow that stops abruptly (a
jerk stop, not the gradual decay), BLINK the body ~0.35 s to read as defeated, then
remove it. Distinct from the player's circle-pop death.

### Level structure -- DECIDED (2026-07-17)
- **Large contiguous maps, streamed in chunks** (not discrete rooms). Hardest streaming
  option: chunk the map, load neighbors as the player moves, free distant chunks, and hand
  enemies off across chunk borders. Enemies use spawner markers + load/unload radius +
  VisibleOnScreenEnabler2D. This is a dedicated milestone, AFTER combat feel (B2) is solid.

### New milestones this implies (rough, sequence TBD)
- Levels: room/level scene structure + transitions (recipes/scene-transitions.md exists)
- Streaming: spawner + load/unload-radius system; VisibleOnScreenEnabler2D on enemies
- Persistence: GameState autoload, checkpoints, save/load

Recommendation: finish combat (B1 tune + B2 juice) in the current arena FIRST --
streaming and checkpoints are meaningless until the moment-to-moment fight is good,
and the arena is a fine harness for that.

## Later milestones (rough, not committed)

- B: enemy AI (idle/chase/attack FSM), player i-frames, knockback, screen shake -> "combat feel"
- C: several enemies, a room, win/lose, a HUD health bar
- D: combos, enemy variety, a second room

*Verified against: Godot 4.7.1-stable. Last updated: 2026-07-17*
