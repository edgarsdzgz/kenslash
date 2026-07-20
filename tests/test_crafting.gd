class_name TestCrafting extends RefCounted
## Craft EXECUTION -- the components/crafting.gd operation that consumes a KNOWN recipe's inputs from the
## Inventory and produces its output (plan-epic1-parts.md Part 3.2; plan-core-loop.md Phase 3; design-crafting.md
## "Track B"). Proves the craft is exact, ATOMIC, weight-aware, and gated on the learned set -- purely and
## deterministically (no scene, no Time/RNG; Crafting + CharacterSheet + Inventory are all RefCounted):
##   * a KNOWN single-input recipe (spin_cord: fiber x3 -> cord x1) crafts -- consuming the EXACT inputs, adding
##     the exact output, leaving the surplus, and updating total_weight() the normal way;
##   * a KNOWN recipe with SURPLUS inputs (bundle_sticks: wood x2 -> stick x4) crafts REPEATEDLY, each craft
##     drawing exactly its input count and yielding exactly its output count;
##   * an UNKNOWN recipe (never learned) and a NONEXISTENT id BOTH refuse -- consuming NOTHING -- even when the
##     materials are present (the learn gate, not the material gate, blocks them);
##   * INSUFFICIENT inputs refuse with NO PARTIAL consumption -- verified on a MULTI-input recipe (flint_kit:
##     stone x2 + fiber x1) short of ONE input: EVERY input count is unchanged and no output appears;
##   * the MULTI-input flint_kit crafts END TO END when both inputs are present (stone x2 + fiber x1 -> cord x1),
##     draining both inputs to 0 and updating weight;
##   * FRAGMENTED input stacks: an input split across several slots drains EXACTLY the needed amount in slot
##     order, nulling the emptied slots without corrupting a bystander stack;
##   * OUTPUT MERGE: an output whose item already sits in a partial stack MERGES onto it (count grows) rather
##     than only taking a fresh empty slot;
##   * TRANSACTIONAL full-inventory: a craft whose output cannot fit even after consuming REFUSES and leaves the
##     inventory byte-identical (no partial consume, output not lost); but when consuming an input EMPTIES a slot
##     the output then fits and the craft SUCCEEDS (no pre-consume space precheck);
##   * DUPLICATE-INPUT aggregation: a recipe listing the same item twice requires + consumes the SUM of the rows
##     (not the max single row), refusing when stock is >= the largest row but < the sum;
##   * STATION-TAG inert: master_cordage's station_tag (&"forge") is ignored in Phase 3 -- it still crafts.
## Fully standalone: pure component instances, no player/scene wiring. Registered in tests/smoke_slash.gd after
## TestRecipes (the learn-model suite this craft-execution suite builds on).

## Catalog ids under test (data/recipes/*.tres) -- their I/O the assertions reason about.
const SPIN: StringName = &"spin_cord"       # fiber x3 -> cord x1
const BUNDLE: StringName = &"bundle_sticks" # wood x2  -> stick x4
const FLINT: StringName = &"flint_kit"      # stone x2 + fiber x1 -> cord x1
const MASTER: StringName = &"master_cordage"# fiber x5 -> cord x3, station_tag &"forge", min_level 3
const GHOST: StringName = &"does_not_exist" # never a real recipe


func run(ctx: TestContext) -> void:
	print("[crafting] --- craft execution: exact consume/produce + atomic (no partial) + weight-aware ---")
	_single_input_craft(ctx)
	_surplus_repeat_craft(ctx)
	_unknown_recipe_blocks(ctx)
	_insufficient_no_partial(ctx)
	_multi_input_end_to_end(ctx)
	_fragmented_stacks_drain(ctx)
	_output_merges_onto_partial(ctx)
	_full_inventory_transactional(ctx)
	_duplicate_input_aggregation(ctx)
	_station_tag_inert(ctx)


## KNOWN single-input recipe consumes the EXACT inputs, adds the exact output, keeps the surplus, and updates
## total_weight() -- the baseline happy path plus the weight-aware assertion.
func _single_input_craft(ctx: TestContext) -> void:
	var FIBER: ItemData = load("res://data/fiber.tres")   # weight 25
	var CORD: ItemData = load("res://data/cord.tres")     # weight 30
	var sheet: CharacterSheet = CharacterSheet.new()
	sheet.known_recipes.learn(SPIN)                        # mark known (Part 3.1 API)
	var inv: Inventory = Inventory.new()
	inv.add_item(FIBER, 5)                                 # 5 fiber -> spin_cord needs 3
	var craft: Crafting = Crafting.new()
	var weight_before: float = inv.total_weight()         # 5 * 25 = 125

	# has_materials_for sees the materials; craft() runs and reports success.
	var ok: bool = craft.has_materials_for(sheet.known_recipes.recipe(SPIN), inv) and craft.craft(SPIN, sheet, inv)
	ctx.check(ok and inv.count_of(FIBER) == 2 and inv.count_of(CORD) == 1,
		"spin_cord crafts: consumes EXACTLY 3 fiber (5 -> 2 surplus) and adds EXACTLY 1 cord",
		"spin_cord craft wrong (ok=%s, fiber=%d, cord=%d)" % [str(ok), inv.count_of(FIBER), inv.count_of(CORD)])

	# Weight tracked the normal way: -3 fiber (75g) + 1 cord (30g) => 125 - 75 + 30 = 80.
	ctx.check(is_equal_approx(weight_before, 125.0) and is_equal_approx(inv.total_weight(), 80.0),
		"craft is weight-aware: total_weight goes 125 -> 80 (removed 3 fiber, added 1 cord)",
		"craft weight not updated correctly (before=%f, after=%f)" % [weight_before, inv.total_weight()])


## SURPLUS inputs -> the recipe crafts REPEATEDLY, each craft drawing exactly its input count and yielding
## exactly its output count (proves per-craft exactness, not a one-shot drain of the whole stack).
func _surplus_repeat_craft(ctx: TestContext) -> void:
	var WOOD: ItemData = load("res://data/wood.tres")
	var STICK: ItemData = load("res://data/stick.tres")
	var sheet: CharacterSheet = CharacterSheet.new()
	sheet.known_recipes.learn(BUNDLE)
	var inv: Inventory = Inventory.new()
	inv.add_item(WOOD, 5)                                  # bundle_sticks needs wood x2 -> stick x4
	var craft: Crafting = Crafting.new()

	var c1: bool = craft.craft(BUNDLE, sheet, inv)
	ctx.check(c1 and inv.count_of(WOOD) == 3 and inv.count_of(STICK) == 4,
		"bundle_sticks craft #1: wood 5 -> 3 (consumed exactly 2), stick 0 -> 4 (produced exactly 4)",
		"bundle_sticks craft #1 wrong (ok=%s, wood=%d, stick=%d)" % [str(c1), inv.count_of(WOOD), inv.count_of(STICK)])

	var c2: bool = craft.craft(BUNDLE, sheet, inv)
	ctx.check(c2 and inv.count_of(WOOD) == 1 and inv.count_of(STICK) == 8,
		"bundle_sticks craft #2 (repeat): wood 3 -> 1, stick 4 -> 8 -- each craft is exact",
		"bundle_sticks craft #2 wrong (ok=%s, wood=%d, stick=%d)" % [str(c2), inv.count_of(WOOD), inv.count_of(STICK)])

	# Now only 1 wood remains (< the 2 needed) -> the next craft refuses, consuming nothing.
	var c3: bool = craft.craft(BUNDLE, sheet, inv)
	ctx.check(not c3 and inv.count_of(WOOD) == 1 and inv.count_of(STICK) == 8,
		"bundle_sticks craft #3 refuses on the leftover 1 wood (< 2) -- consumes NOTHING (wood stays 1, stick 8)",
		"bundle_sticks craft #3 mishandled shortfall (ok=%s, wood=%d, stick=%d)" % [str(c3), inv.count_of(WOOD), inv.count_of(STICK)])


## UNKNOWN (never learned) and NONEXISTENT ids BOTH refuse and consume NOTHING even with materials present:
## the learn gate blocks the craft, not the material gate.
func _unknown_recipe_blocks(ctx: TestContext) -> void:
	var FIBER: ItemData = load("res://data/fiber.tres")
	var CORD: ItemData = load("res://data/cord.tres")
	var sheet: CharacterSheet = CharacterSheet.new()      # nothing learned
	var inv: Inventory = Inventory.new()
	inv.add_item(FIBER, 9)                                 # plenty for spin_cord (needs 3), but it is UNKNOWN
	var craft: Crafting = Crafting.new()

	# spin_cord is a REAL recipe with the mats present, yet NOT known -> refused, nothing consumed.
	var unknown_ok: bool = craft.craft(SPIN, sheet, inv)
	ctx.check(not unknown_ok and inv.count_of(FIBER) == 9 and inv.count_of(CORD) == 0,
		"an UNKNOWN (unlearned) recipe refuses despite sufficient mats -- fiber stays 9, no cord (learn gate blocks it)",
		"unknown recipe crafted or consumed mats (ok=%s, fiber=%d, cord=%d)" % [str(unknown_ok), inv.count_of(FIBER), inv.count_of(CORD)])

	# A wholly NONEXISTENT id also refuses (no recipe, nothing to consume).
	var ghost_ok: bool = craft.craft(GHOST, sheet, inv)
	ctx.check(not ghost_ok and inv.count_of(FIBER) == 9,
		"a NONEXISTENT recipe id refuses and consumes nothing (fiber stays 9)",
		"nonexistent recipe id mishandled (ok=%s, fiber=%d)" % [str(ghost_ok), inv.count_of(FIBER)])


## INSUFFICIENT inputs on a MULTI-input recipe refuse with NO PARTIAL consumption: with one input missing, the
## OTHER (present) input is NOT touched -- the atomic precheck runs entirely before any removal.
func _insufficient_no_partial(ctx: TestContext) -> void:
	var STONE: ItemData = load("res://data/stone.tres")
	var FIBER: ItemData = load("res://data/fiber.tres")
	var CORD: ItemData = load("res://data/cord.tres")
	var craft: Crafting = Crafting.new()

	# Case A -- flint_kit (stone x2 + fiber x1): stone present, fiber MISSING. The precheck must fail WITHOUT
	# draining the stone (the classic partial-consumption bug: consume stone, then discover no fiber).
	var sheet_a: CharacterSheet = CharacterSheet.new()
	sheet_a.known_recipes.learn(FLINT)
	var inv_a: Inventory = Inventory.new()
	inv_a.add_item(STONE, 2)                               # exactly the stone need, but ZERO fiber
	var a_ok: bool = craft.has_materials_for(sheet_a.known_recipes.recipe(FLINT), inv_a)
	var a_craft: bool = craft.craft(FLINT, sheet_a, inv_a)
	ctx.check(not a_ok and not a_craft and inv_a.count_of(STONE) == 2
			and inv_a.count_of(FIBER) == 0 and inv_a.count_of(CORD) == 0,
		"flint_kit with fiber MISSING: refuses with NO partial consumption -- stone stays 2 (not drained), no cord",
		"flint_kit partial-consumed on missing fiber (can=%s, craft=%s, stone=%d, cord=%d)" % [str(a_ok), str(a_craft), inv_a.count_of(STONE), inv_a.count_of(CORD)])

	# Case B -- the reverse shortfall: fiber plenty, stone SHORT (1 < the 2 needed). Neither input moves.
	var sheet_b: CharacterSheet = CharacterSheet.new()
	sheet_b.known_recipes.learn(FLINT)
	var inv_b: Inventory = Inventory.new()
	inv_b.add_item(STONE, 1)                               # one short of the 2 needed
	inv_b.add_item(FIBER, 5)                               # more than enough fiber
	var b_craft: bool = craft.craft(FLINT, sheet_b, inv_b)
	ctx.check(not b_craft and inv_b.count_of(STONE) == 1 and inv_b.count_of(FIBER) == 5
			and inv_b.count_of(CORD) == 0,
		"flint_kit with stone SHORT (1 < 2): refuses with NO partial consumption -- stone stays 1, fiber stays 5, no cord",
		"flint_kit partial-consumed on short stone (ok=%s, stone=%d, fiber=%d, cord=%d)" % [str(b_craft), inv_b.count_of(STONE), inv_b.count_of(FIBER), inv_b.count_of(CORD)])


## MULTI-input flint_kit (stone x2 + fiber x1 -> cord x1) crafts END TO END when both inputs are present:
## BOTH inputs drain to 0, the output appears, and total_weight() updates.
func _multi_input_end_to_end(ctx: TestContext) -> void:
	var STONE: ItemData = load("res://data/stone.tres")   # weight 1000
	var FIBER: ItemData = load("res://data/fiber.tres")   # weight 25
	var CORD: ItemData = load("res://data/cord.tres")     # weight 30
	var sheet: CharacterSheet = CharacterSheet.new()
	sheet.known_recipes.learn(FLINT)
	var inv: Inventory = Inventory.new()
	inv.add_item(STONE, 2)
	inv.add_item(FIBER, 1)
	var craft: Crafting = Crafting.new()
	var weight_before: float = inv.total_weight()         # 2*1000 + 1*25 = 2025

	var ok: bool = craft.craft(FLINT, sheet, inv)
	ctx.check(ok and inv.count_of(STONE) == 0 and inv.count_of(FIBER) == 0 and inv.count_of(CORD) == 1,
		"flint_kit crafts END TO END: BOTH inputs drain (stone 2 -> 0, fiber 1 -> 0), adds 1 cord",
		"flint_kit end-to-end wrong (ok=%s, stone=%d, fiber=%d, cord=%d)" % [str(ok), inv.count_of(STONE), inv.count_of(FIBER), inv.count_of(CORD)])

	# Weight: -2025 of inputs, +30 of cord => 2025 -> 30.
	ctx.check(is_equal_approx(weight_before, 2025.0) and is_equal_approx(inv.total_weight(), 30.0),
		"flint_kit is weight-aware: total_weight 2025 -> 30 after consuming both inputs and adding the cord",
		"flint_kit weight not updated (before=%f, after=%f)" % [weight_before, inv.total_weight()])


## FRAGMENTED input stacks: the SAME input item spans multiple slots (built directly, since resources stack to
## 255 and would otherwise merge). spin_cord (fiber x3) drains in SLOT ORDER -- fully emptying the first fiber
## slot (nulled) and taking the remainder from the next -- while a later fiber fragment and a bystander WOOD
## stack between them are left untouched (no cross-slot corruption).
func _fragmented_stacks_drain(ctx: TestContext) -> void:
	var FIBER: ItemData = load("res://data/fiber.tres")
	var CORD: ItemData = load("res://data/cord.tres")
	var WOOD: ItemData = load("res://data/wood.tres")     # bystander, must stay intact
	var sheet: CharacterSheet = CharacterSheet.new()
	sheet.known_recipes.learn(SPIN)
	var inv: Inventory = Inventory.new()
	# 6 fiber fragmented across slots 0/2/3 (2 each), with a WOOD stack wedged at slot 1 to prove the drain
	# skips non-matching slots and never corrupts them.
	inv.slots[0] = ItemStack.new(FIBER, 2)
	inv.slots[1] = ItemStack.new(WOOD, 7)
	inv.slots[2] = ItemStack.new(FIBER, 2)
	inv.slots[3] = ItemStack.new(FIBER, 2)
	var craft: Crafting = Crafting.new()

	var ok: bool = craft.craft(SPIN, sheet, inv)          # needs fiber x3 across the fragments
	# Drains slot0 fully (2, nulled) then 1 from slot2 (-> 1); slot3 (2) untouched; total fiber 6 -> 3. WOOD
	# bystander stays 7. The emptied slot0 is nulled (no longer fiber) and reused by the cord output.
	ctx.check(ok and inv.count_of(FIBER) == 3 and inv.count_at(2) == 1 and inv.count_at(3) == 2
			and inv.item_at(1) == WOOD and inv.count_at(1) == 7 and inv.item_at(0) != FIBER
			and inv.count_of(CORD) == 1,
		"fragmented fiber drains in slot order: 3 of 6 removed (slot0 emptied + 1 from slot2), slot3 + WOOD bystander untouched, 1 cord out",
		"fragmented drain wrong (ok=%s, fiber=%d, slot2=%d, slot3=%d, wood=%d, cord=%d)" % [str(ok), inv.count_of(FIBER), inv.count_at(2), inv.count_at(3), inv.count_of(WOOD), inv.count_of(CORD)])


## OUTPUT MERGE: the recipe output already exists as a PARTIAL stack, so the produced item merges ONTO that
## stack (count grows) instead of only taking a fresh empty slot. spin_cord (fiber x3 -> cord x1) onto a
## pre-existing single cord: the cord slot goes 1 -> 2, and no second cord slot is created.
func _output_merges_onto_partial(ctx: TestContext) -> void:
	var FIBER: ItemData = load("res://data/fiber.tres")
	var CORD: ItemData = load("res://data/cord.tres")
	var sheet: CharacterSheet = CharacterSheet.new()
	sheet.known_recipes.learn(SPIN)
	var inv: Inventory = Inventory.new()
	inv.add_item(CORD, 1)                                  # existing partial cord stack (slot 0)
	inv.add_item(FIBER, 3)                                 # exact input for spin_cord (slot 1)
	var craft: Crafting = Crafting.new()

	var ok: bool = craft.craft(SPIN, sheet, inv)
	# Output merges onto slot 0's cord (1 -> 2), not into a new slot; the fiber input is fully consumed.
	ctx.check(ok and inv.count_of(CORD) == 2 and inv.count_at(0) == 2 and inv.count_of(FIBER) == 0,
		"spin_cord output MERGES onto the existing partial cord stack (slot0 count 1 -> 2), not a new slot",
		"output did not merge onto the partial stack (ok=%s, cord=%d, slot0=%d, fiber=%d)" % [str(ok), inv.count_of(CORD), inv.count_at(0), inv.count_of(FIBER)])


## TRANSACTIONAL full inventory (fix 1). Case A: every slot is occupied and NO input frees a slot, so the
## output cannot fit -- the craft must REFUSE with the inventory byte-identical (inputs NOT consumed, output NOT
## lost). Case B: consuming the input EMPTIES the only slot, so the output THEN fits and the craft SUCCEEDS --
## proving the craft does not pre-refuse on output space (consuming can free the very slot the output needs).
func _full_inventory_transactional(ctx: TestContext) -> void:
	var WOOD: ItemData = load("res://data/wood.tres")
	var STICK: ItemData = load("res://data/stick.tres")
	var FIBER: ItemData = load("res://data/fiber.tres")
	var CORD: ItemData = load("res://data/cord.tres")
	var craft: Crafting = Crafting.new()

	# Case A -- bundle_sticks (wood x2 -> stick x4). A 2-slot inventory: a FULL wood stack (255, so consuming 2
	# leaves it occupied at 253) and a FULL stick stack (255, at max -> the stick output can neither merge nor
	# find an empty slot). The output cannot fit even after consuming -> refuse, nothing changed.
	var sheet_a: CharacterSheet = CharacterSheet.new()
	sheet_a.known_recipes.learn(BUNDLE)
	var inv_a: Inventory = Inventory.new()
	inv_a.slots.resize(2)
	inv_a.slots[0] = ItemStack.new(WOOD, 255)             # >= the 2 needed, but never emptied by consuming 2
	inv_a.slots[1] = ItemStack.new(STICK, 255)            # full: stick output can't merge, no empty slot
	var a_ok: bool = craft.craft(BUNDLE, sheet_a, inv_a)
	ctx.check(not a_ok and inv_a.count_of(WOOD) == 255 and inv_a.count_of(STICK) == 255
			and inv_a.slots.size() == 2,
		"full inventory: bundle_sticks REFUSES when the stick output cannot fit -- byte-identical (wood stays 255, stick stays 255, no partial consume, output not lost)",
		"full-inventory craft was not atomic (ok=%s, wood=%d, stick=%d)" % [str(a_ok), inv_a.count_of(WOOD), inv_a.count_of(STICK)])

	# Case B -- spin_cord (fiber x3 -> cord x1) in a SINGLE-slot inventory holding exactly 3 fiber. Consuming the
	# 3 fiber EMPTIES the only slot, so the cord output then fits. A pre-consume space check would wrongly refuse
	# (the sole slot looks full up front); the transactional craft SUCCEEDS.
	var sheet_b: CharacterSheet = CharacterSheet.new()
	sheet_b.known_recipes.learn(SPIN)
	var inv_b: Inventory = Inventory.new()
	inv_b.slots.resize(1)
	inv_b.add_item(FIBER, 3)                              # the single slot is now full of fiber
	var b_ok: bool = craft.craft(SPIN, sheet_b, inv_b)
	ctx.check(b_ok and inv_b.count_of(FIBER) == 0 and inv_b.count_of(CORD) == 1 and inv_b.slots.size() == 1,
		"single-slot inventory: consuming the fiber FREES the slot so the cord output fits -- craft SUCCEEDS (fiber 3 -> 0, cord 0 -> 1), no pre-consume refusal",
		"consume-frees-slot craft failed (ok=%s, fiber=%d, cord=%d)" % [str(b_ok), inv_b.count_of(FIBER), inv_b.count_of(CORD)])


## DUPLICATE-INPUT aggregation (fix 2). A test-only RecipeData lists the SAME item (fiber) twice -- rows of 2
## and 3 -- so its true requirement is the SUM (5), not the largest row (3). Injected into the known catalog by
## id, then learned via the public API. Asserts: stock of 4 (>= the max row 3, < the sum 5) REFUSES and consumes
## nothing; stock of exactly 5 requires + consumes the SUM and produces the output.
func _duplicate_input_aggregation(ctx: TestContext) -> void:
	var FIBER: ItemData = load("res://data/fiber.tres")
	var CORD: ItemData = load("res://data/cord.tres")
	var craft: Crafting = Crafting.new()

	# Build the duplicate-input recipe: fiber x2 + fiber x3 -> cord x1 (true need: fiber x5).
	var dup: RecipeData = RecipeData.new()
	dup.id = &"dup_fiber_test"
	dup.display_name = "Dup Fiber (test)"
	var dup_items: Array[ItemData] = [FIBER, FIBER]
	dup.input_items = dup_items
	var dup_counts: Array[int] = [2, 3]
	dup.input_counts = dup_counts
	dup.output_item = CORD
	dup.output_count = 1

	# Case SHORT -- 4 fiber: >= the largest single row (3) but < the aggregated sum (5). A per-row check would
	# wrongly pass (4 >= 3 for each row); aggregation correctly refuses. Nothing consumed.
	var sheet_short: CharacterSheet = CharacterSheet.new()
	sheet_short.known_recipes._by_id[dup.id] = dup        # register the test recipe in the catalog by id
	sheet_short.known_recipes.learn(dup.id)               # then learn it via the public API
	var inv_short: Inventory = Inventory.new()
	inv_short.add_item(FIBER, 4)
	var short_has: bool = craft.has_materials_for(dup, inv_short)
	var short_craft: bool = craft.craft(dup.id, sheet_short, inv_short)
	ctx.check(not short_has and not short_craft and inv_short.count_of(FIBER) == 4 and inv_short.count_of(CORD) == 0,
		"duplicate-input recipe requires the SUM: 4 fiber (>= max row 3, < sum 5) REFUSES and consumes nothing",
		"duplicate-input short case wrong (has=%s, craft=%s, fiber=%d, cord=%d)" % [str(short_has), str(short_craft), inv_short.count_of(FIBER), inv_short.count_of(CORD)])

	# Case EXACT -- 5 fiber == the aggregated sum. Requires (has_materials_for true) and consumes the SUM exactly
	# once (fiber 5 -> 0), producing the output. A per-row consume would drain 2 then 3 = 5 here too, but the
	# aggregation is what makes the >= max-row-but-< sum SHORT case above correct.
	var sheet_ok: CharacterSheet = CharacterSheet.new()
	sheet_ok.known_recipes._by_id[dup.id] = dup
	sheet_ok.known_recipes.learn(dup.id)
	var inv_ok: Inventory = Inventory.new()
	inv_ok.add_item(FIBER, 5)
	var ok_has: bool = craft.has_materials_for(dup, inv_ok)
	var ok_craft: bool = craft.craft(dup.id, sheet_ok, inv_ok)
	ctx.check(ok_has and ok_craft and inv_ok.count_of(FIBER) == 0 and inv_ok.count_of(CORD) == 1,
		"duplicate-input recipe consumes the SUM exactly: 5 fiber (== 2+3) -> 0, 1 cord out",
		"duplicate-input exact case wrong (has=%s, craft=%s, fiber=%d, cord=%d)" % [str(ok_has), str(ok_craft), inv_ok.count_of(FIBER), inv_ok.count_of(CORD)])


## STATION-TAG inert (Phase 3). master_cordage carries station_tag &"forge", but no station exists yet (Phase 4
## adds the in-range gate), so the tag must be IGNORED at craft time. Learned the real way through the sheet
## (min_level 3 met, blueprint cost 3 paid), then crafts end to end: fiber x5 -> cord x3.
func _station_tag_inert(ctx: TestContext) -> void:
	var FIBER: ItemData = load("res://data/fiber.tres")
	var CORD: ItemData = load("res://data/cord.tres")
	var sheet: CharacterSheet = CharacterSheet.new()
	sheet.progression.blueprint_points = 3                # master_cordage costs 3
	sheet.progression.level = 3                           # meet min_level 3 (as the recipe tests do)
	var learned: bool = sheet.learn_recipe(MASTER)
	var inv: Inventory = Inventory.new()
	inv.add_item(FIBER, 5)
	var craft: Crafting = Crafting.new()

	var ok: bool = craft.craft(MASTER, sheet, inv)        # station_tag &"forge" is inert in Phase 3
	ctx.check(learned and ok and inv.count_of(FIBER) == 0 and inv.count_of(CORD) == 3,
		"master_cordage (station_tag &\"forge\") still crafts in Phase 3 -- the tag is ignored: fiber 5 -> 0, cord 0 -> 3",
		"station-tagged recipe did not craft inertly (learned=%s, ok=%s, fiber=%d, cord=%d)" % [str(learned), str(ok), inv.count_of(FIBER), inv.count_of(CORD)])

# Verified against: Godot 4.7.1 (2026-07-19)
