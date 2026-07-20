class_name Interaction
extends RefCounted
## The E4 context-interaction subsystem (design-items.md "Interaction 'f'"): a pure-logic,
## no-new-node 'f'-to-harvest scanner, mirrored on the E3a magnetic-pickup system in
## player.gd (_process_pickups). Each physics frame it scans the "interactables" group for
## the NEAREST node within `radius` of the player and, if the action button is pressed,
## fires that node's interact(). The nearby node's verb is exposed for the HUD prompt.
##
## STATION EXTENSION (plan-epic1-parts.md Part 4.2): the SAME 'f' also OPENS the craft menu when a Station
## (world/station.gd) is in range. STATION TAKES PRIORITY over a harvest -- if a station is within reach, 'f'
## records a request to open the menu (with the station tags in range routed along) and harvests NOTHING; only
## with NO station in reach does 'f' fall through to the bush/pebble/tree/rock harvest. Documented either/or:
## you either open a workbench you are standing beside OR harvest a thing you are standing on, never both from
## one press. The open is surfaced as a pull-only REQUEST (craft_open_pending / consume_craft_open) that the HUD
## polls off the player each frame and turns into CraftMenu.open() -- the interaction never reaches into the UI
## (mirrors "HUD reads player, player never reaches into HUD"). Crafting/Station stay decoupled: this only
## collects Station.tags_in_range and hands the plain tag list up; it never touches a recipe or an inventory.
##
## CONTAINER EXTENSION (plan-epic2-parts.md Phase 2 Part 2.3): the SAME 'f' ALSO opens the container transfer panel
## when a placed StorageContainer (world/container.gd, group "container") is in range. That makes THREE contexts
## the single 'f' can resolve, so the priority is FIXED + DOCUMENTED (DECIDED -- a fixed order, not a distance
## tie-break): STATION-CRAFT first, then CONTAINER-TRANSFER, then HARVEST. Rationale: stations and containers are
## placed DELIBERATELY and seldom overlap, so a fixed, predictable order gives exactly ONE open per press with no
## ambiguous nearest-wins ties (and it extends the existing station-over-harvest precedence in the obvious way --
## the two "operate a placed building" verbs sit ahead of the "harvest a thing underfoot" fallback). Only when NO
## station AND NO container is in reach does 'f' fall through to the harvest, so the existing harvest is untouched
## when nothing else is near. Like the craft request, a container open is a pull-only REQUEST
## (container_open_pending / consume_container_open handing up the bound StorageContainer) the HUD turns into
## ContainerPanel.open(); the interaction never reaches into the UI. The nearest-container scan mirrors
## Station.tags_in_range (a static distance compare over the "container" group) and lives here so world/container.gd
## stays untouched -- this only finds the node and hands it up; it never touches the container's store or transfer.
##
## RefCounted, NOT a Node -- exactly like components/equipment.gd: adding an Area2D/Timer
## detector to player.tscn would bump Performance.OBJECT_NODE_COUNT, which the streaming
## zero-orphan-leak assertion prints as a live baseline. As a RefCounted it is invisible to
## the node monitors, so this whole framework perturbs no streaming node-count anchor. Being
## a RefCounted it cannot receive engine callbacks, so the player "calls down": it passes
## itself into process() each _physics_process (the same shape Equipment's process_* takes).
##
## Input is read DIRECTLY from the InputMap (Input.is_action_just_pressed), NOT via the
## networked FrameInput seam -- the SAME rationale as Equipment.process_inventory_input():
## a local world action (harvest a bush in front of me), not gameplay-simulation state a
## networked peer / AI would replay. Reassignable because the action lives in the InputMap.

## Interact reach in px: a node in the "interactables" group closer than this to the player
## is harvestable. One tile (components/world_scale.gd TILE 40) -- you must be right on the
## bush. Tunable per subsystem instance.
var radius: float = WorldScale.TILE

## Reach (px) for "near a container" -- two tiles (WorldScale.TILE 40), matching Station.DEFAULT_REACH: you stand
## BESIDE a chest to open it, a touch more generous than the one-tile harvest reach. A const so the interaction's
## scan AND the HUD's walk-away auto-close re-scan (ui/hud.gd) judge the SAME distance -- the container analogue of
## Station.DEFAULT_REACH, kept here (not on container.gd) so world/container.gd is untouched.
const CONTAINER_REACH: float = WorldScale.TILE * 2.0

## The nearest in-range interactable found on the last process() scan, or null. Cleared once
## harvested (try_interact) and re-derived every frame, so a freed/harvested node never
## lingers as a stale prompt. Read via current_prompt() by the HUD.
var _nearby: Node = null

## The station tags in range on the last process() scan (Station.tags_in_range), re-derived every frame. Non-
## empty => a station is within reach, so current_prompt() shows the "Craft" verb and 'f' opens the menu instead
## of harvesting. Kept only for the prompt; activate() re-scans fresh so it never depends on process() ordering.
var _station_tags: Array[StringName] = []
## The pull-only OPEN REQUEST the HUD polls: true once 'f' fired next to a station, cleared by consume_craft_open.
## The interaction never reaches into the UI -- it only raises this flag; the HUD turns it into CraftMenu.open().
var _craft_open_pending: bool = false
## The station tags to hand CraftMenu.open() with the pending request (a snapshot of what was in range at the
## press). Emptied when the request is consumed.
var _craft_open_tags: Array[StringName] = []

## The nearest in-range StorageContainer found on the last process() scan, or null. Re-derived every frame; drives
## current_prompt() (the "Open" verb) and is guarded (is_instance_valid) so a freed container never lingers as a
## stale prompt. Kept for the prompt only; activate() re-scans fresh so it never depends on process() ordering.
var _container: StorageContainer = null
## The pull-only CONTAINER OPEN REQUEST the HUD polls: true once 'f' fired next to a container (no station taking
## priority), cleared by consume_container_open. The interaction never reaches into the UI -- it only raises this
## flag; the HUD turns it into ContainerPanel.open().
var _container_open_pending: bool = false
## The StorageContainer to hand ContainerPanel.open() with the pending request (the one in range at the press).
## Cleared when the request is consumed.
var _container_open_target: StorageContainer = null


## Per-frame pass (called from player._physics_process, after the pickup pass). Re-scan the
## "interactables" group for the nearest node within `radius` of the player AND the station tags in range, store
## both, then -- if the action button was just pressed -- run activate() (station-open takes priority over
## harvest). A stray press in open field (no station, no interactable) is a no-op inside activate().
func process(player: Node2D) -> void:
	_nearby = _find_nearest(player)
	_station_tags = _stations_near(player)
	_container = Interaction.nearest_container(player.global_position, CONTAINER_REACH)
	if Input.is_action_just_pressed("the_action_button"):
		activate(player)


## The 'f' ACTION with the FIXED priority STATION-CRAFT > CONTAINER-TRANSFER > HARVEST (documented at the top of
## this file): a Station in reach TAKES PRIORITY -- record a craft-open request (with the tags in range) and do
## nothing else; else a StorageContainer in reach raises a container-open request (with the bound container) and
## does nothing else; else fall through to the harvest. Exactly ONE context resolves per press. PUBLIC so a
## headless test drives the exact same routing the action button triggers, without a real key press. Re-scans
## stations AND containers fresh so it is correct even if called directly without a preceding process() this frame.
func activate(player: Node2D) -> void:
	var tags: Array[StringName] = _stations_near(player)
	if not tags.is_empty():
		_craft_open_tags = tags
		_craft_open_pending = true
		return
	var box: StorageContainer = Interaction.nearest_container(player.global_position, CONTAINER_REACH)
	if box != null:
		_container_open_target = box
		_container_open_pending = true
		return
	try_interact(player)


## Whether an 'f'-near-a-station open request is waiting (the HUD polls this each frame). Pure read.
func craft_open_pending() -> bool:
	return _craft_open_pending


## Take the pending open request: clear the flag and RETURN the station tags to hand CraftMenu.open(). Returns []
## when nothing is pending (the HUD guards on craft_open_pending() first). One-shot -- consuming resets the flag.
func consume_craft_open() -> Array[StringName]:
	_craft_open_pending = false
	var tags: Array[StringName] = _craft_open_tags
	_craft_open_tags = []
	return tags


## Whether an 'f'-near-a-container open request is waiting (the HUD polls this each frame). Pure read -- the
## container analogue of craft_open_pending().
func container_open_pending() -> bool:
	return _container_open_pending


## Take the pending container-open request: clear the flag and RETURN the bound StorageContainer to hand
## ContainerPanel.open(). Returns null when nothing is pending (the HUD guards on container_open_pending() first).
## One-shot -- consuming resets the flag. The container analogue of consume_craft_open().
func consume_container_open() -> StorageContainer:
	_container_open_pending = false
	var box: StorageContainer = _container_open_target
	_container_open_target = null
	return box


## The nearest StorageContainer within `radius` of `world_pos` (the "container" group), or null -- the container
## analogue of Station.tags_in_range (a static distance compare over a placeable group). STATIC + decoupled so the
## interaction (activate/process) AND the HUD's walk-away re-scan (ui/hud.gd) share ONE scan, and so world/
## container.gd stays untouched (the scan lives with the interaction, not on the container). The active SceneTree
## is read via Engine.get_main_loop() (a fixed engine handle, no Time/OS/RNG) -- the same idiom Station.tags_in_range
## uses -- so no tree/player argument is threaded through. Skips freed/queued nodes; returns null when none in reach.
static func nearest_container(world_pos: Vector2, radius: float) -> StorageContainer:
	var loop: SceneTree = Engine.get_main_loop() as SceneTree
	if loop == null:
		return null
	var best: StorageContainer = null
	var best_dist: float = radius
	for node in loop.get_nodes_in_group(StorageContainer.GROUP):
		if not (node is StorageContainer):
			continue
		var box: StorageContainer = node as StorageContainer
		if not is_instance_valid(box) or box.is_queued_for_deletion():
			continue
		var dist: float = world_pos.distance_to(box.global_position)
		if dist <= best_dist:
			best_dist = dist
			best = box
	return best


## The station tags within Station.DEFAULT_REACH of the player -- the pure-logic station scan (world/station.gd),
## the station analogue of _find_nearest. Empty => no station in reach. Used by process() (for the prompt) and
## activate() (for the priority + the open tags).
func _stations_near(player: Node2D) -> Array[StringName]:
	return Station.tags_in_range(player.global_position, Station.DEFAULT_REACH)


## Harvest the current nearby interactable, if still valid: call its interact(player) and
## clear the stored ref (its node frees itself). PUBLIC so a headless test can drive a
## harvest deterministically without simulating a real key press -- the SAME path the action
## button triggers through process(). A no-op when nothing is nearby or it was already freed.
func try_interact(player: Node2D) -> void:
	if _nearby == null or not is_instance_valid(_nearby):
		_nearby = null
		return
	_nearby.interact(player)
	_nearby = null


## The verb the HUD shows, in the SAME fixed priority as activate(): "Craft" when a Station is in reach, else
## "Open" when a StorageContainer is in reach, else the nearby interactable's verb (e.g. "Harvest"), else "" when
## nothing is in reach. Guards a freed container/node so a stale ref never crashes the per-frame HUD read.
func current_prompt() -> String:
	if not _station_tags.is_empty():
		return "Craft"
	if _container != null and is_instance_valid(_container):
		return "Open"
	if _nearby == null or not is_instance_valid(_nearby):
		return ""
	return _nearby.interact_prompt()


## The nearest "interactables" group member within `radius` of the player, or null. Mirrors
## the E3a magnet's group scan: skips freed / queued nodes (is_instance_valid guard) so a
## node harvested this same frame is never returned.
func _find_nearest(player: Node2D) -> Node:
	var tree: SceneTree = player.get_tree()
	if tree == null:
		return null
	var best: Node = null
	var best_dist: float = radius
	for node in tree.get_nodes_in_group("interactables"):
		if not (node is Node2D):
			continue
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		var dist: float = player.global_position.distance_to((node as Node2D).global_position)
		if dist <= best_dist:
			best_dist = dist
			best = node
	return best

# Verified against: Godot 4.7.1 (2026-07-20)
