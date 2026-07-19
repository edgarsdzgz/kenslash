# Multiplayer + Persistence Model -- Kenslash (user-decided + research, 2026-07-19)

The persistent-world MP model. Decisions locked with the user 2026-07-19; persistence details grounded in
Icarus + Windrose (the user's reference points). Design track; built AFTER the single-player core loop is
proven (see build order). Anti-cheat/netcode rests on the determinism rule (NOTES.md) + FrameInput seam.

## Locked decisions (user, 2026-07-19)
- **Build order = SINGLE-PLAYER-PLAYABLE CORE FIRST, MP-READY.** Keep building the authoritative
  deterministic sim playable solo/headless; prove the kill -> gather -> craft -> survive loop is fun;
  THEN add network transport. The FrameInput/determinism work already IS the server core. (Windrose
  proves this path: a solo save opens directly as co-op -- our target too.)
- **PvE, friendly fire ALWAYS ON (Icarus-style).** No PvP. But player attacks CAN hurt allies -- so
  positioning/aim matter in co-op melee; no mindless AoE into a friendly scrum. Confirmed: Icarus keeps
  friendly fire on with no toggle.
- **EVERYTHING portable EXCEPT inventory (CONFIRMED 2026-07-19).** All CHARACTER progression -- levels,
  skill points, talents, AND known-blueprints (knowledge) -- travels with the player between worlds.
  Lore: knowledge is UPLOADED and REPRINTED (ties to the transmission/reprint fiction, design-lore.md).
  INVENTORY (physical items/resources) is the ONLY thing that does NOT travel -- it stays in the world
  UNLESS the player SHIPS it to the space station via a spacecraft (an in-game action, built later).
  MORE restrictive than Windrose (carries everything) and LESS than Icarus (wipes the base each prospect,
  keeps only what you extract).
- **A world = one seed (CONFIRMED 2026-07-19).** Each planet/world IS a `world_seed`. Settles the
  multi-world question below.

## Persistence model (grounded in Windrose; adopt)
- **Per-world, shared, persistent:** bases/structures, world resources (trees/ore), and enemy camps live
  in the WORLD and persist regardless of who is online, with RESPAWN CYCLES (Windrose: daily resource
  respawn, ~24h camp respawn). Fits our "persist only the DELTA from a regenerable baseline": the world
  regenerates from seed; we store only what players changed + timers for respawn.
- **Per-player:** chest/container loot is separate per player (no racing friends to loot); raw world
  resources are shared.
- **Solo -> co-op seamless:** a solo save hosts as co-op with an invite (Windrose). This is the MP-ready
  target and why SP-first is not a detour -- the SP save IS the server save.
- **Multiple worlds per server, one active at a time; character portable across them** (Windrose). ->
  see "planets" below.

## "Planets" = worlds = seeds (reconciled lore, elegant)
A **planet = one persistent world = one `world_seed`** (our ChunkGenerator already takes `world_seed`).
A server hosts several persistent planets; the player travels between them (station deploy/redeploy,
design-lore.md); the character carries over; each planet persists independently. This IS "hundreds of
survey worlds, travel freely, all one persistent whole" -- and it maps onto code we already have.

## Progression currency (CONFIRMED 2026-07-19: TWO currencies, exactly like Icarus)
Icarus has TWO separate point currencies, one per purpose -- and they map 1:1 onto our two tracks:
- **TALENT POINTS -> self-improvement** = **Track A** (personal perks/specialization; PERSIST; portable
  with the character). Icarus: awarded per level (finite, capped).
- **BLUEPRINT POINTS -> building/crafting** = **Track B** (spent to LEARN crafting recipes; the crafting
  tree; PRESTIGE re-locks these per design-crafting.md). Icarus: accrue from ongoing XP (continue after
  talent points cap); a recipe may be gated behind a talent, then a blueprint point learns it.
The split is a REAL second currency, not node-coloring -- so prestige can wipe blueprint (building)
progress WITHOUT ever touching talent (self) progression. That is the whole point of the two-track model.
- Respec: consider an Icarus-style respec allowance so talent specialization isn't a permanent trap.
- Prestige (design-crafting.md) stays SAME-WORLD: re-locks the PLAYER's known-blueprints + refunds/re-
  earns blueprint points (Track B only); TALENT points/perks untouched; shared base structures persist;
  the planet persists; knowledge is personal so other players are unaffected.

## Combat implication of friendly-fire-always-on
- Player attack hitboxes must be able to damage ALLY players in co-op (not just enemies). SP now = no-op
  (no allies), but design combat so an ally on the player layer CAN take hits when MP lands -- do not
  hard-assume "player attacks never touch players." Note for when hurtbox/layer work meets netcode.

## Anti-cheat posture
- Authoritative dedicated server re-simulates client inputs (FrameInput) deterministically; clients
  cannot fabricate state. This is WHY the determinism rule + no-Time/OS + input-struct seam exist. Keep
  every gameplay-affecting system on the deterministic tick (incl. day/night, respawn timers) so the
  server is the single source of truth.

## Shape questions
- RESOLVED (2026-07-19): **multi-world / per-seed.** A world = one seed; a server hosts several
  persistent worlds; character (skills) portable across them; inventory world-bound unless shipped.
- Ship-to-station transfer: shipping inventory up via spacecraft is the ONLY cross-world item move ->
  needs a station cargo/hold concept + a spacecraft send/receive action. (Design later; flag now so the
  inventory data model is built world-scoped from day one, with a separate "station hold" store.)
- Deferred (post-identity): offline progression (do bases/hired NPCs produce while owners are offline?),
  hosting model (official vs self-hosted dedicated), land-claim/anti-grief details (lighter under PvE).

## Sources
- Icarus Steam discussions -- PvE up to 8, friendly fire on with no toggle.
- EIP Gaming / Icarus Wiki -- talent points (1->50) + separate blueprint points; recipes gated behind a
  talent then a blueprint point; shared respec points.
- Windrose MP/persistence guides (egamersworld / method.gg / keengamer / Steam) -- portable character;
  solo save opens as co-op; shared persistent world resources/camps/bases with respawn cycles; per-player
  chest loot; multiple worlds per dedicated server, one active, character carries across.

*MP + persistence model. Last updated: 2026-07-19. Design track; built after the SP core loop is proven.*
