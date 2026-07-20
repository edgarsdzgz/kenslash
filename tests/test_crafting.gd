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
##     draining both inputs to 0 and updating weight.
## Fully standalone: pure component instances, no player/scene wiring. Registered in tests/smoke_slash.gd after
## TestRecipes (the learn-model suite this craft-execution suite builds on).

## Catalog ids under test (data/recipes/*.tres) -- their I/O the assertions reason about.
const SPIN: StringName = &"spin_cord"       # fiber x3 -> cord x1
const BUNDLE: StringName = &"bundle_sticks" # wood x2  -> stick x4
const FLINT: StringName = &"flint_kit"      # stone x2 + fiber x1 -> cord x1
const GHOST: StringName = &"does_not_exist" # never a real recipe


func run(ctx: TestContext) -> void:
	print("[crafting] --- craft execution: exact consume/produce + atomic (no partial) + weight-aware ---")
	_single_input_craft(ctx)
	_surplus_repeat_craft(ctx)
	_unknown_recipe_blocks(ctx)
	_insufficient_no_partial(ctx)
	_multi_input_end_to_end(ctx)


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

	# can_craft sees the materials; craft() runs and reports success.
	var ok: bool = craft.can_craft(sheet.known_recipes.recipe(SPIN), inv) and craft.craft(SPIN, sheet, inv)
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
	var a_ok: bool = craft.can_craft(sheet_a.known_recipes.recipe(FLINT), inv_a)
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

# Verified against: Godot 4.7.1 (2026-07-19)
