class_name TestSwordsman extends RefCounted
## Swordsman behaviour (design-enemies.md "2. Swordsman"), Phase 2 of the enemy roster. Self-contained
## and DETERMINISTIC: it spawns its own Swordsman (enemy/enemy.tscn, now driven by swordsman.gd) plus
## a stand-in player target at REMOTE coords, sets swordsman._target directly (so the shared main.tscn
## player in the "player" group is never picked), and steps physics frames -- no keyboard, no reliance
## on the shared fixture. The player's swing is stubbed by setting player._attacking (the settable
## facade), and simulated hits are delivered by calling the Hurtbox's _on_area_entered directly (the
## same deterministic pattern the dodge-i-frame leg in tests/test_controls.gd uses). Legs:
##   a. A COMBO is telegraphed: a COLD-hitbox wind-up precedes each live strike, and the string ends
##      in a vulnerable RECOVERY window that then clears.
##   b. The reactive dodge EVADES a player swing when off-cooldown: it fires (dodge_count++, i-frames
##      up), a hit landing mid-dodge deals 0, and it shifts out of the swing line.
##   c. Cooldown + punish: a SECOND swing inside dodge_cooldown is NOT dodged and LANDS.
##   d. Spacing: it approaches to duel range then HOLDS -- never beelines onto the player.
##   e. Escalation: a low-HP Swordsman is more aggressive (shorter dodge cooldown + faster combos).
## Registered in tests/smoke_slash.gd after the Tank module.

const ENEMY_SCENE_PATH: String = "res://enemy/enemy.tscn"
const PLAYER_SCENE_PATH: String = "res://player/player.tscn"


func run(ctx: TestContext) -> void:
	print("[swordsman] --- Swordsman dueler: combos + reactive dodge + spacing + escalation (design-enemies.md) ---")
	var enemy_scene: PackedScene = load(ENEMY_SCENE_PATH)
	var player_scene: PackedScene = load(PLAYER_SCENE_PATH)
	if enemy_scene == null or player_scene == null:
		ctx.check(false, "", "enemy/player scene failed to load (test_swordsman)")
		return

	await _combo_telegraphed(ctx, enemy_scene, player_scene)
	await _dodge_and_cooldown(ctx, enemy_scene, player_scene)
	await _spacing_holds(ctx, enemy_scene, player_scene)
	await _escalation(ctx, enemy_scene)


## a. A combo strike is telegraphed (COLD hitbox during the wind-up, then live), and the string closes
## with a vulnerable RECOVERY punish window. Fired via a direct start_combo(3) for deterministic timing
## (windup/gap/recovery shrunk), sampled across the coroutine.
func _combo_telegraphed(ctx: TestContext, enemy_scene: PackedScene, player_scene: PackedScene) -> void:
	var sw: Swordsman = _spawn_swordsman(ctx, enemy_scene, Vector2(50000, 50000))
	var target: Node2D = _spawn_player(ctx, player_scene, Vector2(50060, 50000))
	sw._target = target
	sw.combo_windup = 0.1
	sw.combo_gap = 0.05
	sw.recovery_time = 0.2
	sw.attack_duration = 0.1
	await ctx.tree.physics_frame

	sw.start_combo(3)                   # committed 3-hit string; do NOT await -- sample the tell first
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame        # ~0.033s < combo_windup 0.1 -> still in the first hit's tell
	var windup_cold: bool = sw._telegraphing and sw._attack_shape.disabled and sw._combo_active

	var saw_live: bool = false
	var saw_recovery: bool = false
	for _i in range(180):
		await ctx.tree.physics_frame
		if not sw._attack_shape.disabled:
			saw_live = true
		if sw._recovering:
			saw_recovery = true
		if not sw._combo_active:
			break
	ctx.check(windup_cold and saw_live,
		"combo strike is TELEGRAPHED: a COLD-hitbox wind-up precedes the live hitbox",
		"combo tell missing (windup_cold=" + str(windup_cold) + " saw_live=" + str(saw_live) + ")")
	ctx.check(saw_recovery and not sw._combo_active and not sw._recovering,
		"combo ends in a vulnerable RECOVERY punish window, then clears",
		"combo recovery wrong (saw_recovery=" + str(saw_recovery) + " combo_active=" + str(sw._combo_active) + " recovering=" + str(sw._recovering) + ")")
	sw.queue_free()
	target.queue_free()
	await ctx.settle_idle()


## b+c. Reactive dodge on a cooldown + punish loop: off-cooldown, an incoming swing is EVADED (dodge
## fires, i-frames make a mid-dodge hit deal 0, the body shifts out of the line); then, still inside
## dodge_cooldown, a SECOND swing is NOT dodged and LANDS. The player's swing is stubbed via
## player._attacking; hits are delivered by calling the Hurtbox's _on_area_entered directly.
func _dodge_and_cooldown(ctx: TestContext, enemy_scene: PackedScene, player_scene: PackedScene) -> void:
	var sw: Swordsman = _spawn_swordsman(ctx, enemy_scene, Vector2(52000, 52000))
	var player: Player = _spawn_player(ctx, player_scene, Vector2(51976, 52000)) as Player  # 24px to the left
	player.facing = Vector2.RIGHT
	sw._target = player
	sw.dodge_reaction = 0.0     # raise the i-frames the SAME frame the swing is read (determinism)
	sw.dodge_duration = 0.2
	sw.combo_interval = 999.0   # never step into an own combo during this leg
	var sw_health: HealthComponent = sw.get_node("HealthComponent") as HealthComponent
	var sw_hurtbox: Hurtbox = sw.get_node("Hurtbox") as Hurtbox
	var sword_hitbox: Hitbox = player.get_node("SwordPivot/Sword") as Hitbox
	await ctx.tree.physics_frame

	# --- b. off-cooldown: the swing is dodged (i-frames evade the hit) ---
	var pos_before: Vector2 = sw.global_position
	player._attacking = true                # stub the player's active swing
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame            # detect -> _begin_dodge -> i-frames up (reaction 0)
	var dodged: bool = sw._dodging and sw_hurtbox.dodge_invincible and sw._dodge_count == 1
	var hp_before: int = sw_health.current_health
	sw_hurtbox._on_area_entered(sword_hitbox)   # a hit lands mid-dodge
	var evaded: bool = sw_health.current_health == hp_before
	ctx.check(dodged and evaded,
		"reactive dodge EVADES an off-cooldown swing: it fires + i-frames deal 0 (HP still " + str(sw_health.current_health) + ")",
		"dodge failed to evade (dodging=" + str(sw._dodging) + " inv=" + str(sw_hurtbox.dodge_invincible) + " count=" + str(sw._dodge_count) + " hp " + str(hp_before) + "->" + str(sw_health.current_health) + ")")
	for _i in range(6):
		await ctx.tree.physics_frame        # let the evade burst carry it
	ctx.check(sw.global_position.distance_to(pos_before) > 8.0,
		"the dodge SHIFTED the swordsman out of the swing line (moved " + str(int(sw.global_position.distance_to(pos_before))) + "px)",
		"the dodge did not move the swordsman (moved " + str(sw.global_position.distance_to(pos_before)) + ")")
	player._attacking = false

	# --- c. still inside dodge_cooldown: a second swing is NOT dodged and LANDS ---
	for _i in range(15):
		await ctx.tree.physics_frame        # ~0.25s: burst i-frames dropped, cooldown (1.2s) still up
	player._attacking = true
	await ctx.tree.physics_frame
	var no_second_dodge: bool = sw._dodge_on_cooldown and sw._dodge_count == 1 and not sw._dodging
	var hp2_before: int = sw_health.current_health
	sw_hurtbox._on_area_entered(sword_hitbox)   # this swing lands (no i-frames)
	var landed: bool = sw_health.current_health < hp2_before
	player._attacking = false
	ctx.check(no_second_dodge and landed,
		"cooldown+punish: a SECOND swing inside dodge_cooldown is NOT dodged and LANDS (" + str(hp2_before) + " -> " + str(sw_health.current_health) + ")",
		"cooldown loop wrong (on_cd=" + str(sw._dodge_on_cooldown) + " count=" + str(sw._dodge_count) + " dodging=" + str(sw._dodging) + " hp " + str(hp2_before) + "->" + str(sw_health.current_health) + ")")
	sw.queue_free()
	player.queue_free()
	await ctx.settle_idle()


## d. Spacing: from far out it approaches to duel range and HOLDS there (circling), never beelining all
## the way onto the player. Combos disabled here (combo_interval huge) so it is a pure spacing read.
func _spacing_holds(ctx: TestContext, enemy_scene: PackedScene, player_scene: PackedScene) -> void:
	var sw: Swordsman = _spawn_swordsman(ctx, enemy_scene, Vector2(54000, 54000))
	var target: Node2D = _spawn_player(ctx, player_scene, Vector2(54200, 54000))  # 200px away
	sw._target = target
	sw.combo_interval = 999.0
	await ctx.tree.physics_frame
	var dist_before: float = sw.global_position.distance_to(target.global_position)
	for _i in range(140):
		await ctx.tree.physics_frame
	var dist_after: float = sw.global_position.distance_to(target.global_position)
	ctx.check(dist_after < 120.0 and dist_after > 22.0,
		"spacing: approached to duel range and HELD, not onto the player (dist " + str(int(dist_before)) + " -> " + str(int(dist_after)) + ")",
		"spacing wrong (dist " + str(int(dist_before)) + " -> " + str(int(dist_after)) + "): should close then hold near duel range")
	sw.queue_free()
	target.queue_free()
	await ctx.settle_idle()


## e. Escalation: at low HP the Swordsman is more aggressive -- a shorter effective dodge cooldown AND
## a faster (shorter) combo cadence than at full HP. Read directly off the HP-scaled helpers (pinned so
## no FSM runs; the reads depend only on the HealthComponent).
func _escalation(ctx: TestContext, enemy_scene: PackedScene) -> void:
	var sw: Swordsman = _spawn_swordsman(ctx, enemy_scene, Vector2(56000, 56000))
	sw.stationary = true
	var sw_health: HealthComponent = sw.get_node("HealthComponent") as HealthComponent
	await ctx.tree.physics_frame
	var cd_full: float = sw.effective_dodge_cooldown()
	var ci_full: float = sw.effective_combo_interval()
	sw_health.take_damage(7)   # 10 -> 3 HP: ratio 0.3, below aggression_low_hp 0.4 -> max aggression
	var cd_low: float = sw.effective_dodge_cooldown()
	var ci_low: float = sw.effective_combo_interval()
	ctx.check(cd_low < cd_full and ci_low < ci_full,
		"escalation: a low-HP swordsman dodges sooner + combos faster (cd " + str(cd_full) + "->" + str(cd_low) + ", interval " + str(ci_full) + "->" + str(ci_low) + ")",
		"escalation did not increase aggression (cd " + str(cd_full) + "->" + str(cd_low) + " interval " + str(ci_full) + "->" + str(ci_low) + ")")
	sw.queue_free()
	await ctx.settle_idle()


## Instantiate a free (non-stationary) Swordsman at `at` so its dueling FSM runs.
func _spawn_swordsman(ctx: TestContext, scene: PackedScene, at: Vector2) -> Swordsman:
	var sw: Swordsman = scene.instantiate() as Swordsman
	sw.stationary = false
	ctx.tree.root.add_child(sw)
	sw.global_position = at
	return sw


## Instantiate a magnet-off Player stand-in target (real Hurtbox + Health) at `at`. pickup_radius 0 so
## it never auto-collects; input_override null so it never self-moves.
func _spawn_player(ctx: TestContext, scene: PackedScene, at: Vector2) -> Node2D:
	var p: Player = scene.instantiate() as Player
	p.pickup_radius = 0.0
	ctx.tree.root.add_child(p)
	p.global_position = at
	return p

# Verified against: Godot 4.7.1 (2026-07-19)
