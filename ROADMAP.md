# Kenslash ROADMAP -- multi-phase plan to completion (2026-07-19)

The macro build order from current state to a shippable game. Each EPIC is internally phased and
headless-verified + committed (like the environment track). Built SINGLE-PLAYER-FIRST but MP-READY;
netcode is last because everything is designed to make it additive, not a rewrite.

DEFINITION OF DONE: a shippable persistent-world, PvE co-op, survival hack-and-slash -- Icarus-style
two-track progression (talent points = self, blueprint points = building), printed gatherer NPCs, base
building, reprint/transmission death-and-save, travel between per-seed worlds + Earth Command, prestige,
on an authoritative dedicated server that lasts months.

Design sources: design-crafting.md, design-multiplayer.md, design-lore.md, design-time.md,
design-environment.md. First epic detailed in plan-core-loop.md.

---

## EPIC 0 -- Foundation  [COMPLETE]
Combat (melee, sword up/down/out swings, unarmed punch), enemy roster (tank/swordsman/charger/spitter +
deterministic variety), streamed deterministic world (chunks: trees/rocks/bushes/pebbles/boulders),
inventory/hotbar/items/weight/durability, harvest/pickup/drops, stamina/dodge/sprint/encumbrance, HUD,
environment (meadow ground, boulder terrain, elevation + inside/outside foundation). Suite 343 green.

## EPIC 1 -- Core Progression Loop (SP)   [COMPLETE 2026-07-19]  -> plan-core-loop.md
Turns the sandbox into a GAME: XP + levels -> talent tree (Track A) + blueprint learning (Track B) ->
crafting station -> a better weapon gated behind a mined material. Proves kill/gather -> craft -> survive
is fun and locks the MP-ready character-vs-world data split.
DONE: one complete playable progression loop, end to end. Suite 343 -> 537 PASS / 0 FAIL. Shipped across
5 phases (each headless-verified, adversarially reviewed, committed + pushed):
- P1 XP+levels+dual currency (talent/blueprint points) + award hooks + HUD.
- P2 TalentData/Talents + perks (melee/harvest) + respec; CharacterSheet portable bundle.
- P3 RecipeData/KnownRecipes + learn + atomic (transactional) craft.
- P4 Station + station-gate + 'f' craft menu (live-gated, auto-close).
- P5 gated iron-sword content + end-to-end capstone proof.
OPEN (user's call, not blocking): early-currency balance -- the first weapon spends 100% of the
level-1->3 talent + blueprint banks (heavy_hitter 2 talent + recipe 2 blueprint). Tune or keep as the
single early-game goal.

## EPIC 2 -- Base Building & Storage   (needs Epic 1)
Placeable crafting stations; storage/containers; craft-from-storage (Enshrouded's lesson); Windrose-style
PROXIMITY station-leveling (craft + place add-ons near a station to level it -> base grows campfire ->
workshop). The "building" pillar Track B feeds.
Done: a player can build out a functional, upgradeable base and craft from nearby storage.

## EPIC 3 -- Persistence & Save = Reprint/Transmission   (needs Epic 1-2)  -> design-lore.md
The SP save system, diegetic: memory-transmission autosave on the deterministic game-tick; reprint
respawn; on-planet Reprinting Machine (player respawn point); death penalty (lose XP since last
transmission); old-body corpse recovery; transmission-interval upgrades -> continuous. Persists
character + world-delta + base. Foundation for MP server persistence.
Done: progress saves/loads; death costs un-transmitted XP; corpse recovery works; reprint loop is real.

## EPIC 4 -- Time & Atmosphere   (needs Epic 1; flex order)  -> design-time.md
Deterministic day/night cycle (game_tick -> time-of-day), respecting the region flag (interiors/caves
ignore surface light). Optional gameplay hooks (night = tougher/more spawns, worse visibility) -- kept on
the deterministic tick.
Done: a full day/night cycle; any gameplay effect is deterministic + testable.

## EPIC 5 -- NPCs (Printing)   (needs Epic 2-3)  -> design-crafting.md / design-lore.md
Hireable PRINTED gatherer NPCs: idle base-resource labor, capped to base mats + rate-limited (so
gathering never goes fully passive). Ally job-FSM reuses the enemy _sense/telegraph scaffold. Printed by
the reprinting machine. Persist with the base.
Done: printed NPCs gather base resources within caps; survive save/reload.

## EPIC 6 -- World Travel & Earth Command   (needs Epic 3)  -> design-lore.md / design-multiplayer.md
Multiple per-SEED worlds/planets on one server; station deploy/redeploy travel; ship-to-station cargo
(the ONLY cross-world inventory move; skills/knowledge already travel); Earth Command premium tree --
"space recipes" ordered from the station with rare mined materials (the expensive high-tier tree, gated
behind rare-mineral mining in dangerous regions/caves).
Done: travel between persistent planets; ship inventory up; order + receive Earth Command gear.

## EPIC 7 -- Prestige   (needs Epic 1 + 3)  -> design-crafting.md
The renewable end-game: at talent cap, prestige re-locks the player's known-blueprints + refunds/re-earns
BLUEPRINT points (Track B), while TALENT points/perks + the physical base persist. Same-world, same-base.
Done: prestige loop works; self progression preserved, building knowledge renews.

## EPIC 8 -- Multiplayer (authoritative netcode + dedicated server)   (needs Epic 1-7)
The MP-ready SP core goes online: client/server split, replication over the FrameInput seam, dedicated
server build, solo-save-opens-as-co-op (Windrose model), friendly-fire ally hitboxes, PvE, shared
persistent world with per-player chest loot + resource/camp respawn cycles, server-authoritative anti-
cheat + persistence. Last, because everything above was built to make it additive.
Done: a dedicated server hosts a persistent PvE co-op world that survives restarts and resists cheating.

## EPIC 9 -- Content, Balance & Polish   (ongoing -> ship)
Scale the talent/blueprint trees, enemies, biomes, recipes; tune difficulty/economy/respawn; crafting +
base UI polish; audio; accessibility. Continuous; the last mile to shippable.

---

## Critical path & flex
- Linear spine: Epic 1 -> 2 -> 3 are the backbone (loop -> base -> save). 
- Flex: Epic 4 (time) and Epic 5 (NPCs) can slot anytime after their deps; do them when they add the
  most. Epic 6 needs save (3). Epic 7 needs loop + save (1,3).
- Epic 8 (MP) is deliberately LAST -- we prove a complete, fun SP game first, then network the
  authoritative sim we already have. Retrofitting MP into an unproven game is the classic trap we avoid.
- Every epic: internally phased, each phase headless-verified (bash play.sh --test) + committed, on the
  determinism rule (no Time/OS/global-RNG in sim or generator), delegated to a build agent then
  independently verified before commit.

## Guardrails carried the whole way
Determinism (testable + server-authoritative-ready); two-track separation (talent vs blueprint points);
MP-ready data split (character-portable vs world-bound inventory) from Epic 1; scope discipline (prove a
small vertical slice before scaling any tree); RefCounted component composition; data as Resources.

*Roadmap. Last updated: 2026-07-19. Living doc -- reorder flex epics as we learn from each slice.*
