class_name TestCraftMenu extends RefCounted
## Minimal craft MENU + the 'f'-near-a-station open seam (plan-epic1-parts.md Part 4.2; plan-core-loop.md Phase 4;
## design-crafting.md "Track B"). Where test_crafting proves craft EXECUTION and test_station proves the world
## station gate, this leg proves the OPERABLE-LOOP UI slice: a player stands at a station, sees their KNOWN
## recipes with correct craftable flags, and crafts one through the menu. UI-style structural assertions (state +
## structure, never pixels), mirroring tests/test_hud.gd. Three parts:
##   * MENU API (pure, off ui/craft_menu.tscn): open() lists the KNOWN recipes with the right craftable flags; a
##     station-gated recipe (master_cordage/&"forge") is craftable ONLY when the forge tag is in range while a
##     craft-anywhere recipe (spin_cord) is craftable with NO station; craft_selected/craft consumes inputs +
##     produces output THROUGH the menu and REFRESHES the flag (a now-unaffordable recipe greys out);
##   * INTERACTION SEAM (real player + Station node): 'f' next to a station raises the open request carrying the
##     in-range tags (and the prompt reads "Craft"), while 'f' with NO station in reach still HARVESTS a bush;
##   * INTEGRATION (shipped streaming_world.tscn): the HUD polls that request and OPENS the hosted CraftMenu with
##     the player's live sheet/inventory + the routed tags, listing the learned recipes; a second 'f' toggles it
##     closed -- the player never reaching into the UI.
## Self-contained: builds its own menu/players/stations/bush under private holders at REMOTE coords (clear of
## every other module's region) + its own streaming_world instance, freeing them at the end. Registered in
## tests/smoke_slash.gd after TestStation.

const CRAFT_MENU_SCENE: PackedScene = preload("res://ui/craft_menu.tscn")
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const STATION_SCENE: PackedScene = preload("res://world/station.tscn")
const BUSH_SCENE: PackedScene = preload("res://world/bush.tscn")

const SPIN: StringName = &"spin_cord"          # fiber x3 -> cord x1, craft-anywhere
const MASTER: StringName = &"master_cordage"   # fiber x5 -> cord x3, station_tag &"forge"

## Remote region clear of test_station (-90000, 90000), forage (-30000), etc. -- so no stray station/bush from
## another module wanders into these radius scans, and this module's forge never reaches its own bush player.
const HOME: Vector2 = Vector2(120000.0, -120000.0)


func run(ctx: TestContext) -> void:
	print("[craft_menu] --- Part 4.2 minimal craft menu + 'f'-near-a-station open, end to end ---")
	await _menu_api(ctx)
	await _interaction_seam(ctx)
	await _integration(ctx)


## MENU API (pure): drive ui/craft_menu.tscn directly with hand-built sheet/inventory + tag lists. No station
## node needed -- open() takes the in-range tags as a plain Array, so a station-gated flag is tested by simply
## passing [] vs [&"forge"].
func _menu_api(ctx: TestContext) -> void:
	var holder: Node2D = Node2D.new()
	ctx.tree.root.add_child(holder)
	var menu: CraftMenu = CRAFT_MENU_SCENE.instantiate() as CraftMenu
	holder.add_child(menu)
	await ctx.tree.physics_frame  # let _ready resolve the @onready row container

	var FIBER: ItemData = load("res://data/fiber.tres")
	var CORD: ItemData = load("res://data/cord.tres")
	var sheet: CharacterSheet = CharacterSheet.new()
	sheet.known_recipes.learn(SPIN)     # craft-anywhere
	sheet.known_recipes.learn(MASTER)   # station-gated (&"forge")
	var inv: Inventory = Inventory.new()
	inv.add_item(FIBER, 5)              # >= spin (3) AND >= master (5)

	# --- open with NO station in range: both KNOWN recipes listed; spin craftable, master BLOCKED (no forge) ---
	menu.open(sheet, inv, [] as Array[StringName])
	var ids: Array[StringName] = menu.listed_ids()
	ctx.check(menu.is_open and ids.has(SPIN) and ids.has(MASTER) and ids.size() == 2,
		"open() lists the player's KNOWN recipes (spin_cord + master_cordage) and marks the menu open (got " + str(ids) + ")",
		"open() listing wrong (open=%s, ids=%s)" % [str(menu.is_open), str(ids)])
	ctx.check(menu.is_craftable(SPIN) and not menu.is_craftable(MASTER),
		"with NO station in range: craft-anywhere spin_cord is craftable, station-gated master_cordage is BLOCKED (no forge)",
		"craftable flags wrong with no station (spin=%s, master=%s)" % [str(menu.is_craftable(SPIN)), str(menu.is_craftable(MASTER))])

	# --- re-open WITH &"forge" in range: the station-gated recipe becomes craftable ---
	menu.open(sheet, inv, [&"forge"] as Array[StringName])
	ctx.check(menu.is_craftable(MASTER) and menu.is_craftable(SPIN),
		"with &\"forge\" in range: master_cordage is NOW craftable (station gate opens), spin_cord still craftable",
		"station-gated flag did not open with the forge tag in range (master=%s, spin=%s)" % [str(menu.is_craftable(MASTER)), str(menu.is_craftable(SPIN))])

	# --- craft spin_cord THROUGH the menu: consumes inputs, produces output, and REFRESHES the flag ---
	menu.select(SPIN)
	var crafted: bool = menu.craft_selected()
	ctx.check(crafted and inv.count_of(FIBER) == 2 and inv.count_of(CORD) == 1 and menu.selected_id() == SPIN,
		"craft_selected() crafts spin_cord through the menu: fiber 5 -> 2, cord 0 -> 1 (consumes + produces via Crafting)",
		"menu craft did not consume/produce (ok=%s, fiber=%d, cord=%d)" % [str(crafted), inv.count_of(FIBER), inv.count_of(CORD)])
	# fiber is now 2 (< the 3 spin needs, < the 5 master needs) -> both flags refreshed to BLOCKED post-craft.
	ctx.check(not menu.is_craftable(SPIN) and not menu.is_craftable(MASTER),
		"the menu REFRESHED after the craft: spin_cord + master_cordage now BLOCKED on the reduced fiber (2)",
		"menu did not refresh craftable flags after crafting (spin=%s, master=%s)" % [str(menu.is_craftable(SPIN)), str(menu.is_craftable(MASTER))])

	# --- station-gated craft THROUGH the menu: refuses without the tag, succeeds with it (fresh stock) ---
	var sheet2: CharacterSheet = CharacterSheet.new()
	sheet2.known_recipes.learn(MASTER)
	var inv2: Inventory = Inventory.new()
	inv2.add_item(FIBER, 5)
	menu.open(sheet2, inv2, [] as Array[StringName])       # no forge
	var blocked: bool = menu.craft(MASTER)                  # gate refuses -> nothing consumed
	ctx.check(not blocked and inv2.count_of(FIBER) == 5 and inv2.count_of(CORD) == 0,
		"menu.craft(master_cordage) REFUSES with no forge in range -- nothing consumed (fiber stays 5)",
		"station-gated craft ran through the menu without a station (ok=%s, fiber=%d, cord=%d)" % [str(blocked), inv2.count_of(FIBER), inv2.count_of(CORD)])
	menu.open(sheet2, inv2, [&"forge"] as Array[StringName])  # forge now in range
	var forged: bool = menu.craft(MASTER)
	ctx.check(forged and inv2.count_of(FIBER) == 0 and inv2.count_of(CORD) == 3,
		"menu.craft(master_cordage) SUCCEEDS with &\"forge\" in range: fiber 5 -> 0, cord 0 -> 3 through the menu",
		"station-gated craft failed through the menu in range (ok=%s, fiber=%d, cord=%d)" % [str(forged), inv2.count_of(FIBER), inv2.count_of(CORD)])

	# --- close() drops the open flag ---
	menu.close()
	ctx.check(not menu.is_open,
		"close() marks the menu not open",
		"close() did not clear is_open")

	holder.queue_free()
	await ctx.tree.physics_frame


## INTERACTION SEAM: a real Player next to a real forge Station -- 'f' (the test-callable player.interact() path)
## raises the open REQUEST carrying the in-range tags (station priority, prompt "Craft"); a SECOND player on a
## bush with NO station in reach still HARVESTS on 'f' (activate falls through to try_interact).
func _interaction_seam(ctx: TestContext) -> void:
	var holder: Node2D = Node2D.new()
	ctx.tree.root.add_child(holder)

	# Player standing beside a forge (30 px < Station.DEFAULT_REACH 80 px).
	var p_station: Player = _spawn_player(holder, HOME)
	var forge: Station = STATION_SCENE.instantiate() as Station
	forge.station_tag = &"forge"
	holder.add_child(forge)
	forge.global_position = HOME + Vector2(30.0, 0.0)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame

	ctx.check(p_station.interaction_prompt() == "Craft",
		"a player beside a Station reads the \"Craft\" prompt (station priority over harvest)",
		"station prompt wrong (\"" + p_station.interaction_prompt() + "\")")

	p_station.interact()  # the action-button path -> activate() -> station priority -> open request
	ctx.check(p_station._interaction.craft_open_pending(),
		"'f' beside a Station raises the craft-open REQUEST (station takes 'f' priority)",
		"'f' beside a station did not raise the open request")
	var tags: Array[StringName] = p_station._interaction.consume_craft_open()
	ctx.check(tags.has(&"forge") and tags.size() == 1 and not p_station._interaction.craft_open_pending(),
		"the open request carries the in-range station tags ([&\"forge\"]) and consuming it clears the flag (got " + str(tags) + ")",
		"open-request tags wrong (tags=%s, still_pending=%s)" % [str(tags), str(p_station._interaction.craft_open_pending())])

	# --- existing harvest 'f' still works: a player on a bush FAR from the forge harvests on interact() ---
	var STICK: ItemData = load("res://data/stick.tres")
	var FIBER: ItemData = load("res://data/fiber.tres")
	var p_bush: Player = _spawn_player(holder, HOME + Vector2(60000.0, 0.0))  # far from the forge (no station near)
	var bush: Bush = BUSH_SCENE.instantiate() as Bush
	holder.add_child(bush)
	bush.global_position = p_bush.global_position + Vector2(15.0, 0.0)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	ctx.check(p_bush.interaction_prompt() == "Harvest",
		"a player on a bush with NO station in reach still reads \"Harvest\" (no false station prompt)",
		"harvest prompt wrong with no station (\"" + p_bush.interaction_prompt() + "\")")
	var want_stick: int = bush.yield_count_a
	var want_fiber: int = bush.yield_count_b
	p_bush.interact()  # activate() finds no station -> falls through to try_interact() -> harvest
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	ctx.check(not is_instance_valid(bush) and _count_of(p_bush, STICK) == want_stick and _count_of(p_bush, FIBER) == want_fiber,
		"existing harvest 'f' STILL WORKS through activate(): bush freed + " + str(want_stick) + " Stick/" + str(want_fiber) + " Fiber collected (no station -> harvest)",
		"harvest broke after the station routing (bush_valid=%s, stick=%d, fiber=%d)" % [str(is_instance_valid(bush)), _count_of(p_bush, STICK), _count_of(p_bush, FIBER)])

	holder.queue_free()
	await ctx.tree.physics_frame


## INTEGRATION: the shipped streaming_world.tscn hosts + binds the HUD, which hosts the CraftMenu. Learn a couple
## recipes on the player's sheet, stock fiber, place a forge beside the player, then 'f' -> the HUD poll OPENS the
## menu with the live sheet/inventory + routed tags; a second 'f' toggles it closed. Mirrors test_hud's isolation.
func _integration(ctx: TestContext) -> void:
	var sw_scene: PackedScene = load("res://world/streaming_world.tscn")
	ctx.check(sw_scene != null,
		"streaming_world.tscn loads (hosts the HUD + CraftMenu)",
		"streaming_world.tscn failed to load")
	if sw_scene == null:
		return
	var sw: Node2D = sw_scene.instantiate()
	ctx.tree.root.add_child(sw)
	var player: Player = sw.get_node("Player") as Player
	var hud: Hud = sw.get_node("HUD") as Hud
	player.pickup_radius = 0.0  # no magnet interference
	await ctx.settle_idle()
	await ctx.settle_idle()

	# Move to a remote spot, learn the recipes, stock fiber, and drop a forge right beside the player.
	var spot: Vector2 = Vector2(8000.0, 8000.0)
	player.global_position = spot
	player.character().known_recipes.learn(SPIN)
	player.character().known_recipes.learn(MASTER)
	var FIBER: ItemData = load("res://data/fiber.tres")
	player.inventory.add_item(FIBER, 5)
	var forge: Station = STATION_SCENE.instantiate() as Station
	forge.station_tag = &"forge"
	sw.add_child(forge)
	forge.global_position = spot + Vector2(20.0, 0.0)
	await ctx.tree.physics_frame
	await ctx.settle_idle()

	# 'f' beside the forge -> the interaction raises the request -> the HUD's per-frame poll OPENS the menu.
	player.interact()
	await ctx.settle_idle()
	await ctx.settle_idle()
	var cm: CraftMenu = hud.craft_menu()
	var ids: Array[StringName] = cm.listed_ids()
	ctx.check(cm.is_open and ids.has(SPIN) and ids.has(MASTER),
		"'f' beside a Station OPENED the hosted craft menu through the HUD, listing the learned recipes (got " + str(ids) + ")",
		"the HUD did not open the craft menu on 'f' near a station (open=%s, ids=%s)" % [str(cm.is_open), str(ids)])
	ctx.check(cm.is_craftable(MASTER) and cm.is_craftable(SPIN),
		"the opened menu got the routed &\"forge\" tag: master_cordage + spin_cord both craftable from the player's live inventory",
		"routed tags/inventory wrong in the opened menu (master=%s, spin=%s)" % [str(cm.is_craftable(MASTER)), str(cm.is_craftable(SPIN))])

	# A second 'f' beside the station TOGGLES the menu closed (still operable, minimal).
	player.interact()
	await ctx.settle_idle()
	await ctx.settle_idle()
	ctx.check(not cm.is_open,
		"a second 'f' beside the Station TOGGLES the craft menu closed",
		"second 'f' did not close the craft menu (open=%s)" % [str(cm.is_open)])

	sw.queue_free()
	await ctx.settle_idle()


## Instantiate a real Player at `at` under the holder so its _physics_process (and the interaction scan) runs.
func _spawn_player(holder: Node2D, at: Vector2) -> Player:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	holder.add_child(player)
	player.global_position = at
	return player


## Total count of `item` across every inventory slot (proves a harvest yield actually landed).
func _count_of(player: Player, item: ItemData) -> int:
	var total: int = 0
	for i in range(player.inventory.slots.size()):
		if player.inventory.item_at(i) == item:
			total += player.inventory.count_at(i)
	return total

# Verified against: Godot 4.7.1 (2026-07-19)
