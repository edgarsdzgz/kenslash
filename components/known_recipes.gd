class_name KnownRecipes
extends RefCounted
## The character's Track B recipe KNOWLEDGE -- which recipes have been LEARNED, plus the learn/gate/spend
## VALIDATION that fences them (plan-core-loop.md Phase 3, Part 3.1; design-crafting.md "Track B -- Building /
## crafting"). CHARACTER data in the MP-ready split (design-multiplayer.md): recipe knowledge is part of the
## portable character blob (like Progression + Talents), never world-bound -- design-crafting.md's prestige loop
## re-locks EXACTLY this known set while the physical stations stay placed, so the "uploaded + reprinted
## knowledge" is precisely this per-recipe learned state. Self-contained data + logic that reads NO Input, NO
## scene, NO Time/OS/RNG and can be saved/loaded as one blob later. RefCounted (NOT a Node), exactly like
## components/talents.gd / progression.gd / stamina.gd, so it never perturbs the streaming node-count / orphan
## baselines. Part 3.2 adds craft EXECUTION (consume inputs -> produce output); THIS part is only the recipe
## catalog + the LEARN rules + standalone tests.
##
## DECOUPLED FROM PROGRESSION AND TALENTS ON PURPOSE -- the SAME pattern as Talents. Blueprint points are banked
## by Progression and talents are unlocked on Talents, but KnownRecipes reaches into NEITHER: the caller passes
## the AVAILABLE blueprint points, the UNLOCKED-talent set, and the current LEVEL to can_learn(), and after
## learn() reports the cost the CALLER (CharacterSheet.learn_recipe) deducts it from Progression.blueprint_points.
## That keeps this component pure and standalone-testable (no Progression/Talents instance needed to prove the
## learn math) and keeps the blueprint-point banking rules in one place (Progression) rather than smeared across.
##
## I/O + STATION ARE INERT HERE. Learning a recipe only adds its id to the known set; the recipe's input/output
## items + counts (RecipeData) and its station_tag change NO inventory in Part 3.1 -- Part 3.2 reads the I/O to
## execute a craft, and Phase 4 reads station_tag to gate WHERE. DETERMINISM: every method is pure set/integer/
## membership logic; no Time/OS or RNG (NOTES.md rule), so the known set and the reported costs are exactly
## headless-assertable and server-re-simulable.

## The authored recipe catalog, preloaded as shared DEFINITION resources (mirrors Talents preloading its TREE /
## player.gd preloading its ToolData .tres). CHARACTER learned state lives in `_known` below, never on these
## shared recipes. A code registry of the .tres set keeps the catalog in one greppable place; new recipes are one
## preload line + one .tres.
const CATALOG: Array[RecipeData] = [
	preload("res://data/recipes/bundle_sticks.tres"),
	preload("res://data/recipes/spin_cord.tres"),
	preload("res://data/recipes/flint_kit.tres"),
	preload("res://data/recipes/honed_edge_kit.tres"),
	preload("res://data/recipes/master_cordage.tres"),
	preload("res://data/recipes/forge_iron_sword.tres"),
]

## id (StringName) -> RecipeData, built once from CATALOG in _init so lookups are O(1). Read-only after init.
var _by_id: Dictionary = {}
## The KNOWN set: id (StringName) -> true. Dictionary-as-set (has()/keys()) -- this is the only per-character
## state here, and the one thing a save blob would persist (and a prestige re-lock would clear).
var _known: Dictionary = {}


## Index the catalog by id once. (A member initializer cannot loop, so build the map here.)
func _init() -> void:
	for r: RecipeData in CATALOG:
		_by_id[r.id] = r


## The definition for `id`, or null if no such recipe exists. Lets a caller read a recipe's cost/gates/I-O.
func recipe(id: StringName) -> RecipeData:
	return _by_id.get(id, null)


## The whole catalog (definition recipes), for enumeration (a future UI, a test). Read-only -- callers must not
## mutate the shared RecipeData nodes. Returns the const CATALOG directly.
func all_recipes() -> Array[RecipeData]:
	return CATALOG


## Whether `id` is currently KNOWN (learned) on this character.
func is_known(id: StringName) -> bool:
	return _known.has(id)


## The known ids (insertion order -- deterministic). A copy of the keys, safe for a caller to iterate.
func known_ids() -> Array:
	return _known.keys()


## How many recipes are known. Cheap facade for tests / a future crafting-menu counter.
func known_count() -> int:
	return _known.size()


## True IFF `id` names a real recipe that is NOT already known, whose blueprint cost the caller can afford
## (available_blueprint_points >= cost), whose prereq_talent gate (if any) is satisfied (the id is in the passed
## unlocked-talent set), and whose min_level gate (if any) is satisfied (level >= min_level). All three facts --
## available points, the unlocked-talent set, and the level -- are passed IN by the caller (from Progression +
## Talents) so this component stays decoupled from both. Pure query -- no state change; the caller pairs it with
## learn() + the point deduction.
func can_learn(id: StringName, available_blueprint_points: int, unlocked_talent_ids: Array, level: int) -> bool:
	var r: RecipeData = _by_id.get(id, null)
	if r == null:
		return false
	if _known.has(id):
		return false
	if available_blueprint_points < r.blueprint_cost:
		return false
	if r.prereq_talent != &"" and not (r.prereq_talent in unlocked_talent_ids):
		return false
	if level < r.min_level:
		return false
	return true


## Add `id` to the known set and RETURN its blueprint_cost (the amount the caller must deduct from
## Progression.blueprint_points). GUARDED and idempotent: returns 0 and changes NOTHING if the id is unknown or
## already known (a refused no-op). Deliberately does NOT re-check points / talent / level gates -- those live
## in Progression + Talents, and can_learn() is the gate the caller runs first; learn() enforces only the
## structural rules (existence / re-learn) so it can never be tricked into a double-learn regardless of how the
## caller drives it.
func learn(id: StringName) -> int:
	var r: RecipeData = _by_id.get(id, null)
	if r == null:
		return 0
	if _known.has(id):
		return 0
	_known[id] = true
	return r.blueprint_cost

# Verified against: Godot 4.7.1 (2026-07-19)
