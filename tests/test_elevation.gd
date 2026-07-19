class_name TestElevation extends RefCounted
## Elevation + inside/outside FOUNDATION (design-environment.md #3, DECIDED fork: continuous float z +
## ground shadow; depth-sort by y + z). Proves the FOUNDATION is wired without building real floors or
## an isometric projection -- everything sits at z=0, so behaviour is unchanged today, but the hooks
## exist so jumps / stacked floors / a screen projection are purely ADDITIVE later:
##   * Elevation: a fresh player defaults z=0, carries a ground-shadow node drawn UNDER the body, and
##     exposes an elevation-aware depth key (y + z). Driving z>0 offsets the body UP while the shadow
##     stays pinned to the ground -- proving the draw hook is additive -- then restores cleanly.
##   * Inside/outside: the player's Region flag defaults OUTSIDE and flips OUTSIDE -> INSIDE -> OUTSIDE
##     as it is driven through a RegionTrigger (world/region_trigger.tscn), with `changed` firing.
## Self-contained: builds its own holder + player + trigger at a REMOTE coord (no other body wanders
## in), frees them at the end, and touches no shared game state. Registered in tests/smoke_slash.gd.

## Remote region for this leg, clear of every other self-contained module's coords.
const HOME: Vector2 = Vector2(48000, 0)


func run(ctx: TestContext) -> void:
	print("[elevation] --- z + ground shadow + depth key, and inside/outside region flag ---")
	var player_scene: PackedScene = load("res://player/player.tscn")
	var trigger_scene: PackedScene = load("res://world/region_trigger.tscn")
	ctx.check(player_scene != null and trigger_scene != null,
		"player.tscn + region_trigger.tscn load (elevation foundation)",
		"player.tscn or region_trigger.tscn failed to load")
	if player_scene == null or trigger_scene == null:
		return

	var holder: Node2D = Node2D.new()
	ctx.tree.root.add_child(holder)

	var player: Player = player_scene.instantiate() as Player
	player.pickup_radius = 0.0  # nothing to grab out here; keep it inert like the other remote players
	holder.add_child(player)
	player.global_position = HOME + Vector2(0, 500)  # start OUTSIDE the trigger below

	var trigger: RegionTrigger = trigger_scene.instantiate() as RegionTrigger
	holder.add_child(trigger)
	trigger.global_position = HOME

	await ctx.settle_idle()
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame

	# --- Elevation: default z, shadow node, depth key -----------------------------------------
	ctx.check(player._elevation != null and is_equal_approx(player._elevation.z, 0.0),
		"player elevation defaults to z = 0.0 (on the ground)",
		"player elevation z did not default to 0.0 (" + str(player._elevation.z if player._elevation != null else -1.0) + ")")

	var shadow: Node = player.get_node_or_null("GroundShadow")
	ctx.check(shadow is GroundShadow and (shadow as GroundShadow).z_index < 0,
		"player carries a GroundShadow node drawn UNDER the body (z_index " + str((shadow as GroundShadow).z_index if shadow is GroundShadow else 0) + " < 0)",
		"player GroundShadow missing or not drawn under the body")
	ctx.check(player._elevation._shadow == shadow,
		"elevation is wired to the same GroundShadow node (call-down)",
		"elevation shadow ref is not the player's GroundShadow node")

	# Depth-sort key = world_y + z. At z=0 it equals plain y (behaviour unchanged today); a nonzero z
	# biases it, which is the whole point of the hook once entities leave the ground.
	ctx.check(is_equal_approx(Elevation.depth_sort_key(100.0, 0.0), 100.0)
			and is_equal_approx(Elevation.depth_sort_key(100.0, 25.0), 125.0),
		"Elevation.depth_sort_key is world_y + z (100,0 -> 100; 100,25 -> 125)",
		"Elevation.depth_sort_key is not world_y + z")
	ctx.check(is_equal_approx(player._elevation.depth_key(100.0), 100.0),
		"at z=0 the player's depth key equals plain world_y (100 -> 100, unchanged)",
		"player depth key at z=0 did not equal plain world_y")

	# --- Elevation is additive: raise z -> body draws UP, shadow stays pinned to the ground ----
	var body: Node2D = player.get_node("Body") as Node2D
	var base_body_y: float = body.position.y
	var base_shadow_pos: Vector2 = (shadow as Node2D).position
	player._elevation.set_z(10.0)
	ctx.check(is_equal_approx(body.position.y, base_body_y - 10.0)
			and (shadow as Node2D).position == base_shadow_pos
			and is_equal_approx(player._elevation.depth_key(100.0), 110.0),
		"z=10 offsets the body UP by 10 (y - z) while the shadow stays on the ground and depth key -> 110",
		"z=10 did not offset the body up / pin the shadow / bias the depth key")
	player._elevation.set_z(0.0)  # back to the foundation state (everything on the ground)
	ctx.check(is_equal_approx(body.position.y, base_body_y),
		"restoring z=0 returns the body to its authored y (foundation state)",
		"restoring z=0 did not return the body to its authored y")

	# --- Inside/outside region flag: OUTSIDE default, flips through the trigger ----------------
	var changes: Array = [0]
	player._region.changed.connect(func(_s: Region.State) -> void: changes[0] += 1)
	ctx.check(player._region.state == Region.State.OUTSIDE,
		"region flag defaults to OUTSIDE",
		"region flag did not default to OUTSIDE (" + str(player._region.state) + ")")

	# Drive the player INTO the trigger -> INSIDE.
	player.global_position = HOME
	for _i in range(4):
		await ctx.tree.physics_frame
	ctx.check(player._region.state == Region.State.INSIDE,
		"entering the RegionTrigger flips the region OUTSIDE -> INSIDE",
		"region did not flip to INSIDE inside the trigger (" + str(player._region.state) + ")")

	# Drive the player back OUT -> OUTSIDE.
	player.global_position = HOME + Vector2(0, 700)
	for _i in range(4):
		await ctx.tree.physics_frame
	ctx.check(player._region.state == Region.State.OUTSIDE,
		"leaving the RegionTrigger flips the region INSIDE -> OUTSIDE",
		"region did not flip back to OUTSIDE outside the trigger (" + str(player._region.state) + ")")
	ctx.check(changes[0] >= 2,
		"region `changed` fired on both the enter and the exit (" + str(changes[0]) + " changes)",
		"region `changed` did not fire on enter + exit (" + str(changes[0]) + ")")

	holder.queue_free()
	await ctx.tree.physics_frame

# Verified against: Godot 4.7.1 (2026-07-19)
