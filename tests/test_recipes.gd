class_name TestRecipes extends RefCounted
## KnownRecipes component + the recipe learn/gate/spend rules (plan-core-loop.md Phase 3, Part 3.1;
## design-crafting.md "Track B"). Proves the CHARACTER-data recipe-knowledge model (components/known_recipes.gd +
## the data/recipes/*.tres catalog) validates LEARNS purely and deterministically -- no scene, no Time/RNG:
##   * the authored catalog loads with the expected recipes/costs/gates and a fresh character KNOWS nothing;
##   * an unknown recipe is never known/learnable (is_known false, recipe() null, can_learn false, learn -> 0);
##   * a recipe cannot be learned without enough AVAILABLE blueprint points (available < cost is refused);
##   * a prereq_talent-gated recipe cannot be learned while that talent is locked (points+level alone are not
##     enough) and CAN once the talent id is in the passed unlocked set;
##   * a min_level-gated recipe cannot be learned below its level and CAN at/above it (points alone are not enough);
##   * learning SUCCEEDS, reports the EXACT blueprint cost the caller must spend, and adds exactly it to the set;
##   * re-learning (and unknown ids) are refused no-ops that report cost 0 and never grow the known set;
##   * the CharacterSheet.learn_recipe chokepoint deducts EXACTLY the blueprint cost from the owned Progression,
##     enforces both gates off the live Progression + Talents, and refuses (deducting nothing) when any gate fails.
## Craft EXECUTION (consume inputs -> produce output) is INERT in Part 3.1 (Part 3.2 adds it), so this suite
## asserts ONLY the learn model + the gates. Fully standalone: pure component instances, no player/scene wiring.
## Registered in tests/smoke_slash.gd, mirroring tests/test_talents.gd.

## The authored catalog ids (data/recipes/*.tres) + their costs/gates the tests reason about.
const BUNDLE: StringName = &"bundle_sticks"      # cost 1, no gate (wood x2 -> stick x4)
const SPIN: StringName = &"spin_cord"            # cost 1, no gate (fiber x3 -> cord x1)
const FLINT: StringName = &"flint_kit"           # cost 2, no gate (stone x2 + fiber x1 -> cord x1)
const HONED: StringName = &"honed_edge_kit"      # cost 2, prereq_talent blade_focus (stone x3 + stick x1 -> cord x2)
const MASTER: StringName = &"master_cordage"     # cost 3, min_level 3 (fiber x5 -> cord x3)
const FORGE: StringName = &"forge_iron_sword"    # cost 2, prereq heavy_hitter + min_level 3 + station forge (iron_ore x3 + stick x1 -> iron_sword)
const MASTERWORK: StringName = &"forge_masterwork_blade"  # cost 2, station forge + min_station_level 2 (iron_ore x2 + cord x1 -> iron_sword)
## The Track A talent id the honed_edge_kit recipe is gated behind (an EXISTING data/talents node).
const BLADE: StringName = &"blade_focus"
## The Track A talent id the forge_iron_sword recipe is gated behind (an EXISTING data/talents node).
const HEAVY: StringName = &"heavy_hitter"


func run(ctx: TestContext) -> void:
	print("[recipes] --- recipe learn model (blueprint-point gate + talent gate + level gate + exact cost) ---")
	_catalog_tests(ctx)
	_points_gate_tests(ctx)
	_talent_gate_tests(ctx)
	_level_gate_tests(ctx)
	_sheet_learn_tests(ctx)


## Catalog-shape + fresh-state tests -- the authored recipes are present at the documented costs/gates and a
## brand-new KnownRecipes knows nothing. No learn yet; pure reads.
func _catalog_tests(ctx: TestContext) -> void:
	var k: KnownRecipes = KnownRecipes.new()

	# The authored catalog has all seven recipes and no strays.
	ctx.check(k.all_recipes().size() == 7 and k.recipe(BUNDLE) != null and k.recipe(SPIN) != null
			and k.recipe(FLINT) != null and k.recipe(HONED) != null and k.recipe(MASTER) != null
			and k.recipe(FORGE) != null and k.recipe(MASTERWORK) != null,
		"recipe catalog loads the 7 authored recipes (bundle_sticks, spin_cord, flint_kit, honed_edge_kit, master_cordage, forge_iron_sword, forge_masterwork_blade)",
		"recipe catalog missing a recipe or wrong size (size %d)" % k.all_recipes().size())

	# The tier-gated masterwork recipe pins its Part 4.2 gate: station forge + min_station_level 2 (an un-tiered
	# recipe reads min_station_level 0). Composes with station_tag -- enforced at craft in tests/test_station_leveling.
	var masterwork: RecipeData = k.recipe(MASTERWORK)
	ctx.check(masterwork.station_tag == &"forge" and masterwork.min_station_level == 2
			and k.recipe(MASTER).min_station_level == 0 and k.recipe(BUNDLE).min_station_level == 0,
		"forge_masterwork_blade authors the TIER gate (station forge + min_station_level 2); un-tiered recipes read min_station_level 0",
		"tier-gate authoring drifted from the .tres (masterwork tag=%s lvl=%d)" % [str(masterwork.station_tag), masterwork.min_station_level])

	# Costs + the two gate values match the authored .tres (pins the catalog the test reasons about).
	var honed: RecipeData = k.recipe(HONED)
	var master: RecipeData = k.recipe(MASTER)
	ctx.check(k.recipe(BUNDLE).blueprint_cost == 1 and k.recipe(SPIN).blueprint_cost == 1
			and k.recipe(FLINT).blueprint_cost == 2 and honed.blueprint_cost == 2 and master.blueprint_cost == 3
			and honed.prereq_talent == BLADE and honed.min_level == 0
			and master.min_level == 3 and master.prereq_talent == &"",
		"authored costs (bundle 1, spin 1, flint 2, honed 2, master 3) and the gates (honed<-blade_focus, master<-level 3) match",
		"authored catalog costs/gates drifted from the .tres")

	# The authored I/O (parallel input arrays + output) is present -- INERT in Part 3.1, but pins that the .tres
	# wired the ItemData refs + counts craft execution (Part 3.2) will consume.
	ctx.check(honed.input_items.size() == 2 and honed.input_counts.size() == 2 and honed.output_item != null
			and honed.output_count == 2 and k.recipe(BUNDLE).input_items.size() == 1
			and k.recipe(BUNDLE).input_counts[0] == 2 and k.recipe(BUNDLE).output_count == 4,
		"authored I/O loads: honed_edge_kit has 2 parallel inputs + an output x2, bundle_sticks 1 input x2 -> output x4 (inert until Part 3.2)",
		"authored recipe I/O arrays did not load as expected")

	# The Part 5.1 gated WEAPON recipe: forge_iron_sword carries the FULL triple gate (talent + level + station)
	# AND wires its ore-in/weapon-out. Pins the closes-the-loop recipe the gated-weapon suite exercises.
	var forge: RecipeData = k.recipe(FORGE)
	ctx.check(forge.blueprint_cost == 2 and forge.prereq_talent == HEAVY and forge.min_level == 3
			and forge.station_tag == &"forge" and forge.input_items.size() == 2
			and forge.input_counts.size() == 2 and forge.input_counts[0] == 3 and forge.input_counts[1] == 1
			and (forge.output_item as ToolData) != null and forge.output_count == 1,
		"authored forge_iron_sword: cost 2, gated by heavy_hitter + level 3 + station forge, consumes ore x3 + stick x1, outputs a ToolData weapon x1",
		"forge_iron_sword costs/gates/IO drifted from the .tres")

	# Unknown id -> no recipe.
	ctx.check(k.recipe(&"does_not_exist") == null,
		"an unknown id resolves to no recipe (recipe() null)",
		"an unknown id wrongly resolved to a recipe")

	# Fresh character: nothing known.
	ctx.check(k.known_count() == 0 and not k.is_known(BUNDLE) and not k.is_known(HONED),
		"a fresh KnownRecipes has an empty known set (count 0, nothing is_known)",
		"a fresh KnownRecipes was not empty (count %d)" % k.known_count())


## Blueprint-points-gate + exact-cost + re-learn + unknown-id tests on an ungated recipe (no talent/level gate in
## play, so this isolates the AVAILABLE-points gate and the reported cost). Facts are passed IN (decoupled).
func _points_gate_tests(ctx: TestContext) -> void:
	var k: KnownRecipes = KnownRecipes.new()  # bundle_sticks: cost 1, no gate

	# UNKNOWN recipe is never known and never learnable -- can_learn false at any points, learn() returns 0.
	var bogus: int = k.learn(&"does_not_exist")
	ctx.check(not k.is_known(&"does_not_exist") and not k.can_learn(&"does_not_exist", 99, [], 99)
			and bogus == 0 and k.known_count() == 0,
		"an unknown recipe is never known or learnable (is_known false, can_learn false, learn returns 0, set unchanged)",
		"an unknown recipe was treated as known/learnable (bogus %d, count %d)" % [bogus, k.known_count()])

	# CANNOT learn without enough points: 0 available < cost 1.
	ctx.check(not k.can_learn(BUNDLE, 0, [], 0),
		"cannot learn bundle_sticks with 0 available blueprint points (below its cost of 1)",
		"bundle_sticks wrongly learnable with 0 points")
	# flint_kit (cost 2) is not affordable at 1 either -- the gate is `available >= cost`, not > 0.
	ctx.check(not k.can_learn(FLINT, 1, [], 0) and k.can_learn(FLINT, 2, [], 0),
		"cannot learn flint_kit with 1 point (cost 2) but can with 2 -- gate is available >= cost",
		"flint_kit affordability gate wrong at the cost boundary")

	# With enough points can_learn is true; learn() SUCCEEDS and reports the EXACT cost (1) for the caller to
	# deduct. The set grows by exactly one.
	ctx.check(k.can_learn(BUNDLE, 1, [], 0),
		"bundle_sticks is learnable once available points (1) meet its cost (1)",
		"bundle_sticks not learnable at exactly its cost")
	var spent: int = k.learn(BUNDLE)
	ctx.check(spent == 1 and k.is_known(BUNDLE) and k.known_count() == 1,
		"learning bundle_sticks succeeds, reports the EXACT cost 1, and adds exactly it to the known set",
		"bundle_sticks learn reported wrong cost / did not enter the set (cost %d, count %d)" % [spent, k.known_count()])

	# RE-LEARN is a refused no-op: reports 0, does not grow the set, stays known. And an already-known recipe is
	# no longer can_learn even with points to spare.
	var again: int = k.learn(BUNDLE)
	ctx.check(again == 0 and k.known_count() == 1 and k.is_known(BUNDLE) and not k.can_learn(BUNDLE, 99, [], 99),
		"re-learning bundle_sticks is a refused no-op (cost 0, set unchanged) and can_learn is now false",
		"re-learn mutated state or stayed learnable (again %d, count %d)" % [again, k.known_count()])


## Talent-gate tests: honed_edge_kit is gated on the blade_focus talent, so it must refuse until that id is in the
## passed unlocked-talent set -- even with points + level to burn -- then succeed. The unlocked set is passed IN
## (from Talents) so KnownRecipes stays decoupled from Talents.
func _talent_gate_tests(ctx: TestContext) -> void:
	var k: KnownRecipes = KnownRecipes.new()  # honed_edge_kit: cost 2, prereq_talent blade_focus

	# CANNOT learn with the talent gate unmet -- 99 points + level 99 is plenty, but blade_focus is not unlocked.
	ctx.check(not k.can_learn(HONED, 99, [], 99),
		"cannot learn honed_edge_kit while its prereq talent (blade_focus) is locked, even with 99 points + level 99",
		"honed_edge_kit wrongly learnable with an unmet talent gate")
	# A DIFFERENT unlocked talent does not satisfy the gate (must be blade_focus specifically).
	ctx.check(not k.can_learn(HONED, 99, [&"forager"], 99),
		"an unrelated unlocked talent (forager) does not satisfy honed_edge_kit's blade_focus gate",
		"honed_edge_kit gate satisfied by the wrong talent")

	# WITH blade_focus in the unlocked set the talent gate clears -- but still gated on its OWN cost (2):
	# affordable at 2, not at 1.
	ctx.check(k.can_learn(HONED, 2, [BLADE], 0) and not k.can_learn(HONED, 1, [BLADE], 0),
		"with blade_focus unlocked, honed_edge_kit becomes learnable at its cost (2) but not at 1 point",
		"honed_edge_kit talent/points gate wrong after the talent was unlocked")
	var spent: int = k.learn(HONED)
	ctx.check(spent == 2 and k.is_known(HONED),
		"learning honed_edge_kit after its talent gate is met succeeds and reports the EXACT cost 2",
		"honed_edge_kit learn reported wrong cost / did not enter the set (cost %d)" % spent)


## Level-gate tests: master_cordage is gated on min_level 3, so it must refuse below level 3 -- even with points
## to burn -- then succeed at/above it. The level is passed IN (from Progression) so KnownRecipes stays decoupled.
func _level_gate_tests(ctx: TestContext) -> void:
	var k: KnownRecipes = KnownRecipes.new()  # master_cordage: cost 3, min_level 3

	# CANNOT learn below the level gate -- 99 points is plenty, but level 2 < min_level 3.
	ctx.check(not k.can_learn(MASTER, 99, [], 2),
		"cannot learn master_cordage at level 2 (below its min_level of 3), even with 99 points",
		"master_cordage wrongly learnable below its min_level")

	# AT the level gate (3) the gate clears -- but still gated on its OWN cost (3): affordable at 3, not at 2.
	ctx.check(k.can_learn(MASTER, 3, [], 3) and not k.can_learn(MASTER, 2, [], 3),
		"at level 3 master_cordage becomes learnable at its cost (3) but not at 2 points",
		"master_cordage level/points gate wrong at the level boundary")
	# ABOVE the level gate it stays learnable (>= is the gate, not ==).
	ctx.check(k.can_learn(MASTER, 3, [], 5),
		"master_cordage stays learnable above its min_level (level 5 >= 3)",
		"master_cordage not learnable above its min_level")
	var spent: int = k.learn(MASTER)
	ctx.check(spent == 3 and k.is_known(MASTER) and k.known_count() == 1,
		"learning master_cordage at/above its min_level succeeds and reports the EXACT cost 3",
		"master_cordage learn reported wrong cost / did not enter the set (cost %d)" % spent)


## The CharacterSheet.learn_recipe SPEND chokepoint (pure: a RefCounted CharacterSheet needs no scene). Proves
## learn_recipe deducts the EXACT blueprint points from the owned Progression, refuses when points are
## insufficient, enforces BOTH gates off the live Progression + Talents (unlock a talent -> the talent gate
## clears; raise the level -> the level gate clears), and that a re-learn deducts nothing.
func _sheet_learn_tests(ctx: TestContext) -> void:
	var sheet: CharacterSheet = CharacterSheet.new()

	# Fresh: known_recipes wired, nothing known.
	ctx.check(sheet.known_recipes != null and sheet.known_recipes.known_count() == 0,
		"fresh CharacterSheet: known_recipes wired, known set empty",
		"fresh CharacterSheet known_recipes not wired / not empty")

	# INSUFFICIENT POINTS: 0 blueprint points -> learn_recipe refused, deducts nothing, recipe stays unknown.
	ctx.check(not sheet.learn_recipe(BUNDLE) and sheet.progression.blueprint_points == 0
			and not sheet.known_recipes.is_known(BUNDLE),
		"learn_recipe refuses bundle_sticks with 0 blueprint points and deducts NOTHING (recipe stays unknown)",
		"learn_recipe wrongly spent/learned with insufficient points")

	# Bank blueprint points, then learn bundle_sticks (cost 1): deducts EXACTLY 1, recipe becomes known.
	sheet.progression.blueprint_points = 5
	var ok_bundle: bool = sheet.learn_recipe(BUNDLE)
	ctx.check(ok_bundle and sheet.progression.blueprint_points == 4 and sheet.known_recipes.is_known(BUNDLE),
		"learn_recipe(bundle_sticks) succeeds, deducts EXACTLY its cost (5 -> 4), recipe becomes known",
		"bundle_sticks learn deducted the wrong points / not known (pts %d)" % sheet.progression.blueprint_points)

	# RE-LEARN via the sheet is a refused no-op: already known -> deducts nothing, points unchanged.
	ctx.check(not sheet.learn_recipe(BUNDLE) and sheet.progression.blueprint_points == 4
			and sheet.known_recipes.known_count() == 1,
		"learn_recipe(bundle_sticks) again is a refused no-op (already known) -- deducts nothing (pts stay 4)",
		"re-learning via the sheet mutated points/known set (pts %d, count %d)" % [sheet.progression.blueprint_points, sheet.known_recipes.known_count()])

	# TALENT GATE via the sheet: honed_edge_kit needs blade_focus. With points but the talent locked -> refused,
	# nothing deducted, recipe stays unknown.
	ctx.check(not sheet.learn_recipe(HONED) and sheet.progression.blueprint_points == 4
			and not sheet.known_recipes.is_known(HONED),
		"learn_recipe refuses honed_edge_kit while blade_focus is locked -- deducts NOTHING (talent gate off the live Talents)",
		"honed_edge_kit was learnable via the sheet with the talent gate unmet")

	# Unlock blade_focus (Track A spend), then honed_edge_kit (cost 2) learns and deducts EXACTLY 2. This proves
	# the talent gate reads the LIVE Talents.unlocked_ids() the sheet gathers.
	sheet.progression.talent_points = 5
	var ok_talent: bool = sheet.unlock_talent(BLADE)
	var ok_honed: bool = sheet.learn_recipe(HONED)
	ctx.check(ok_talent and ok_honed and sheet.progression.blueprint_points == 2
			and sheet.known_recipes.is_known(HONED),
		"after unlocking blade_focus, learn_recipe(honed_edge_kit) succeeds and deducts EXACTLY 2 (4 -> 2) -- talent gate cleared off the live Talents",
		"honed_edge_kit learn after the talent gate cleared wrong (talent %s, honed %s, pts %d)" % [str(ok_talent), str(ok_honed), sheet.progression.blueprint_points])

	# LEVEL GATE via the sheet: master_cordage needs level 3. A fresh sheet is level 1 -> refused with points to
	# spare, nothing deducted. Then raise the level -> it learns and deducts EXACTLY 3. Proves the level gate
	# reads the LIVE Progression.level the sheet gathers.
	var s2: CharacterSheet = CharacterSheet.new()
	s2.progression.blueprint_points = 10
	ctx.check(not s2.learn_recipe(MASTER) and s2.progression.blueprint_points == 10
			and not s2.known_recipes.is_known(MASTER),
		"learn_recipe refuses master_cordage at level 1 (min_level 3) with points to spare -- deducts NOTHING",
		"master_cordage was learnable via the sheet below its min_level")
	s2.progression.level = 3
	var ok_master: bool = s2.learn_recipe(MASTER)
	ctx.check(ok_master and s2.progression.blueprint_points == 7 and s2.known_recipes.is_known(MASTER),
		"at level 3 learn_recipe(master_cordage) succeeds and deducts EXACTLY 3 (10 -> 7) -- level gate cleared off the live Progression",
		"master_cordage learn after the level gate cleared wrong (ok %s, pts %d)" % [str(ok_master), s2.progression.blueprint_points])

# Verified against: Godot 4.7.1 (2026-07-19)
