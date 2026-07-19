# Working Plan -- Single-Player Core Progression Loop (2026-07-19)

The FIRST build target after the design pause. Goal: turn the working combat + harvest sandbox into a
GAME with a loop -- **kill / gather -> earn XP -> spend on skills + learn recipes -> craft better gear ->
survive harder things.** Deliberately small: prove the loop is fun and shake out the data model BEFORE
scaling trees or touching netcode. Every phase headless-verified + committed, like the environment work.

Grounds in: design-crafting.md (two-track + prestige), design-multiplayer.md (dual currency, MP-ready
data split, portability), design-time.md (deterministic tick), design-lore.md (reprint/transmission).

## Guiding constraints (non-negotiable)
- **Determinism:** no Time/OS/global-RNG in the sim; XP/recipes/talents are DATA; any randomness seeded.
  Every gameplay-affecting number must be headless-assertable to an exact value.
- **TWO currencies (confirmed, exactly like Icarus):** TALENT POINTS -> self-improvement (Track A;
  personal perks; PORTABLE; persist) and BLUEPRINT POINTS -> building/crafting (Track B; spent to learn
  recipes; PRESTIGE-resettable). A real second currency, so prestige wipes building progress without
  touching self progression. Do not entangle them.
- **Portability (confirmed):** ALL character progression is portable across worlds (levels, skill points,
  talents, known-blueprints -- "upload + reprint knowledge"); ONLY inventory is world-bound. Build the
  data split accordingly (below).
- **MP-ready data split (build this way from day 1):**
  - CHARACTER data (portable across worlds): level, XP, talent points, blueprint points, unlocked
    talents, known-recipes.
  - WORLD data (world-bound; inventory only leaves via ship-to-station later): inventory, containers,
    placed stations, world deltas.
  Keep these as SEPARATE saveable stores now so portability + per-seed worlds are additive later, not a
  refactor.
- **Component discipline:** new systems are RefCounted components (like equipment/combat/stamina/
  elevation) unless they must be nodes. Data is Resource-based (like ItemData .tres).
- **Scope guard:** systems over chrome. Minimal interaction to prove the loop; polished crafting UI is
  LATER. No storage system, no NPCs, no prestige UI, no netcode in this slice (see Deferred).

## Phase 1 -- XP + Levels (the spine)
- A `Progression` component on the player (CHARACTER data): `xp`, `level`, `talent_points`,
  `blueprint_points`. XP awarded on: enemy kill (hook the existing death/kill path) and harvest yield
  (hook tree-fell / rock-mine / forage). Level curve = a pure function of xp (deterministic). Leveling
  awards TALENT points (self, Track A) and BLUEPRINT points (building, Track B) -- two separate
  currencies per Icarus (talent points level-gated/capped; blueprint points continue from XP; exact
  rates = tuning).
- No UI required beyond an optional HUD readout of level/xp.
- **Headless test (test_progression.gd):** killing an enemy grants exact XP; harvesting grants exact XP;
  crossing a threshold increments level and awards the exact point counts; curve is deterministic
  (same actions -> same level twice).
- **Done:** player accrues XP from combat + harvest and levels deterministically; points bank.

## Phase 2 -- Talent tree (Track A)
- Data-driven talents: a `TalentData` Resource (id, name, cost, prereq talent(s), effect payload).
  Author a TINY tree (3-5 nodes) with 1-2 CONCRETE perks first (e.g. +melee damage, +harvest yield).
- A `Talents` component (CHARACTER data): spend `talent_points` to unlock a node if prereqs met; apply
  its effect to the relevant stat. Include a small respec allowance (Icarus-style respec points).
- **Headless test:** cannot unlock without points/prereqs; unlocking spends the exact points and the
  perk measurably changes the stat (e.g. a swing deals more, a harvest yields more); respec refunds and
  reverts the stat.
- **Done:** points -> talents -> a measurable gameplay perk, deterministically.

## Phase 3 -- Recipe + known-blueprint model (Track B)
- A `RecipeData` Resource: inputs (ItemData + count[]) -> output (ItemData + count), optional station
  requirement, optional gate (level/talent). Author ~5 recipes.
- A `KnownRecipes` component (CHARACTER data): the set of recipe ids the player has learned. Learning a
  recipe spends a `blueprint_point` (and checks any gate, e.g. a prerequisite talent) to add it to the
  known-set. Unknown recipes are NOT craftable. (This is exactly the datum prestige re-locks later.)
- ALL recipes in this slice are WORLD recipes (craftable on-planet from world materials). "Space"
  recipes (Earth Command, ordered from the station with rare materials) come LATER, after the core loop
  is complete -- confirmed deferred.
- Crafting logic (no station yet): craft a KNOWN recipe -> validate inputs in inventory -> consume ->
  produce output. Respect weight/encumbrance already in place.
- **Headless test (test_crafting.gd):** an unknown recipe cannot be crafted; learning spends a blueprint
  point and gates correctly; crafting a known recipe consumes exact inputs and yields exact output;
  insufficient mats blocks cleanly.
- **Done:** the two-track gate works end to end: learn (Track B) then craft.

## Phase 4 -- Crafting station + minimal craft interaction
- A `Station` node the player interacts with via the existing 'f'/interaction pattern. Station-required
  recipes can only be crafted in range of the right station; craft-anywhere recipes still work loose.
- Crafting pulls mats from INVENTORY now. **Craft-from-storage is the RULE to honor the moment storage
  exists (Enshrouded's lesson) -- but storage is NOT in this slice; note the seam so it slots in.**
- Minimal craft UI: interact -> list known+craftable recipes -> craft. Chrome is minimal on purpose.
- **Headless test:** a station-gated recipe fails without the station and succeeds in range; the craft
  consumes from inventory and yields output; interaction wiring works headlessly (drive via FrameInput/
  interaction seam, not real input).
- **Done:** crafting has a place and a gate; the interaction is real and tested.

## Phase 5 -- The gated-weapon proof (the "is it fun" slice)
- Author real content that closes the loop: a higher-tier ORE (mineable, needs the current tool tier),
  a RECIPE for a better weapon (higher atk) gated behind mining that ore + spending a blueprint point
  (and maybe a talent/level gate), craftable at the station.
- Wire the full loop: fight/harvest -> level -> learn the weapon recipe -> mine the ore -> craft the
  weapon -> the weapon is measurably stronger -> harder enemies become viable.
- **Headless test:** the full chain reaches a craftable better weapon; the weapon's atk exceeds the
  starting weapon; the gate genuinely blocks until ore+point are present.
- **Done:** one complete, playable progression loop exists end to end -- the thing we actually evaluate
  for fun.

## Explicitly DEFERRED (not in this slice)
Storage/containers + craft-from-storage; hired gatherer NPCs (printing); prestige action + UI;
Earth Command premium tree; day/night; reprint/transmission save + corpse-run; ship-to-station cargo;
netcode/dedicated server; polished crafting UI; large talent/recipe trees. All additive onto this spine.

## Open confirmations -- RESOLVED (2026-07-19)
1. RESOLVED: known-blueprint knowledge IS portable (all character progression portable except inventory;
   "upload + reprint knowledge").
2. RESOLVED: only WORLD recipes this slice; space/Earth-Command recipes deferred until the core loop is
   done. (Within world recipes: default to STATION-crafted with a few basics hand-craftable -- keeps the
   station meaningful for proximity-leveling later; adjust in Phase 4 if desired.)
3. RESOLVED: TWO currencies exactly like Icarus -- TALENT points (self-improvement, Track A) + BLUEPRINT
   points (building/crafting, Track B). No separate scrap/currency layer; recipe INPUTS remain pure
   materials.

## Sequencing
Phases are ordered by dependency (1 -> 2/3 can parallel conceptually but build 1->2->3->4->5 for clean
verification). Each is a bounded build agent -> I verify headless + commit, exactly like the environment
track (meadow -> elevation -> boulders).

*Working plan. Last updated: 2026-07-19. Approve before code; then Phase 1 is the next build.*
