# Lore + Diegetic Systems -- Kenslash (user-decided, 2026-07-19)

The sci-fi frame that makes respawn, save, death-penalty, and NPC recruitment DIEGETIC (in-fiction)
instead of bare game conventions. This is the narrative spine every meta-system hangs off. Design track;
the "build later" pieces are called out.

## The premise
A **space station in orbit** is searching for a livable world -- the next Earth. There are **hundreds**
of survey worlds; you are a deployed surveyor/operator on the surface. NOTE (2026-07-19): the "hundreds
of worlds" are TRAVELABLE PERSISTENT REGIONS within ONE persistent world/server -- NOT prestige resets,
NOT separate instances. Players CAN travel to a new world, but it all lives in the same persistent world
(see "Persistence + multiplayer" below).

## Respawn = REPRINTING (the core conceit)
- You are 3D-printed. **Save and respawn are literally reprinting the person.** Death = your pattern is
  reprinted from your last backed-up memory.
- **Default reprint site: the space station** (you die -> reprinted in orbit).
- **Redeployment = shooting back down** from the station to your spawn point on the surface.
- **On-planet Reprinting Machine (buildable):** build one on the surface so you reprint LOCALLY instead
  of redeploying from orbit -- i.e. a closer, player-placed respawn point. (This is our respawn-point
  building; ties into the base + crafting-station work.)

## Save = MEMORY TRANSMISSION (backup)
- Progress is saved by **backing up your memories** -- a transmission to the station. Happens every
  **X IRL minutes**, like a world autosave.
- **Death penalty (diegetic):** if you die BEFORE transmitting, you reprint MISSING the XP earned since
  your last backup (the reprint only knows your last transmitted memory).
- **Recovery (corpse run, lore-justified):** recovering your **OLD BODY** recovers the lost XP -- the
  un-transmitted memories are still in the dead body. (Souls/Valheim-style retrieval, but it MAKES SENSE
  here instead of being an arbitrary tombstone.)
- **Transmission upgrades (progression sink):** upgrade to **shorter transmission intervals**, and
  eventually to **CONTINUOUS transmission** (approaching zero progress loss on death). A meaningful
  thing to invest in.

## Earth Command store (BUILD LATER)
- If materials/things were sent up, the player can **order from Earth Command** -- a special tree of
  **expensive equipment** obtained by **mining rare materials** (the currency you ship to orbit).
- This is the premium/high-tier crafting tree, gated behind rare-mineral mining. Pairs with the
  "high-quality minerals live in dangerous regions/caves" gate in design-crafting.md.

## NPCs = PRINTED
- Getting an NPC is just a matter of **printing** one. The printer/reprinting machine that reprints YOU
  also prints NPCs. This is the diegetic source of the hired GATHERER NPCs in design-crafting.md (idle
  base-resource labor). No separate "recruitment" fiction needed -- you print your crew.

## How this locks the meta-systems together
- Respawn system (already exists in code) reskins as: reprint at station by default; at the on-planet
  Reprinting Machine once built.
- Save system (BUILD LATER) = memory transmission on an interval; death restores last transmitted state.
- Death penalty + corpse recovery (BUILD LATER) = lost-since-transmission XP, restored by reaching the
  old body.
- Earth Command (BUILD LATER) = the premium crafting tree (rare-material currency).
- NPCs (design-crafting.md) = printed by the same machine.

## Prestige is NOT planet-hopping (REJECTED 2026-07-19)
Earlier proposal -- "prestige = redeploy to a fresh planet" -- is REJECTED by the user: it would defeat
the purpose of building large, long-lasting bases. Prestige stays SAME-WORLD, SAME-BASE: it re-locks
only the blueprints (per design-crafting.md); the base and the planet persist. "Traveling to a new
world" is a normal in-world action, not a prestige/reset.

## Persistence + multiplayer (DECIDED direction, 2026-07-19)
- GOAL: **multiplayer servers that last MONTHS.** Bases are large and long-lasting; the world and its
  bases outlive any session. This is a persistent-world survival game (Rust/Valheim/Icarus-dedicated
  lineage), not a run-based one.
- ONE persistent world per server. The "hundreds of worlds" are travelable persistent REGIONS in that
  same world -- players may travel to a new world, but everything stays in the one persistent world.
- Reconciled lore: the station orbits and can DEPLOY/REDEPLOY you to different survey regions ("worlds")
  that are all part of the same persistent server. Reprinting/transmission (above) is how persistence +
  respawn read in-fiction.
- The determinism rule + FrameInput seam were always the foundation for this: an authoritative server
  sim + anti-cheat needs exactly that. (Open decisions on netcode/PvP/persistence scope are being
  settled before the working plan -- see the plan discussion.)

## Engineering note (determinism)
The transmission/save timer is IRL-minute (wall-clock) based -- KEEP IT OUT of the deterministic
gameplay + generator path (our rule: no RNG/Time/OS in the sim or generator baseline). Treat save/
transmission as a SYSTEM-layer feature with an INJECTABLE tick (like the FrameInput seam), so headless
tests drive it deterministically and the gameplay simulation stays pure.

## Build order (when we get to it)
Respawn reskin (cheap, mostly narrative) -> on-planet Reprinting Machine (respawn-point building) ->
memory-transmission save + interval -> death penalty + old-body XP recovery -> transmission-interval
upgrades -> Earth Command premium tree. NPC printing rides on the crafting/printer work.

*Lore + diegetic-systems doc. Last updated: 2026-07-19. Design track; "build later" pieces flagged.*
