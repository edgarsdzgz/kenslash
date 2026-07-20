class_name TestContainerPanel extends RefCounted
## EPIC 2 Phase 2 Part 2.3 -- the container 'f'-open TRANSFER UI (plan-epic2-parts.md Phase 2; design-crafting.md
## "Track B -- Building"). Where test_container proves the container ENTITY + its atomic deposit/withdraw + contents
## persistence, this leg proves the OPERABLE UI slice: a player stands beside a placed StorageContainer, presses
## 'f', sees the container's contents alongside their own inventory, and moves items either way THROUGH the panel.
## UI-style STRUCTURAL assertions (state + structure, never pixels), mirroring tests/test_craft_menu.gd. Four legs:
##   * PANEL API (pure, off ui/container_panel.tscn): open() lists the container's stored contents AND the player
##     inventory; deposit/withdraw THROUGH the panel move EXACT items both ways and REFRESH the listing; an
##     over-count withdraw refuses; close() drops the open flag.
##   * INTERACTION PRIORITY (real Player + Station + Container nodes): 'f' beside a container raises the container-
##     open request (prompt "Open"); 'f' beside BOTH a station and a container raises the CRAFT request instead
##     (fixed priority station-craft > container-transfer, only ONE opens); 'f' with nothing but a bush near still
##     HARVESTS (the harvest fallthrough is intact).
##   * INTEGRATION (shipped streaming_world.tscn): the HUD polls the request and OPENS the hosted ContainerPanel
##     with the player's live inventory, listing both stores; walking the container out of reach AUTO-CLOSES it.
##   * MUTUAL EXCLUSION (streaming_world.tscn): with the container panel open, an 'f' beside a station opens the
##     craft menu and CLOSES the container panel -- only ONE of the two is ever open at once.
## Self-contained: builds its own panel/players/containers/stations/bush under private holders at REMOTE coords
## (clear of every other module's region) + its own streaming_world instance, freeing them at the end. Registered
## in tests/smoke_slash.gd after TestContainer.

const CONTAINER_PANEL_SCENE: PackedScene = preload("res://ui/container_panel.tscn")
const CONTAINER_SCENE: PackedScene = preload("res://world/container.tscn")
const STATION_SCENE: PackedScene = preload("res://world/station.tscn")
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const BUSH_SCENE: PackedScene = preload("res://world/bush.tscn")

## Remote region clear of test_container (140000,140000), test_craft_menu (120000,-120000 / 200000,-200000),
## station (-90000), builder (120000), etc. -- so no placeable wanders into these radius scans and vice-versa.
const SEAM: Vector2 = Vector2(-140000.0, 140000.0)
## Distinct integration streaming spots, clear of test_craft_menu's (8000,8000)/(-8000,-8000) and each other.
const INT_SPOT: Vector2 = Vector2(12000.0, -12000.0)
const EXCL_SPOT: Vector2 = Vector2(16000.0, -16000.0)


func run(ctx: TestContext) -> void:
	print("[container_panel] --- Part 2.3 container 'f'-open transfer UI: open, deposit/withdraw, priority, auto-close, mutual exclusion ---")
	await _panel_api(ctx)
	await _interaction_priority(ctx)
	await _integration(ctx)


## PANEL API (pure): drive ui/container_panel.tscn directly against a real StorageContainer's store + a hand-built
## player inventory. open() lists both stores; deposit/withdraw THROUGH the panel move exact items and refresh; an
## over-count withdraw refuses; close() clears the flag.
func _panel_api(ctx: TestContext) -> void:
	var holder: Node2D = Node2D.new()
	ctx.tree.root.add_child(holder)
	var panel: ContainerPanel = CONTAINER_PANEL_SCENE.instantiate() as ContainerPanel
	holder.add_child(panel)
	var box: StorageContainer = CONTAINER_SCENE.instantiate() as StorageContainer
	holder.add_child(box)
	box.global_position = SEAM
	await ctx.tree.physics_frame  # let both _ready passes resolve (@onready rows + the container group join)

	var WOOD: ItemData = load("res://data/wood.tres")
	var STONE: ItemData = load("res://data/stone.tres")
	# Seed the container with STONE and the player inventory with WOOD + STONE, so both sides list distinct items.
	box.store.add_item(STONE, 3)
	var player_inv: Inventory = Inventory.new()
	player_inv.add_item(WOOD, 10)
	player_inv.add_item(STONE, 5)

	# --- open(): the panel lists the container's contents AND the player inventory, and marks open ---
	panel.open(box, player_inv)
	var c_ids: Array[ItemData] = panel.container_ids()
	var i_ids: Array[ItemData] = panel.inventory_ids()
	ctx.check(panel.is_open and c_ids.has(STONE) and c_ids.size() == 1
			and i_ids.has(WOOD) and i_ids.has(STONE) and i_ids.size() == 2
			and panel.bound_container() == box,
		"open() lists the container's contents (STONE) AND the player inventory (WOOD + STONE), binds the container, and marks the panel open",
		"open() listing wrong (open=%s, container=%s, inventory=%s, bound=%s)" % [str(panel.is_open), str(c_ids), str(i_ids), str(panel.bound_container() == box)])

	# --- deposit 4 WOOD player->container THROUGH the panel: exact both sides, and the listing REFRESHES ---
	var dep: int = panel.deposit(WOOD, 4)
	ctx.check(dep == 4 and player_inv.count_of(WOOD) == 6 and box.store.count_of(WOOD) == 4
			and panel.container_ids().has(WOOD),
		"deposit() THROUGH the panel moves EXACTLY 4 WOOD player->container (player 10->6, container 0->4) and REFRESHES the container listing (WOOD now shown)",
		"panel deposit did not move/refresh (moved=%d, player=%d, box=%d, listed=%s)" % [dep, player_inv.count_of(WOOD), box.store.count_of(WOOD), str(panel.container_ids().has(WOOD))])

	# --- withdraw 2 STONE container->player THROUGH the panel: the mirror direction, exact + refreshed ---
	var wd: int = panel.withdraw(STONE, 2)
	ctx.check(wd == 2 and box.store.count_of(STONE) == 1 and player_inv.count_of(STONE) == 7,
		"withdraw() THROUGH the panel moves EXACTLY 2 STONE container->player (container 3->1, player 5->7) -- the mirror direction, exact",
		"panel withdraw did not move (moved=%d, box=%d, player=%d)" % [wd, box.store.count_of(STONE), player_inv.count_of(STONE)])

	# --- over-count withdraw THROUGH the panel: refuses, moves NOTHING (atomic no-dupe/no-loss surfaces) ---
	var box_s: int = box.store.count_of(STONE)
	var pl_s: int = player_inv.count_of(STONE)
	var over: int = panel.withdraw(STONE, 5)
	ctx.check(over == 0 and box.store.count_of(STONE) == box_s and player_inv.count_of(STONE) == pl_s,
		"over-count withdraw THROUGH the panel REFUSES (withdraw 5 of 1): returns 0 and moves NOTHING -- the container's atomic guarantee surfaces unchanged",
		"panel over-count withdraw was not atomic (ret=%d, box=%d, player=%d)" % [over, box.store.count_of(STONE), player_inv.count_of(STONE)])

	# --- close() drops the open flag ---
	panel.close()
	ctx.check(not panel.is_open,
		"close() marks the container panel not open",
		"close() did not clear is_open")

	holder.queue_free()
	await ctx.tree.physics_frame


## INTERACTION PRIORITY: a real Player next to real placeables -- 'f' beside a container raises the container-open
## request (prompt "Open"); 'f' beside BOTH a station and a container raises the CRAFT request (station priority,
## only one opens); 'f' with only a bush near still HARVESTS. Drives player.interact() (the action-button path).
func _interaction_priority(ctx: TestContext) -> void:
	var holder: Node2D = Node2D.new()
	ctx.tree.root.add_child(holder)

	# (a) Player beside a container ONLY (no station): prompt "Open", 'f' raises the container-open request.
	var p_box: Player = _spawn_player(holder, SEAM)
	var box: StorageContainer = CONTAINER_SCENE.instantiate() as StorageContainer
	holder.add_child(box)
	box.global_position = SEAM + Vector2(30.0, 0.0)  # 30 px < CONTAINER_REACH 80 px
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame

	ctx.check(p_box.interaction_prompt() == "Open",
		"a player beside a Container reads the \"Open\" prompt (container context, no station)",
		"container prompt wrong (\"" + p_box.interaction_prompt() + "\")")
	p_box.interact()  # activate() -> no station -> container -> container-open request
	ctx.check(p_box._interaction.container_open_pending() and not p_box._interaction.craft_open_pending(),
		"'f' beside a Container raises the CONTAINER-open request (and NOT the craft request)",
		"'f' beside a container did not raise only the container request (container=%s, craft=%s)" % [str(p_box._interaction.container_open_pending()), str(p_box._interaction.craft_open_pending())])
	var bound: StorageContainer = p_box._interaction.consume_container_open()
	ctx.check(bound == box and not p_box._interaction.container_open_pending(),
		"the container-open request carries the in-range container and consuming it clears the flag",
		"container open-request wrong (bound=%s, still_pending=%s)" % [str(bound == box), str(p_box._interaction.container_open_pending())])

	# (b) Player beside BOTH a station AND a container: 'f' raises the CRAFT request (fixed priority station>container).
	var p_both: Player = _spawn_player(holder, SEAM + Vector2(40000.0, 0.0))
	var forge: Station = STATION_SCENE.instantiate() as Station
	forge.station_tag = &"forge"
	holder.add_child(forge)
	forge.global_position = p_both.global_position + Vector2(25.0, 0.0)
	var box2: StorageContainer = CONTAINER_SCENE.instantiate() as StorageContainer
	holder.add_child(box2)
	box2.global_position = p_both.global_position + Vector2(-25.0, 0.0)  # both within reach
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame

	ctx.check(p_both.interaction_prompt() == "Craft",
		"beside BOTH a Station and a Container the prompt is \"Craft\" (station-craft takes 'f' priority over container-transfer)",
		"priority prompt wrong beside station+container (\"" + p_both.interaction_prompt() + "\")")
	p_both.interact()  # station priority -> CRAFT request, container request NOT raised
	ctx.check(p_both._interaction.craft_open_pending() and not p_both._interaction.container_open_pending(),
		"'f' beside BOTH raises ONLY the CRAFT request (station priority) -- exactly one context opens, never both",
		"priority routing wrong (craft=%s, container=%s)" % [str(p_both._interaction.craft_open_pending()), str(p_both._interaction.container_open_pending())])

	# (c) Harvest still works: a player with only a bush near (no station, no container) HARVESTS on 'f'.
	var STICK: ItemData = load("res://data/stick.tres")
	var p_bush: Player = _spawn_player(holder, SEAM + Vector2(80000.0, 0.0))
	var bush: Bush = BUSH_SCENE.instantiate() as Bush
	holder.add_child(bush)
	bush.global_position = p_bush.global_position + Vector2(15.0, 0.0)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	ctx.check(p_bush.interaction_prompt() == "Harvest",
		"a player with only a bush near (no station, no container) still reads \"Harvest\" (the harvest fallthrough is intact)",
		"harvest prompt wrong with nothing else near (\"" + p_bush.interaction_prompt() + "\")")
	var want_stick: int = bush.yield_count_a
	p_bush.interact()  # no station, no container -> falls through to harvest
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	ctx.check(not is_instance_valid(bush) and _count_of(p_bush, STICK) == want_stick,
		"harvest 'f' STILL WORKS with nothing else near: the bush freed + " + str(want_stick) + " Stick collected (container routing did not steal the harvest)",
		"harvest broke with a container in the codebase (bush_valid=%s, stick=%d)" % [str(is_instance_valid(bush)), _count_of(p_bush, STICK)])

	holder.queue_free()
	await ctx.tree.physics_frame


## INTEGRATION + MUTUAL EXCLUSION on the shipped streaming_world.tscn (hosts + binds the HUD, which hosts the
## ContainerPanel). Two remote spots on ONE instance: at INT_SPOT 'f' opens the hosted panel (listing both stores)
## and walking the container away AUTO-CLOSES it; at EXCL_SPOT an 'f' beside a station closes an open container
## panel (only one of the two panels open at once).
func _integration(ctx: TestContext) -> void:
	var sw_scene: PackedScene = load("res://world/streaming_world.tscn")
	ctx.check(sw_scene != null,
		"streaming_world.tscn loads (hosts the HUD + ContainerPanel)",
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

	var WOOD: ItemData = load("res://data/wood.tres")
	var STONE: ItemData = load("res://data/stone.tres")

	# --- INT_SPOT: place a container beside the player, stock its store + the player, then 'f' opens the panel ---
	player.global_position = INT_SPOT
	player.inventory.add_item(WOOD, 6)
	var box: StorageContainer = CONTAINER_SCENE.instantiate() as StorageContainer
	sw.add_child(box)
	box.global_position = INT_SPOT + Vector2(20.0, 0.0)
	box.store.add_item(STONE, 4)
	await ctx.tree.physics_frame
	await ctx.settle_idle()

	player.interact()  # 'f' beside the container -> the HUD's per-frame poll OPENS the panel
	await ctx.settle_idle()
	await ctx.settle_idle()
	var cp: ContainerPanel = hud.container_panel()
	ctx.check(cp.is_open and cp.bound_container() == box
			and cp.container_ids().has(STONE) and cp.inventory_ids().has(WOOD),
		"'f' beside a Container OPENED the hosted panel through the HUD, bound to that container, listing its STONE + the player's WOOD (got container=%s inventory=%s)" % [str(cp.container_ids()), str(cp.inventory_ids())],
		"the HUD did not open the container panel on 'f' (open=%s, bound=%s, container=%s, inventory=%s)" % [str(cp.is_open), str(cp.bound_container() == box), str(cp.container_ids()), str(cp.inventory_ids())])

	# --- WALK the container out of CONTAINER_REACH: the HUD re-scans the bound container's proximity -> AUTO-CLOSE ---
	player.global_position = INT_SPOT + Vector2(100000.0, 0.0)
	await ctx.settle_idle()
	await ctx.settle_idle()
	ctx.check(not cp.is_open,
		"walking the Container out of reach AUTO-CLOSES the panel (HUD re-scans the bound container's live proximity; never stuck, never transfers against a container you left)",
		"container panel stayed open after walking away (open=%s)" % [str(cp.is_open)])

	# --- EXCL_SPOT: open the container panel, then 'f' beside a station opens the craft menu + CLOSES the panel ---
	player.global_position = EXCL_SPOT
	player.character().known_recipes.learn(&"spin_cord")  # a craft-anywhere recipe so the craft menu has a row
	var box2: StorageContainer = CONTAINER_SCENE.instantiate() as StorageContainer
	sw.add_child(box2)
	box2.global_position = EXCL_SPOT + Vector2(20.0, 0.0)
	await ctx.tree.physics_frame
	await ctx.settle_idle()

	player.interact()  # container in range, no station -> container panel opens
	await ctx.settle_idle()
	await ctx.settle_idle()
	var excl_open: bool = cp.is_open and cp.bound_container() == box2
	ctx.check(excl_open,
		"[exclusion] the container panel is OPEN beside the second container (setup for the mutual-exclusion check)",
		"[exclusion] the container panel did not open beside the second container (open=%s, bound=%s)" % [str(cp.is_open), str(cp.bound_container() == box2)])

	# Bring a forge into range (the container is STILL in reach, so the panel would NOT auto-close on its own).
	# 'f' now takes station priority -> the craft menu opens AND the container panel is closed by the exclusion rule.
	var forge: Station = STATION_SCENE.instantiate() as Station
	forge.station_tag = &"forge"
	sw.add_child(forge)
	forge.global_position = EXCL_SPOT + Vector2(-20.0, 0.0)
	await ctx.tree.physics_frame
	await ctx.settle_idle()
	player.interact()  # station priority -> craft request -> craft opens, container panel closes
	await ctx.settle_idle()
	await ctx.settle_idle()
	var cm: CraftMenu = hud.craft_menu()
	ctx.check(cm.is_open and not cp.is_open,
		"[exclusion] opening the craft menu ('f' beside a station) CLOSED the still-in-range container panel -- only ONE panel (craft OR container) open at a time",
		"[exclusion] both panels open or wrong panel open (craft=%s, container=%s)" % [str(cm.is_open), str(cp.is_open)])

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

# Verified against: Godot 4.7.1 (2026-07-20)
