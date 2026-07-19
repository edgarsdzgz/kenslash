# Player Controls + Stamina -- Design (decided 2026-07-19)

Sprint, dodge, a stamina bar, and an attack remap. Built BEFORE the enemy roster (you want
dodge/sprint to fight the Swordsman). Numbers are INTENT (standard action-game feel), tuned at
build and exposed as @exports so they are all upgradable later.

## Input remap (all stay reassignable via the InputMap)
- **attack**: was Space(32)+J(74) -> **Left Mouse Button**. (Headless tests call `player.attack()`
  directly, so the rebind does not affect them.)
- **dodge** (NEW): **Spacebar** (freed up from attack).
- **sprint** (NEW): **Left Shift**, HOLD (a toggle option comes with the future settings menu).
- Add `dodge` + `sprint` to `project.godot [input]`; rebind `attack` to `MOUSE_BUTTON_LEFT`.
- Thread `sprint` + `dodge` through the **FrameInput** struct (like `move`/`attack`), so
  `_gather_input` fills them from the InputMap and a test/AI/peer can drive them via `input_override`.

## Stamina (new `components/stamina.gd` RefCounted + HUD bar)
Familiar behavior (BOTW / Souls-like). All values @export/tunable:
- **max** 100. **current** starts full.
- **Sprint drain** ~25/s (while sprinting). **Dodge cost** ~30 (flat, on the dash).
- **Regen** ~35/s, but only after a **regen delay ~0.4s** since the last consumption.
- **Exhaustion**: if `current` hits **0**, a longer **~1.2s cooldown** before regen begins (winded).
- **Low state**: `current/max < 0.25` -> the HUD bar turns red/warning.
- **Gating**: dodge requires `current >= dodge_cost`; sprint stops when `current` reaches 0.
- API sketch: `try_spend(amount) -> bool` (dodge), `drain(rate*delta)` (sprint), `tick(delta,
  consuming: bool)` (regen w/ delay + exhaustion), `ratio()`, `is_low()`. Player owns `_stamina`,
  ticks it each `_physics_process`, and exposes a facade (`stamina_ratio()`, `stamina_low()`) the HUD reads.

## Sprint -- hold Shift
- While `sprint` held AND moving AND stamina > 0: target walk speed x **SPRINT_MULT ~1.5**,
  draining stamina. Release / empty -> normal.
- **Stacks with encumbrance (DECIDED)**: multiply the ALREADY encumbrance-scaled speed, i.e.
  `max_speed * inventory.encumbrance_factor() * (sprinting ? SPRINT_MULT : 1.0)`. Weight always
  matters; overloaded sprint > overloaded walk but < light sprint.

## Dodge -- tap Space
- Tap `dodge` (just-pressed): if stamina >= dodge_cost AND not already dodging AND off cooldown ->
  spend stamina, start a **dash**.
- **Dash**: a tiny burst (~0.18s, ~1.3 tiles) in the **held move direction** (or `facing` if idle),
  via a strong short-lived velocity (not the walk speed). Short **cooldown ~0.4s** after.
- **I-frames + phase (DECIDED)**: for the dash duration the player is INVULNERABLE (set the Hurtbox
  invincible -- manage/restore it without clobbering a normal post-hit i-frame) AND **passes through
  enemies** (temporarily clear the ENEMY collision layer from the player's `collision_mask`, restore
  after -- keep WORLD collision so you do not dash through rocks/trees; if enemies share the world
  layer, give enemies their own layer bit first). Not a get-out-of-combat: it is short.

## HUD -- stamina bar
- Add a `StaminaBar` (ProgressBar, like the health bar) near the health readout (top-left) or above
  the hotbar. Reads `player.stamina_ratio()`; turns a warning tint when `stamina_low()`. Test queries
  `stamina_bar_ratio()` / `stamina_bar_low()`.

## Architecture / cap
- player.gd is 413 (soft cap 400, hard 500). Stamina -> its own component. Sprint (a speed multiply)
  + dodge (a dash state) live in the movement path; keep the additions tight. If player.gd would
  exceed ~470, extract a `components/locomotion.gd` (movement + sprint + dodge) that the player
  delegates to -- same pattern as Combat/Pickup.

## Phased build (each headless-verified via input_override + direct calls)
1. Input remap (attack->LMB, add dodge/sprint) + FrameInput fields + `components/stamina.gd` +
   HUD stamina bar. Tests: stamina consume/regen/delay/exhaustion/low math; bar reflects it.
2. Sprint: hold-sprint speed x1.5 stacked on encumbrance, drains stamina, stops at empty. Tests:
   sprinting player travels farther than walking; drains stamina; empty -> no sprint; stacks w/ weight.
3. Dodge: dash + i-frames + phase-through-enemies + cost + cooldown. Tests: dash moves ~distance in
   held dir; costs stamina; blocked when stamina < cost; invulnerable during dash (a hit does no
   damage); passes through an enemy body (ends past it); cooldown gates re-dodge.

## Non-goals (now)
- No sprint toggle (settings-menu later). No stamina-gated attacks (attacks are free for now). No
  dodge-cancel of a swing (dodge available when not mid-swing; revisit for feel). No stamina on the
  enemies yet (the Swordsman's own stamina idea is in design-enemies.md as a knob, later).

*Verified against: Godot 4.7.1. Last updated: 2026-07-19*
