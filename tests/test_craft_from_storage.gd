class_name TestCraftFromStorage extends RefCounted
## CRAFT-FROM-STORAGE -- EPIC 2 Phase 3 Part 3.1 goal post (plan-epic2-parts.md Phase 3; the seam long marked in
## components/crafting.gd). Crafting now sources a recipe's inputs from the player's Inventory PLUS the stores of
## in-range StorageContainers, aggregating AVAILABILITY across all of them and CONSUMING in a stable order
## (personal inventory FIRST, then each container store in order), ATOMICALLY across every touched store. Proves,
## purely + deterministically (Crafting/Inventory are RefCounted; the two scene legs build their own remote
## world):
##   * SHARED SCAN: Interaction.containers_in_range returns EVERY container in reach (the ONE group-within-radius
##     traversal), and nearest_container -- refactored to reuse it -- still returns the closest;
##   * STORAGE MAKES CRAFTABLE: a recipe UNCRAFTABLE from the inventory alone (a missing input) becomes craftable
##     when a nearby container holds the shortfall -- has_materials_for + would_craft both reflect the storage;
##   * EXACT SPLIT, PERSONAL FIRST: the craft drains the personal inventory to empty FIRST, then takes only the
##     remainder from the container (a single input split across the two sources), output landing in the inventory;
##   * INSUFFICIENT ACROSS ALL SOURCES: short even with the container summed in -> refuse, consuming NOTHING from
##     the inventory OR the container (atomic multi-store, no partial);
##   * MULTI-STORE OUTPUT-OVERFLOW ROLLBACK: a full inventory whose output cannot fit -> refuse, and the container
##     (already drained mid-transaction) is RESTORED byte-identical -- a failed craft touches no store;
##   * MENU FROM A CHEST (pure ui/craft_menu.tscn): passing the container store to open() lights up is_craftable
##     and craft_selected() consumes across inventory + chest through the menu the player operates;
##   * HUD END TO END (shipped streaming_world.tscn): a forge opens the craft menu and a chest beside the player
##     is auto-collected as a source by the HUD -- the recipe lights up + crafts from the chest on 'f'.
## Registered in tests/smoke_slash.gd after TestContainerPanel (it builds on the container + craft-menu slices).

const CONTAINER_SCENE: PackedScene = preload("res://world/container.tscn")
const STATION_SCENE: PackedScene = preload("res://world/station.tscn")
const CRAFT_MENU_SCENE: PackedScene = preload("res://ui/craft_menu.tscn")

const SPIN: StringName = &"spin_cord"   # fiber x3 -> cord x1, craft-anywhere
const FLINT: StringName = &"flint_kit"  # stone x2 + fiber x1 -> cord x1, craft-anywhere

## Remote region clear of every other module's placeables (container 140000/21000-24000, builder 120000,
## craft-menu 120000/200000, ...) so no stray container leaks into these radius scans and vice-versa.
const SCAN_HOME: Vector2 = Vector2(160000.0, -160000.0)
const HUD_SPOT: Vector2 = Vector2(-160000.0, 160000.0)


func run(ctx: TestContext) -> void:
	print("[craft_from_storage] --- Epic 2 Part 3.1: craft sources inputs from inventory + in-range containers, atomic across all stores ---")
	await _scan_containers_in_range(ctx)
	_storage_makes_craftable(ctx)
	_exact_split_personal_first(ctx)
	_insufficient_all_sources_atomic(ctx)
	_multi_store_output_overflow_atomic(ctx)
	await _menu_lights_up_from_chest(ctx)
	await _hud_end_to_end(ctx)


## SHARED SCAN: Interaction.containers_in_range returns ALL containers within the radius (two near, one far
## excluded); nearest_container, now reusing that same traversal, returns the closest. Proves the group-within-
## radius scan is shared, not duplicated, and both entry points agree on the in-range set.
func _scan_containers_in_range(ctx: TestContext) -> void:
	var holder: Node2D = Node2D.new()
	ctx.tree.root.add_child(holder)
	var near1: StorageContainer = _spawn_container(holder, SCAN_HOME)                       # dist 0
	var near2: StorageContainer = _spawn_container(holder, SCAN_HOME + Vector2(30.0, 0.0))  # dist 30 < reach
	var far: StorageContainer = _spawn_container(holder, SCAN_HOME + Vector2(5000.0, 0.0))  # far out of reach
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame

	var in_range: Array[StorageContainer] = Interaction.containers_in_range(SCAN_HOME, Interaction.CONTAINER_REACH)
	ctx.check(in_range.size() == 2 and in_range.has(near1) and in_range.has(near2) and not in_range.has(far),
		"containers_in_range returns EVERY container in reach (both near ones) and excludes the far one -- the ONE shared group-within-radius scan",
		"containers_in_range wrong (size=%d, near1=%s, near2=%s, far=%s)" % [in_range.size(), str(in_range.has(near1)), str(in_range.has(near2)), str(in_range.has(far))])

	var nearest: StorageContainer = Interaction.nearest_container(SCAN_HOME, Interaction.CONTAINER_REACH)
	ctx.check(nearest == near1,
		"nearest_container (refactored to reuse containers_in_range) still returns the CLOSEST in-range container",
		"nearest_container wrong (got %s, want near1)" % [str(nearest)])

	holder.queue_free()
	await ctx.tree.physics_frame


## STORAGE MAKES CRAFTABLE: FLINT (stone x2 + fiber x1) with the stone in the inventory but the fiber MISSING is
## uncraftable from the inventory alone -- until a container store supplies the fiber. has_materials_for +
## would_craft both flip true once the container is summed in.
func _storage_makes_craftable(ctx: TestContext) -> void:
	var STONE: ItemData = load("res://data/stone.tres")
	var FIBER: ItemData = load("res://data/fiber.tres")
	var sheet: CharacterSheet = CharacterSheet.new()
	sheet.known_recipes.learn(FLINT)
	var inv: Inventory = Inventory.new()
	inv.add_item(STONE, 2)                 # the stone need, but ZERO fiber
	var chest: Inventory = Inventory.new()  # a container store
	chest.add_item(FIBER, 1)               # the missing fiber
	var craft: Crafting = Crafting.new()
	var r: RecipeData = sheet.known_recipes.recipe(FLINT)

	# Inventory alone: no fiber -> not craftable.
	var alone_has: bool = craft.has_materials_for(r, inv)
	var alone_would: bool = craft.would_craft(FLINT, sheet, inv)
	# With the container summed in: the fiber is available -> craftable.
	var stores: Array[Inventory] = [chest]
	var storage_has: bool = craft.has_materials_for(r, inv, stores)
	var storage_would: bool = craft.would_craft(FLINT, sheet, inv, [], stores)
	ctx.check(not alone_has and not alone_would and storage_has and storage_would,
		"a recipe UNCRAFTABLE from inventory alone (fiber missing) becomes craftable when a container holds the shortfall -- has_materials_for + would_craft both reflect storage",
		"storage-availability wrong (alone_has=%s, alone_would=%s, storage_has=%s, storage_would=%s)" % [str(alone_has), str(alone_would), str(storage_has), str(storage_would)])

	# would_craft is a NET NO-OP: the dry-run left BOTH stores byte-identical.
	ctx.check(inv.count_of(STONE) == 2 and inv.count_of(FIBER) == 0 and chest.count_of(FIBER) == 1,
		"the would_craft dry-run committed NOTHING across either store (inv stone 2 + fiber 0, chest fiber 1 -- byte-identical)",
		"would_craft mutated a store (inv_stone=%d, inv_fiber=%d, chest_fiber=%d)" % [inv.count_of(STONE), inv.count_of(FIBER), chest.count_of(FIBER)])


## EXACT SPLIT, PERSONAL FIRST: SPIN needs fiber x3; the inventory holds 2 and the container holds 5. The craft
## drains the personal inventory to EMPTY first (fiber 2 -> 0), then takes only the remaining 1 from the container
## (5 -> 4), and the cord output lands in the inventory. Proves the stable personal-first consume + the exact split.
func _exact_split_personal_first(ctx: TestContext) -> void:
	var FIBER: ItemData = load("res://data/fiber.tres")
	var CORD: ItemData = load("res://data/cord.tres")
	var sheet: CharacterSheet = CharacterSheet.new()
	sheet.known_recipes.learn(SPIN)
	var inv: Inventory = Inventory.new()
	inv.add_item(FIBER, 2)                 # personal: 2 of the 3 needed
	var chest: Inventory = Inventory.new()
	chest.add_item(FIBER, 5)               # container: the surplus
	var craft: Crafting = Crafting.new()

	var ok: bool = craft.craft(SPIN, sheet, inv, [], [chest] as Array[Inventory])
	ctx.check(ok and inv.count_of(FIBER) == 0 and chest.count_of(FIBER) == 4 and inv.count_of(CORD) == 1,
		"exact split, PERSONAL FIRST: SPIN (fiber x3) drains the inventory to 0 (took 2) then takes ONLY the remaining 1 from the chest (5 -> 4); the cord output lands in the inventory",
		"cross-store split wrong (ok=%s, inv_fiber=%d, chest_fiber=%d, cord=%d)" % [str(ok), inv.count_of(FIBER), chest.count_of(FIBER), inv.count_of(CORD)])


## INSUFFICIENT ACROSS ALL SOURCES: SPIN needs fiber x3 but the inventory (1) + container (1) sum to only 2. The
## craft refuses, consuming NOTHING from EITHER store (atomic multi-store, no partial), and both predicates agree.
func _insufficient_all_sources_atomic(ctx: TestContext) -> void:
	var FIBER: ItemData = load("res://data/fiber.tres")
	var CORD: ItemData = load("res://data/cord.tres")
	var sheet: CharacterSheet = CharacterSheet.new()
	sheet.known_recipes.learn(SPIN)
	var inv: Inventory = Inventory.new()
	inv.add_item(FIBER, 1)
	var chest: Inventory = Inventory.new()
	chest.add_item(FIBER, 1)               # aggregate 2 < the 3 needed
	var craft: Crafting = Crafting.new()

	var stores: Array[Inventory] = [chest]
	var can: bool = craft.has_materials_for(sheet.known_recipes.recipe(SPIN), inv, stores)
	var ok: bool = craft.craft(SPIN, sheet, inv, [], stores)
	ctx.check(not can and not ok and inv.count_of(FIBER) == 1 and chest.count_of(FIBER) == 1 and inv.count_of(CORD) == 0,
		"insufficient ACROSS ALL sources (inv 1 + chest 1 < 3): refuses with NO consumption from inventory OR chest -- both stay 1, no cord (atomic multi-store)",
		"multi-store shortfall was not atomic (can=%s, ok=%s, inv_fiber=%d, chest_fiber=%d, cord=%d)" % [str(can), str(ok), inv.count_of(FIBER), chest.count_of(FIBER), inv.count_of(CORD)])


## MULTI-STORE OUTPUT-OVERFLOW ROLLBACK: a FULL single-slot inventory (a bystander stick) whose cord output cannot
## fit, with the fiber input sourced entirely from the container. The precheck passes (chest has the fiber), the
## consume drains the chest, the output overflows -> the transaction rolls back EVERY store: the chest is RESTORED
## byte-identical, so a failed craft consumed nothing from any source. would_craft agrees and also leaves it intact.
func _multi_store_output_overflow_atomic(ctx: TestContext) -> void:
	var FIBER: ItemData = load("res://data/fiber.tres")
	var CORD: ItemData = load("res://data/cord.tres")
	var STICK: ItemData = load("res://data/stick.tres")
	var sheet: CharacterSheet = CharacterSheet.new()
	sheet.known_recipes.learn(SPIN)
	var inv: Inventory = Inventory.new()
	inv.slots.resize(1)
	inv.slots[0] = ItemStack.new(STICK, 1)  # sole slot occupied by a non-input bystander -> cord cannot fit
	var chest: Inventory = Inventory.new()
	chest.add_item(FIBER, 5)                # all 3 fiber come from the chest (inv has none)
	var craft: Crafting = Crafting.new()

	var stores: Array[Inventory] = [chest]
	# would_craft first: it must report false AND leave the chest byte-identical (dry-run rolled it back).
	var would: bool = craft.would_craft(SPIN, sheet, inv, [], stores)
	var chest_after_dry: int = chest.count_of(FIBER)
	# craft(): the overflow rollback must restore the chest the consume already drained.
	var ok: bool = craft.craft(SPIN, sheet, inv, [], stores)
	ctx.check(not would and not ok and chest_after_dry == 5 and chest.count_of(FIBER) == 5
			and inv.count_of(CORD) == 0 and inv.item_at(0) == STICK and inv.count_at(0) == 1,
		"multi-store OUTPUT-OVERFLOW rolls back EVERY store: the cord cannot fit -> refuse, and the chest the consume already drained is RESTORED byte-identical (fiber stays 5, no cord, bystander stick intact) -- would_craft agrees",
		"cross-store overflow rollback wrong (would=%s, ok=%s, dry_chest=%d, chest=%d, cord=%d, slot0=%s)" % [str(would), str(ok), chest_after_dry, chest.count_of(FIBER), inv.count_of(CORD), str(inv.item_at(0) == STICK)])


## MENU FROM A CHEST (pure ui/craft_menu.tscn): passing the container store to open()'s extra_stores lights up
## is_craftable for a recipe the inventory alone cannot afford, and craft_selected() consumes across the inventory
## + chest THROUGH the menu (personal first). The menu adds no craft rules -- it just routes the stores to Crafting.
func _menu_lights_up_from_chest(ctx: TestContext) -> void:
	var holder: Node2D = Node2D.new()
	ctx.tree.root.add_child(holder)
	var menu: CraftMenu = CRAFT_MENU_SCENE.instantiate() as CraftMenu
	holder.add_child(menu)
	await ctx.tree.physics_frame

	var FIBER: ItemData = load("res://data/fiber.tres")
	var CORD: ItemData = load("res://data/cord.tres")
	var sheet: CharacterSheet = CharacterSheet.new()
	sheet.known_recipes.learn(SPIN)
	var inv: Inventory = Inventory.new()
	inv.add_item(FIBER, 1)                 # 1 of the 3 SPIN needs
	var chest: StorageContainer = _spawn_container(holder, SCAN_HOME + Vector2(0.0, 500.0))
	chest.store.add_item(FIBER, 5)         # the chest supplies the rest
	await ctx.tree.physics_frame

	# Open WITHOUT the chest store -> not craftable (inventory alone is short).
	menu.open(sheet, inv, [] as Array[StringName])
	var without: bool = menu.is_craftable(SPIN)
	# Open WITH the chest store -> lights up.
	menu.open(sheet, inv, [] as Array[StringName], [chest.store] as Array[Inventory])
	var with_store: bool = menu.is_craftable(SPIN)
	ctx.check(not without and with_store,
		"the CraftMenu lights up from a chest: SPIN is NOT craftable on inventory alone (1 fiber) but IS once the container store is routed into open()",
		"menu craftable flag did not reflect storage (without=%s, with=%s)" % [str(without), str(with_store)])

	# Craft through the menu: personal fiber 1 -> 0, chest 5 -> 3 (took 2), cord in the inventory.
	menu.select(SPIN)
	var crafted: bool = menu.craft_selected()
	ctx.check(crafted and inv.count_of(FIBER) == 0 and chest.store.count_of(FIBER) == 3 and inv.count_of(CORD) == 1,
		"craft_selected() crafts from the chest THROUGH the menu: inventory fiber 1 -> 0 (drained first), chest 5 -> 3, cord 0 -> 1 in the inventory",
		"menu cross-store craft wrong (ok=%s, inv_fiber=%d, chest_fiber=%d, cord=%d)" % [str(crafted), inv.count_of(FIBER), chest.store.count_of(FIBER), inv.count_of(CORD)])

	holder.queue_free()
	await ctx.tree.physics_frame


## HUD END TO END (shipped streaming_world.tscn): a forge Station opens the craft menu (station 'f' priority) while
## a StorageContainer sits beside the player. The HUD auto-collects that chest as a craft source
## (Interaction.containers_in_range around the player), so a recipe the player's inventory cannot afford alone
## LIGHTS UP and CRAFTS from the chest -- end to end, the player never reaching into the UI. Mirrors test_craft_menu's
## streaming-world isolation.
func _hud_end_to_end(ctx: TestContext) -> void:
	var sw_scene: PackedScene = load("res://world/streaming_world.tscn")
	if sw_scene == null:
		ctx.check(false, "", "streaming_world.tscn failed to load (craft-from-storage HUD leg)")
		return
	var sw: Node2D = sw_scene.instantiate()
	ctx.tree.root.add_child(sw)
	var player: Player = sw.get_node("Player") as Player
	var hud: Hud = sw.get_node("HUD") as Hud
	player.pickup_radius = 0.0  # no magnet interference
	await ctx.settle_idle()
	await ctx.settle_idle()

	# Remote spot; learn SPIN; stock 1 fiber (short of the 3 needed); forge + chest beside the player.
	player.global_position = HUD_SPOT
	player.character().known_recipes.learn(SPIN)
	var FIBER: ItemData = load("res://data/fiber.tres")
	var CORD: ItemData = load("res://data/cord.tres")
	player.inventory.add_item(FIBER, 1)
	var forge: Station = STATION_SCENE.instantiate() as Station
	forge.station_tag = &"forge"
	sw.add_child(forge)
	forge.global_position = HUD_SPOT + Vector2(20.0, 0.0)   # opens the menu (station 'f' priority)
	var chest: StorageContainer = CONTAINER_SCENE.instantiate() as StorageContainer
	sw.add_child(chest)
	chest.global_position = HUD_SPOT + Vector2(0.0, 20.0)   # within CONTAINER_REACH -> a HUD-collected source
	chest.store.add_item(FIBER, 5)
	await ctx.tree.physics_frame
	await ctx.settle_idle()

	# 'f' beside the forge -> the HUD opens the menu AND feeds the nearby chest store in.
	player.interact()
	await ctx.settle_idle()
	await ctx.settle_idle()
	var cm: CraftMenu = hud.craft_menu()
	ctx.check(cm.is_open and cm.is_craftable(SPIN),
		"'f' opened the craft menu at the forge and the HUD auto-collected the beside-player chest: SPIN LIGHTS UP though the player's inventory (1 fiber) alone cannot afford it",
		"HUD did not light SPIN up from the nearby chest (open=%s, craftable=%s)" % [str(cm.is_open), str(cm.is_craftable(SPIN))])

	# Craft through the menu: inventory fiber 1 -> 0 (first), chest 5 -> 3, cord in the player inventory.
	cm.select(SPIN)
	var crafted: bool = cm.craft_selected()
	ctx.check(crafted and player.inventory.count_of(FIBER) == 0 and chest.store.count_of(FIBER) == 3
			and player.inventory.count_of(CORD) == 1,
		"crafting through the HUD menu consumes across the split END TO END: player fiber 1 -> 0 (drained first), chest 5 -> 3, cord 0 -> 1 in the player inventory",
		"HUD cross-store craft wrong (ok=%s, player_fiber=%d, chest_fiber=%d, cord=%d)" % [str(crafted), player.inventory.count_of(FIBER), chest.store.count_of(FIBER), player.inventory.count_of(CORD)])

	sw.queue_free()
	await ctx.settle_idle()


## Instantiate a StorageContainer at `at` under `holder` (joins the "container" group via _ready so the scans find it).
func _spawn_container(holder: Node2D, at: Vector2) -> StorageContainer:
	var box: StorageContainer = CONTAINER_SCENE.instantiate() as StorageContainer
	holder.add_child(box)
	box.global_position = at
	return box

# Verified against: Godot 4.7.1 (2026-07-20)
