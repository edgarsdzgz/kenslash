class_name Talents
extends RefCounted
## The character's Track A talent state -- which nodes of the talent tree are UNLOCKED, plus the
## unlock/prereq/spend VALIDATION that gates them (plan-core-loop.md Phase 2, Part 2.1; design-crafting.md
## "Track A -- Personal"). CHARACTER data in the MP-ready split (design-multiplayer.md): talents are part
## of the portable character blob (like Progression), never world-bound, so this is self-contained data +
## logic that reads NO Input, NO scene, NO Time/OS/RNG and can be saved/loaded as one blob later.
## RefCounted (NOT a Node), exactly like components/progression.gd / stamina.gd / elevation.gd, so it never
## perturbs the streaming node-count / orphan baselines. Part 2.2 wires one onto the player and applies the
## unlocked nodes' effects; THIS part is only the data model + the unlock rules + standalone tests.
##
## DECOUPLED FROM PROGRESSION ON PURPOSE. Talent points are banked by Progression, but Talents never reaches
## into it -- the caller passes an AVAILABLE points count to can_unlock(), and after unlock() reports the
## cost the CALLER (Part 2.2) deducts it from Progression.talent_points. That keeps this component pure and
## standalone-testable (no Progression instance needed to prove the unlock math) and keeps the two-currency
## banking rules in one place (Progression) rather than smeared across both.
##
## EFFECTS ARE INERT HERE. Unlocking a node only adds its id to the unlocked set; the node's
## effect_kind/magnitude (TalentData) change NO gameplay stat in Part 2.1 -- Part 2.2 reads them to apply
## the perk. DETERMINISM: every method is pure set/integer logic; no Time/OS or RNG (NOTES.md rule), so the
## unlocked set and the reported costs are exactly headless-assertable and server-re-simulable.

## The authored tree, preloaded as shared DEFINITION resources (mirrors player.gd preloading its ToolData
## .tres). CHARACTER unlock state lives in `_unlocked` below, never on these shared nodes. A code registry
## of the .tres set keeps the tree in one greppable place; new nodes are one preload line + one .tres.
const TREE: Array[TalentData] = [
	preload("res://data/talents/blade_focus.tres"),
	preload("res://data/talents/keen_edge.tres"),
	preload("res://data/talents/master_strike.tres"),
	preload("res://data/talents/forager.tres"),
	preload("res://data/talents/heavy_hitter.tres"),
]

## id (StringName) -> TalentData, built once from TREE in _init so lookups are O(1). Read-only after init.
var _by_id: Dictionary = {}
## The UNLOCKED set: id (StringName) -> true. Dictionary-as-set (has()/keys()) -- this is the only
## per-character state here, and the one thing a save blob would persist.
var _unlocked: Dictionary = {}


## Index the tree by id once. (A member initializer cannot loop, so build the map here.)
func _init() -> void:
	for t: TalentData in TREE:
		_by_id[t.id] = t


## The whole tree (definition nodes), for enumeration (a future UI, a test). Read-only -- callers must not
## mutate the shared TalentData nodes. Returns the const TREE directly.
func tree() -> Array[TalentData]:
	return TREE


## The definition for `id`, or null if no such node exists. Lets a caller read a node's cost/prereqs/effect.
func get_talent(id: StringName) -> TalentData:
	return _by_id.get(id, null)


## Whether the tree contains a node with this id (independent of unlock state).
func has_talent(id: StringName) -> bool:
	return _by_id.has(id)


## Whether `id` is currently unlocked on this character.
func is_unlocked(id: StringName) -> bool:
	return _unlocked.has(id)


## The unlocked ids (insertion order -- deterministic). A copy of the keys, safe for a caller to iterate.
func unlocked_ids() -> Array:
	return _unlocked.keys()


## How many nodes are unlocked. Cheap facade for tests / a future HUD counter.
func unlocked_count() -> int:
	return _unlocked.size()


## Whether every prereq id of `t` is already unlocked (a root node with no prereqs trivially passes).
func _prereqs_met(t: TalentData) -> bool:
	for p: StringName in t.prereqs:
		if not _unlocked.has(p):
			return false
	return true


## True IFF `id` names a real node that is NOT already unlocked, whose prereqs are ALL unlocked, and whose
## cost the caller can afford (available_points >= cost). `available_points` is passed in by the caller
## (from Progression.talent_points) so this component stays decoupled from Progression. Pure query -- no
## state change; the caller pairs it with unlock() + the point deduction.
func can_unlock(id: StringName, available_points: int) -> bool:
	var t: TalentData = _by_id.get(id, null)
	if t == null:
		return false
	if _unlocked.has(id):
		return false
	if not _prereqs_met(t):
		return false
	return available_points >= t.cost


## Add `id` to the unlocked set and RETURN its cost (the amount the caller must deduct from
## Progression.talent_points). GUARDED and idempotent: returns 0 and changes NOTHING if the id is unknown,
## already unlocked, or has an unmet prereq (a refused no-op). Deliberately does NOT check available points
## -- points live in Progression, and can_unlock() is the affordability gate the caller runs first; unlock()
## enforces only the structural rules (existence / re-unlock / prereqs) so it can never be tricked into a
## double-unlock or a prereq skip regardless of how the caller drives it.
func unlock(id: StringName) -> int:
	var t: TalentData = _by_id.get(id, null)
	if t == null:
		return 0
	if _unlocked.has(id):
		return 0
	if not _prereqs_met(t):
		return 0
	_unlocked[id] = true
	return t.cost


## Whether `id` is listed as a prereq of ANY currently-unlocked node -- i.e. relocking `id` would strand a
## still-unlocked descendant with an unmet prereq. The RESPEC gate the caller (CharacterSheet.respec) checks
## so an un-pick can never orphan the tree. Pure query over the unlocked set + the definition prereqs.
func is_prereq_of_unlocked(id: StringName) -> bool:
	for other: StringName in _unlocked:
		var t: TalentData = _by_id.get(other, null)
		if t != null and id in t.prereqs:
			return true
	return false


## The inverse of unlock(): REMOVE `id` from the unlocked set and RETURN its cost (the amount the caller
## must REFUND to Progression.talent_points). GUARDED no-op -- returns 0 and changes NOTHING if `id` is not
## currently unlocked. Deliberately does NOT check prereq-orphaning or the respec allowance: those are the
## respec RULES, enforced by the caller (CharacterSheet.respec) exactly as unlock() leaves the point
## affordability to the caller. Pairing unlock()<->relock() keeps the unlocked set and the reported costs
## symmetric, so a respec exactly reverses the spend it undoes.
func relock(id: StringName) -> int:
	if not _unlocked.has(id):
		return 0
	var cost: int = _by_id[id].cost
	_unlocked.erase(id)
	return cost

# Verified against: Godot 4.7.1 (2026-07-19)
