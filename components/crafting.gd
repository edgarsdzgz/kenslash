class_name Crafting
extends RefCounted
## Craft EXECUTION -- turn a KNOWN recipe's inputs (held in the player's Inventory) into its output
## (plan-epic1-parts.md Part 3.2; plan-core-loop.md Phase 3; design-crafting.md "Track B"). The COMPANION
## to KnownRecipes: KnownRecipes owns WHICH recipes a character has LEARNED (Part 3.1); this owns actually
## RUNNING one -- validate the inputs are present, consume the exact counts, produce the output. RefCounted
## (NOT a Node), exactly like components/known_recipes.gd / stamina.gd / elevation.gd, so it never perturbs
## the streaming node-count / orphan baselines and is directly testable with `Crafting.new()` + plain
## component instances (no player/scene wiring needed).
##
## STATELESS. This component holds NO per-character state -- the known set lives on the CharacterSheet's
## KnownRecipes, the materials live on the Inventory -- so ONE Crafting instance can serve any sheet/inventory
## pair (or a test can `Crafting.new()` per call). It only ORCHESTRATES the two: read the known recipe off the
## sheet, mutate the inventory.
##
## ATOMIC. craft() verifies known + EVERY input present BEFORE it removes anything; on ANY shortfall it
## consumes NOTHING and returns false -- never a partial consumption. Determinism: pure membership + integer
## counts over the passed components; no Input/scene/Time/OS/RNG (NOTES.md rule), so every craft is exactly
## headless-assertable and server-re-simulable.
##
## INVENTORY-ONLY SOURCE (Epic 1). Inputs are pulled from the player's Inventory ONLY; Epic 2's craft-from-
## nearby-STORAGE plugs in at the marked seam in _has_inputs / _consume (see the comments there). Weight is
## respected the NORMAL way: removing inputs and adding the output re-flow through the Inventory's own
## remove_item/add_item, so total_weight()/encumbrance update exactly as for any pickup; this component invents
## NO hard weight block (the inventory enforces none on add -- pickup never blocks, so neither does a craft).


## Whether `recipe` can be crafted RIGHT NOW from `inventory` -- the recipe is real (non-null) and the
## inventory holds EVERY input_items[i] in at least input_counts[i]. This is the MATERIAL-availability half of
## craftability; the known-set membership is enforced by craft() at its chokepoint (it resolves the recipe off
## the sheet's KnownRecipes first), kept separate so a future craft UI can grey out un-affordable KNOWN recipes
## without re-resolving them. Pure read -- changes nothing. A null recipe (or inventory) -> false.
##
## EPIC 2 STORAGE SEAM: today availability is (inventory) only. When craft-from-storage lands, this becomes
## "held across inventory + every in-range container"; the extra source is OR-ed in via _has_inputs, leaving
## this signature and the atomic contract intact.
func can_craft(recipe: RecipeData, inventory: Inventory) -> bool:
	if recipe == null or inventory == null:
		return false
	return _has_inputs(recipe, inventory)


## Execute one craft of `recipe_id` for `sheet`, pulling inputs from `inventory`. ATOMIC + guarded:
##   (1) the id must be KNOWN on the sheet's KnownRecipes (Part 3.1 learn gate) -- else refuse;
##   (2) resolve the RecipeData; a missing definition refuses;
##   (3) PRECHECK every input is present in the required count (_has_inputs) -- else refuse, consuming NOTHING;
##   (4) only THEN remove the exact input counts and add output_item x output_count.
## Returns true IFF the craft ran (inputs consumed + output produced). On ANY failure it returns false and the
## inventory is byte-identical to before (no partial consumption). Deterministic integer/membership work, no
## Time/OS/RNG. (Phase 4 adds a station_tag in-range gate BEFORE (3); this part is station-independent.)
func craft(recipe_id: StringName, sheet: CharacterSheet, inventory: Inventory) -> bool:
	if sheet == null or sheet.known_recipes == null or inventory == null:
		return false
	# (1) LEARN gate -- an UNKNOWN recipe never crafts (Part 3.1 known set).
	if not sheet.known_recipes.is_known(recipe_id):
		return false
	# (2) Resolve the shared definition (its I/O counts).
	var recipe: RecipeData = sheet.known_recipes.recipe(recipe_id)
	if recipe == null:
		return false
	# (3) ATOMIC PRECHECK -- verify ALL inputs present BEFORE removing any. Bail with nothing consumed.
	if not _has_inputs(recipe, inventory):
		return false
	# (4) Consume the exact inputs, then produce the output. The precheck guarantees every remove is full.
	_consume(recipe, inventory)
	inventory.add_item(recipe.output_item, recipe.output_count)
	return true


## True IFF the inventory holds every input_items[i] in at least input_counts[i] (the atomic precheck's
## material test). Parallel arrays (RecipeData): input_items[i] needs input_counts[i]. A shorter counts array
## reads 0 for the missing tail and a null input row is skipped (both defensive; authored recipes keep the two
## arrays equal length with non-null items).
##
## EPIC 2 STORAGE SEAM: availability here is inventory.count_of ONLY. Craft-from-storage widens the held count
## to (inventory + nearby containers) before the >= compare, without changing WHO calls this or the atomic
## guarantee -- one summation site, one place to extend.
func _has_inputs(recipe: RecipeData, inventory: Inventory) -> bool:
	for i in range(recipe.input_items.size()):
		var item: ItemData = recipe.input_items[i]
		if item == null:
			continue
		var need: int = recipe.input_counts[i] if i < recipe.input_counts.size() else 0
		if inventory.count_of(item) < need:
			return false
	return true


## Remove the exact input counts from the inventory. Called ONLY after _has_inputs cleared, so each
## remove_item takes its full amount (never partial). Kept separate from the precheck so the READ (can I?) and
## the WRITE (do it) never interleave -- that separation IS the atomicity guarantee.
##
## EPIC 2 STORAGE SEAM: today every input is drawn from `inventory`. Craft-from-storage drains the inventory
## FIRST, then the shortfall from in-range containers here, in a fixed deterministic order.
func _consume(recipe: RecipeData, inventory: Inventory) -> void:
	for i in range(recipe.input_items.size()):
		var item: ItemData = recipe.input_items[i]
		if item == null:
			continue
		var need: int = recipe.input_counts[i] if i < recipe.input_counts.size() else 0
		if need <= 0:
			continue
		inventory.remove_item(item, need)

# Verified against: Godot 4.7.1 (2026-07-19)
