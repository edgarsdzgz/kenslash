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
## SCOPE (Part 2.2b): the sheet owns the Progression (XP + level + the two point currencies) AND the Track A
## Talents, forwarding the XP award + level/xp readouts and now OWNING the talent SPEND (unlock_talent deducts
## talent points), the RESPEC allowance (respec refunds them), and the perk SUMS the rest of the game reads
## (melee_damage_bonus / harvest_yield_bonus). It is the SINGLE HOME the remaining character systems move into
## WITHOUT touching player.gd again: known-recipes (Phase 3) join HERE too, so player.gd accrues zero new
## per-system fields/facades. Determinism is unchanged -- pure integer ownership over Progression + Talents,
## reading/writing NO Input/scene/Time/OS/RNG; every point spend/refund and every bonus is exactly assertable.

## The player's XP + level pool and the two point currencies (components/progression.gd). Owned here (made
## in _init), not on player.gd. Public so the HUD/tests reach it via player.character().progression when
## they need a field the delegating API below does not surface (e.g. talent_points / blueprint_points).
var progression: Progression = null

## The character's Track A talent state (components/talents.gd): the unlocked-node set + the unlock/prereq/
## spend VALIDATION. Owned here (made in _init) alongside Progression, so player.gd accrues no field/facade
## for it. Public so the HUD/tests reach the raw tree/unlock queries (is_unlocked / tree() / get_talent) the
## delegating API below does not surface. The perk EFFECTS are summed off this set (melee/harvest bonuses).
var talents: Talents = null

## RESPEC allowance (design-multiplayer.md Icarus talents): a SMALL, finite number of un-picks the character
## may perform. Each respec() spends one and refunds the talent's cost; when this hits 0 no further respec is
## allowed (picks become permanent). A const start, tuning like the Progression rates -- integer, no RNG.
const RESPEC_START: int = 3
var respec_points: int = RESPEC_START


## Make the owned character systems. (A member var initializer cannot reliably reference construction of
## another component, so build here -- same pattern as Stamina seeding `current` in its _init.) Phase 3
## the known-recipes join here too.
func _init() -> void:
	progression = Progression.new()
	talents = Talents.new()


## Spend talent points to UNLOCK `id` (plan-epic1-parts.md Part 2.2b). The single spend chokepoint: gates on
## Talents.can_unlock(id, AVAILABLE points) -- reading the live Progression.talent_points -- and only on
## success does Talents.unlock() report the cost that is then DEDUCTED from Progression here. So Talents stays
## decoupled from Progression (it never touches the bank) while the two-currency banking rules stay in
## Progression. Returns whether the node actually unlocked; a refused unlock (unaffordable / unmet prereq /
## already unlocked / unknown id) deducts NOTHING and returns false. Deterministic integer spend, no Time/OS/RNG.
func unlock_talent(id: StringName) -> bool:
	if not talents.can_unlock(id, progression.talent_points):
		return false
	var cost: int = talents.unlock(id)
	progression.talent_points -= cost
	return true


## Total MELEE_DAMAGE perk from the UNLOCKED talents -- the flat ATK bonus a swing adds (read by
## components/combat.gd off the owning player's sheet). Deterministic integer sum over the unlocked set;
## 0 with nothing unlocked, and it AUTO-REVERTS when a node is respecced (it is computed, never cached).
func melee_damage_bonus() -> int:
	return _effect_sum(TalentData.EffectKind.MELEE_DAMAGE)


## Total HARVEST_YIELD perk from the UNLOCKED talents -- the extra drop count a fell/mine yields (read by
## world/harvestable_body.gd off the group-resolved player). Deterministic integer sum over the unlocked set;
## 0 with nothing unlocked, auto-reverting on respec exactly like melee_damage_bonus().
func harvest_yield_bonus() -> int:
	return _effect_sum(TalentData.EffectKind.HARVEST_YIELD)


## Sum `magnitude` over every UNLOCKED talent whose effect_kind matches `kind`. The one place the perk
## payload (TalentData.effect_kind + magnitude) is turned into a number, so both bonus readers stay a
## one-liner. Pure integer fold over the unlocked set -- no Time/OS/RNG, exactly headless-assertable.
func _effect_sum(kind: TalentData.EffectKind) -> int:
	var total: int = 0
	for id: StringName in talents.unlocked_ids():
		var t: TalentData = talents.get_talent(id)
		if t != null and t.effect_kind == kind:
			total += t.magnitude
	return total


## RESPEC (un-pick) `id`, refunding its cost to Progression.talent_points (plan-epic1-parts.md Part 2.2b).
## REFUSED (returns false, changes NOTHING) unless ALL hold: respec_points remain; `id` is currently
## unlocked; and `id` is NOT a prereq of any OTHER still-unlocked talent (un-picking it would orphan them --
## Talents.is_prereq_of_unlocked gates that). On success it relocks the node (Talents.relock reports the cost
## to refund), banks the refund, and spends one respec_point. The melee/harvest bonuses auto-revert because
## they are summed off the unlocked set. Deterministic integer refund, no Time/OS/RNG.
func respec(id: StringName) -> bool:
	if respec_points <= 0:
		return false
	if not talents.is_unlocked(id):
		return false
	if talents.is_prereq_of_unlocked(id):
		return false
	progression.talent_points += talents.relock(id)
	respec_points -= 1
	return true


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
