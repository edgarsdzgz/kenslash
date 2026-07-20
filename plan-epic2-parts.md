# Epic 2 -- Base Building & Storage: detailed parts + goal posts (2026-07-20)

The automation checklist for Epic 2 (ROADMAP.md). Turns the player from a lone crafter into a
base-builder: PLACE crafting stations + storage in the persistent world, CRAFT FROM nearby storage
(the seam already marked in crafting.gd), and LEVEL stations by placing add-ons (Windrose). Built
SP-first / MP-ready on the character-vs-world split (placed objects + containers = WORLD data). Each PART
= a bounded build (delegated -> lead gates -> commit); each PHASE ends with the paired adversarial review.

## Automation loop (same as Epic 1; GDScript-correct gate/review)
`get phase -> detail-plan -> build PART -> GATE -> next PART -> ... -> finish PHASE -> REVIEW -> next PHASE`
- GATE: headless suite green (bash play.sh --test, no new FAIL) + determinism (no Time/OS/RNG in sim/gen)
  + parse-check + no main.tscn/scene leak + player.gd < 500 + changed-files sanity. Lead verifies, commits.
- REVIEW: 2 parallel read-only reviewers (correctness/behavior + quality/coverage). Batch fixes, re-gate.
- Standing: no emoji, no Co-Authored-By, stage by name, never read .env, RefCounted components, data as
  Resources, MP-ready character(portable)-vs-world(placed/containers) split.

## Key design decisions (sensible defaults -- flag to user only if a fork is contentious)
- PLACED OBJECTS ARE WORLD DELTAS. The streamed world = generator baseline + deltas (removals like
  gone-rocks already persist via ChunkManager). Placed stations/containers are ADDITION deltas persisted
  per-chunk, so they survive unload/reload exactly like a mined rock stays mined. Determinism preserved:
  additions are keyed by placement, NOT drawn from the generator rng, so per-Kind generator counts are
  untouched.
- PLACEMENT UX minimal + deterministic: enter build mode, a ghost preview snaps in front of the player /
  to a coarse grid, confirm places it and deducts BUILD MATERIALS from inventory (a recipe-like cost).
  Headless tests drive placement as a direct op (place(kind, world_pos)); the ghost/key-bind UX is thin.
- CONTAINERS reuse components/inventory.gd for their internal store (DRY). A container is a placed world
  entity holding its own Inventory; contents persist with the placement delta.
- CRAFT-FROM-STORAGE (the marked seam): craft aggregates availability across the player's inventory + the
  inventories of containers in range, and consumes across both (personal first, then containers, stable
  order). The craft menu's would_craft/is_craftable already funnel through Crafting, so they light up
  once storage is a source.
- STATION LEVELING (Windrose): a station carries a level; placing ADD-ON objects within its reach raises
  it; level maps to a station TIER that recipes can require (station_tag already exists -> extend with a
  tier/level the gate reads). Base visibly grows campfire -> workshop.

---

## PHASE 1 -- Placeable stations (build + place + persist)
**Part 1.1 -- Placement operation + build cost.** A `Placeable`/build path: place a Station entity at a
world position, deducting a build-material cost from inventory (recipe-like). Deterministic direct op for
tests; a thin build-mode/ghost hook may be stubbed. GOAL POST: placing a station consumes the exact build
materials and spawns a Station at the target; insufficient materials refuses (nothing consumed); the
placed Station is a real, station-gate-satisfying node (its tag works with crafting). Suite green.
**Part 1.2 -- Persistence of placed objects (world delta).** Placed stations survive chunk unload/reload:
register a placement ADDITION delta in the streaming persistence (extend ChunkManager's delta model);
regenerating the chunk reproduces baseline + the placed addition, no generator-count shift, no orphan
leak. GOAL POST: place a station, unload+reload its chunk, the station is still there (same pos/tag);
streaming determinism (existing-kind counts) unchanged; zero-orphan assertion holds. Suite green.
**PHASE 1 REVIEW.**

## PHASE 2 -- Storage containers (place + store/retrieve + persist)
**Part 2.1 -- Container entity + placement.** A placeable Container world entity holding its own
components/inventory.gd store; placed via the Part 1.1 path. GOAL POST: a container places (build cost);
it exposes an internal Inventory; 'f'/interaction opens a transfer context. Suite green.
**Part 2.2 -- Store/retrieve + persistence.** Transfer items inventory<->container (deterministic
move-N-of-item, weight-aware, atomic); container contents persist with the placement delta across unload/
reload. GOAL POST: move items both ways with exact counts (no dupe/loss), weight updates; reload restores
container contents exactly. Suite green.
**PHASE 2 REVIEW.**

## PHASE 3 -- Craft-from-storage (the marked seam)
**Part 3.1 -- Storage-sourced craft.** Extend Crafting (_has_inputs/_consume + would_craft, at the EPIC 2
STORAGE SEAM comments) to aggregate availability across the player's inventory + in-range containers, and
consume across both in a stable order (personal first, then containers). Keep ATOMIC (transactional
snapshot across all touched stores; a shortfall consumes nothing). GOAL POST: a recipe uncraftable from
inventory alone becomes craftable when a nearby container holds the missing inputs; the craft consumes the
exact split across inventory + container(s); insufficient across ALL sources refuses, nothing consumed;
the CraftMenu flag lights up from storage. Suite green.
**PHASE 3 REVIEW.**

## PHASE 4 -- Proximity station-leveling (Windrose)
**Part 4.1 -- Add-on placement raises station level.** A station carries a level (default 1); placing
ADD-ON objects within its reach raises the level (capped). Deterministic. GOAL POST: placing N add-ons
near a station raises its level by the right amount up to a cap; add-ons persist as placement deltas.
Suite green.
**Part 4.2 -- Station level effect (tier gate).** A station's level maps to a TIER; recipes may require a
minimum station tier (extend the station gate the recipe already reads). GOAL POST: a tier-gated recipe is
uncraftable at a low-level station and craftable once the station is leveled up; the tier gate composes
with the existing station_tag gate. Suite green.
**PHASE 4 REVIEW = EPIC 2 COMPLETION REVIEW.** A player can build + upgrade a functional base and craft
from nearby storage. -> Epic 3.

## Open confirmations (do NOT block Phase 1; resolve by the phase that needs them)
1. Build-material cost model: a dedicated build recipe/cost per placeable, or reuse RecipeData with a
   "placed entity" output? (Lean: a small BuildCost on the placeable; decide in Part 1.1.)
2. Placement UX depth this epic: minimal (place-in-front + confirm) vs a real grid/ghost build mode.
   (Lean minimal; polish later.)
3. Station-leveling effect: tier-gates-recipes (chosen default) vs craft-speed vs both. (Decide Part 4.2.)
4. Container capacity/slots: reuse inventory's slot+weight model as-is, or a distinct container size.

*Epic 2 detailed parts. Last updated: 2026-07-20. Built after Epic 1 (sealed 537 green).*
