class_name TestCombat extends RefCounted
## Integration legs a-i on the SHARED main.tscn instance (refs passed via ctx), run
## WITHOUT keyboard input by calling methods directly and stepping physics frames:
##   a. player slash damages + knocks back the flesh enemy; flesh costs the sword 0
##      durability (Band A) -- plus the creatures-are-never-tool-gated proof (SWORD/
##      AXE/PICKAXE each land their own ATK-based HP on flesh, ordered pickaxe<axe<sword);
##   b. the enemy AI chases; c. enemy attack damages the player + knockback + i-frames +
##   blink; d. the death burst spawns/animates/frees; e. the ARMORED dummy (ATK/DEF,
##   sword wear Band B, armor wear + break -> flesh); f. the 3-hit combo advances and
##   hit 3 lunges; g. enemy death disables body collision then frees; h. live bodies are
##   solid; i. the input seam runs from an injected FrameInput.
## Runs FIRST of the two ordered gameplay modules; test_durability_tools.gd runs after,
## reusing the same instance and its mutated state. Split out of the former monolithic
## tests/smoke_slash.gd (CONVENTIONS.md Rule 1).


func run(ctx: TestContext) -> void:
	var player: Player = ctx.player
	var enemy: Enemy = ctx.enemy
	var dummy: Enemy = ctx.dummy
	var player_health: HealthComponent = ctx.player_health
	var enemy_health: HealthComponent = ctx.enemy_health
	var dummy_health: HealthComponent = ctx.dummy_health
	var sword_dura: DurabilityComponent = ctx.sword_dura
	# --- a. Player slash: ATK/DEF damage + knockback; flesh costs 0 durability ---
	# Sword atk 6 vs flesh def 1 -> max(1,6-1)=5 HP. Durability: over=hardness(2)-
	# power(5)=-3 -> Band A -> weapon_wear 0, so the blade is untouched by flesh.
	# Enemy at origin, player close on its left (dist 24). Reliability rule learned the
	# hard way (see NOTES.md, "arc-tween vs physics sampling"): the ARC rotation is a
	# TWEEN on idle-frame time while area overlap samples on PHYSICS frames, and against
	# a small Hurtbox (flesh r16) only one near-0deg sampled angle grazes it -- whether
	# that exact angle lands on a physics frame is luck. So this leg fires the LUNGE
	# (combo hit 3), which holds the blade fixed at 0deg for the whole swing window
	# instead of sweeping -- a guaranteed overlap on every physics frame. Bigger targets
	# (dummy r22, rocks 40x40) tolerate the arc; the small flesh Hurtbox needs the lunge.
	# Knockback is captured via the Hurtbox `hit_taken` signal (the exact hit frame),
	# since `_knockback` decays over the frames the awaited swing spans.
	enemy.stationary = true
	enemy.global_position = Vector2.ZERO
	enemy._move_velocity = Vector2.ZERO
	enemy._knockback = Vector2.ZERO
	player.global_position = Vector2(-24, 0)
	player.facing = Vector2.RIGHT
	player._combo_index = 2  # lunge: blade held straight at facing for the full window
	player._knockback = Vector2.ZERO
	await ctx.tree.physics_frame
	var enemy_hurtbox: Hurtbox = enemy.get_node("Hurtbox") as Hurtbox
	var enemy_start: int = enemy_health.current_health
	var sword_before_flesh: int = sword_dura.current_durability
	var hit_knockback: Array = [0.0]
	var on_flesh_hit: Callable = func(_hb: Hitbox) -> void: hit_knockback[0] = enemy._knockback.length()
	enemy_hurtbox.hit_taken.connect(on_flesh_hit)
	await player.attack()
	for _i in range(4):
		await ctx.tree.physics_frame
	enemy_hurtbox.hit_taken.disconnect(on_flesh_hit)
	enemy.stationary = false  # restore chasing for leg b
	var enemy_after_slash: int = enemy_health.current_health
	var enemy_knockback: float = hit_knockback[0]
	ctx.check(enemy_after_slash < enemy_start,
		"player slash damaged flesh enemy (" + str(enemy_start) + " -> " + str(enemy_after_slash) + ")",
		"player slash did not damage enemy (" + str(enemy_start) + " -> " + str(enemy_after_slash) + ")")
	ctx.check(enemy_after_slash == enemy_start - 5,
		"flesh HP damage is max(1,ATK-DEF)=5 (" + str(enemy_start) + " -> " + str(enemy_after_slash) + ")",
		"flesh HP damage wrong (expected -5, got " + str(enemy_start) + " -> " + str(enemy_after_slash) + ")")
	ctx.check(enemy_knockback > 0.0,
		"enemy knocked back on hit (impulse " + str(int(enemy_knockback)) + ")",
		"enemy knockback not applied on hit")
	ctx.check(sword_dura.current_durability == sword_before_flesh,
		"slashing flesh cost the sword 0 durability (Band A, still " + str(sword_dura.current_durability) + ")",
		"flesh slash wrongly wore the sword (" + str(sword_before_flesh) + " -> " + str(sword_dura.current_durability) + ")")

	# --- System 3: creatures are NEVER tool-gated -- SWORD/AXE/PICKAXE each still
	# land their own ATK-based HP on flesh (System 3, design-durability.md: the
	# tool-type gate applies ONLY to resource nodes). Heal to full before each
	# controlled hit so accumulated damage cannot kill the enemy mid-check -- it
	# needs to survive intact for leg b's chase test right after. Reuses the LUNGE
	# technique from leg a above (the HEADLESS TIMING TRAP: an arc sweep can miss the
	# small flesh Hurtbox between physics samples; the lunge holds the blade fixed at
	# facing for the whole window, a guaranteed overlap).
	enemy.stationary = true
	player.equip_tool(Player.SWORD_DATA)
	enemy_health.heal(enemy_health.max_health)
	enemy.global_position = Vector2.ZERO
	enemy._move_velocity = Vector2.ZERO
	enemy._knockback = Vector2.ZERO
	var flesh_before_sword: int = enemy_health.current_health
	await ctx.lunge_hit(player, Vector2(-24, 0), Vector2.RIGHT)
	var sword_flesh_dmg: int = flesh_before_sword - enemy_health.current_health
	ctx.check(sword_flesh_dmg == 5,
		"sword dealt max(0,ATK-DEF)=5 HP to flesh (dealt " + str(sword_flesh_dmg) + ")",
		"sword HP damage on flesh wrong (dealt " + str(sword_flesh_dmg) + ")")

	player.equip_tool(Player.AXE_DATA)
	enemy_health.heal(enemy_health.max_health)
	# Reset position/knockback -- the sword hit above shoved the enemy away from
	# origin via its own knockback impulse, which would otherwise make this fixed
	# lunge position miss.
	enemy.global_position = Vector2.ZERO
	enemy._move_velocity = Vector2.ZERO
	enemy._knockback = Vector2.ZERO
	var flesh_before_axe: int = enemy_health.current_health
	await ctx.lunge_hit(player, Vector2(-24, 0), Vector2.RIGHT)
	var axe_flesh_dmg: int = flesh_before_axe - enemy_health.current_health
	ctx.check(axe_flesh_dmg == 3,
		"axe dealt max(0,ATK-DEF)=3 HP to flesh, ungated by tool type (dealt " + str(axe_flesh_dmg) + ")",
		"axe HP damage on flesh wrong (dealt " + str(axe_flesh_dmg) + ")")

	player.equip_tool(Player.PICKAXE_DATA)
	enemy_health.heal(enemy_health.max_health)
	enemy.global_position = Vector2.ZERO
	enemy._move_velocity = Vector2.ZERO
	enemy._knockback = Vector2.ZERO
	var flesh_before_pick: int = enemy_health.current_health
	await ctx.lunge_hit(player, Vector2(-24, 0), Vector2.RIGHT)
	var pickaxe_flesh_dmg: int = flesh_before_pick - enemy_health.current_health
	ctx.check(pickaxe_flesh_dmg == 1,
		"pickaxe dealt max(0,ATK-DEF)=1 HP to flesh, ungated by tool type (dealt " + str(pickaxe_flesh_dmg) + ")",
		"pickaxe HP damage on flesh wrong (dealt " + str(pickaxe_flesh_dmg) + ")")
	ctx.check(pickaxe_flesh_dmg < axe_flesh_dmg and axe_flesh_dmg < sword_flesh_dmg,
		"creature damage strictly satisfies pickaxe(" + str(pickaxe_flesh_dmg) + ") < axe(" + str(axe_flesh_dmg) + ") < sword(" + str(sword_flesh_dmg) + ")",
		"tool ATK ordering violated (pickaxe=" + str(pickaxe_flesh_dmg) + " axe=" + str(axe_flesh_dmg) + " sword=" + str(sword_flesh_dmg) + ")")

	player.equip_tool(Player.SWORD_DATA)  # restore the default tool
	enemy_health.heal(enemy_health.max_health)  # leave the enemy healthy for leg b
	enemy.stationary = false  # restore chasing for leg b

	# --- b. Enemy AI chases the player -------------------------------------
	player.global_position = Vector2.ZERO
	enemy.global_position = Vector2(150, 0)
	await ctx.tree.physics_frame
	var dist_before: float = enemy.global_position.distance_to(player.global_position)
	for _i in range(40):
		await ctx.tree.physics_frame
	var dist_after: float = enemy.global_position.distance_to(player.global_position)
	ctx.check(dist_after < dist_before,
		"enemy chased player (dist " + str(int(dist_before)) + " -> " + str(int(dist_after)) + ")",
		"enemy did not close distance (" + str(int(dist_before)) + " -> " + str(int(dist_after)) + ")")

	# --- c. Enemy attack damages the player + knockback + i-frames + blink -
	enemy.global_position = Vector2.ZERO
	player.global_position = Vector2(26, 0)
	await ctx.tree.physics_frame
	var player_start: int = player_health.current_health
	enemy.attack()
	var player_after: int = player_start
	var player_knockback: float = 0.0
	for _i in range(20):
		await ctx.tree.physics_frame
		if player_health.current_health < player_start:
			player_after = player_health.current_health
			player_knockback = player._knockback.length()  # captured at the hit frame
			break
	ctx.check(player_after < player_start,
		"enemy attack damaged player (" + str(player_start) + " -> " + str(player_after) + ")",
		"enemy attack did not damage player (" + str(player_start) + " -> " + str(player_after) + ")")
	ctx.check(player_knockback > 0.0,
		"player knocked back on hit (impulse " + str(int(player_knockback)) + ")",
		"player knockback not applied on hit")
	var player_hurtbox: Hurtbox = player.get_node("Hurtbox") as Hurtbox
	ctx.check(player_hurtbox.is_invincible,
		"player i-frames active after hit",
		"player not invincible after hit")
	ctx.check(player._blink_tween != null and player._blink_tween.is_valid(),
		"player blink running during i-frames",
		"player blink not running during i-frames")

	# --- d. Death burst effect spawns circles and cleans itself up ---------
	var burst: DeathBurst = DeathBurst.new()
	ctx.tree.root.add_child(burst)
	burst.global_position = Vector2.ZERO
	var burst_done: Array = [false]
	burst.finished.connect(func() -> void: burst_done[0] = true)
	burst.play()
	var circle_count: int = burst.get_child_count()
	var watchdog: SceneTreeTimer = ctx.tree.create_timer(2.0)
	while not burst_done[0] and watchdog.time_left > 0.0:
		await ctx.tree.physics_frame
	await ctx.tree.physics_frame  # let the deferred queue_free resolve
	ctx.check(burst_done[0] and circle_count == 8 and not is_instance_valid(burst),
		"death burst spawned 8 circles, animated, and freed",
		"death burst (finished=" + str(burst_done[0]) + " circles=" + str(circle_count) + " freed=" + str(not is_instance_valid(burst)) + ")")

	# --- e. Armored dummy: ATK/DEF + sword wear + armor wear + break -> flesh -
	var dummy_hurtbox: Hurtbox = dummy.get_node("Hurtbox") as Hurtbox
	var dummy_armor: DurabilityComponent = dummy.get_node("Armor") as DurabilityComponent
	# Park the chaser far away so it cannot wander into this check.
	enemy.global_position = Vector2(2000, 2000)
	dummy.global_position = Vector2.ZERO
	player.global_position = Vector2(-40, 0)
	player.facing = Vector2.RIGHT
	await ctx.tree.physics_frame
	var dummy_pos_before: Vector2 = dummy.global_position
	for _i in range(20):
		await ctx.tree.physics_frame
	var dummy_moved: float = dummy.global_position.distance_to(dummy_pos_before)
	ctx.check(dummy_moved < 1.0,
		"dummy held position with player adjacent (moved " + str(dummy_moved) + ")",
		"dummy moved though it should be stationary (" + str(dummy_moved) + ")")

	# Hit 1 (armor intact): armored def 4 -> HP max(1,6-4)=2 (12 -> 10). Durability:
	# over=hardness(7)-power(5)=2 -> Band B -> weapon_wear ceil(4*2/3)=3; armor wears 1.
	var dmg_hp_before: int = dummy_health.current_health
	var sword_before_armor: int = sword_dura.current_durability
	var armor_before: int = dummy_armor.current_durability
	await ctx.slash_target(player, Vector2(-30, 0))
	var dmg_hp_after: int = dummy_health.current_health
	var sword_after_armor: int = sword_dura.current_durability
	var armor_after: int = dummy_armor.current_durability
	ctx.check(dmg_hp_before == 12 and dmg_hp_after == 10,
		"armored dummy took max(1,ATK-DEF)=2 HP (" + str(dmg_hp_before) + " -> " + str(dmg_hp_after) + ")",
		"armored HP damage wrong (" + str(dmg_hp_before) + " -> " + str(dmg_hp_after) + ")")
	ctx.check(sword_after_armor == sword_before_armor - 3,
		"sword wore 3 hitting armor (Band B) (" + str(sword_before_armor) + " -> " + str(sword_after_armor) + ")",
		"sword wear on armor wrong (expected -3, " + str(sword_before_armor) + " -> " + str(sword_after_armor) + ")")
	ctx.check(armor_after == armor_before - 1,
		"dummy armor wore on the hit (" + str(armor_before) + " -> " + str(armor_after) + ")",
		"dummy armor did not wear (" + str(armor_before) + " -> " + str(armor_after) + ")")

	# Two more hits break the armor (3 total). On break def/hardness drop to flesh.
	await ctx.slash_target(player, Vector2(-30, 0))
	await ctx.slash_target(player, Vector2(-30, 0))
	ctx.check(dummy_hurtbox.def == 1 and dummy_hurtbox.hardness == 2,
		"armor broke -> dummy def/hardness dropped to flesh (1/2)",
		"armor break did not drop to flesh (def=" + str(dummy_hurtbox.def) + " hardness=" + str(dummy_hurtbox.hardness) + ")")

	# Hit 4 (armor gone): now flesh (def 1, hardness 2). Durability over=2-5=-3 ->
	# Band A -> weapon_wear 0. Prove the sword stops wearing once the plate is gone.
	var sword_before_flesh2: int = sword_dura.current_durability
	await ctx.slash_target(player, Vector2(-30, 0))
	ctx.check(sword_dura.current_durability == sword_before_flesh2,
		"post-break the sword stops wearing (Band A, still " + str(sword_dura.current_durability) + ")",
		"sword wrongly wore after armor broke (" + str(sword_before_flesh2) + " -> " + str(sword_dura.current_durability) + ")")

	# --- f. Three-hit combo: index advances 0->1->2, hit 3 lunges forward ---
	enemy.global_position = Vector2(4000, 4000)
	dummy.global_position = Vector2(4000, -4000)
	player.global_position = Vector2.ZERO
	player.facing = Vector2.RIGHT
	player._knockback = Vector2.ZERO
	for _i in range(30):
		if not player._attacking:
			break
		await ctx.tree.physics_frame
	player._combo_index = 0
	await ctx.tree.physics_frame
	await player.attack()
	var combo_after_1: int = player._combo_index
	await player.attack()
	var combo_after_2: int = player._combo_index
	ctx.check(combo_after_1 == 1 and combo_after_2 == 2,
		"combo advanced 0 -> 1 -> 2 across the first two hits",
		"combo index wrong (after1=" + str(combo_after_1) + " after2=" + str(combo_after_2) + ")")
	var lunge_before: Vector2 = player.global_position
	await player.attack()
	for _i in range(12):
		await ctx.tree.physics_frame
	var lunge_dx: float = player.global_position.x - lunge_before.x
	ctx.check(lunge_dx > 1.0,
		"hit-3 lunge slid the player forward (dx " + str(lunge_dx) + ")",
		"hit-3 lunge did not move player forward (dx " + str(lunge_dx) + ")")

	# --- g. Enemy death sequence: pass-through collision, then freed ---------
	enemy.global_position = Vector2(500, 500)
	await ctx.tree.physics_frame
	var victim_body_shape: CollisionShape2D = enemy.get_node("CollisionShape2D") as CollisionShape2D
	enemy_health.take_damage(enemy_health.current_health) # guaranteed lethal
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	ctx.check(victim_body_shape.disabled and enemy.is_dead,
		"dead enemy body collision disabled (player passes through)",
		"dead enemy collision not disabled (disabled=" + str(victim_body_shape.disabled) + " is_dead=" + str(enemy.is_dead) + ")")
	var death_watchdog: SceneTreeTimer = ctx.tree.create_timer(2.0)
	while is_instance_valid(enemy) and death_watchdog.time_left > 0.0:
		await ctx.tree.physics_frame
	ctx.check(not is_instance_valid(enemy),
		"dead enemy freed after the blink/lurch sequence",
		"dead enemy not freed within watchdog")

	# --- h. Live bodies are solid: player cannot pass through the dummy -----
	dummy.global_position = Vector2.ZERO
	player.global_position = Vector2(-60, 0)
	player.facing = Vector2.RIGHT
	await ctx.tree.physics_frame
	for _i in range(40):
		player._knockback = Vector2(220, 0)
		await ctx.tree.physics_frame
	player._knockback = Vector2.ZERO
	ctx.check(player.global_position.x < -20.0,
		"live bodies collide: player blocked by the dummy (x " + str(int(player.global_position.x)) + ")",
		"player passed through the live dummy (x " + str(int(player.global_position.x)) + ")")

	# --- i. Input seam: the controller runs from an injected FrameInput ------
	dummy.global_position = Vector2(5000, 5000)  # clear the area of obstacles
	player.global_position = Vector2.ZERO
	player._move_velocity = Vector2.ZERO
	player._knockback = Vector2.ZERO
	var injected: FrameInput = FrameInput.new()
	injected.move = Vector2.RIGHT
	player.input_override = injected
	var seam_before_x: float = player.global_position.x
	for _i in range(20):
		await ctx.tree.physics_frame
	var seam_dx: float = player.global_position.x - seam_before_x
	player.input_override = null
	ctx.check(seam_dx > 1.0,
		"controller runs from injected FrameInput (moved dx " + str(int(seam_dx)) + ")",
		"injected input did not move the player (dx " + str(seam_dx) + ")")

	# --- j. Only the sword combos: axe/pickaxe do single regular swings ------
	# has_combo gates the CHAIN, not the swing shape: a regular tool's press never advances
	# _combo_index past 0 (so it never reaches arc B or the hit-3 lunge), unlike the sword's
	# leg f above which advanced 0 -> 1 -> 2. Runs LAST and parks the player far from every
	# other body so its attacks (and leftover position) cannot perturb the earlier collision
	# legs -- only the combo index matters here.
	player.global_position = Vector2(6000, 6000)
	player.facing = Vector2.RIGHT
	player._knockback = Vector2.ZERO
	player.input_override = null
	ctx.check(player._combo_enabled,
		"the sword is a combo weapon (_combo_enabled true)",
		"sword should combo but _combo_enabled is false")
	player.equip_tool(Player.AXE_DATA)
	ctx.check(not player._combo_enabled,
		"the axe is a NON-combo weapon (single regular swings)",
		"axe should not combo but _combo_enabled is true")
	for _i in range(30):
		if not player._attacking:
			break
		await ctx.tree.physics_frame
	player._combo_index = 0
	await ctx.tree.physics_frame
	await player.attack()
	var axe_after_1: int = player._combo_index
	await player.attack()
	var axe_after_2: int = player._combo_index
	ctx.check(axe_after_1 == 0 and axe_after_2 == 0,
		"axe swings never advance the combo (index stays 0 across presses)",
		"axe combo advanced when it should not (after1=" + str(axe_after_1) + " after2=" + str(axe_after_2) + ")")
	player.equip_tool(Player.SWORD_DATA)  # restore the default combo weapon
	player._combo_index = 0

	# --- k. Sword swing DIRECTIONS vary + perspective RESET (CHANGE 2) -----------
	# ONLY the sword varies its direction: hit 0 is the overhead DOWN-slash (top ->
	# bottom on screen), hit 1 the RISING UP-slash (the reverse arc, bottom -> top),
	# hit 2 the forward thrust (leg f already proves the thrust slides forward). Assert
	# hit 1 is the exact reverse of hit 0 (swapped sweep endpoints) AND that the two sweep
	# OPPOSITE vertical ways for facing right; then that a swing leaves NO residual blade
	# scale/skew (the perspective cue is reset in _end_swing). Park far from every body.
	player.equip_tool(Player.SWORD_DATA)
	player.global_position = Vector2(6000, 6000)
	player.facing = Vector2.RIGHT
	player._knockback = Vector2.ZERO
	for _i in range(30):
		if not player._attacking:
			break
		await ctx.tree.physics_frame
	player._combo_index = 0
	await ctx.tree.physics_frame
	await player.attack()  # hit 0: overhead down-slash
	var down_start: float = player._combat._last_arc_start
	var down_end: float = player._combat._last_arc_end
	await player.attack()  # hit 1: rising up-slash (the reverse arc)
	var up_start: float = player._combat._last_arc_start
	var up_end: float = player._combat._last_arc_end
	ctx.check(is_equal_approx(up_start, down_end) and is_equal_approx(up_end, down_start),
		"sword hit 1 is the REVERSE arc of hit 0 (up-slash swaps the down-slash sweep endpoints)",
		"sword hit 1 did not reverse hit 0 (down " + str(down_start) + "->" + str(down_end) + " up " + str(up_start) + "->" + str(up_end) + ")")
	ctx.check(down_end > down_start and up_end < up_start,
		"hit 0 sweeps DOWN while hit 1 sweeps UP (opposite vertical directions, facing right)",
		"sword sweep directions not opposite (down " + str(down_start) + "->" + str(down_end) + " up " + str(up_start) + "->" + str(up_end) + ")")
	ctx.check(player._blade.scale == Vector2.ONE and is_equal_approx(player._blade.skew, 0.0),
		"the blade scale/skew reset after the swing (no residual perspective distortion)",
		"blade left distorted after a swing (scale=" + str(player._blade.scale) + " skew=" + str(player._blade.skew) + ")")
	player._combo_index = 0

# Verified against: Godot 4.7.1 (2026-07-19)
