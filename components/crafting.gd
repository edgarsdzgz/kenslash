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
## CRAFT-FROM-STORAGE (Epic 2 Part 3.1). Inputs are pulled from the player's Inventory PLUS any in-range
## container stores passed as `extra_stores` (ui/hud.gd collects them via Interaction.containers_in_range).
## AVAILABILITY aggregates count_of across the inventory + every store; CONSUME is a STABLE order -- personal
## inventory FIRST, then each store in the passed order, taking only the shortfall from each. The transaction is
## ATOMIC ACROSS ALL touched stores: the inventory AND every store are snapshotted before consuming, and on any
## output-overflow EVERY snapshot is restored, so a failed craft leaves the inventory AND every container byte-
## identical (consuming nothing from any source). This atomic/no-dupe guarantee is UNCONDITIONAL: each public
## entry first _normalize_stores() the extra_stores -- dropping any entry that IS the personal `inventory` (an
## alias would otherwise double-count in availability and double-drain on consume) and de-duplicating repeated
## Inventory refs (keep first, drop nulls) -- so snapshot/consume/restore always operate on ONE set of DISTINCT
## non-alias stores. For the normal distinct-store case normalization is a no-op (byte-identical). `extra_stores`
## DEFAULTS to [] so every Epic 1 inventory-only call is byte-identical. Weight is respected the NORMAL way: removing inputs and adding the output re-flow
## through each Inventory's own remove_item/add_item, so total_weight()/encumbrance update exactly as for any
## pickup; this component invents NO hard weight block (the inventory enforces none on add -- pickup never
## blocks, so neither does a craft).


## Whether `inventory` holds the MATERIALS for `recipe` RIGHT NOW -- the recipe is real (non-null) and the
## inventory holds EVERY distinct input in at least its TOTAL required count (duplicate input rows for the same
## item are summed first). This is a MATERIAL-ONLY predicate, NOT a may-I-craft gate: it deliberately ignores
## the learn-set membership (enforced by craft() at its chokepoint, which resolves the recipe off the sheet's
## KnownRecipes first) and the output-fit check (craft() handles that transactionally). Kept separate so a
## future craft UI can grey out un-affordable KNOWN recipes without re-resolving them. Pure read -- changes
## nothing. A null recipe (or inventory) -> false.
##
## CRAFT-FROM-STORAGE (Epic 2 Part 3.1): availability is aggregated across the player's `inventory` AND every
## `extra_store` (the in-range container stores ui/hud.gd feeds in). `extra_stores` DEFAULTS to [] so an
## inventory-only query is byte-identical to before; when a nearby chest holds the shortfall, this reports true
## and the recipe becomes craftable. The list is _normalize_stores()d first so a store that ALIASES `inventory`
## or a DUPLICATE ref can never phantom-inflate the aggregate (a null entry is dropped) -- the availability is
## always over one set of distinct non-alias sources. Still a MATERIAL-ONLY predicate (no learn/station/output-
## fit) -- craft() owns those.
func has_materials_for(recipe: RecipeData, inventory: Inventory, extra_stores: Array[Inventory] = []) -> bool:
	if recipe == null or inventory == null:
		return false
	return _has_inputs(_aggregate_inputs(recipe), inventory, _normalize_stores(inventory, extra_stores))


## Execute one craft of `recipe_id` for `sheet`, pulling inputs from `inventory`. ATOMIC + guarded:
##   (1) the id must be KNOWN on the sheet's KnownRecipes (Part 3.1 learn gate) -- else refuse;
##   (2) resolve the RecipeData; a missing definition refuses;
##   (2.5) STATION gate (Part 4.1) + TIER gate (Part 4.2): if the recipe needs a station (station_tag != "") then
##       its tag MUST be present in `in_range_station_levels` AND the mapped in-range level MUST be >= the recipe's
##       min_station_level -- else refuse, consuming NOTHING. Craft-anywhere recipes (station_tag == "") ignore the
##       param entirely. Checked BEFORE the snapshot/consume so atomicity holds (a station-blocked craft touches
##       the inventory not at all).
##   (3) AGGREGATE the input rows by item (duplicate rows summed) and PRECHECK every DISTINCT input is present
##       in its TOTAL required count (_has_inputs) -- else refuse, consuming NOTHING;
##   (4) SNAPSHOT the inventory, remove each distinct input's total, add output_item x output_count, and if the
##       output does not fully fit (overflow > 0) RESTORE the snapshot and refuse -- so a full inventory can
##       never consume the inputs while losing the output.
## Returns true IFF the craft ran (inputs consumed + output produced). On ANY failure it returns false and the
## inventory is byte-identical to before (no partial consumption). Deterministic integer/membership work, no
## Time/OS/RNG.
##
## `in_range_station_levels` is the tag -> MAX-in-range-level map currently near the player (world/station.gd's
## Station.levels_in_range collects it); it DEFAULTS to {} so every existing craft-anywhere call site is unchanged
## and only ever matters for a station-gated recipe. The plain STATION gate reads `.has(station_tag)` (the keys are
## exactly the tags that would be "in range") and the TIER gate additionally requires the mapped level to clear
## min_station_level. Crafting stays decoupled from station NODES -- it sees only this passed map, never a Station.
##
## CRAFT-FROM-STORAGE (Epic 2 Part 3.1): `extra_stores` is the in-range container stores (ui/hud.gd collects
## them via Interaction.containers_in_range) and DEFAULTS to [] so an inventory-only craft is byte-identical to
## Epic 1. The list is _normalize_stores()d ONCE up front (alias-to-`inventory` and duplicate refs dropped, nulls
## dropped) so the availability precheck and the snapshot/consume/restore all span the SAME set of distinct non-
## alias stores -- the atomic/no-dupe guarantee holds UNCONDITIONALLY, not just for a caller that happens to pass
## distinct stores. AVAILABILITY is aggregated across the inventory + every store; CONSUME is in a STABLE order --
## the personal INVENTORY drained FIRST, then each store in the passed order until each input's need is
## met. ATOMIC ACROSS ALL touched stores: the inventory AND every store are snapshotted before consuming,
## and on output-overflow EVERY snapshot is restored -- a failed craft leaves the inventory AND every container
## byte-identical. The output is always added to the personal `inventory`.
func craft(recipe_id: StringName, sheet: CharacterSheet, inventory: Inventory, in_range_station_levels: Dictionary = {}, extra_stores: Array[Inventory] = []) -> bool:
	if sheet == null or sheet.known_recipes == null or inventory == null:
		return false
	# NORMALIZE the stores ONCE (drop alias-to-inventory / duplicate / null) so consume/snapshot/restore below all
	# operate on ONE set of distinct non-alias sources -- makes the atomic/no-dupe guarantee unconditional.
	var stores: Array[Inventory] = _normalize_stores(inventory, extra_stores)
	# (1) LEARN gate -- an UNKNOWN recipe never crafts (Part 3.1 known set).
	if not sheet.known_recipes.is_known(recipe_id):
		return false
	# (2) Resolve the shared definition (its I/O counts).
	var recipe: RecipeData = sheet.known_recipes.recipe(recipe_id)
	if recipe == null:
		return false
	# (2.5) STATION + TIER gate (Part 4.1/4.2) -- a station-gated recipe crafts ONLY when its tag is in range AND
	# that tag's in-range level clears min_station_level. Placed BEFORE the precheck/snapshot so a station-blocked
	# craft consumes NOTHING (atomicity). Craft-anywhere recipes fall straight through (needs_station false).
	if needs_station(recipe) and not _station_satisfies(recipe, in_range_station_levels):
		return false
	# (3) ATOMIC PRECHECK -- aggregate duplicate input rows, then verify every DISTINCT input's TOTAL is present
	# ACROSS the inventory + extra_stores BEFORE removing any. Bail with nothing consumed.
	var needs: Dictionary = _aggregate_inputs(recipe)
	if not _has_inputs(needs, inventory, stores):
		return false
	# (4) TRANSACTIONAL across ALL touched stores: snapshot the inventory AND every store, consume the exact
	# per-item totals (personal first, then the stores in order), produce the output into the inventory. If the
	# output does not fully fit (a full inventory), roll back EVERY snapshot so the craft consumes NOTHING from
	# ANY store and produces NOTHING. We do NOT precheck output space first: consuming can free the needed slot.
	var snap: Array = inventory.snapshot()
	var extra_snaps: Array = _snapshot_stores(stores)
	_consume(needs, inventory, stores)
	var overflow: int = inventory.add_item(recipe.output_item, recipe.output_count)
	if overflow > 0:
		inventory.restore(snap)
		_restore_stores(stores, extra_snaps)
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
## RNG. `in_range_station_levels` mirrors craft() -- defaults to {} so a craft-anywhere dry-run ignores it, and it
## enforces the SAME station-tag + tier (min_station_level) gate.
##
## CRAFT-FROM-STORAGE (Epic 2 Part 3.1): `extra_stores` mirrors craft() -- defaults to [] so an inventory-only
## dry-run is byte-identical. When passed, it is _normalize_stores()d ONCE (alias-to-`inventory`/duplicate/null
## dropped) exactly as craft() does, so the dry-run's verdict matches craft() even for a caller that passes an
## aliasing or duplicate store; availability aggregates across the inventory + the normalized stores and the
## snapshot/consume/restore spans the inventory AND every store, so a full-inventory dry-run leaves EVERY
## store byte-identical (a net no-op) exactly as craft() would leave them on its overflow rollback. This is what
## makes CraftMenu.is_craftable light up from a nearby chest while committing nothing.
func would_craft(recipe_id: StringName, sheet: CharacterSheet, inventory: Inventory, in_range_station_levels: Dictionary = {}, extra_stores: Array[Inventory] = []) -> bool:
	if sheet == null or sheet.known_recipes == null or inventory == null:
		return false
	# NORMALIZE identically to craft() so the dry-run verdict tracks craft() even under an aliasing/duplicate store.
	var stores: Array[Inventory] = _normalize_stores(inventory, extra_stores)
	# (1) LEARN gate -- an UNKNOWN recipe is never craftable (matches craft()'s is_known chokepoint).
	if not sheet.known_recipes.is_known(recipe_id):
		return false
	# (2) Resolve the shared definition.
	var recipe: RecipeData = sheet.known_recipes.recipe(recipe_id)
	if recipe == null:
		return false
	# (2.5) STATION + TIER gate -- a station-gated recipe is craftable ONLY when its tag is in range AND that tag's
	# in-range level clears min_station_level (matches craft()'s gate exactly).
	if needs_station(recipe) and not _station_satisfies(recipe, in_range_station_levels):
		return false
	# (3) MATERIAL precheck -- every distinct input's aggregated total must be present across inventory + stores.
	var needs: Dictionary = _aggregate_inputs(recipe)
	if not _has_inputs(needs, inventory, stores):
		return false
	# (4) OUTPUT-FIT dry-run -- run craft()'s exact multi-store snapshot/consume/produce, then ALWAYS roll back
	# EVERY store. The overflow tells us whether the output would have fit (a full inventory where consuming the
	# inputs did not free the needed slot makes craft() refuse); either way the inventory AND every store
	# are restored byte-identical (never committed).
	var snap: Array = inventory.snapshot()
	var extra_snaps: Array = _snapshot_stores(stores)
	_consume(needs, inventory, stores)
	var overflow: int = inventory.add_item(recipe.output_item, recipe.output_count)
	inventory.restore(snap)
	_restore_stores(stores, extra_snaps)
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
## CRAFT-FROM-STORAGE (Epic 2 Part 3.1): availability is the SUM of count_of across the inventory + every
## extra_store (via _available), so an input the player lacks but a nearby chest holds still clears the >=
## compare. One summation site, unchanged callers, unchanged atomic guarantee (craft()/would_craft() own the
## transaction). An empty extra_stores collapses to the Epic 1 inventory-only test.
func _has_inputs(needs: Dictionary, inventory: Inventory, extra_stores: Array[Inventory]) -> bool:
	for item: ItemData in needs:
		if _available(item, inventory, extra_stores) < int(needs[item]):
			return false
	return true


## Normalize `extra_stores` into the set the transaction may safely touch: DROP any entry that IS the personal
## `inventory` (an alias would double-count in _available and double-drain in _consume, since the personal
## inventory is already the FIRST source), DROP duplicate Inventory refs (keep the FIRST occurrence -- a repeated
## chest snapshotted/consumed/restored twice would phantom-inflate availability and mis-restore), and DROP nulls.
## Called ONCE at the top of every public entry (has_materials_for/would_craft/craft) so _available/_consume/
## _snapshot_stores/_restore_stores all see the SAME clean set. For the normal DISTINCT-store case this returns a
## copy with identical membership/order, so behavior is byte-identical -- it only ever REMOVES the pathological
## alias/dup/null entries that would otherwise break the unconditional atomic/no-dupe guarantee. Pure; no Time/OS/
## RNG (order is preserved from the input). Returns a fresh typed Array[Inventory].
func _normalize_stores(inventory: Inventory, extra_stores: Array[Inventory]) -> Array[Inventory]:
	var out: Array[Inventory] = []
	for store: Inventory in extra_stores:
		if store == null or store == inventory:
			continue
		if out.has(store):
			continue
		out.append(store)
	return out


## Total count of `item` held across the personal inventory + every extra_store (the aggregate craft-from-storage
## availability). A null store is skipped. Pure read.
func _available(item: ItemData, inventory: Inventory, extra_stores: Array[Inventory]) -> int:
	var total: int = inventory.count_of(item)
	for store: Inventory in extra_stores:
		if store != null:
			total += store.count_of(item)
	return total


## Remove each DISTINCT input's aggregated TOTAL from the inventory. Called ONLY after _has_inputs cleared, so
## each remove_item takes its full amount (never partial). Because `needs` sums duplicate rows, each item is
## removed EXACTLY once at its total -- never row-by-row (which would double-drain a repeated item). Kept
## separate from the precheck so the READ (can I?) and the WRITE (do it) never interleave.
##
## CRAFT-FROM-STORAGE (Epic 2 Part 3.1): each input's total is drained in a STABLE deterministic order --
## the personal `inventory` FIRST, then each extra_store in the passed order -- taking from each only what is
## still needed (remove_item returns how many it actually pulled) until the per-item need is met. Called ONLY
## after _has_inputs cleared, so the aggregate is guaranteed sufficient and `remaining` always reaches 0 (never
## a partial). No Time/OS/RNG -- the order is fixed by the arguments, so the split is exactly reproducible.
func _consume(needs: Dictionary, inventory: Inventory, extra_stores: Array[Inventory]) -> void:
	for item: ItemData in needs:
		var remaining: int = int(needs[item])
		remaining -= inventory.remove_item(item, remaining)  # personal inventory drained FIRST
		for store: Inventory in extra_stores:
			if remaining <= 0:
				break
			if store != null:
				remaining -= store.remove_item(item, remaining)


## Snapshot every extra_store for the cross-store transaction -- a parallel array of Inventory.snapshot()
## captures (null for a null store slot), the multi-store analogue of the single inventory snapshot. Pairs with
## _restore_stores; craft()/would_craft() take these before consuming so a failed/dry craft rolls every store
## back byte-identical.
func _snapshot_stores(extra_stores: Array[Inventory]) -> Array:
	var snaps: Array = []
	for store: Inventory in extra_stores:
		snaps.append(store.snapshot() if store != null else null)
	return snaps


## Restore every extra_store from a _snapshot_stores() capture (the inverse) -- the cross-store rollback that,
## with inventory.restore(), leaves EVERY touched store byte-identical when a craft overflows or a dry-run ends.
func _restore_stores(extra_stores: Array[Inventory], snaps: Array) -> void:
	for i in range(extra_stores.size()):
		if extra_stores[i] != null:
			extra_stores[i].restore(snaps[i])


## Whether `recipe` requires a crafting station to EXECUTE -- true IFF it carries a non-empty station_tag
## (RecipeData). A craft-anywhere recipe ("" tag) returns false and is never gated. Pure read; a null recipe ->
## false. Exposed (not inlined) so a future craft UI can grey out a recipe the player cannot craft here without
## re-deriving the rule, mirroring how has_materials_for exposes the material predicate.
func needs_station(recipe: RecipeData) -> bool:
	return recipe != null and recipe.station_tag != &""


## Whether the in-range stations SATISFY `recipe`'s station gate (plan-epic2-parts.md Phase 4 Part 4.2) -- the
## composed STATION-TAG + TIER check craft()/would_craft() run for a station-gated recipe. `in_range_station_levels`
## is the tag -> max-in-range-level map (Station.levels_in_range). Returns true IFF the recipe's station_tag is a KEY
## (a matching station is present -- the plain Part 4.1 gate) AND its mapped level is >= recipe.min_station_level
## (the Part 4.2 tier gate). COMPOSES cleanly: no matching tag -> false (refused as before); tag present but level
## below the threshold -> false (the NEW tier gate); default min_station_level 0 -> satisfied by ANY present station
## (a placed station is level >= 1, so this is BYTE-IDENTICAL to the Part 4.1 tag-only gate for un-tiered recipes).
## Assumes needs_station(recipe) already held (a craft-anywhere recipe never reaches here). Pure integer/membership.
func _station_satisfies(recipe: RecipeData, in_range_station_levels: Dictionary) -> bool:
	return in_range_station_levels.has(recipe.station_tag) \
		and int(in_range_station_levels[recipe.station_tag]) >= recipe.min_station_level

# Verified against: Godot 4.7.1 (2026-07-20)
