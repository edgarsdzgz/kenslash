class_name TestCoreLoop extends RefCounted
## Part 5.2 -- the END-TO-END PROOF, the Epic 1 payoff (plan-epic1-parts.md Part 5.2; plan-core-loop.md
## Phase 5). Part 5.1 proved every PIECE in isolation; THIS module walks the WHOLE core progression loop as
## ONE deterministic chain on a SINGLE fresh player + its own CharacterSheet, and asserts each link connects
## to the next with ZERO new production logic (5.1 found the crafted weapon equippable at the existing seam):
##   a. FIGHT + HARVEST -> XP -- a REAL kill (an enemy struck dead through its Hurtbox seam grants xp_reward)
##      AND a REAL harvest (a current-pickaxe strike through a rock's Hurtbox grants XP_PER_MINE) bank XP from
##      the live gameplay hooks; then a deterministic top-up reaches LEVEL 3, banking exactly 2 talent + 2
##      blueprint points (the two currencies the recipe + talent gates below spend);
##   b. GATED LEARN -- forge_iron_sword REFUSES to learn while heavy_hitter is locked (points + level met),
##      then heavy_hitter UNLOCKS (talent points deducted), then forge_iron_sword LEARNS (blueprint deducted);
##   c. MINE the ore -- the shipped pickaxe mines the ore_rock OUT for iron_ore x3, COLLECTED into the player's
##      own inventory through the pickup facade; a stick is placed alongside;
##   d. GATED CRAFT -- with the mats in hand the craft still REFUSES with no forge in range (a real Station +
##      the real tags_in_range scan return []), then a forge Station placed in range makes it CRAFT (ore x3 +
##      stick x1 -> iron_sword; ore + stick consumed);
##   e. STRONGER + EQUIPPED -- the crafted iron_sword equips at the SAME Inventory.equipped_tool() seam and its
##      live Sword-Hitbox atk (10) EXCEEDS the starting sword (6);
##   f. HARDER ENEMY VIABLE -- a REAL lunge with the iron_sword lands MORE HP damage on an enemy than the same
##      lunge with the starting sword would, the heavy_hitter melee bonus applied consistently to both, so the
##      delta is purely the crafted weapon's higher atk. The gate genuinely blocked until ore + blueprint point
##      + forge + talent + level were ALL present.
## Fully self-contained + deterministic (no Time/OS/RNG): its own player/enemies/rocks/station at a remote
## region, driven through the same Hurtbox / award_xp / character-sheet / craft / equip seams the game uses.
## Registered LAST in tests/smoke_slash.gd, the capstone after every other module.

const ENEMY_SCENE: PackedScene = preload("res://enemy/enemy.tscn")
const ROCK_SCENE: PackedScene = preload("res://world/rock.tscn")
const ORE_ROCK_SCENE: PackedScene = preload("res://world/ore_rock.tscn")
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const STATION_SCENE: PackedScene = preload("res://world/station.tscn")

const IRON_ORE: ItemData = preload("res://data/iron_ore.tres")
const IRON_SWORD: ToolData = preload("res://data/iron_sword.tres")
const SWORD: ToolData = preload("res://data/sword_data.tres")
const PICKAXE: ToolData = preload("res://data/pickaxe_data.tres")
const STICK: ItemData = preload("res://data/stick.tres")

const FORGE: StringName = &"forge_iron_sword"   # the recipe id (data/recipes/forge_iron_sword.tres)
const HEAVY: StringName = &"heavy_hitter"        # the recipe's prereq talent (data/talents/heavy_hitter.tres), cost 2, MELEE +2

## The exact level-3 cumulative XP threshold (components/progression.gd curve: L3 at 220 xp).
const LEVEL3_XP: int = 220
## Remote region clear of every other self-contained module (gated-weapon (-120000,120000), boulder 90000,
## talents 70000, xp-award 60000, ...). This capstone sits far past all of them.
const HOME: Vector2 = Vector2(140000.0, -140000.0)


func run(ctx: TestContext) -> void:
	print("[core-loop] --- Part 5.2: END-TO-END fight/harvest -> level -> learn -> mine -> craft -> stronger weapon -> harder enemy viable ---")
	var holder: Node2D = Node2D.new()
	ctx.tree.root.add_child(holder)
	var player: Player = PLAYER_SCENE.instantiate() as Player
	player.pickup_radius = 0.0  # drive collection explicitly (like the other remote players -- no incidental magnet)
	holder.add_child(player)
	player.global_position = HOME
	await ctx.settle_idle()
	await ctx.tree.physics_frame

	# Take over the "player" group so the kill/harvest XP hooks (which resolve the recipient through the group,
	# exactly as the game does) bank onto OUR controlled player, not the incidental shared main player. Displaced
	# members are restored at teardown so no later module is polluted (mirrors tests/test_talents.gd's harvest leg).
	var displaced: Array = []
	for other in ctx.tree.get_nodes_in_group("player"):
		if other != player:
			other.remove_from_group("player")
			displaced.append(other)

	await _fight_harvest_to_level_3(ctx, holder, player)
	_gated_learn(ctx, player)
	await _mine_ore_into_inventory(ctx, holder, player)
	_gated_craft(ctx, holder, player)
	_equip_stronger(ctx, player)
	await _harder_enemy_viable(ctx, holder, player)

	# Teardown: restore the displaced group members, free everything this module spawned.
	for other in displaced:
		if is_instance_valid(other):
			other.add_to_group("player")
	holder.queue_free()
	await ctx.tree.physics_frame


## STEP a -- a REAL kill and a REAL harvest bank XP from the live gameplay hooks, then a deterministic top-up
## reaches LEVEL 3 with exactly the two-currency points the gates below spend. The kill routes a lethal strike
## through the enemy's Hurtbox (enemy.gd _on_died awards xp_reward to the group player); the harvest routes a
## current-pickaxe strike through a rock's Hurtbox (rock.gd awards XP_PER_MINE per affecting mine).
func _fight_harvest_to_level_3(ctx: TestContext, holder: Node2D, player: Player) -> void:
	var prog: Progression = player.character().progression
	ctx.check(prog.xp == 0 and prog.level == 1 and prog.talent_points == 0 and prog.blueprint_points == 0,
		"a FRESH player starts the loop at xp 0 / level 1 / 0 talent + 0 blueprint points",
		"fresh player progression not at defaults (xp %d L%d T%d B%d)" % [prog.xp, prog.level, prog.talent_points, prog.blueprint_points])

	# --- REAL KILL: an enemy struck dead through its Hurtbox seam banks xp_reward on the group player ---
	var enemy: Enemy = ENEMY_SCENE.instantiate() as Enemy
	holder.add_child(enemy)
	enemy.global_position = HOME + Vector2(300.0, 0.0)
	await ctx.tree.physics_frame
	var reward: int = enemy.xp_reward
	var enemy_hurt: Hurtbox = enemy.get_node("Hurtbox") as Hurtbox
	var xp_before_kill: int = prog.xp
	var blow: Hitbox = Hitbox.new()   # a lethal strike (atk far above the enemy's HP) -- one killing hit via the seam
	blow.atk = 100
	holder.add_child(blow)
	enemy_hurt._on_area_entered(blow)
	await ctx.tree.physics_frame
	ctx.check(enemy.is_dead and prog.xp == xp_before_kill + reward and reward == 20,
		"a REAL kill (enemy struck dead through its Hurtbox) banks its exact xp_reward (%d) on the player (%d -> %d)" % [reward, xp_before_kill, prog.xp],
		"kill did not bank xp_reward (dead %s, xp %d -> %d, reward %d)" % [str(enemy.is_dead), xp_before_kill, prog.xp, reward])

	# --- REAL HARVEST: a current-pickaxe strike through a rock's Hurtbox banks XP_PER_MINE ---
	var rock_holder: Node2D = Node2D.new()
	holder.add_child(rock_holder)
	var rock: Rock = ROCK_SCENE.instantiate() as Rock
	rock_holder.add_child(rock)
	rock.global_position = HOME + Vector2(600.0, 0.0)
	await ctx.tree.physics_frame
	var rock_hurt: Hurtbox = rock.get_node("Hurtbox") as Hurtbox
	var xp_before_mine: int = prog.xp
	var pick: Hitbox = _pickaxe_hitbox(holder)
	await ctx.tree.physics_frame
	rock_hurt._on_area_entered(pick)   # one affecting mine -> rock.gd chips stone + awards XP_PER_MINE once
	await ctx.tree.physics_frame
	ctx.check(prog.xp == xp_before_mine + Rock.XP_PER_MINE and Rock.XP_PER_MINE == 5,
		"a REAL harvest (current-pickaxe strike through the rock's Hurtbox) banks XP_PER_MINE (%d) on the player (%d -> %d)" % [Rock.XP_PER_MINE, xp_before_mine, prog.xp],
		"harvest did not bank XP_PER_MINE (xp %d -> %d)" % [xp_before_mine, prog.xp])
	pick.queue_free()
	rock_holder.queue_free()
	await ctx.tree.physics_frame

	# --- REACH LEVEL 3: top up deterministically to the exact L3 threshold; bank exactly 2 talent + 2 blueprint ---
	ctx.check(prog.xp == reward + Rock.XP_PER_MINE and prog.xp == 25,
		"the two live hooks banked exactly the kill + mine XP so far (%d)" % prog.xp,
		"banked XP after the two hooks wrong (got %d, expected 25)" % prog.xp)
	player.award_xp(LEVEL3_XP - prog.xp)   # deterministic top-up to the L3 threshold via the same award facade
	ctx.check(prog.level == 3 and prog.xp == LEVEL3_XP and prog.talent_points == 2 and prog.blueprint_points == 2,
		"reaching LEVEL 3 (xp %d) banks exactly 2 talent + 2 blueprint points (the currencies the gates below spend)" % prog.xp,
		"level-3 banking wrong (L%d xp%d T%d B%d)" % [prog.level, prog.xp, prog.talent_points, prog.blueprint_points])


## STEP b -- the LEARN gate genuinely blocks: forge_iron_sword refuses while heavy_hitter is locked (blueprint
## points + level 3 already met), then heavy_hitter unlocks (talent points deducted), then it learns (blueprint
## points deducted). Driven through the real CharacterSheet chokepoints on the player's own sheet.
func _gated_learn(ctx: TestContext, player: Player) -> void:
	var sheet: CharacterSheet = player.character()
	var prog: Progression = sheet.progression

	# REFUSED while the TALENT gate is unmet -- points (2) + level (3) are met, heavy_hitter is not unlocked yet.
	ctx.check(not sheet.learn_recipe(FORGE) and prog.blueprint_points == 2 and not sheet.known_recipes.is_known(FORGE),
		"forge_iron_sword REFUSES to learn while heavy_hitter is locked (blueprint 2 + level 3 met) -- deducts NOTHING",
		"forge_iron_sword learnable with its talent gate unmet (known %s, blueprint %d)" % [str(sheet.known_recipes.is_known(FORGE)), prog.blueprint_points])

	# UNLOCK heavy_hitter (cost 2): talent points 2 -> 0, exactly its cost deducted.
	ctx.check(sheet.unlock_talent(HEAVY) and prog.talent_points == 0 and sheet.talents.is_unlocked(HEAVY),
		"unlock_talent(heavy_hitter) succeeds and deducts EXACTLY its cost (talent 2 -> 0)",
		"heavy_hitter unlock/deduction wrong (unlocked %s, talent %d)" % [str(sheet.talents.is_unlocked(HEAVY)), prog.talent_points])

	# NOW every gate clears -> LEARNS, deducting exactly the blueprint cost (blueprint 2 -> 0).
	ctx.check(sheet.learn_recipe(FORGE) and sheet.known_recipes.is_known(FORGE) and prog.blueprint_points == 0,
		"with heavy_hitter + level 3 + points ALL met, forge_iron_sword LEARNS and deducts EXACTLY its cost (blueprint 2 -> 0)",
		"forge_iron_sword learn wrong after the gates cleared (known %s, blueprint %d)" % [str(sheet.known_recipes.is_known(FORGE)), prog.blueprint_points])


## STEP c -- the shipped pickaxe mines the ore_rock OUT (integrity 6 / wear 2 = 3 affecting hits -> 3 Iron Ore),
## and the yielded drops are COLLECTED into the player's own inventory through the pickup facade; a stick is
## placed alongside so the forge recipe (ore x3 + stick x1) has all its inputs in hand.
func _mine_ore_into_inventory(ctx: TestContext, holder: Node2D, player: Player) -> void:
	var ore_holder: Node2D = Node2D.new()
	holder.add_child(ore_holder)
	var ore: Rock = ORE_ROCK_SCENE.instantiate() as Rock
	ore_holder.add_child(ore)
	ore.global_position = HOME + Vector2(900.0, 0.0)
	await ctx.tree.physics_frame
	var ore_hurt: Hurtbox = ore.get_node("Hurtbox") as Hurtbox
	var ore_mat: DurabilityComponent = ore.get_node("Material") as DurabilityComponent

	# First a REAL current-pickaxe strike through the ore's Hurtbox (proves the shipped tool carves it), then
	# drive the remaining integrity to 0 the deterministic way (Material.wear, exactly as test_gated_weapon /
	# test_harvest) so the rock mines OUT to its full 3-ore yield.
	var pick: Hitbox = _pickaxe_hitbox(holder)
	await ctx.tree.physics_frame
	# The FIRST real strike must be LOAD-BEARING (mirrors test_gated_weapon's real-strike leg): capture the
	# pick's durability, land ONE real pickaxe strike through the ore's Hurtbox, and assert it AFFECTED the ore
	# -- a drop yielded AND the pick WORE -- BEFORE the deterministic wear-loop top-up. Without this the mine
	# step is insensitive to the real strike: the collected==3 total below is reached whether the strike lands
	# (1 drop + a 2-drop wear loop) or whiffs (0 drops + a 3-drop wear loop), so a pickaxe->Band-C regression
	# would pass here silently. This assertion makes such a regression FAIL the capstone, not just Part 5.1.
	var pick_dura: DurabilityComponent = pick.durability
	var pick_dura_before: int = pick_dura.current_durability
	ore_hurt._on_area_entered(pick)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame   # settle the deferred drop add_child of the first real chip
	ctx.check(_ore_drops(ore_holder).size() == 1 and pick_dura.current_durability < pick_dura_before,
		"the FIRST REAL pickaxe strike AFFECTED the ore: 1 Iron Ore yielded + the pick WORE (%d -> %d) -- a pickaxe->Band-C whiff (0 drops, no wear) fails HERE, not just in Part 5.1" % [pick_dura_before, pick_dura.current_durability],
		"the first real pickaxe strike did not affect the ore (drops %d, pick %d -> %d)" % [_ore_drops(ore_holder).size(), pick_dura_before, pick_dura.current_durability])
	while is_instance_valid(ore_mat) and ore_mat.current_durability > 0:
		ore_mat.wear(2)
		await ctx.tree.physics_frame
	await ctx.tree.physics_frame   # settle the deferred drop add_child of the final chip

	# COLLECT every yielded Iron Ore drop into the player's OWN inventory through the pickup facade (player.collect
	# -> Inventory.add_item), the same seam the magnet + bushes use -- the real mine -> inventory link.
	var collected: int = 0
	for child in ore_holder.get_children():
		if child is Drop and (child as Drop).item == IRON_ORE:
			var d: Drop = child as Drop
			collected += d.count - player.collect(d.item, d.count)   # count minus overflow = actually taken
			d.queue_free()
	pick.queue_free()
	ctx.check(collected == 3 and player.inventory.count_of(IRON_ORE) == 3,
		"the ore_rock mines OUT for 3 Iron Ore, COLLECTED into the player's inventory (count_of Iron Ore == 3)",
		"ore mine -> inventory wrong (collected %d, inventory holds %d)" % [collected, player.inventory.count_of(IRON_ORE)])

	# The recipe also needs a stick -- place one so the forge inputs (ore x3 + stick x1) are fully in hand.
	player.inventory.add_item(STICK, 1)
	ctx.check(player.inventory.count_of(STICK) == 1,
		"a stick is present alongside the ore -- the forge recipe's inputs (Iron Ore x3 + Stick x1) are all in hand",
		"stick not present after placing one (holds %d)" % player.inventory.count_of(STICK))

	ore_holder.queue_free()
	await ctx.tree.physics_frame


## STEP d -- the CRAFT gate genuinely blocks: even learned + with the mats in hand, forge_iron_sword refuses to
## craft while NO forge is in range (a real Station + the real tags_in_range scan return []); a forge Station
## placed in range makes it craft (ore x3 + stick x1 -> iron_sword; inputs consumed). Real Station -> real scan
## -> real Crafting.craft, the whole Part 4.1 + 3.2 path.
func _gated_craft(ctx: TestContext, holder: Node2D, player: Player) -> void:
	var craft: Crafting = Crafting.new()
	var inv: Inventory = player.inventory

	# STATION gate -- no forge placed yet: the scan around the player finds nothing, so the craft refuses,
	# consuming NOTHING (ore stays 3, stick stays 1, no sword).
	var no_forge_tags: Array[StringName] = Station.tags_in_range(player.global_position, Station.DEFAULT_REACH)
	var no_forge: bool = craft.craft(FORGE, player.character(), inv, no_forge_tags)
	ctx.check(no_forge_tags.is_empty() and not no_forge and inv.count_of(IRON_ORE) == 3
			and inv.count_of(STICK) == 1 and inv.count_of(IRON_SWORD) == 0,
		"forge_iron_sword REFUSES to craft with no forge in range (scan []) -- ore stays 3, stick stays 1, no sword",
		"station-gated weapon crafted with no forge (tags %s, ok %s, ore %d, stick %d, sword %d)" % [str(no_forge_tags), str(no_forge), inv.count_of(IRON_ORE), inv.count_of(STICK), inv.count_of(IRON_SWORD)])

	# Place a real forge Station in range, re-scan, and craft: ore 3 -> 0, stick 1 -> 0, iron_sword 0 -> 1.
	var station: Station = STATION_SCENE.instantiate() as Station
	station.station_tag = &"forge"
	holder.add_child(station)
	station.global_position = HOME + Vector2(40.0, 0.0)   # within DEFAULT_REACH of the player at HOME
	var forge_tags: Array[StringName] = Station.tags_in_range(player.global_position, Station.DEFAULT_REACH)
	var forged: bool = craft.craft(FORGE, player.character(), inv, forge_tags)
	ctx.check(forge_tags == [&"forge"] and forged and inv.count_of(IRON_ORE) == 0
			and inv.count_of(STICK) == 0 and inv.count_of(IRON_SWORD) == 1,
		"a forge Station in range (scan [forge]) makes forge_iron_sword CRAFT: ore 3 -> 0, stick 1 -> 0, iron_sword 0 -> 1",
		"forge_iron_sword did not craft with a forge present (tags %s, ok %s, ore %d, stick %d, sword %d)" % [str(forge_tags), str(forged), inv.count_of(IRON_ORE), inv.count_of(STICK), inv.count_of(IRON_SWORD)])


## STEP e -- the crafted iron_sword EQUIPS at the SAME Inventory.equipped_tool() seam the starting tools use,
## and its live Sword-Hitbox base atk (10) EXCEEDS the starting sword (6) -- a measurably stronger weapon, in
## hand, produced by the loop.
func _equip_stronger(ctx: TestContext, player: Player) -> void:
	var slot: int = _slot_of(player.inventory, IRON_SWORD)
	player.inventory.equip_index(slot)
	player._apply_equipped()   # the real equip chokepoint: writes the tool's base atk onto the Sword Hitbox
	var equipped: ToolData = player.inventory.equipped_tool()
	ctx.check(slot >= 0 and equipped == IRON_SWORD and player._sword.atk == IRON_SWORD.atk
			and IRON_SWORD.atk > SWORD.atk and player._sword.atk == 10,
		"the crafted iron_sword EQUIPS at the shared seam -- live Sword-Hitbox atk %d EXCEEDS the starting sword (%d)" % [player._sword.atk, SWORD.atk],
		"crafted iron_sword did not equip stronger (slot %d, equipped %s, live atk %d vs %d)" % [slot, str(equipped), player._sword.atk, SWORD.atk])


## STEP f -- HARDER ENEMY VIABLE: a REAL lunge with the crafted iron_sword lands MORE HP damage on an enemy than
## the same lunge with the starting sword would. The heavy_hitter melee bonus (+2, unlocked in step b) is applied
## to BOTH swings via combat.gd's per-swing bonus, so the damage delta is PURELY the crafted weapon's higher atk
## (iron 10 vs sword 6). Both measured on the SAME pinned enemy, healed to full between, so the numbers are exact.
func _harder_enemy_viable(ctx: TestContext, holder: Node2D, player: Player) -> void:
	var enemy: Enemy = ENEMY_SCENE.instantiate() as Enemy
	holder.add_child(enemy)
	var enemy_pos: Vector2 = HOME + Vector2(1500.0, 0.0)
	enemy.global_position = enemy_pos
	await ctx.tree.physics_frame
	var ehealth: HealthComponent = enemy.get_node("HealthComponent") as HealthComponent

	# heavy_hitter is unlocked -> a +2 melee bonus lands on every swing; the same bonus applies to both weapons.
	ctx.check(player.character().melee_damage_bonus() == 2,
		"the heavy_hitter melee bonus (+2) is live and will apply CONSISTENTLY to both weapons' swings",
		"melee bonus not +2 before the harder-hits measurement (got %d)" % player.character().melee_damage_bonus())

	# Same lunge, starting sword: base 6 + heavy 2 = 8 atk vs the enemy's def 1 -> max(0,8-1) = 7 HP.
	var sword_dmg: int = await _measure_lunge_damage(ctx, player, enemy, ehealth, enemy_pos, SWORD)
	# Same lunge, crafted iron_sword: base 10 + heavy 2 = 12 atk vs def 1 -> max(0,12-1) = 11 HP.
	var iron_dmg: int = await _measure_lunge_damage(ctx, player, enemy, ehealth, enemy_pos, IRON_SWORD)

	ctx.check(iron_dmg > sword_dmg and sword_dmg == 7 and iron_dmg == 11
			and (iron_dmg - sword_dmg) == (IRON_SWORD.atk - SWORD.atk),
		"a REAL lunge with the crafted iron_sword lands MORE HP damage than the starting sword (%d > %d); the delta (%d) is exactly the crafted atk advantage (10 - 6) -- harder enemies are now viable" % [iron_dmg, sword_dmg, iron_dmg - sword_dmg],
		"the crafted weapon did not land harder in real combat (iron %d, sword %d, atk delta %d)" % [iron_dmg, sword_dmg, IRON_SWORD.atk - SWORD.atk])


## Equip `tool`, pin the enemy at `enemy_pos` healed to full, land ONE real lunge (combo hit 3 -- the blade held
## fixed for the whole window, a guaranteed overlap on physics frames; test_context.lunge_hit's technique), and
## return the HP damage that single strike dealt. The lunge routes through the player's real combat swing, so the
## live melee bonus is applied on the Sword Hitbox exactly as in play. Resets the enemy's position + knockback +
## HP each call so the two measurements are independent and exact.
func _measure_lunge_damage(ctx: TestContext, player: Player, enemy: Enemy, ehealth: HealthComponent, enemy_pos: Vector2, tool: ToolData) -> int:
	player.equip_tool(tool)
	enemy.stationary = true                       # pin it so it neither chases nor drifts between measurements
	enemy.global_position = enemy_pos
	enemy._move_velocity = Vector2.ZERO
	enemy._knockback = Vector2.ZERO               # clear the prior lunge's knockback so the fixed geometry holds
	ehealth.heal(ehealth.max_health)              # full HP so the single strike's damage reads exact
	await ctx.tree.physics_frame
	var before: int = ehealth.current_health
	await ctx.lunge_hit(player, enemy_pos + Vector2(-24.0, 0.0), Vector2.RIGHT)
	return before - ehealth.current_health


## Build a Hitbox carrying the shipped pickaxe's authored stats + a fresh runtime durability, parented under
## `holder` so it is in-tree, ready to route a real MINE strike through a rock's Hurtbox (mirrors the pickaxe
## strike in tests/test_gated_weapon.gd).
func _pickaxe_hitbox(holder: Node2D) -> Hitbox:
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
	return pick


## The live Iron Ore Drop instances directly under a holder (empty if none). Mirrors tests/test_gated_weapon.gd's
## _ore_drops -- used by the mine step to assert the FIRST real pickaxe strike yielded a drop.
func _ore_drops(parent: Node) -> Array:
	var out: Array = []
	for child in parent.get_children():
		if child is Drop and (child as Drop).item == IRON_ORE:
			out.append(child)
	return out


## The first slot index holding `item`, or -1 if none (mirrors tests/test_gated_weapon.gd).
func _slot_of(inv: Inventory, item: ItemData) -> int:
	for i in range(inv.slots.size()):
		if inv.item_at(i) == item:
			return i
	return -1

# Verified against: Godot 4.7.1 (2026-07-19)
