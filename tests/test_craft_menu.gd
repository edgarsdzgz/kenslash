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

## FLAGSHIP recipe (the triple-gated iron sword) + its inputs/output, exercised THROUGH the real menu UI.
const FORGE: StringName = &"forge_iron_sword"  # iron_ore x3 + stick x1 -> iron_sword, gated by heavy_hitter + level 3 + &"forge"
const HEAVY: StringName = &"heavy_hitter"      # the recipe's prereq talent (cost 2)
const IRON_ORE: ItemData = preload("res://data/iron_ore.tres")
const IRON_SWORD: ToolData = preload("res://data/iron_sword.tres")
const STICK_ITEM: ItemData = preload("res://data/stick.tres")

## Remote region clear of test_station (-90000, 90000), forage (-30000), etc. -- so no stray station/bush from
## another module wanders into these radius scans, and this module's forge never reaches its own bush player.
const HOME: Vector2 = Vector2(120000.0, -120000.0)
## Distinct remote region for the flagship-forge leg (clear of HOME + every other module) so its own forge
## Station never wanders into another leg's tag scan and vice-versa.
const FLAGSHIP: Vector2 = Vector2(200000.0, -200000.0)


func run(ctx: TestContext) -> void:
	print("[craft_menu] --- Part 4.2 minimal craft menu + 'f'-near-a-station open, end to end ---")
	await _menu_api(ctx)
	await _flagship_forge(ctx)
	await _interaction_seam(ctx)
	await _integration(ctx)
	await _regressions_pure(ctx)
	await _regressions_hud(ctx)


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


## FLAGSHIP through the REAL menu UI: the triple-gated iron sword is only ever crafted via Crafting.craft directly
## (test_gated_weapon / the capstone) -- never through the CraftMenu the player actually operates. This leg closes
## that: a sheet that LEARNED forge_iron_sword through its real gates (unlock heavy_hitter, reach level 3, spend the
## blueprint point) + an inventory holding iron_ore x3 + stick x1, opened on the real menu near a real forge Station.
## Asserts is_craftable(forge) is FALSE with no forge and TRUE with the forge (real Station.tags_in_range scan), then
## that craft_selected() THROUGH THE MENU consumes the inputs + produces the iron_sword. Pure menu API off
## ui/craft_menu.tscn (no HUD needed), mirroring _menu_api's structural style.
func _flagship_forge(ctx: TestContext) -> void:
	var holder: Node2D = Node2D.new()
	ctx.tree.root.add_child(holder)
	var menu: CraftMenu = CRAFT_MENU_SCENE.instantiate() as CraftMenu
	holder.add_child(menu)
	await ctx.tree.physics_frame  # let _ready resolve the row container

	# A sheet that LEARNED forge_iron_sword through the REAL triple gate (mirrors test_gated_weapon's learn leg):
	# blueprint points + level 3 + the heavy_hitter talent unlocked, then learn_recipe spends the blueprint point.
	var sheet: CharacterSheet = CharacterSheet.new()
	sheet.progression.blueprint_points = 5
	sheet.progression.talent_points = 5
	sheet.progression.level = 3
	var ok_talent: bool = sheet.unlock_talent(HEAVY)
	var ok_learn: bool = sheet.learn_recipe(FORGE)
	ctx.check(ok_talent and ok_learn and sheet.known_recipes.is_known(FORGE),
		"flagship setup: forge_iron_sword LEARNED through its real gates (heavy_hitter unlocked + level 3 + blueprint point spent)",
		"flagship setup failed to learn forge_iron_sword (talent=%s, learn=%s, known=%s)" % [str(ok_talent), str(ok_learn), str(sheet.known_recipes.is_known(FORGE))])

	var inv: Inventory = Inventory.new()
	inv.add_item(IRON_ORE, 3)
	inv.add_item(STICK_ITEM, 1)

	# A REAL forge Station at the flagship coords; its tags are collected by the same Station.tags_in_range scan
	# the game uses -- so the menu is judged against a genuine world station, not a hand-passed tag literal.
	var forge: Station = STATION_SCENE.instantiate() as Station
	forge.station_tag = &"forge"
	holder.add_child(forge)
	forge.global_position = FLAGSHIP
	await ctx.tree.physics_frame

	# --- open with NO forge in range: the learned recipe is LISTED but NOT craftable (station gate blocks it) ---
	menu.open(sheet, inv, [] as Array[StringName])
	ctx.check(menu.listed_ids().has(FORGE) and not menu.is_craftable(FORGE),
		"the learned forge_iron_sword is LISTED but NOT craftable through the menu with no forge in range (station gate)",
		"flagship craftable flag wrong with no forge (listed=%s, craftable=%s)" % [str(menu.listed_ids().has(FORGE)), str(menu.is_craftable(FORGE))])

	# --- re-open WITH the real forge Station in range (scan [forge]): NOW craftable through the menu ---
	var forge_tags: Array[StringName] = Station.tags_in_range(FLAGSHIP, Station.DEFAULT_REACH)
	menu.open(sheet, inv, forge_tags)
	ctx.check(forge_tags == [&"forge"] and menu.is_craftable(FORGE),
		"with a REAL forge Station in range (scan [forge]) the flagship forge_iron_sword is NOW craftable through the menu",
		"flagship not craftable with the forge in range (tags=%s, craftable=%s)" % [str(forge_tags), str(menu.is_craftable(FORGE))])

	# --- craft the flagship THROUGH the menu (select + craft_selected): ore x3 + stick x1 -> iron_sword ---
	menu.select(FORGE)
	var forged: bool = menu.craft_selected()
	ctx.check(forged and menu.selected_id() == FORGE and inv.count_of(IRON_ORE) == 0
			and inv.count_of(STICK_ITEM) == 0 and inv.count_of(IRON_SWORD) == 1,
		"craft_selected() forges the iron sword THROUGH THE MENU the player operates: ore 3 -> 0, stick 1 -> 0, iron_sword 0 -> 1",
		"flagship craft through the menu wrong (ok=%s, ore=%d, stick=%d, sword=%d)" % [str(forged), inv.count_of(IRON_ORE), inv.count_of(STICK_ITEM), inv.count_of(IRON_SWORD)])

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


## REGRESSIONS (pure menu API): the honesty + edge-case gaps the PHASE 4 review batch closed. is_craftable now
## delegates to Crafting.would_craft (known + materials + station + the output FITS), so the flag can no longer lie
## about an UNLEARNED catalog id or a full inventory the output cannot fit; the empty-selection + unknown-id craft
## paths refuse cleanly; and an unaffordable flag flips to craftable once materials arrive. All off the raw menu.
func _regressions_pure(ctx: TestContext) -> void:
	var holder: Node2D = Node2D.new()
	ctx.tree.root.add_child(holder)
	var menu: CraftMenu = CRAFT_MENU_SCENE.instantiate() as CraftMenu
	holder.add_child(menu)
	await ctx.tree.physics_frame

	var FIBER: ItemData = load("res://data/fiber.tres")
	var CORD: ItemData = load("res://data/cord.tres")
	var STICK: ItemData = load("res://data/stick.tres")

	# --- would_craft HONESTY 1: an UNLEARNED catalog id is NOT craftable even with its materials + a forge in
	# range. master_cordage is a real CATALOG recipe but this sheet only LEARNED spin_cord; the old is_craftable
	# resolved ids from the full catalog and ignored the learn set, so it would have shown master_cordage craftable.
	var sheet: CharacterSheet = CharacterSheet.new()
	sheet.known_recipes.learn(SPIN)                          # SPIN learned; MASTER a real catalog id but UNLEARNED
	var inv: Inventory = Inventory.new()
	inv.add_item(FIBER, 5)                                   # enough for MASTER's 5 fiber, were it known
	menu.open(sheet, inv, [&"forge"] as Array[StringName])  # forge in range -> only the LEARN gate can block MASTER
	ctx.check(not menu.is_craftable(MASTER) and menu.is_craftable(SPIN),
		"is_craftable is HONEST about the learn set: an UNLEARNED catalog id (master_cordage) is NOT craftable even with materials + forge in range; the learned spin_cord IS",
		"is_craftable lied about an unlearned catalog id (master=%s, spin=%s)" % [str(menu.is_craftable(MASTER)), str(menu.is_craftable(SPIN))])

	# --- would_craft HONESTY 2: a FULL inventory where the output cannot fit -> is_craftable false AND craft()
	# refuses (they AGREE). fiber(5) in slot 0 (consuming 3 leaves 2, so that slot stays occupied), the other 14
	# slots packed with sticks -> no room for the cord output -> overflow -> craft() rolls back, would_craft false.
	var full_sheet: CharacterSheet = CharacterSheet.new()
	full_sheet.known_recipes.learn(SPIN)
	var full_inv: Inventory = Inventory.new()
	full_inv.add_item(FIBER, 5)                              # slot 0
	full_inv.add_item(STICK, 255 * 14)                      # slots 1..14 -> every slot now occupied
	menu.open(full_sheet, full_inv, [] as Array[StringName])
	var full_flag: bool = menu.is_craftable(SPIN)
	var full_craft: bool = menu.craft(SPIN)
	ctx.check(not full_flag and not full_craft and full_inv.count_of(FIBER) == 5 and full_inv.count_of(CORD) == 0,
		"is_craftable + craft() AGREE on a full inventory: the output cannot fit -> not craftable AND craft() refuses (fiber stays 5, no cord, nothing lost)",
		"full-inventory honesty broke (flag=%s, craft=%s, fiber=%d, cord=%d)" % [str(full_flag), str(full_craft), full_inv.count_of(FIBER), full_inv.count_of(CORD)])

	# --- craft_selected() with NOTHING selected (EMPTY known set) -> refuses (reaches the empty-selection branch) ---
	var empty_sheet: CharacterSheet = CharacterSheet.new()   # knows nothing
	var empty_inv: Inventory = Inventory.new()
	menu.open(empty_sheet, empty_inv, [] as Array[StringName])
	ctx.check(menu.row_count() == 0 and menu.selected_id() == &"" and not menu.craft_selected(),
		"craft_selected() with an EMPTY known set refuses (no rows, no selection) -- reaches the empty-selection branch",
		"craft_selected did not refuse on an empty known set (rows=%d, sel=%s, ok=%s)" % [menu.row_count(), str(menu.selected_id()), str(menu.craft_selected())])

	# --- craft() an UNKNOWN / non-listed id THROUGH the menu -> refuses, consumes NOTHING ---
	var known_sheet: CharacterSheet = CharacterSheet.new()
	known_sheet.known_recipes.learn(SPIN)
	var known_inv: Inventory = Inventory.new()
	known_inv.add_item(FIBER, 5)
	menu.open(known_sheet, known_inv, [] as Array[StringName])
	var bogus: bool = menu.craft(&"not_a_real_recipe")
	ctx.check(not bogus and known_inv.count_of(FIBER) == 5 and known_inv.count_of(CORD) == 0,
		"menu.craft(unknown id) refuses through the menu -- nothing consumed (fiber stays 5, no cord)",
		"menu crafted an unknown id (ok=%s, fiber=%d, cord=%d)" % [str(bogus), known_inv.count_of(FIBER), known_inv.count_of(CORD)])

	# --- unaffordable -> affordable FLAG FLIP: not craftable on 2 fiber, craftable once a 3rd arrives (is_craftable
	# recomputes live off the inventory, so no re-open is needed) ---
	var flip_sheet: CharacterSheet = CharacterSheet.new()
	flip_sheet.known_recipes.learn(SPIN)                     # spin needs fiber x3
	var flip_inv: Inventory = Inventory.new()
	flip_inv.add_item(FIBER, 2)                              # one short
	menu.open(flip_sheet, flip_inv, [] as Array[StringName])
	var before_flip: bool = menu.is_craftable(SPIN)
	flip_inv.add_item(FIBER, 1)                              # now 3 -- affordable
	var after_flip: bool = menu.is_craftable(SPIN)
	ctx.check(not before_flip and after_flip,
		"craftable FLAG FLIPS with materials: spin_cord not craftable on 2 fiber, craftable once a 3rd is gained",
		"craftable flag did not flip on gaining materials (before=%s, after=%s)" % [str(before_flip), str(after_flip)])

	holder.queue_free()
	await ctx.tree.physics_frame


## REGRESSIONS (HUD-managed open menu): the HUD now MANAGES the open menu each frame, so it can never get STUCK and
## its station gate is re-judged against LIVE station presence. Prove (a) walking the forge out of range AUTO-
## CLOSES the menu and the forge recipe is no longer craftable against the now-empty live tags (the stale-snapshot
## bypass is gone), and (b) 'f' TOGGLES open -> close -> OPEN across three presses. On the shipped streaming_world.
func _regressions_hud(ctx: TestContext) -> void:
	var sw_scene: PackedScene = load("res://world/streaming_world.tscn")
	if sw_scene == null:
		ctx.check(false, "", "streaming_world.tscn failed to load (hud regressions)")
		return
	var sw: Node2D = sw_scene.instantiate()
	ctx.tree.root.add_child(sw)
	var player: Player = sw.get_node("Player") as Player
	var hud: Hud = sw.get_node("HUD") as Hud
	player.pickup_radius = 0.0  # no magnet interference
	await ctx.settle_idle()
	await ctx.settle_idle()

	# Remote spot, clear of _integration's (8000, 8000) and every other module's region.
	var spot: Vector2 = Vector2(-8000.0, -8000.0)
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

	# 'f' opens the menu beside the forge -- master_cordage craftable (forge in range).
	player.interact()
	await ctx.settle_idle()
	await ctx.settle_idle()
	var cm: CraftMenu = hud.craft_menu()
	ctx.check(cm.is_open and cm.is_craftable(MASTER),
		"[station-leaves] menu OPEN beside the forge with master_cordage craftable (forge in range)",
		"[station-leaves] menu did not open craftable beside the forge (open=%s, master=%s)" % [str(cm.is_open), str(cm.is_craftable(MASTER))])

	# WALK the forge out of Station.DEFAULT_REACH, then let the HUD run a frame: the menu AUTO-CLOSES (never stuck).
	player.global_position = spot + Vector2(100000.0, 0.0)
	await ctx.settle_idle()
	await ctx.settle_idle()
	ctx.check(not cm.is_open,
		"[station-leaves] walking the forge out of range AUTO-CLOSES the menu (HUD re-scans live tags -> empty -> close; never stuck)",
		"[station-leaves] menu stayed open after walking away (open=%s)" % [str(cm.is_open)])

	# GATE NOT BYPASSABLE: with the live tags now EMPTY, master_cordage is not craftable and a craft refuses -- the
	# gate reads current station presence, never the stale [&"forge"] snapshot open() captured.
	cm.set_tags(Station.tags_in_range(player.global_position, Station.DEFAULT_REACH))
	var stale_craft: bool = cm.craft(MASTER)
	ctx.check(not cm.is_craftable(MASTER) and not stale_craft and player.inventory.count_of(FIBER) == 5,
		"[station-leaves] with live tags EMPTY the forge recipe is NOT craftable and craft() refuses -- the stale-snapshot bypass is gone (fiber stays 5)",
		"[station-leaves] stale forge gate was bypassable (craftable=%s, crafted=%s, fiber=%d)" % [str(cm.is_craftable(MASTER)), str(stale_craft), player.inventory.count_of(FIBER)])

	# --- 'f' TOGGLE open -> close -> OPEN: bring the player back beside the forge and press three times. ---
	player.global_position = spot
	await ctx.tree.physics_frame
	await ctx.settle_idle()
	player.interact()   # 1st press -> open
	await ctx.settle_idle()
	await ctx.settle_idle()
	var open1: bool = cm.is_open
	player.interact()   # 2nd press -> close
	await ctx.settle_idle()
	await ctx.settle_idle()
	var closed2: bool = cm.is_open
	player.interact()   # 3rd press -> reopen
	await ctx.settle_idle()
	await ctx.settle_idle()
	var open3: bool = cm.is_open
	ctx.check(open1 and not closed2 and open3,
		"'f' TOGGLES the menu open -> close -> OPEN across three presses (the third press reopens)",
		"'f' toggle open/close/open failed (open1=%s, closed2=%s, open3=%s)" % [str(open1), str(closed2), str(open3)])

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
