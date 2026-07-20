# Epic 3 -- Persistence & Save (Reprint / Transmission): detailed parts + goal posts (2026-07-20)

Automation checklist for Epic 3 (ROADMAP.md + design-lore.md + design-time.md). The diegetic SP save loop:
a deterministic game-tick, a memory-transmission autosave to DISK (character + world-delta + base), reprint
respawn, death penalty (lose XP since last transmission), old-body corpse recovery, and transmission-
interval upgrades toward continuous. This is also the FOUNDATION for MP server persistence.

## Automation loop (same discipline)
`get phase -> build PART -> GATE (suite green + determinism + player.gd < 500 + no main.tscn/gen leak) ->
commit -> ... -> finish PHASE -> paired REVIEW -> batch fixes -> PUSH -> next PHASE`. Proceed autonomously.

## KEY DESIGN DECISIONS (defensible defaults per the design docs; flagged forks noted)
- **game_tick is a deterministic COUNTER** (design-time.md): a single int incremented once per FIXED
  physics step (`_physics_process`), NOT accumulated render delta, NOT wall-clock. Time-of-day (Epic 4)
  and the save cadence both read it. Save/restore it as one int.
- **Autosave = memory TRANSMISSION on the game-tick** (design-time.md determinism): a SYSTEM-layer scheduler
  fires every `TRANSMIT_INTERVAL_TICKS` (an injectable tick, so headless tests fast-forward deterministically
  -- NEVER wall-clock in the sim). "Every X minutes of PLAY," not real minutes -> tick-driven + deterministic.
- **Disk save = the DELTA from a regenerable baseline** (NOTES.md streaming model): serialize {game_tick,
  CharacterSheet (level/xp/talent+blueprint points/unlocked talents/known recipes/respec), ChunkManager
  delta store (removals + placement ADDITIONS incl container contents), player position, inventory} via
  store_var/JSON (paths not refs -- the idiom DROP/container contents already use). Load on start. Small +
  deterministic (baseline regenerates from seed).
- **Reprint = restore MEMORY (XP/skills) to last transmission** (design-lore.md): on death the character
  reprints with the last-TRANSMITTED memory -> XP earned since the last transmission is LOST; the old body
  (corpse) holds that un-transmitted XP; recovering it reclaims the XP. World/base/inventory are NOT rolled
  back by a death (only the character MEMORY reverts) -- FORK: inventory-on-death = KEEP (default, matches
  lore's XP-only focus) vs drop-at-corpse (decide in Phase 3; default KEEP).
- **Reprinting Machine is a PLACEABLE** -- rides Epic 2's build path (place_placeable + persistence for
  free); sets the player's on-planet reprint point (else the default spawn).
- **player.gd is at 497/500** -- Epic 3 touches player death/respawn, so the FIRST structural step (Phase 2)
  must EXTRACT from player.gd (a Respawn/Reprint concern into a component, or consolidate) to make room BEFORE
  adding reprint wiring. Do not breach 500.

---

## PHASE 1 -- game_tick + disk save/load + transmission autosave
**Part 1.1 -- deterministic game_tick.** A `game_tick` int on the world/sim, +1 per fixed physics step;
pure, saveable, no Time/OS/RNG. GOAL POST: tick advances by exactly N over N physics frames; deterministic
(same steps -> same tick); it is a single int the save can round-trip. Suite green.
**Part 1.2 -- SaveState serialize/deserialize (DISK).** A SaveState that serializes character + world-delta
+ player pos + inventory + game_tick to a user:// file (store_var/JSON, paths), and loads it back restoring
all. GOAL POST: save then load reconstructs character (level/xp/points/talents/recipes), the world deltas
(a mined rock stays mined, a placed station+contents restore), inventory, and game_tick EXACTLY; a fresh
load with no file starts clean. Determinism intact. Suite green.
**Part 1.3 -- transmission autosave scheduler.** A SYSTEM-layer scheduler that writes the save every
TRANSMIT_INTERVAL_TICKS, driven by the game_tick via an INJECTABLE tick (headless fast-forwards it). GOAL
POST: advancing the injected tick past the interval triggers exactly one transmission (a save write) and
records the last-transmitted game_tick + a snapshot of transmitted XP; no wall-clock anywhere. Suite green.
**PHASE 1 REVIEW.**

## PHASE 2 -- reprint respawn + Reprinting Machine
**Part 2.1 -- player.gd extraction + reprint respawn.** FIRST extract a Respawn/Reprint concern out of
player.gd (make room under 500). Then reskin respawn as REPRINT: on death, restore the character MEMORY
(XP) to the last-transmitted value and respawn at the reprint point. GOAL POST: player.gd < 500 after the
extraction; death -> reprint restores last-transmitted XP; behavior-neutral for the non-death path. Suite green.
**Part 2.2 -- on-planet Reprinting Machine (placeable).** A `StationReprinter`/reprint-point Placeable
(build cost; rides place_placeable + persistence); placing it sets the player's reprint point; reprint
occurs there instead of the default spawn. GOAL POST: place a reprinter, die, reprint AT it (not default);
it persists across unload/reload like the other placeables. Suite green.
**PHASE 2 REVIEW.**

## PHASE 3 -- death penalty + old-body corpse recovery
**Part 3.1 -- death XP penalty.** On death the character keeps only last-transmitted XP; the delta (XP
since transmission) is the penalty. GOAL POST: earn XP after a transmission, die -> reprinted XP == the
transmitted value (delta lost); a death right after a transmission loses ~nothing. Suite green.
**Part 3.2 -- old-body corpse + recovery.** On death spawn a CORPSE at the death spot holding the un-
transmitted XP (deterministic; persists as a world delta / drop). Recover it ('f') to reclaim that XP. GOAL
POST: death spawns a corpse carrying the lost XP; recovering it restores exactly that XP; the corpse
persists across unload/reload; recovering an empty/none is a clean no-op. Suite green.
**PHASE 3 REVIEW.**

## PHASE 4 -- transmission-interval upgrades
**Part 4.1 -- interval upgrade toward continuous.** The TRANSMIT_INTERVAL_TICKS is reducible via an upgrade
(craft/unlock), eventually CONTINUOUS (interval -> 1 tick = ~no death loss). GOAL POST: applying an upgrade
shortens the interval so transmissions fire more often and the death penalty shrinks; the max upgrade =
continuous (transmit every tick). Suite green.
**PHASE 4 REVIEW = EPIC 3 COMPLETION REVIEW.** Progress saves/loads; death costs un-transmitted XP; corpse
recovery works; the reprint loop is real. -> Epic 4 (Time; day/night rides the SAME game_tick from P1.1).

## Open forks (defensible defaults chosen; revisit only if they surface a real problem)
1. Inventory-on-death: DEFAULT KEEP (only XP reverts, per lore) vs drop-at-corpse. (Phase 3.)
2. Save file location/format: user:// + store_var (binary, simplest, store_var-safe idiom already in use)
   vs JSON. DEFAULT store_var. (Phase 1.2.)
3. Autosave vs manual save: DEFAULT autosave-only this epic (manual save is polish).
4. Does a death roll back the WORLD/BASE? DEFAULT NO -- only character memory reverts (base + world deltas
   persist through death; they only load from the last DISK save on game restart). (Phase 2/3.)

*Epic 3 detailed parts. Last updated: 2026-07-20. Built autonomously after Epic 2 (+ build-UX slice).*
