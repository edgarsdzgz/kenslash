# Enemy Roster -- Design (brainstormed + decided 2026-07-19)

Four archetypes: two REWORKED existing (Elephant-Tank from the dummy, Swordsman from the
humanoid chaser) + two NEW (Charger, Spitter). Goal: fights you must READ, not out-DPS --
every attacker telegraphs, every threat has counter-play. Build is queued as task 4 (after the
pebbles + the real-gram weight revision). All numbers below are INTENT (relative), tuned at build.

## Shared tech (build FIRST -- the fairness backbone, reused by all)
- **Telegraph -> strike**: every enemy attack has a readable wind-up (flash / brief pause /
  pose) then the hit. This is what makes "hard" feel fair. A small reusable helper on the enemy.
- **Aggro / provoke states**: extend the enemy FSM with a PASSIVE state and a provoke trigger
  (on `hit_taken` -> become hostile), plus a de-aggro timer (calm down after N seconds of no
  contact). Used by the Tank now; reusable.
- **Difficulty knobs as @exports** from day one (per type): move/attack speed, telegraph time,
  ATK/DEF/HP, and the type-specific ones (dodge cooldown, charge speed, fire interval). Lets one
  script back a normal AND an elite/named variant by tuning.
- **Reactive dodge** (Swordsman): "player attack active + I'm in its arc -> evade" behavior.
- **Enemy sword combo** (Swordsman): a multi-hit attack string with per-hit telegraph + recovery.
- **Projectile** (Spitter): a small moving Area2D that damages the player -- reusable for future
  ranged enemies and an eventual player bow/thrown weapon.
- Architecture note: likely a shared enemy BASE (health/hurtbox/knockback/flash/death/FSM
  scaffold -- what enemy.gd already has) + per-type AI (subclass or a behavior component). Decide
  at build; keep each type's file small and the shared bits shared.

## 1. Elephant-Tank (reworks the dummy) -- "don't poke the bear" -- DECIDED
- **Shape**: the existing 2x2 big body (dummy footprint), a heavy grey/brown look. Slow, huge.
- **AI (FSM: GRAZE -> ENRAGED -> CALM)**:
  * GRAZE (default): wanders slowly / idles, IGNORES the player entirely -- walk right past it.
  * On `hit_taken` -> ENRAGED: turns and pursues, SLOW but relentless.
  * **Calms down (decided)**: after ~5-8s with no new hit / player out of range, returns to GRAZE.
- **Stats intent**: HP very high, DEF very high (soaks many hits), ATK BRUTAL with huge knockback
  (a telegraphed stomp: long wind-up -> big AoE-ish hit that launches the player), move VERY slow,
  attack slow + heavily telegraphed. Only attacks when provoked.
- **Feel / counter**: a "is the reward worth waking it?" decision. Kite it (it's slow), dodge the
  telegraphed stomp, chip it down; one mistake hurts a lot. Should drop something good.

## 2. Swordsman (reworks the humanoid chaser) -- the DUELER -- DECIDED (the main event)
- **Shape**: the humanoid D-shape (existing), sharper/armored look, its own color (steel/crimson).
- **Offense**: 2-3 hit sword COMBOS (arc/arc/lunge-like), each with a short wind-up flash then
  fast execution; a GAP-CLOSER step-in/lunge to start a combo (so you can't just back away);
  MIX-UPS -- alternates a fast short jab (safe) with a committed combo (big, punishable).
- **Defense / mobility**: **reactive dodge** -- when your swing goes active in its face it
  side-steps / back-dashes out of the hitbox, then counters; SPACING -- circles/strafes at duel
  range, steps in to strike and out after, never just beelines. (Guard/parry = possible v2.)
- **Dodge tuning = COOLDOWN + PUNISH WINDOW (decided)**: dodges only every ~1.2s, with a short
  reaction DELAY (~0.15s) so a fast/close or well-timed hit still lands; and EVERY combo has a
  ~0.6s vulnerable RECOVERY. The skill loop: bait the dodge, punish the recovery, respect the
  combo. Perfect/omniscient dodging is deliberately removed.
- **Escalation**: more aggressive as its HP drops (and/or as the fight drags); optional low-HP
  "desperation" -- shorter dodge cooldown, faster combos.
- **Stats intent**: HP moderate-high, DEF high, ATK high, move fast. A genuine duel, not a stat check.
- **Knobs**: dodge chance/cooldown, reaction delay, combo speed, aggression -- tune fair-rival ->
  brutal-boss; reuse for a named elite later.

## 3. Charger (NEW) -- dash bruiser
- **Shape**: a big wide ARROWHEAD triangle pointing at its aim; dark maroon, heavier than the chaser.
- **AI (FSM: TRACK -> WIND-UP -> CHARGE -> RECOVER)**: tracks at a slow walk; with a clear line,
  STOPS + telegraphs (~0.6s flash/shake), then DASHES fast in a STRAIGHT line toward where you
  were, overshooting past you; then RECOVER (~1s stunned, vulnerable). Repeat.
- **Stats intent**: HP moderate, DEF moderate, ATK high on the charge with big knockback; slow
  walk, fast dash.
- **Counter**: dodge sideways during wind-up/charge, punish the recovery.

## 4. Spitter (NEW) -- ranged kiter
- **Shape**: a small DIAMOND with a little muzzle-nub; violet, fragile-looking.
- **AI (FSM: REPOSITION -> AIM -> FIRE)**: maintains a preferred distance -- backs away if you
  close in, sidesteps to keep line of sight, FIRES a slow projectile at you every ~1.5s. Low HP.
- **Stats intent**: HP low, DEF low, ATK moderate (the projectile); move moderate (kites).
- **Counter**: close the gap while dodging shots, or corner it against terrain.
- **Needs**: the reusable Projectile entity (Area2D, travels, damages the player, despawns on hit/
  range/timeout -- treat like a culled world object).

## Phased build (each headless-verified)
0. Shared: telegraph->strike helper; PASSIVE/provoke/de-aggro FSM states; difficulty @exports.
1. Elephant-Tank (rework dummy): GRAZE/ENRAGED/CALM + brutal telegraphed stomp.
2. Swordsman (rework humanoid): combos + reactive dodge (cooldown+delay+recovery) + spacing + escalation.
3. Charger: the dash FSM.
4. Spitter: Projectile entity + kiting FSM.
Chunk streaming: the new types plug into the existing ENEMY generation (or new Kinds) -- decide at
build; harvested/killed enemies already persist via the ChunkManager gone-flagging.

*Verified against: Godot 4.7.1. Last updated: 2026-07-19*
