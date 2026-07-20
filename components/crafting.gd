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
## ATOMIC. craft() verifies known + EVERY input present BEFORE it removes anything; on ANY input shortfall it
## consumes NOTHING and returns false -- never a partial consumption. It is atomic on the OUTPUT side too: it
## SNAPSHOTS the inventory before consuming, and if the produced output does not fully fit (a full inventory),
## it RESTORES the snapshot and returns false -- so a full inventory can never eat the output while the inputs
## are already gone. It does NOT precheck output space before consuming, because consuming the inputs can FREE
## the very slot the output needs (a pre-consume space check would wrongly refuse). Determinism: pure
## membership + integer counts over the passed components; no Input/scene/Time/OS/RNG (NOTES.md rule), so every
## craft is exactly headless-assertable and server-re-simulable.
##
## INVENTORY-ONLY SOURCE (Epic 1). Inputs are pulled from the player's Inventory ONLY; Epic 2's craft-from-
## nearby-STORAGE plugs in at the marked seam in _has_inputs / _consume (see the comments there). Weight is
## respected the NORMAL way: removing inputs and adding the output re-flow through the Inventory's own
## remove_item/add_item, so total_weight()/encumbrance update exactly as for any pickup; this component invents
## NO hard weight block (the inventory enforces none on add -- pickup never blocks, so neither does a craft).


## Whether `inventory` holds the MATERIALS for `recipe` RIGHT NOW -- the recipe is real (non-null) and the
## inventory holds EVERY distinct input in at least its TOTAL required count (duplicate input rows for the same
## item are summed first). This is a MATERIAL-ONLY predicate, NOT a may-I-craft gate: it deliberately ignores
## the learn-set membership (enforced by craft() at its chokepoint, which resolves the recipe off the sheet's
## KnownRecipes first) and the output-fit check (craft() handles that transactionally). Kept separate so a
## future craft UI can grey out un-affordable KNOWN recipes without re-resolving them. Pure read -- changes
## nothing. A null recipe (or inventory) -> false.
##
## EPIC 2 STORAGE SEAM: today availability is (inventory) only. When craft-from-storage lands, this becomes
## "held across inventory + every in-range container"; the extra source is OR-ed in via _has_inputs, leaving
## this signature and the atomic contract intact.
func has_materials_for(recipe: RecipeData, inventory: Inventory) -> bool:
	if recipe == null or inventory == null:
		return false
	return _has_inputs(_aggregate_inputs(recipe), inventory)


## Execute one craft of `recipe_id` for `sheet`, pulling inputs from `inventory`. ATOMIC + guarded:
##   (1) the id must be KNOWN on the sheet's KnownRecipes (Part 3.1 learn gate) -- else refuse;
##   (2) resolve the RecipeData; a missing definition refuses;
##   (2.5) STATION gate (Part 4.1): if the recipe needs a station (station_tag != "") and that tag is NOT in
##       `in_range_station_tags`, refuse -- consuming NOTHING. Craft-anywhere recipes (station_tag == "") ignore
##       the param entirely. Checked BEFORE the snapshot/consume so atomicity holds (a station-blocked craft
##       touches the inventory not at all).
##   (3) AGGREGATE the input rows by item (duplicate rows summed) and PRECHECK every DISTINCT input is present
##       in its TOTAL required count (_has_inputs) -- else refuse, consuming NOTHING;
##   (4) SNAPSHOT the inventory, remove each distinct input's total, add output_item x output_count, and if the
##       output does not fully fit (overflow > 0) RESTORE the snapshot and refuse -- so a full inventory can
##       never consume the inputs while losing the output.
## Returns true IFF the craft ran (inputs consumed + output produced). On ANY failure it returns false and the
## inventory is byte-identical to before (no partial consumption). Deterministic integer/membership work, no
## Time/OS/RNG.
##
## `in_range_station_tags` is the plain list of station tags currently near the player (world/station.gd's
## Station.tags_in_range collects it); it DEFAULTS to [] so every existing craft-anywhere call site is
## unchanged and only ever matters for a station-gated recipe. Crafting stays decoupled from station NODES --
## it sees only this passed tag list, never a Station.
func craft(recipe_id: StringName, sheet: CharacterSheet, inventory: Inventory, in_range_station_tags: Array[StringName] = []) -> bool:
	if sheet == null or sheet.known_recipes == null or inventory == null:
		return false
	# (1) LEARN gate -- an UNKNOWN recipe never crafts (Part 3.1 known set).
	if not sheet.known_recipes.is_known(recipe_id):
		return false
	# (2) Resolve the shared definition (its I/O counts).
	var recipe: RecipeData = sheet.known_recipes.recipe(recipe_id)
	if recipe == null:
		return false
	# (2.5) STATION gate (Part 4.1) -- a station-gated recipe crafts ONLY when its tag is in range. Placed BEFORE
	# the precheck/snapshot so a station-blocked craft consumes NOTHING (atomicity). Craft-anywhere recipes fall
	# straight through (needs_station false).
	if needs_station(recipe) and not in_range_station_tags.has(recipe.station_tag):
		return false
	# (3) ATOMIC PRECHECK -- aggregate duplicate input rows, then verify every DISTINCT input's TOTAL is present
	# BEFORE removing any. Bail with nothing consumed.
	var needs: Dictionary = _aggregate_inputs(recipe)
	if not _has_inputs(needs, inventory):
		return false
	# (4) TRANSACTIONAL: snapshot, consume the exact per-item totals, produce the output. If the output does not
	# fully fit (a full inventory), roll the snapshot back so the craft consumes NOTHING and produces NOTHING.
	# We do NOT precheck output space first: consuming the inputs can free the very slot the output needs.
	var snap: Array = inventory.snapshot()
	_consume(needs, inventory)
	var overflow: int = inventory.add_item(recipe.output_item, recipe.output_count)
	if overflow > 0:
		inventory.restore(snap)
		return false
	return true


## DRY-RUN of craft() -- WOULD this exact craft succeed RIGHT NOW, without committing? Runs the IDENTICAL guards
## and the SAME snapshot -> consume -> add-output transaction as craft() (known + materials + station + the output
## FITS), but ALWAYS restores the snapshot before returning -- so the inventory is byte-identical whether it would
## have succeeded or not (a net no-op; never commits). Returns craft()'s would-be verdict: true IFF craft() would
## consume + produce. The craft-menu's is_craftable() delegates here so the "craftable" flag EXACTLY matches
## craft() acceptance -- no ad-hoc catalog lookup that could show craftable for an UNLEARNED id (recipe() reads the
## full CATALOG, is_known reads the learned set) or when a full inventory would make craft() refuse the output.
## Deterministic: pure membership + integer counts over the passed components, snapshot/restore only, no Time/OS/
## RNG. `in_range_station_tags` mirrors craft() -- defaults to [] so a craft-anywhere dry-run ignores it.
func would_craft(recipe_id: StringName, sheet: CharacterSheet, inventory: Inventory, in_range_station_tags: Array[StringName] = []) -> bool:
	if sheet == null or sheet.known_recipes == null or inventory == null:
		return false
	# (1) LEARN gate -- an UNKNOWN recipe is never craftable (matches craft()'s is_known chokepoint).
	if not sheet.known_recipes.is_known(recipe_id):
		return false
	# (2) Resolve the shared definition.
	var recipe: RecipeData = sheet.known_recipes.recipe(recipe_id)
	if recipe == null:
		return false
	# (2.5) STATION gate -- a station-gated recipe is craftable ONLY when its tag is in range.
	if needs_station(recipe) and not in_range_station_tags.has(recipe.station_tag):
		return false
	# (3) MATERIAL precheck -- every distinct input's aggregated total must be present.
	var needs: Dictionary = _aggregate_inputs(recipe)
	if not _has_inputs(needs, inventory):
		return false
	# (4) OUTPUT-FIT dry-run -- run craft()'s exact snapshot/consume/produce, then ALWAYS roll back. The overflow
	# tells us whether the output would have fit (a full inventory where consuming the inputs did not free the
	# needed slot makes craft() refuse); either way the inventory is restored byte-identical (never committed).
	var snap: Array = inventory.snapshot()
	_consume(needs, inventory)
	var overflow: int = inventory.add_item(recipe.output_item, recipe.output_count)
	inventory.restore(snap)
	return overflow == 0


## Aggregate a recipe's parallel input rows (input_items[i] / input_counts[i]) into a per-item TOTAL:
## ItemData -> summed count. Summing FIRST is what makes a recipe that lists the SAME item twice correct --
## the precheck then compares the SUM (not the max single row) to count_of, and the consume removes the SUM
## exactly once per distinct item. A shorter counts array reads 0 for the missing tail; null items and
## non-positive counts are skipped (both defensive; authored recipes keep the two arrays equal length with
## non-null items). Pure -- builds a fresh Dictionary, changes nothing.
func _aggregate_inputs(recipe: RecipeData) -> Dictionary:
	var needs: Dictionary = {}
	for i in range(recipe.input_items.size()):
		var item: ItemData = recipe.input_items[i]
		if item == null:
			continue
		var need: int = recipe.input_counts[i] if i < recipe.input_counts.size() else 0
		if need <= 0:
			continue
		needs[item] = int(needs.get(item, 0)) + need
	return needs


## True IFF the inventory holds every DISTINCT input in at least its aggregated TOTAL (the atomic precheck's
## material test). `needs` is the item -> total map from _aggregate_inputs, so duplicate rows were already
## summed and each item is checked once against the whole-inventory count.
##
## EPIC 2 STORAGE SEAM: availability here is inventory.count_of ONLY. Craft-from-storage widens the held count
## to (inventory + nearby containers) before the >= compare, without changing WHO calls this or the atomic
## guarantee -- one summation site, one place to extend.
func _has_inputs(needs: Dictionary, inventory: Inventory) -> bool:
	for item: ItemData in needs:
		if inventory.count_of(item) < int(needs[item]):
			return false
	return true


## Remove each DISTINCT input's aggregated TOTAL from the inventory. Called ONLY after _has_inputs cleared, so
## each remove_item takes its full amount (never partial). Because `needs` sums duplicate rows, each item is
## removed EXACTLY once at its total -- never row-by-row (which would double-drain a repeated item). Kept
## separate from the precheck so the READ (can I?) and the WRITE (do it) never interleave.
##
## EPIC 2 STORAGE SEAM: today every input is drawn from `inventory`. Craft-from-storage drains the inventory
## FIRST, then the shortfall from in-range containers here, in a fixed deterministic order.
func _consume(needs: Dictionary, inventory: Inventory) -> void:
	for item: ItemData in needs:
		inventory.remove_item(item, int(needs[item]))


## Whether `recipe` requires a crafting station to EXECUTE -- true IFF it carries a non-empty station_tag
## (RecipeData). A craft-anywhere recipe ("" tag) returns false and is never gated. Pure read; a null recipe ->
## false. Exposed (not inlined) so a future craft UI can grey out a recipe the player cannot craft here without
## re-deriving the rule, mirroring how has_materials_for exposes the material predicate.
func needs_station(recipe: RecipeData) -> bool:
	return recipe != null and recipe.station_tag != &""

# Verified against: Godot 4.7.1 (2026-07-19)
