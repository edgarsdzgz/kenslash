# Crafting System -- Kenslash DIRECTION (user-decided, 2026-07-19)

Our crafting design, distinct from the cross-game survey (see design-crafting-research.md, which is
research). This doc records DECISIONS + the architecture mapping + open questions. Not a build spec yet;
crafting stays a DESIGN track (not built) until the forks below are settled.

## Influences (user-chosen)
- **Icarus** -- the base. Deep tech tree + talent/specialization trees + leveling. What the user has been
  building toward. Its known dead-end (below) is what our prestige loop fixes.
- **Enshrouded** -- borrow the HIRED-NPC idea, tuned: NPCs idly gather/mine ONLY base resources so
  players stay afloat while hunting higher-quality minerals. (Enshrouded made its NPCs crafters not
  gatherers to avoid trivializing the economy -- we make ours gatherers but cap them to base mats +
  rate-limit; same guardrail, different role.)
- **Windrose** -- borrow PROXIMITY station-leveling: you level a crafting station by crafting + placing
  add-on furniture near it; the base physically grows campfire -> industrial workshop. Also its
  category talent split (general/mobility, one-handed, two-handed, ranged).
- **DROPPED on purpose:** Minecraft (user dislikes it; no shape-grid). Subnautica scanning (no scan
  mechanic -- we gate by danger/depth instead).

## The core model -- TWO progression tracks
**Track A -- Personal (PERSISTS through prestige).** Character levels -> skill points -> specialization
skill trees (Icarus talents + Windrose category split: general/mobility, 1H, 2H, ranged). This is WHO
the character is. Never lost.

**Track B -- Building / crafting-station tech tree (RESETS on prestige).** WHAT the base can make.
Renewable.

### The prestige loop (user's key idea -- fixes Icarus's dead-end)
Icarus caps advancement because personal skill points run out of LEVELS to spend -- you hit the ceiling
and have nothing left to chase. Fix: when personal skills reach max, allow a **PRESTIGE RESET** ->
- KEEP all personal abilities + points (Track A untouched).
- RESET the building tech tree (Track B) -> re-climb it, chasing deeper mineral tiers.
Track A = the trophy case; Track B = the renewable engine. This is the renewable end-game grind.

**What prestige RESETS, exactly (DECIDED 2026-07-19):** prestige re-locks ONLY the crafting BLUEPRINTS
(recipe knowledge) in the tech tree. The physical crafting TABLES/STATIONS the player built stay placed
on the base -- nothing is razed. After prestige the player simply cannot craft recipes they no longer
know, and must re-unlock the blueprints. So the base stays intact; only the KNOWLEDGE is reset, and the
re-climb runs on the tables you already own.

## Hired gatherer NPCs (the "stay afloat" floor)
- Hireable NPCs that IDLY gather/mine BASE resources (wood, stone, low minerals) so the player is not
  re-grinding trivial mats (Icarus's #1 complaint) and can spend time hunting HIGH-quality minerals.
- GUARDRAIL: cap NPC output to base mats only + rate-limit it. NPCs must never supply high-tier
  minerals and never make gathering fully passive, or gathering loses meaning.

## Windrose proximity station-leveling (pairs with, not vs, the tech tree)
- Tech tree = WHAT you can build/unlock. Proximity add-ons = HOW GOOD a placed station is (craft + place
  add-on furniture near a station to level it).
- Bonus: makes the prestige rebuild TACTILE (hands-on base growth) instead of a menu re-grind.

## World-gating WITHOUT scanning
- Higher-quality minerals live in more DANGEROUS regions / deeper areas / caves. Progression gate =
  danger + depth (fits a hack-and-slash), not scan-to-learn. Ties directly into the streamed tiered
  world + enemy tiers + boulders/caves/elevation we already have.

## How the current codebase sets this up (architecture mapping)
Almost nothing here fights our architecture -- it adds components onto existing rails:
- **RefCounted component composition** -- skills, specialization trees, NPC gather-job, and
  station-leveling all drop in as components exactly like equipment/combat/stamina/elevation/region do.
- **Hired NPCs reuse the enemy AI scaffold** -- enemy.gd's `_sense()`/telegraph/de-aggro FSM is already
  a general agent brain; an ally gatherer is a sibling behavior (mine/haul job FSM vs attack FSM).
- **ItemData + weight + durability** already model tiered materials -- base vs high-quality minerals are
  higher-tier ItemData; better minerals -> better tools; weight gates hauling; durability gives crafted
  gear a lifecycle.
- **Environment work just shipped is the substrate:** boulders divide areas + seed CAVES; the
  inside/outside REGION flag is the hook for base interiors AND where NPCs work; ELEVATION sets up
  multi-level mines/bases later. High-tier minerals live in the dangerous regions/caves = our gate.
- **FrameInput + determinism seam** -- NPC idle labor stays deterministic (no RNG), so it is
  headless-testable AND multiplayer-safe by construction.

## Open questions / risks to resolve BEFORE building
1. ~~What does "reset the building tech tree" concretely destroy?~~ **RESOLVED (2026-07-19):** prestige
   re-locks ONLY the blueprints (recipe knowledge). Tables/stations stay placed; nothing is razed. The
   player just can't craft recipes they no longer know and re-unlocks the blueprint tree on the base
   they already own. (Implies: blueprint-known state is per-recipe data reset on prestige; placed
   station nodes + their proximity-level state are NOT reset -- to decide separately whether station
   PROXIMITY LEVELS also reset or persist.)
2. **NPC gathering trivializing the economy** -- must stay capped to base mats + rate-limited.
3. **Personal cap must be reachable** -- the prestige loop only works if maxing Track A is a real but
   achievable investment. Tune the level ceiling.
4. **Station model** -- craft-at-station vs craft-anywhere? (Windrose/Icarus use stations; leaning
   stations to make proximity-leveling meaningful.)
5. **Currency layer?** -- pure-material recipes, or a scrap/currency research layer (Rust) on top? (Rust
   admits currency-unlock kills the thrill of the first find -- lean pure-material + discovery-by-doing.)
6. **Craft-from-storage** -- adopt from day one once storage exists (Enshrouded's loudest complaint is
   its absence).
7. How do specialization trees map onto our weapon/tool set (sword / 2H / ranged-later / unarmed / tools)?

## Sources (Windrose)
- Nerdbot -- Windrose review (intuitive station chain, inventory/recipe UI).
- 2UpSkill / NeonLightsMedia -- Windrose base-building (proximity add-on station leveling; moving structures).
- Boostmatch -- Windrose crafting stations + build order.
- Bits N' Pixels / Prima Games / Sypnotix -- Windrose talent trees (general/mobility, 1H, 2H, ranged),
  "respects the player's time" polish.

*Design direction doc. Last updated: 2026-07-19. Crafting is a DESIGN track -- not built until forks settle.*
