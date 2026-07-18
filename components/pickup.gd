class_name Pickup
extends RefCounted
## The E3a magnetic auto-pickup subsystem, extracted from player.gd (design-items.md
## "Drops -- Magnetic pickup"). Stardew-style: a ground Drop within pickup_radius slides
## toward the player and is grabbed on contact into the inventory -- no button. PURE
## extraction -- behavior is identical to the pre-split player.gd; the player keeps a thin
## facade (collect / pickup_radius) that forwards here so tests and world code read
## player.X unchanged.
##
## RefCounted, NOT a Node -- exactly like components/equipment.gd and components/interaction.gd.
## An Area2D/Timer detector added to player.tscn to do the magnet would bump the global
## Performance.OBJECT_NODE_COUNT (or ORPHAN count), which the streaming zero-orphan-leak
## assertion prints as a literal baseline -- changing that message and breaking the
## "same 194 assertions, byte-identical" refactor anchor. As a RefCounted it is invisible to
## both node monitors, so this magnet perturbs no streaming node-count anchor. E3a is pickup
## ONLY -- the 5-min lifetime cull (E3b) and chunk-persistence (E3c) are deliberately NOT here.
##
## "Call down" wiring (patterns/scene-composition.md): being a RefCounted it cannot receive
## engine callbacks, so the player "calls down" -- it passes itself into process() each
## _physics_process (the same shape Interaction.process(player) takes) and into collect() when
## the facade forwards a direct grab. This object reads player.global_position and adds via
## player.inventory.add_item, but never reaches up to store the player.
##
## Tunable placement (pickup_radius / pickup_pull_speed / pickup_grab_radius): these stay as
## plain @export fields ON THE PLAYER and are read off the passed-in player every frame, NOT
## moved onto this component. That is DELIBERATE and load-bearing: a test disables the magnet
## with `player.pickup_radius = 0.0` set the SAME frame the scene is instantiated -- BEFORE the
## player's _ready() runs (a SceneTree test has no idle frame between add_child and the next
## line). A plain node field accepts that pre-_ready write; a facade routed through this
## RefCounted could not, because the component does not exist until _ready creates it. Reading
## the tunables off the player each frame keeps the pre-_ready disable working byte-for-byte.

## Collect `count` of `item` into the player's inventory -- the magnet's grab, and the target of
## the directly test/world-callable player.collect facade (world/bush.gd harvests through it).
## Routed through the inventory facade (player.inventory) so a full inventory leaves the loot for
## the caller. Returns the overflow add_item could not fit (0 = all taken). Takes the player
## (never stored) so this RefCounted reaches the inventory the same way process() does.
func collect(player: Node2D, item: ItemData, count: int) -> int:
	return player.inventory.add_item(item, count)


## Per-frame magnet pass (called from player._physics_process, before the interaction pass).
## For each in-range Drop: home it toward the player (clamped so a fast pull never overshoots)
## and, on contact, collect it -- freeing it if it fully fit, shrinking its count on a partial
## take, or leaving it wholly untouched when the inventory is full. Reads the tunables (see the
## header note) and the position off the passed-in player; identical logic to the pre-split
## _process_pickups, so `player.pickup_radius = 0.0` disables the pass exactly as before.
func process(player: Node2D, delta: float) -> void:
	# Disabled player (pickup_radius 0), or nothing to do: bail cheaply before the group query.
	if player.pickup_radius <= 0.0:
		return
	var tree: SceneTree = player.get_tree()
	if tree == null or tree.paused:
		return
	var drops: Array = tree.get_nodes_in_group("drops")
	if drops.is_empty():
		return
	var step: float = player.pickup_pull_speed * delta
	for node in drops:
		if not (node is Drop):
			continue
		var drop: Drop = node as Drop
		# A drop freed / queued mid-iteration must be skipped, not touched.
		if not is_instance_valid(drop) or drop.is_queued_for_deletion():
			continue
		if player.global_position.distance_to(drop.global_position) > player.pickup_radius:
			continue
		drop.global_position = drop.global_position.move_toward(player.global_position, step)
		# Re-measure post-move so a same-frame arrival still grabs this tick.
		if player.global_position.distance_to(drop.global_position) <= player.pickup_grab_radius:
			var overflow: int = collect(player, drop.item, drop.count)
			if overflow <= 0:
				drop.queue_free()          # fully collected
			elif overflow < drop.count:
				drop.count = overflow      # partial take -- leave the remainder on the ground
			# overflow == count: inventory full -> leave the drop entirely (no free, no dupe).

# Verified against: Godot 4.7.1 (2026-07-18)
