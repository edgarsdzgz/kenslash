class_name Stamina
extends RefCounted
## The player's stamina pool (design-controls.md): a familiar BOTW / Souls-like meter that
## sprinting DRAINS per-frame and a dodge SPENDS in a flat lump, then regenerates -- but only
## after a short grace since the last consumption, with a LONGER "winded" cooldown if it ever
## bottomed out at zero. RefCounted (NOT a Node), exactly like components/combat.gd and the
## other subsystems, so it never perturbs the streaming node-count / orphan baselines. The
## player owns one `_stamina`, ticks it each _physics_process, and exposes a facade
## (stamina_ratio / stamina_low) the HUD reads.
##
## DELAY vs EXHAUSTION -- the two distinct waits, both measured off `_since_spend` (seconds since
## the last drain/spend):
##   * regen_delay (~0.4s, SHORT): the normal pause after ANY consumption before regen resumes,
##     while stamina still has charge left. Keeps a tap of sprint from instantly refilling.
##   * exhaust_cooldown (~1.2s, LONG): applies ONLY after `current` hit 0 (the `_exhausted`
##     latch). You are "winded" -- regen waits the longer window before it begins. The latch is
##     cleared the moment regen actually starts again.
## `can_sprint()` is false while exhausted (current 0), so sprint cannot resume until regen has
## clawed stamina back above zero after the winded wait.

## Full pool. `current` starts here. @export-style tunable (a plain var so a future upgrade or a
## test can set it) -- kept as fields rather than @export since Stamina is a RefCounted, not a Node.
var max_stamina: float = 100.0
## Per-SECOND drain while sprinting (applied as sprint_drain * delta by the caller via drain()).
var sprint_drain: float = 25.0
## Flat cost SPENT on a dodge dash (try_spend). A dodge is blocked when current < this.
var dodge_cost: float = 30.0
## Per-second regeneration once the applicable wait (delay, or the longer exhaust cooldown) elapses.
var regen_rate: float = 35.0
## SHORT grace after any consumption before regen resumes (while stamina still has charge).
var regen_delay: float = 0.4
## LONG "winded" cooldown that replaces regen_delay after `current` hit 0 (the `_exhausted` latch).
var exhaust_cooldown: float = 1.2
## Below this fraction of max, is_low() is true -> the HUD bar turns a warning tint.
var low_frac: float = 0.25

## Current charge, 0..max_stamina. Seeded to max_stamina in _init.
var current: float = 100.0
## Seconds since the last consumption (drain or spend). Regen is gated until it passes the
## applicable wait; consuming resets it to 0.
var _since_spend: float = 0.0
## Latched true when `current` reaches 0; selects the LONGER exhaust_cooldown wait and blocks
## sprint (can_sprint) until regen begins. Cleared the moment regen resumes.
var _exhausted: bool = false


## Start full. (A member var initializer cannot reference another member reliably, so seed here.)
func _init() -> void:
	current = max_stamina


## Try to SPEND `amount` (a dodge). Returns false and changes nothing if there is not enough;
## on success it deducts, resets the regen clock, and latches exhaustion if it drained to 0.
func try_spend(amount: float) -> bool:
	if current < amount:
		return false
	current -= amount
	_since_spend = 0.0
	if current <= 0.0:
		current = 0.0
		_exhausted = true
	return true


## DRAIN `amount` (sprint's per-frame cost = sprint_drain * delta). Clamps at 0, resets the regen
## clock, and latches exhaustion on hitting 0. Unlike try_spend this always applies (sprint just
## stops once can_sprint() goes false; the caller gates that).
func drain(amount: float) -> void:
	current = maxf(0.0, current - amount)
	_since_spend = 0.0
	if current <= 0.0:
		_exhausted = true


## Advance regen one tick. `consuming` = the player sprinted or dodged THIS frame; while true (or
## within the applicable wait since the last consumption) NO regen happens. Once the wait elapses,
## clear any exhaustion latch and regen toward max. The wait is the long exhaust_cooldown while
## exhausted, else the short regen_delay.
func tick(delta: float, consuming: bool) -> void:
	if consuming:
		_since_spend = 0.0
		return
	_since_spend += delta
	var wait: float = exhaust_cooldown if _exhausted else regen_delay
	if _since_spend < wait:
		return
	_exhausted = false
	current = minf(max_stamina, current + regen_rate * delta)


## Current charge as a 0..1 fraction of max (the HUD bar fill).
func ratio() -> float:
	return current / max_stamina if max_stamina > 0.0 else 0.0


## Whether stamina is in the low/warning band (< low_frac of max) -> the HUD tints the bar.
func is_low() -> bool:
	return ratio() < low_frac


## Whether sprinting is allowed: any charge left AND not currently exhausted (winded at 0).
func can_sprint() -> bool:
	return current > 0.0 and not _exhausted

# Verified against: Godot 4.7.1 (2026-07-19)
