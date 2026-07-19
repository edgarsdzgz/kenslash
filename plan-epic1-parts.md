# Epic 1 -- Core Progression Loop: detailed parts + goal posts (2026-07-19)

The automation checklist for Epic 1 (plan-core-loop.md). Each PHASE is split into PARTS; each part is a
bounded build (delegated to an agent, then independently verified). GOAL POSTS are the exact pass
criteria. This is the granular plan the automation loop walks.

## Automation loop (GDScript-correct; /2-gate & /3-review are RN/Supabase-only, substituted)
`get phase -> detail-plan -> build PART -> GATE -> next PART -> ... -> finish PHASE -> REVIEW -> next PHASE`
- **GATE (after each part):** headless suite green (`bash play.sh --test`, no new FAIL) + determinism
  (no Time/OS/global-RNG in sim/generator) + parse-check + no main.tscn/scene leak + changed-files
  sanity. Verified by lead BEFORE commit. Each passed part = one commit.
- **REVIEW (after each phase):** parallel read-only code-review sweep (correctness + behavior + DRY/dead
  code). Fixes batched + re-verified before moving on.
- Standing: no emoji, no Co-Authored-By, stage by name, never read .env, RefCounted components, data as
  Resources, MP-ready character-vs-world data split.

---

## PHASE 1 -- XP + Levels (the spine)
**Part 1.1 -- Progression component + deterministic level curve.**
- Build: `components/progression.gd` (RefCounted, CHARACTER data): `xp`, `level`, `talent_points`,
  `blueprint_points`; `add_xp(amount)`; pure `level_for_xp(xp)->int` curve; on level-up award talent pts
  (level-gated/capped) + blueprint pts (continue) per Icarus. Wire onto player (no award hooks yet).
- GOAL POST: `test_progression.gd` asserts the curve is deterministic (same xp -> same level twice),
  crossing each threshold increments level and awards the EXACT point counts, and the talent cap holds.
  Suite green.

**Part 1.2 -- XP award hooks + HUD readout.**
- Build: award XP on enemy kill (hook the existing death/kill path) and on harvest yield (tree-fell /
  rock-mine / forage). Add a minimal HUD readout of level + xp.
- GOAL POST: test asserts a kill grants exact XP and a harvest grants exact XP, and a scripted sequence
  crosses a level boundary and banks the right points. HUD shows level/xp. Suite green.

**PHASE 1 REVIEW** -> then Phase 2.

## PHASE 2 -- Talent tree (Track A)
**Part 2.1 -- TalentData resource + Talents component (unlock/prereq/spend).**
- Build: `TalentData` Resource (id, name, cost, prereq[], effect payload); author a 3-5 node tree;
  `components/talents.gd` spends `talent_points`, enforces prereqs, tracks unlocked set (CHARACTER data).
- GOAL POST: test -- cannot unlock without points or with unmet prereq; unlocking spends the EXACT cost;
  unlocked set persists. Suite green.

**Part 2.2 -- Apply perk effects + respec.**
- Build: wire 1-2 CONCRETE perks to real stats (e.g. +melee damage, +harvest yield); Icarus-style respec
  that refunds a point and reverts the effect.
- GOAL POST: test -- a swing deals measurably more / a harvest yields measurably more after unlock;
  respec refunds the point and reverts the stat exactly. Suite green.

**PHASE 2 REVIEW** -> then Phase 3.

## PHASE 3 -- Recipe + known-blueprint model (Track B)
**Part 3.1 -- RecipeData resource + KnownRecipes + learn (spend blueprint_point).**
- Build: `RecipeData` Resource (inputs [ItemData+count], output [ItemData+count], optional station req,
  optional gate talent/level); author ~5 WORLD recipes; `components/known_recipes.gd` (CHARACTER data);
  a `learn(recipe)` that spends a `blueprint_point` + checks the gate; unknown recipes uncraftable.
- GOAL POST: test -- unknown recipe cannot craft; learning spends the exact blueprint point and respects
  the gate; known-set is correct. Suite green.

**Part 3.2 -- Craft logic (inventory inputs -> output, weight-aware).**
- Build: craft a KNOWN recipe -> validate inputs present in inventory -> consume exact inputs -> produce
  output; respect existing weight/encumbrance; block cleanly on insufficient mats.
- GOAL POST: test -- craft consumes exact inputs and yields exact output; insufficient mats blocks with
  no partial consumption; weight updates. Suite green.

**PHASE 3 REVIEW** -> then Phase 4.

## PHASE 4 -- Station + minimal craft interaction
**Part 4.1 -- Station node + interaction + station-gating.**
- Build: a `Station` node interacted with via the existing 'f'/interaction pattern; station-required
  recipes craftable only in range; a few basics remain hand-craftable.
- GOAL POST: test -- a station-gated recipe FAILS without the station and SUCCEEDS in range; hand-craft
  basics still work; interaction driven headlessly via the seam. Suite green.

**Part 4.2 -- Minimal craft UI + craft-from-inventory (storage seam).**
- Build: interact -> list known+craftable recipes -> craft (chrome minimal, systems-first); leave a clean
  seam where craft-from-storage slots in later (Epic 2).
- GOAL POST: test -- crafting through the UI path consumes from inventory and yields output; the storage
  seam is present but inert. Suite green.

**PHASE 4 REVIEW** -> then Phase 5.

## PHASE 5 -- Gated-weapon proof (the "is it fun" slice)
**Part 5.1 -- Content: higher-tier ore + better-weapon recipe + gates.**
- Build: a higher-tier ORE (mineable, needs current tool tier) as ItemData + a mineable source; a
  RecipeData for a stronger weapon gated behind the ore + a blueprint point (+ optional talent/level).
- GOAL POST: test -- the ore mines + yields; the recipe exists and its gates are wired (blocked until
  ore+point present). Suite green.

**Part 5.2 -- Full-loop wiring + end-to-end test.**
- Build: connect the chain fight/harvest -> level -> learn weapon recipe -> mine ore -> craft weapon ->
  weapon is stronger -> harder enemies viable.
- GOAL POST: an end-to-end test walks the WHOLE chain and asserts the crafted weapon's atk exceeds the
  starting weapon and the gate genuinely blocked until ore+point. Suite green.

**PHASE 5 REVIEW = EPIC 1 COMPLETION REVIEW.** One playable progression loop, end to end. -> Epic 2.

## Notes
- Later-phase detail (esp. 4-5) is provisional -- earlier phases may surface data-model tweaks; adjust
  the part before building it.
- Each part -> build agent -> lead GATE -> commit. Each phase end -> REVIEW -> batch fixes -> proceed.

*Epic 1 detailed parts. Last updated: 2026-07-19.*
