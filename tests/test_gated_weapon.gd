class_name TestGatedWeapon extends RefCounted
## Part 5.1 -- the CONTENT that closes the core loop: a higher-tier ORE that the CURRENT pickaxe can still mine,
## and a STRONGER weapon recipe fenced behind that ore + a blueprint point + a talent + a level + a forge station
## (plan-epic1-parts.md Part 5.1; plan-core-loop.md Phase 5). No new equip/craft LOGIC -- ToolData IS an ItemData,
## so the recipe's output_item is the iron_sword ToolData directly and the crafted stack down-casts at the SAME
## equip seam (Inventory.equipped_tool()) the existing Equipment uses. This suite proves, purely + deterministically
## (no Time/OS/RNG; a self-contained ore rock at remote coords + pure component instances):
##   * MINEABLE NOW -- the ore rock is HARDER than the basic rock yet the current pickaxe still AFFECTS it (Band B),
##     and a REAL pickaxe strike through the ore's Hurtbox YIELDS the ore (and wears the pick -- a real harder mine);
##   * STRONGER -- the iron_sword's atk EXCEEDS the starting sword's atk;
##   * GATED LEARN -- forge_iron_sword cannot be learned until its blueprint-point + talent (heavy_hitter) + level
##     gates are ALL met, and learns (deducting exactly its cost) once they are;
##   * GATED CRAFT -- even learned + with the ore/stick in hand it will not craft without the &"forge" station in
##     range, and DOES craft (ore x3 + stick x1 -> iron_sword) once the forge tag is present;
##   * EQUIPPABLE -- the crafted iron_sword down-casts to a ToolData at the equip seam and reads its higher atk
##     (full equip+use is Part 5.2). Registered in tests/smoke_slash.gd after TestCrafting.

const IRON_ORE: ItemData = preload("res://data/iron_ore.tres")
const IRON_SWORD: ToolData = preload("res://data/iron_sword.tres")
const SWORD: ToolData = preload("res://data/sword_data.tres")
const PICKAXE: ToolData = preload("res://data/pickaxe_data.tres")
const STICK: ItemData = preload("res://data/stick.tres")
const ROCK_SCENE: PackedScene = preload("res://world/rock.tscn")
const ORE_ROCK_SCENE: PackedScene = preload("res://world/ore_rock.tscn")

const FORGE: StringName = &"forge_iron_sword"
const HEAVY: StringName = &"heavy_hitter"   # an EXISTING data/talents node, no prereqs (cost 2)
## Remote region clear of every other self-contained module's coords (boulder 90000, elevation 48000, ...).
const HOME: Vector2 = Vector2(-120000.0, 120000.0)


func run(ctx: TestContext) -> void:
	print("[gated-weapon] --- Part 5.1: mineable ore + stronger gated weapon recipe + equippable crafted sword ---")
	await _ore_mineable_by_current_pickaxe(ctx)
	_iron_sword_is_stronger(ctx)
	_recipe_learn_gated(ctx)
	_recipe_craft_gated_then_equippable(ctx)


## The ore rock is HARDER than the basic rock but the CURRENT pickaxe still affects it (Band B), and a REAL
## pickaxe strike through its Hurtbox yields the ore + wears the pick. Then the rock mines out to exactly one
## ore per affecting hit. Proves the "encounter placement is later; a scene the test instantiates is enough"
## content is mineable NOW with the shipped tool.
func _ore_mineable_by_current_pickaxe(ctx: TestContext) -> void:
	var holder: Node2D = Node2D.new()
	ctx.tree.root.add_child(holder)

	var basic: Rock = ROCK_SCENE.instantiate() as Rock
	holder.add_child(basic)
	basic.global_position = HOME + Vector2(0.0, -400.0)
	var ore: Rock = ORE_ROCK_SCENE.instantiate() as Rock
	holder.add_child(ore)
	ore.global_position = HOME
	await ctx.tree.physics_frame

	# HARDER-but-mineable: the ore's hardness beats the basic rock's, and the DurabilityResolver run with the
	# CURRENT pickaxe's authored stats still AFFECTS the ore (Band B -- it even wears the pick), so the shipped
	# tool can carve it. A basic rock is Band A (no wear) for the same pick; the ore is a real step up.
	var ore_res: Dictionary = DurabilityResolver.resolve(PICKAXE.power, ore.hardness, PICKAXE.break_threshold, PICKAXE.wear_max)
	ctx.check(ore.hardness > basic.hardness and bool(ore_res["affects_target"]) and int(ore_res["weapon_wear"]) > 0,
		"ore rock is HARDER (hardness %d > basic %d) yet the CURRENT pickaxe still affects it (Band B, pick wears %d) -- mineable now" % [ore.hardness, basic.hardness, int(ore_res["weapon_wear"])],
		"ore rock not a mineable higher tier (ore hardness %d, basic %d, affects %s, wear %d)" % [ore.hardness, basic.hardness, str(ore_res["affects_target"]), int(ore_res["weapon_wear"])])

	# A REAL strike: a Hitbox carrying the pickaxe's authored stats, routed through the ore's own Hurtbox
	# resolution (not a fabricated Material.wear). It must yield the ore AND wear the pick -- the true harder mine.
	var ore_hurt: Hurtbox = ore.get_node("Hurtbox") as Hurtbox
	var ore_mat: DurabilityComponent = ore.get_node("Material") as DurabilityComponent
	var pick: Hitbox = Hitbox.new()
	pick.power = PICKAXE.power
	pick.break_threshold = PICKAXE.break_threshold
	pick.wear_max = PICKAXE.wear_max
	pick.harvest_type = Harvest.Type.MINE
	var pick_dura: DurabilityComponent = DurabilityComponent.new()
	pick_dura.max_durability = PICKAXE.max_durability
	pick.durability = pick_dura
	pick.add_child(pick_dura)
	holder.add_child(pick)
	await ctx.tree.physics_frame
	var pick_dura_before: int = pick_dura.current_durability
	ore_hurt._on_area_entered(pick)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	ctx.check(_ore_drops(holder).size() == 1 and pick_dura.current_durability < pick_dura_before and is_instance_valid(ore),
		"a REAL current-pickaxe strike MINES the ore rock: 1 Iron Ore yielded + the pick worn (%d -> %d), rock still standing" % [pick_dura_before, pick_dura.current_durability],
		"pickaxe strike did not mine the ore correctly (ore drops %d, pick %d -> %d)" % [_ore_drops(holder).size(), pick_dura_before, pick_dura.current_durability])

	# Mine it OUT: one Iron Ore per affecting hit, freed after the last. integrity 6 / wear_taken 2 = 3 affecting
	# hits total; the real strike above was the first, so drive the remaining integrity to 0 the deterministic way
	# (Material.wear, exactly as tests/test_harvest.gd's mineral-per-hit leg) and count the full ore yield.
	# Guard on the Material node's validity: the mine-to-0 hit frees the rock (and this child) on the settle
	# frame, so the short-circuit stops us reading current_durability on a freed node once it is gone.
	while is_instance_valid(ore_mat) and ore_mat.current_durability > 0:
		ore_mat.wear(2)
		await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	ctx.check(_ore_drops(holder).size() == 3 and not is_instance_valid(ore),
		"mined OUT: exactly 3 Iron Ore yielded (one per affecting hit on integrity 6 / wear 2) and the ore rock freed",
		"ore mine-out yield/free wrong (ore drops %d, valid %s)" % [_ore_drops(holder).size(), str(is_instance_valid(ore))])

	holder.queue_free()
	await ctx.tree.physics_frame


## The crafted weapon is measurably STRONGER: iron_sword.atk exceeds the starting sword's atk (System 1 HP damage).
func _iron_sword_is_stronger(ctx: TestContext) -> void:
	ctx.check(IRON_SWORD.atk > SWORD.atk and IRON_SWORD is ToolData,
		"iron_sword is a STRONGER weapon than the starting sword (atk %d > %d)" % [IRON_SWORD.atk, SWORD.atk],
		"iron_sword not stronger than the starting sword (atk %d vs %d)" % [IRON_SWORD.atk, SWORD.atk])


## forge_iron_sword LEARN is fenced by all three character gates (blueprint points + heavy_hitter talent + level 3):
## it refuses until every gate is met, then learns once, deducting exactly its cost. Driven through the real
## CharacterSheet.learn_recipe chokepoint (live Progression + Talents), mirroring tests/test_recipes.gd.
func _recipe_learn_gated(ctx: TestContext) -> void:
	var sheet: CharacterSheet = CharacterSheet.new()

	# Points to spare + level to spare, but the TALENT gate (heavy_hitter) is locked -> refused, nothing deducted.
	sheet.progression.blueprint_points = 5
	sheet.progression.talent_points = 5
	sheet.progression.level = 3
	ctx.check(not sheet.learn_recipe(FORGE) and sheet.progression.blueprint_points == 5
			and not sheet.known_recipes.is_known(FORGE),
		"forge_iron_sword refuses to learn while heavy_hitter is locked (points + level met) -- deducts NOTHING",
		"forge_iron_sword learnable with its talent gate unmet")

	# Unlock heavy_hitter but DROP the level below 3 -> the LEVEL gate now blocks it (talent alone is not enough).
	var got_talent: bool = sheet.unlock_talent(HEAVY)
	sheet.progression.level = 2
	ctx.check(got_talent and not sheet.learn_recipe(FORGE) and not sheet.known_recipes.is_known(FORGE),
		"with heavy_hitter unlocked but level 2 (< min_level 3), forge_iron_sword still refuses (level gate)",
		"forge_iron_sword learnable below its min_level (talent %s)" % str(got_talent))

	# Meet the level gate too: every gate clears -> learns once, deducting EXACTLY its blueprint cost (2).
	sheet.progression.level = 3
	var pts_before: int = sheet.progression.blueprint_points
	var learned: bool = sheet.learn_recipe(FORGE)
	ctx.check(learned and sheet.known_recipes.is_known(FORGE) and sheet.progression.blueprint_points == pts_before - 2,
		"with points + heavy_hitter + level 3 ALL met, forge_iron_sword learns and deducts EXACTLY its cost (%d -> %d)" % [pts_before, sheet.progression.blueprint_points],
		"forge_iron_sword learn wrong after gates cleared (learned %s, pts %d)" % [str(learned), sheet.progression.blueprint_points])


## The learned recipe still will not CRAFT without the &"forge" station in range; with the ore + stick in hand AND
## the forge tag present it crafts (ore x3 + stick x1 -> iron_sword), and the crafted stack is EQUIPPABLE -- it
## down-casts to a ToolData at the SAME Inventory.equipped_tool() seam the Equipment uses, reading its higher atk.
func _recipe_craft_gated_then_equippable(ctx: TestContext) -> void:
	var sheet: CharacterSheet = CharacterSheet.new()
	sheet.progression.blueprint_points = 5
	sheet.progression.talent_points = 5
	sheet.progression.level = 3
	sheet.unlock_talent(HEAVY)
	sheet.learn_recipe(FORGE)   # all gates met (proven in _recipe_learn_gated)
	var craft: Crafting = Crafting.new()

	# STATION gate: learned + mats present, but NO forge in range (default-empty tag list) -> refuses, nothing consumed.
	var inv: Inventory = Inventory.new()
	inv.add_item(IRON_ORE, 3)
	inv.add_item(STICK, 1)
	var no_forge: bool = craft.craft(FORGE, sheet, inv)   # default in_range_station_tags == []
	ctx.check(not no_forge and inv.count_of(IRON_ORE) == 3 and inv.count_of(STICK) == 1
			and inv.count_of(IRON_SWORD) == 0,
		"forge_iron_sword REFUSES to craft with no forge in range -- ore stays 3, stick stays 1, no sword",
		"station-gated weapon crafted without a forge (ok %s, ore %d, stick %d, sword %d)" % [str(no_forge), inv.count_of(IRON_ORE), inv.count_of(STICK), inv.count_of(IRON_SWORD)])

	# With &"forge" in range it crafts end to end: ore 3 -> 0, stick 1 -> 0, iron_sword 0 -> 1.
	var forge_tags: Array[StringName] = [&"forge"]
	var forged: bool = craft.craft(FORGE, sheet, inv, forge_tags)
	ctx.check(forged and inv.count_of(IRON_ORE) == 0 and inv.count_of(STICK) == 0 and inv.count_of(IRON_SWORD) == 1,
		"forge_iron_sword crafts with &\"forge\" in range: ore 3 -> 0, stick 1 -> 0, iron_sword 0 -> 1",
		"forge_iron_sword did not craft with a forge present (ok %s, ore %d, stick %d, sword %d)" % [str(forged), inv.count_of(IRON_ORE), inv.count_of(STICK), inv.count_of(IRON_SWORD)])

	# EQUIPPABLE: equip the slot the crafted sword landed in; the inventory hands back a ToolData (the exact
	# down-cast Equipment.apply_equipped() uses) that IS the iron_sword and reads its higher-than-starting atk.
	var slot: int = _slot_of(inv, IRON_SWORD)
	inv.equip_index(slot)
	var equipped: ToolData = inv.equipped_tool()
	ctx.check(slot >= 0 and equipped == IRON_SWORD and equipped != null and equipped.atk > SWORD.atk,
		"the crafted iron_sword is EQUIPPABLE: it down-casts to a ToolData at the equip seam with atk %d (> starting %d)" % [IRON_SWORD.atk, SWORD.atk],
		"crafted iron_sword not equippable as a stronger ToolData (slot %d, equipped %s)" % [slot, str(equipped)])


## The live Iron Ore Drop instances directly under a holder (empty if none).
func _ore_drops(parent: Node) -> Array:
	var out: Array = []
	for child in parent.get_children():
		if child is Drop and (child as Drop).item == IRON_ORE:
			out.append(child)
	return out


## The first slot index holding `item`, or -1 if none.
func _slot_of(inv: Inventory, item: ItemData) -> int:
	for i in range(inv.slots.size()):
		if inv.item_at(i) == item:
			return i
	return -1

# Verified against: Godot 4.7.1 (2026-07-19)
