class_name Progression
extends RefCounted
## The player's XP + level pool and the two point currencies it banks (plan-core-loop.md Phase 1;
## the "spine" of the core progression loop). This is CHARACTER data in the MP-ready data split
## (design-multiplayer.md): level / xp / talent points / blueprint points are PORTABLE across worlds
## (uploaded + reprinted knowledge), unlike inventory which is world-bound -- so this component is
## deliberately self-contained data/logic that reads/writes NO Input, NO scene, NO Time/OS/RNG, and
## can be saved/loaded as one character blob later without dragging world state along. RefCounted
## (NOT a Node), exactly like components/stamina.gd / elevation.gd / region.gd, so it never perturbs
## the streaming node-count / orphan baselines. The player owns one `_progression`; Part 1.2 will feed
## it XP from kills + harvest (no award hooks here yet -- this part is the curve + the banking only).
##
## TWO currencies, exactly like Icarus (design-multiplayer.md), and they must NOT entangle:
##   * TALENT POINTS  -> self-improvement (Track A). LEVEL-GATED + CAPPED: awarded once per level-up
##     only while the new level is <= TALENT_LEVEL_CAP, then they STOP. Portable, never prestige-wiped.
##   * BLUEPRINT POINTS -> building/crafting (Track B). CONTINUE: awarded every level-up, forever, with
##     no cap -- so blueprint progress keeps accruing from XP after talent points have capped out.
## Prestige (built much later) re-locks Track B without touching Track A; keeping them as two separate
## counters banked by two separate rules here is what makes that split real rather than node-coloring.
##
## DETERMINISM: the level curve and the point awards are PURE integer math -- same xp always yields the
## same level and the same banked points, so every number is headless-assertable to an exact value and
## the authoritative server can re-simulate it (NOTES.md determinism rule; design-multiplayer.md anti-
## cheat). Nothing here samples Time/OS or any RNG.

## --- TUNING (placeholders; exact rates are for later balancing) -----------------------------------
## Level curve is a CUMULATIVE TRIANGULAR RAMP. The XP cost of the step from level k to level k+1 is
## `BASE_XP + XP_STEP * (k - 1)` -- a flat base that grows linearly each level -- so the TOTAL xp needed
## to REACH level n (from level 1) is the sum of those steps:
##     xp_to_reach(n) = BASE_XP * (n - 1) + XP_STEP * ((n - 1) * (n - 2) / 2)      [n >= 1]
## The (n-1)*(n-2)/2 term is a triangular number (product of two consecutive ints, always even -> the
## /2 is exact integer division). With BASE_XP=100, XP_STEP=20 the exact thresholds are:
##     level 1 -> 0     level 2 -> 100    level 3 -> 220    level 4 -> 360
##     level 5 -> 520   level 6 -> 700    ... (each step 100, 120, 140, 160, ... apart)
## level_for_xp(xp) returns the highest n whose xp_to_reach(n) <= xp. Pure, deterministic, unbounded.
const BASE_XP: int = 100
## Extra XP added to each successive level step (the linear ramp on top of BASE_XP).
const XP_STEP: int = 20
## Highest LEVEL at which a level-up still grants a talent point (Icarus caps talents at level ~50).
## Reaching levels 2..TALENT_LEVEL_CAP each grant TALENT_PER_LEVEL; beyond it talent points stop while
## blueprint points keep accruing. Level-gated + capped -- the whole point of Track A being finite.
const TALENT_LEVEL_CAP: int = 50
## Talent points granted per qualifying level-up (<= the cap). Track A rate; tuning.
const TALENT_PER_LEVEL: int = 1
## Blueprint points granted per level-up, ALWAYS (no cap). Track B rate; tuning.
const BLUEPRINT_PER_LEVEL: int = 1

## Total accumulated experience. Only ever grows (add_xp adds a non-negative amount). Public so a test
## and a future HUD/save can read it directly.
var xp: int = 0
## Current level, derived from `xp` via the curve. Starts at 1 (level 1 costs 0 xp) and only rises.
var level: int = 1
## Banked TALENT points (Track A, self-improvement). Spent later by the Talents component (Phase 2).
var talent_points: int = 0
## Banked BLUEPRINT points (Track B, building/crafting). Spent later to learn recipes (Phase 3).
var blueprint_points: int = 0


## Award `amount` XP, then recompute the level and bank the points for EVERY level crossed. A single big
## add_xp that jumps several levels awards each intermediate level's points (the while-loop below), so
## the banked totals never depend on how the XP arrived -- only on the level reached (determinism).
## A non-positive amount is a no-op (XP never goes down; nothing to award).
func add_xp(amount: int) -> void:
	if amount <= 0:
		return
	xp += amount
	var new_level: int = level_for_xp(xp)
	# Walk one level at a time so a multi-level jump banks each level's award exactly once.
	while level < new_level:
		level += 1
		_award_for_level(level)


## PURE, DETERMINISTIC curve: the highest level whose cumulative XP threshold is met by `total_xp`.
## No Time/OS/RNG -- same input always yields the same output. Loops up from level 1 (the ramp grows,
## so it always terminates); reads NOTHING off `self`, so it can be called to preview a level for any xp.
func level_for_xp(total_xp: int) -> int:
	var lvl: int = 1
	while total_xp >= _xp_to_reach(lvl + 1):
		lvl += 1
	return lvl


## Cumulative XP required to REACH level `n` from level 1 (the triangular ramp documented in TUNING).
## n <= 1 -> 0. The (n-1)*(n-2)/2 factor is a triangular number, so the integer division is always exact.
func _xp_to_reach(n: int) -> int:
	if n <= 1:
		return 0
	return BASE_XP * (n - 1) + XP_STEP * ((n - 1) * (n - 2) / 2)


## Bank the point awards for having just reached `new_level` (called once per level gained). Blueprint
## points always accrue (Track B continues); talent points accrue only while at/under the cap (Track A
## level-gated + capped). Kept separate on purpose -- the two currencies must never entangle.
func _award_for_level(new_level: int) -> void:
	blueprint_points += BLUEPRINT_PER_LEVEL
	if new_level <= TALENT_LEVEL_CAP:
		talent_points += TALENT_PER_LEVEL

# Verified against: Godot 4.7.1 (2026-07-19)
