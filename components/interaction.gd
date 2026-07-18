class_name Interaction
extends RefCounted
## The E4 context-interaction subsystem (design-items.md "Interaction 'f'"): a pure-logic,
## no-new-node 'f'-to-harvest scanner, mirrored on the E3a magnetic-pickup system in
## player.gd (_process_pickups). Each physics frame it scans the "interactables" group for
## the NEAREST node within `radius` of the player and, if the action button is pressed,
## fires that node's interact(). The nearby node's verb is exposed for the HUD prompt.
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

## The nearest in-range interactable found on the last process() scan, or null. Cleared once
## harvested (try_interact) and re-derived every frame, so a freed/harvested node never
## lingers as a stale prompt. Read via current_prompt() by the HUD.
var _nearby: Node = null


## Per-frame pass (called from player._physics_process, after the pickup pass). Re-scan the
## "interactables" group for the nearest node within `radius` of the player, store it, then
## -- if the action button was just pressed AND something is nearby -- harvest it. Skipping
## the harvest branch when nothing is nearby means a stray press in open field is a no-op.
func process(player: Node2D) -> void:
	_nearby = _find_nearest(player)
	if _nearby != null and Input.is_action_just_pressed("the_action_button"):
		try_interact(player)


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


## The verb the HUD shows for the nearby interactable (e.g. "Harvest"), or "" when nothing is
## in reach. Guards a freed node so a stale ref never crashes the per-frame HUD read.
func current_prompt() -> String:
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

# Verified against: Godot 4.7.1 (2026-07-18)
