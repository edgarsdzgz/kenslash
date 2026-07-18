class_name TestPlayable extends RefCounted
## Playable-loop D1 (design-playable-loop.md): world-PRESERVING death/respawn. Instantiates
## the shipped streaming_world.tscn (the new default boot scene), kills the player, and proves
## a FINITE respawn_point respawns the player IN PLACE while the ChunkManager and its live
## content SURVIVE (no reload_current_scene freed them). Also proves revive() makes death
## repeatable, and that a fresh player.tscn defaults to Vector2.INF (the arena reload path).
## Self-contained: builds its own streaming_world instance, never main.tscn.


func run(ctx: TestContext) -> void:
	print("[playable] --- D1 world-preserving respawn: die -> respawn in place, world survives ---")
	var sw_scene: PackedScene = load("res://world/streaming_world.tscn")
	ctx.check(sw_scene != null,
		"streaming_world.tscn loads (the D1 boot scene)",
		"streaming_world.tscn failed to load")
	if sw_scene == null:
		return
	var sw: Node2D = sw_scene.instantiate()
	ctx.tree.root.add_child(sw)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame

	var player: Player = sw.get_node("Player") as Player
	var manager: ChunkManager = sw.get_node("ChunkManager") as ChunkManager
	var health: HealthComponent = player.get_node("HealthComponent") as HealthComponent

	# A FINITE respawn point => respawn in place + keep the world. (streaming_world._ready
	# already set Vector2.ZERO; override to a distinct point so the assertion is unambiguous.
	# (500,500) is still chunk (0,0) at CHUNK_PX 640, so the active set does not change.)
	player.respawn_point = Vector2(500, 500)
	var manager_id: int = manager.get_instance_id()

	# Pre-death world mutation: partial-mine a rock in an active chunk so we can prove the
	# built world (its live content + state) survived death -- not just the manager Node.
	var mutated_mat: DurabilityComponent = _first_rock_material(manager)
	var mutated_integrity: int = -1
	if mutated_mat != null:
		mutated_mat.wear(1)
		mutated_integrity = mutated_mat.current_durability

	# Kill the player straight through its HealthComponent (forces `died`), then let the death
	# sequence run (pause -> burst -> 0.4s -> respawn). The tree is PAUSED during the burst, but
	# physics_frame still fires and the burst/timer are process_always, so a real-time watchdog
	# advances it; _respawn_in_place unpauses. Assert the pre-death state first.
	ctx.check(ctx.tree.paused == false, "tree is running before death", "tree already paused before death")
	health.take_damage(health.max_health)
	var watchdog: SceneTreeTimer = ctx.tree.create_timer(8.0)
	while ctx.tree.paused and watchdog.time_left > 0.0:
		await ctx.tree.physics_frame
	await ctx.tree.physics_frame

	ctx.check(player.global_position == Vector2(500, 500),
		"respawn: player is back at the finite respawn_point (500, 500)",
		"respawn position wrong (" + str(player.global_position) + ")")
	ctx.check(health.current_health == health.max_health,
		"respawn: health revived to max (" + str(health.current_health) + "/" + str(health.max_health) + ")",
		"respawn health not revived (" + str(health.current_health) + "/" + str(health.max_health) + ")")
	ctx.check(is_instance_valid(manager) and manager.get_instance_id() == manager_id,
		"world preserved: the SAME ChunkManager instance survived death (reload_current_scene would have freed it)",
		"ChunkManager was freed/replaced across death -- the world reloaded")
	ctx.check(ctx.tree.paused == false,
		"respawn: tree unpaused after respawn",
		"tree still paused after respawn")

	# Nice-to-have: the pre-death rock mutation is still present (the built world, incl. its
	# harvested state, was NOT reset -- reload would have regenerated a fresh integrity-4 rock).
	if mutated_mat != null:
		ctx.check(is_instance_valid(mutated_mat) and mutated_mat.current_durability == mutated_integrity,
			"world preserved: a pre-death rock mutation (integrity " + str(mutated_integrity) + ") persisted across respawn -- world state kept, not regenerated",
			"pre-death chunk mutation was lost across respawn (rock " + str(is_instance_valid(mutated_mat)) + ")")

	# --- Playable again: revive() made death repeatable ----------------------------
	# Disconnect the player's own death handler so a second kill does not start ANOTHER
	# pause/respawn sequence, then prove `died` fires a SECOND time and HP reaches 0.
	var died_again: Array = [false]
	health.died.disconnect(Callable(player, "_on_died"))
	health.died.connect(func() -> void: died_again[0] = true)
	health.take_damage(health.max_health)
	ctx.check(health.current_health == 0 and died_again[0],
		"playable again: after respawn the player took damage and `died` fired a SECOND time (revive works, death repeatable)",
		"player could not die again after respawn (hp " + str(health.current_health) + ", died_again " + str(died_again[0]) + ")")

	sw.queue_free()
	await ctx.tree.physics_frame

	# --- Arena default preserved: a fresh player.tscn defaults to Vector2.INF -------
	var p_scene: PackedScene = load("res://player/player.tscn")
	var fresh_player: Player = p_scene.instantiate() as Player
	ctx.check(not is_finite(fresh_player.respawn_point.x) and not is_finite(fresh_player.respawn_point.y),
		"arena path preserved: a fresh Player defaults respawn_point to Vector2.INF (-> reload on death, unchanged)",
		"fresh Player respawn_point was not Vector2.INF (" + str(fresh_player.respawn_point) + ")")
	fresh_player.free()


## First Rock's Material DurabilityComponent among the manager's active chunk containers,
## or null if the active set happens to hold none.
func _first_rock_material(manager: ChunkManager) -> DurabilityComponent:
	for container in manager.get_children():
		for child in container.get_children():
			if child is Rock:
				return child.get_node("Material") as DurabilityComponent
	return null

# Verified against: Godot 4.7.1 (2026-07-17)
