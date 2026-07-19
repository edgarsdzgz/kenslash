class_name CharacterSheet
extends RefCounted
## The portable CHARACTER bundle (design-multiplayer.md). In the MP-ready data split, CHARACTER data --
## level / xp / skill (talent) points / talents / known-recipes -- is the bundle that TRAVELS BETWEEN
## WORLDS (uploaded + reprinted knowledge), unlike inventory which is world-bound. This component IS that
## bundle: it OWNS the player's per-character systems so player.gd stops growing a field + facade per
## system (CONVENTIONS.md Rule 1, the 500-line cap). RefCounted (NOT a Node), exactly like
## components/progression.gd / stamina.gd / elevation.gd / region.gd, so it never perturbs the streaming
## node-count / orphan baselines. The player owns one `_character` and reaches its systems through here.
##
## SCOPE (Part 2.2a): today the sheet owns only the Progression (XP + level + the two point currencies)
## and forwards the award + the level/xp readouts. It is the SINGLE HOME the rest of the character
## systems move into WITHOUT touching player.gd again: talents (Part 2.2b) and known-recipes (Phase 3)
## join HERE, so player.gd accrues zero new per-system fields/facades as those land. Determinism is
## unchanged -- this is a pure ownership seam over Progression, reading/writing NO Input/scene/Time/OS/RNG.

## The player's XP + level pool and the two point currencies (components/progression.gd). Owned here (made
## in _init), not on player.gd. Public so the HUD/tests reach it via player.character().progression when
## they need a field the delegating API below does not surface (e.g. talent_points / blueprint_points).
var progression: Progression = null


## Make the owned character systems. (A member var initializer cannot reliably reference construction of
## another component, so build here -- same pattern as Stamina seeding `current` in its _init.) Part 2.2b
## will also construct the Talents here; Phase 3 the known-recipes.
func _init() -> void:
	progression = Progression.new()


## Award `amount` XP to the owned Progression (delegating API -> Progression.add_xp). The player's group-
## resolved award_xp facade forwards here, so kill/harvest callers bank XP without knowing the sheet owns
## the Progression. Integer amounts, no Time/OS/RNG -- add_xp does the deterministic level/point banking.
func award_xp(amount: int) -> void:
	progression.add_xp(amount)


## Current level (delegating read -> Progression.level). The HUD polls this each frame for its level line.
func level() -> int:
	return progression.level


## Total accumulated XP (delegating read -> Progression.xp). The HUD polls this each frame for its xp line.
func xp() -> int:
	return progression.xp

# Verified against: Godot 4.7.1 (2026-07-19)
