# Project Conventions -- Sword Slash

Living list of self-imposed engineering rules for this project. Add rules as they are
decided. Each rule states the WHY (rules without reasons get cargo-culted or ignored)
and HOW TO APPLY. These are tripwires and defaults, not religion -- a documented,
justified exception beats a rule followed blindly.

---

## Rule 1 -- File line limits (anti-monolith)

**Production `.gd`: soft target 400 lines, hard cap 500 lines.**
- Under 400: fine.
- 400-500 (the warning band): pause and ask "does this file have more than ONE
  responsibility?" If yes, extract the extra one into a component / resource / helper.
- Over 500: SPLIT it, OR (rare) add a top-of-file justification comment
  `# LINE-CAP OK: <one-line reason this file is cohesive despite its length>`.

**Line count is a PROXY, not the goal.** The real target is single-responsibility;
the number is just the cheap, greppable tripwire. A clean 480-line file doing one thing
is fine; a 300-line file doing four things is the actual smell. When you hit the cap,
the fix is almost always "this file grew a second job -- give that job its own
component," which is exactly how the rest of this codebase already stays small
(Hitbox/Hurtbox/HealthComponent/DurabilityComponent/Inventory/ChunkData are all < 100
lines because each does one thing).

**Exceptions:**
- **Test files** (`tests/`): NOT subject to the 500 hard cap -- they legitimately
  aggregate assertions. But when a test file exceeds ~600 lines, SPLIT IT BY SYSTEM
  (e.g. `test_combat.gd`, `test_durability.gd`, `test_inventory.gd`, `test_streaming.gd`)
  rather than growing one monolith. Same anti-monolith spirit, applied per-feature.
- **Scenes (`.tscn`) and data (`.tres`)**: exempt. A long hand-authored scene is not a
  monolithic-logic problem; it is data.
- **Generated / third-party files**: exempt.

**Why these numbers:** this codebase uses heavy, load-bearing docstrings (a deliberate
good -- see the component files). That inflates raw line count per unit of logic, so a
stricter 300 would fight our own documentation. 400/500 accounts for the comment style
while still catching real accumulation. Measured as TOTAL lines (comments included --
they add scan/cognitive length too), because it is trivially enforceable with `wc -l`.

**How to apply / audit** (run from the project root):
```
find . -name "*.gd" -not -path "./.godot/*" | xargs wc -l | sort -rn | head
```
Any production `.gd` over 500 (or a test over ~600) is a refactor flag.

**Current standing (audited 2026-07-19):**
- `player/player.gd` -- **494 (2026-07-19): in the 400-500 WARNING band, under the 500 hard
  cap.** Still single-responsibility -- a player controller plus thin component facades -- so
  it stays a documented, justified occupant of the band rather than a split flag; keep the
  next subsystem out (extract it into its own component, as E1a did) rather than growing this
  file past 500. History: E1a (2026-07-18) extracted the equipment subsystem
  (equip_tool/_apply_equipped/_apply_unarmed, the per-tool durability map, the active-tool/
  broken-gate state, the inventory selection + mouse-wheel input) into
  `components/equipment.gd` (260 lines, also under cap), landing player.gd at 399; player.gd
  keeps a thin forwarding facade (equip_tool/_apply_equipped +
  inventory/_active_durability/_sword_broken getters) so the tests and HUD read `player.X`
  unchanged. It has since grown back to 494 (movement + the 3-hit combo/attack + hit-feedback
  + death/respawn + the accreted component facades).
- `tests/smoke_slash.gd` -- **RESOLVED (split 2026-07-17).** No longer the 1350-line
  monolith: it is now a ~100-line thin orchestrator + entry point that drives per-system
  modules (`tests/test_units.gd`, `tests/test_combat.gd`, `tests/test_durability_tools.gd`,
  `tests/test_streaming.gd`) over a shared `tests/test_context.gd`. Each module is under the
  ~600 test soft cap; the split preserved all 118 [PASS] assertions byte-for-byte.
- Every other production `.gd` is comfortably under 400 (the composition architecture
  keeping files small, as intended).

*Last updated: 2026-07-19*
