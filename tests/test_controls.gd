class_name TestControls extends RefCounted
## design-controls.md: the player controls overhaul -- STAMINA + SPRINT + DODGE (attack was also
## remapped to Left Mouse Button, but headless tests call player.attack() directly so that rebind
## is exercised only by the InputMap, not here). Three self-contained sections, all deterministic
## via input_override + direct state (never real keyboard input), driven at remote coords so no
## other body can wander into range:
##   * Phase 1 -- Stamina math (pure, no scene): spend/regen-after-delay/exhaustion/low/can_sprint.
##   * Phase 2 -- Sprint: a sprinting player travels FARTHER than a walker, DRAINS stamina, gives
##     NO boost when empty, and STACKS multiplicatively with encumbrance.
##   * Phase 3 -- Dodge: a dash moves ~the dash distance, costs dodge_cost, is BLOCKED under cost,
##     grants i-frames (0 damage mid-dash), PHASES through an enemy body, and gates re-dodge on a
##     cooldown.
## Registered in tests/smoke_slash.gd after the other self-contained modules.

## Physics frames to drive each sprint player -- long enough to reach terminal speed and open a wide
## distance gap between the walk / sprint / encumbered variants, short enough that nothing wanders in.
const SPRINT_FRAMES: int = 40


func run(ctx: TestContext) -> void:
	print("[controls] --- stamina + sprint + dodge (design-controls.md) ---")
	_stamina_unit_legs(ctx)
	await _sprint_legs(ctx)
	await _dodge_legs(ctx)


## Phase 1 -- pure Stamina math (no scene). Proves the spend gate, the regen DELAY (short pause
## after any consumption) vs the EXHAUSTION cooldown (longer wait after bottoming out at 0), the low
## band, and can_sprint gating.
func _stamina_unit_legs(ctx: TestContext) -> void:
	# Consume: try_spend deducts on success, changes nothing (and returns false) when short.
	var s: Stamina = Stamina.new()
	var spent_ok: bool = s.try_spend(30.0)
	ctx.check(spent_ok and is_equal_approx(s.current, 70.0),
		"stamina try_spend(30) succeeds and leaves 70 (current " + str(s.current) + ")",
		"stamina try_spend(30) wrong (ok=" + str(spent_ok) + " current " + str(s.current) + ")")
	var spent_fail: bool = s.try_spend(1000.0)
	ctx.check(not spent_fail and is_equal_approx(s.current, 70.0),
		"stamina try_spend beyond current is refused and spends nothing (current " + str(s.current) + ")",
		"stamina over-spend not refused (ok=" + str(spent_fail) + " current " + str(s.current) + ")")

	# Regen only AFTER the delay: a tick inside regen_delay does not regen; once cumulative time
	# passes the delay, regen resumes.
	var r: Stamina = Stamina.new()
	r.try_spend(30.0)  # current 70, regen clock reset
	r.tick(0.3, false)  # 0.3 < regen_delay 0.4 -> still no regen
	ctx.check(is_equal_approx(r.current, 70.0),
		"stamina does NOT regen within the regen delay (current " + str(r.current) + ")",
		"stamina regened too early inside the delay (current " + str(r.current) + ")")
	r.tick(0.2, false)  # cumulative 0.5 >= 0.4 -> regen 35*0.2 = 7
	ctx.check(r.current > 70.0,
		"stamina regens once past the regen delay (current " + str(r.current) + ")",
		"stamina did not regen after the delay (current " + str(r.current) + ")")

	# Exhaustion: draining to 0 latches a LONGER cooldown before regen -- a tick that would have
	# passed the short delay still yields no regen while exhausted; only past exhaust_cooldown does it.
	var e: Stamina = Stamina.new()
	e.drain(100.0)  # current 0, exhausted latched
	ctx.check(is_equal_approx(e.current, 0.0) and not e.can_sprint(),
		"stamina drained to 0 is exhausted -> can_sprint() false",
		"stamina at 0 not exhausted (current " + str(e.current) + " can_sprint " + str(e.can_sprint()) + ")")
	e.tick(0.5, false)  # 0.5 > regen_delay 0.4 BUT < exhaust_cooldown 1.2 -> still no regen
	ctx.check(is_equal_approx(e.current, 0.0),
		"exhausted stamina waits the LONGER cooldown, not the short delay (current " + str(e.current) + ")",
		"exhausted stamina regened before its cooldown (current " + str(e.current) + ")")
	e.tick(0.8, false)  # cumulative 1.3 >= 1.2 -> exhaustion clears + regen 35*0.8 = 28
	ctx.check(e.current > 0.0 and e.can_sprint(),
		"exhausted stamina regens + can sprint again after the exhaust cooldown (current " + str(e.current) + ")",
		"exhausted stamina did not recover after its cooldown (current " + str(e.current) + " can_sprint " + str(e.can_sprint()) + ")")

	# Low band: is_low() flips true strictly UNDER low_frac (0.25). 25/100 is NOT low; 20/100 is.
	var lo: Stamina = Stamina.new()
	ctx.check(not lo.is_low(),
		"full stamina is not low",
		"full stamina wrongly reported low")
	lo.drain(75.0)  # current 25 -> ratio exactly 0.25, not < 0.25
	ctx.check(not lo.is_low(),
		"stamina at exactly 25% is not yet low (boundary is strict <)",
		"stamina at 25% wrongly reported low (current " + str(lo.current) + ")")
	lo.drain(5.0)  # current 20 -> ratio 0.20 < 0.25
	ctx.check(lo.is_low(),
		"stamina under 25% reports low (current " + str(lo.current) + ")",
		"stamina under 25% not reported low (current " + str(lo.current) + ")")


## Phase 2 -- Sprint. Five freshly instantiated players driven RIGHT for the same frames via
## input_override, all magnet-off at distinct remote coords: a light walker, a light sprinter, a
## light EMPTY-stamina sprinter, and an over-capacity walker + sprinter. Asserts the sprint boost,
## the drain, the no-boost-when-empty, and the multiplicative stack with encumbrance.
func _sprint_legs(ctx: TestContext) -> void:
	var player_scene: PackedScene = load("res://player/player.tscn")
	if player_scene == null:
		ctx.check(false, "", "player.tscn failed to load (sprint legs)")
		return
	var STONE: ItemData = load("res://data/stone.tres")

	var walker: Player = _spawn(ctx, player_scene, Vector2(20000, 20000))
	var sprinter: Player = _spawn(ctx, player_scene, Vector2(20000, -20000))
	var empty: Player = _spawn(ctx, player_scene, Vector2(-20000, 20000))
	var heavy_walk: Player = _spawn(ctx, player_scene, Vector2(-20000, -20000))
	var heavy_sprint: Player = _spawn(ctx, player_scene, Vector2(23000, 23000))
	heavy_walk.inventory.add_item(STONE, 200)  # -> ratio ~4 -> ULTRA factor 0.25
	heavy_sprint.inventory.add_item(STONE, 200)

	# Let _ready wire the inventories + Stamina before we drain/read them.
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	empty._stamina.drain(1000.0)  # bottom out -> exhausted, no sprint boost for the drive

	_drive_right(walker, false)
	_drive_right(sprinter, true)
	_drive_right(empty, true)
	_drive_right(heavy_walk, false)
	_drive_right(heavy_sprint, true)

	var wx: float = walker.global_position.x
	var sx: float = sprinter.global_position.x
	var ex: float = empty.global_position.x
	var hwx: float = heavy_walk.global_position.x
	var hsx: float = heavy_sprint.global_position.x
	for _i in range(SPRINT_FRAMES):
		await ctx.tree.physics_frame
	var walk_dx: float = walker.global_position.x - wx
	var sprint_dx: float = sprinter.global_position.x - sx
	var empty_dx: float = empty.global_position.x - ex
	var heavy_walk_dx: float = heavy_walk.global_position.x - hwx
	var heavy_sprint_dx: float = heavy_sprint.global_position.x - hsx

	ctx.check(sprint_dx > walk_dx * 1.1,
		"sprinting travels measurably farther than walking (sprint " + str(int(sprint_dx)) + " > walk " + str(int(walk_dx)) + ")",
		"sprint gave no distance advantage (sprint " + str(int(sprint_dx)) + " vs walk " + str(int(walk_dx)) + ")")
	ctx.check(sprinter._stamina.ratio() < 0.95,
		"sprinting DRAINED stamina (ratio " + str(sprinter._stamina.ratio()) + ")",
		"sprinting did not drain stamina (ratio " + str(sprinter._stamina.ratio()) + ")")
	ctx.check(empty_dx < sprint_dx and empty_dx <= walk_dx * 1.15,
		"empty-stamina sprint gives NO boost -- moves like a walker (empty " + str(int(empty_dx)) + " ~ walk " + str(int(walk_dx)) + ")",
		"empty-stamina player still got a sprint boost (empty " + str(int(empty_dx)) + " vs walk " + str(int(walk_dx)) + ")")
	ctx.check(heavy_walk_dx < heavy_sprint_dx and heavy_sprint_dx < sprint_dx,
		"sprint STACKS with encumbrance: overloaded-walk < overloaded-sprint < light-sprint (" + str(int(heavy_walk_dx)) + " < " + str(int(heavy_sprint_dx)) + " < " + str(int(sprint_dx)) + ")",
		"encumbrance/sprint stack wrong (heavy_walk " + str(int(heavy_walk_dx)) + " heavy_sprint " + str(int(heavy_sprint_dx)) + " sprint " + str(int(sprint_dx)) + ")")

	for p in [walker, sprinter, empty, heavy_walk, heavy_sprint]:
		p.input_override = null
		p.queue_free()
	await ctx.settle_idle()


## Phase 3 -- Dodge. Uses a fresh dodger (distance + cost + cooldown), a low-stamina player (blocked
## under cost), and a stationary enemy (i-frames deal 0 damage mid-dash, and the dash phases through
## the enemy body). All input_override + direct state, remote coords.
func _dodge_legs(ctx: TestContext) -> void:
	var player_scene: PackedScene = load("res://player/player.tscn")
	var enemy_scene: PackedScene = load("res://enemy/enemy.tscn")
	if player_scene == null or enemy_scene == null:
		ctx.check(false, "", "player.tscn/enemy.tscn failed to load (dodge legs)")
		return

	# --- a+b. A dodge dashes ~the dash distance in the held direction and costs dodge_cost ---------
	var d: Player = _spawn(ctx, player_scene, Vector2(30000, 30000))
	d.facing = Vector2.RIGHT
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	var start_stam: float = d._stamina.current
	var fi: FrameInput = FrameInput.new()
	fi.dodge = true  # idle move -> dash direction falls back to facing (RIGHT)
	d.input_override = fi
	var dx0: float = d.global_position.x
	await ctx.tree.physics_frame  # dash starts + first step
	fi.dodge = false  # drop the edge so it cannot retrigger after the dash
	for _i in range(15):
		await ctx.tree.physics_frame  # let the ~0.18s dash finish
	var dash_dx: float = d.global_position.x - dx0
	ctx.check(dash_dx > 30.0 and dash_dx < 100.0,
		"dodge dashed ~1.3 tiles in the facing direction (dx " + str(int(dash_dx)) + " px)",
		"dodge dash distance out of range (dx " + str(int(dash_dx)) + " px)")
	ctx.check(is_equal_approx(start_stam - d._stamina.current, 30.0),
		"dodge cost exactly dodge_cost (30) stamina (" + str(start_stam) + " -> " + str(d._stamina.current) + ")",
		"dodge stamina cost wrong (" + str(start_stam) + " -> " + str(d._stamina.current) + ")")

	# --- f. Cooldown gates an immediate second dodge (dash just ended, cooldown still running) -----
	var cd_stam: float = d._stamina.current
	fi.dodge = true
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	ctx.check(not d._locomotion._dodging and is_equal_approx(d._stamina.current, cd_stam),
		"a second dodge is BLOCKED during the cooldown (no dash, no spend; stamina " + str(d._stamina.current) + ")",
		"dodge cooldown did not block the re-dodge (dodging=" + str(d._locomotion._dodging) + " stamina " + str(d._stamina.current) + ")")
	d.input_override = null
	d.queue_free()

	# --- c. A dodge is blocked when stamina < dodge_cost (no dash, no spend) -----------------------
	var low: Player = _spawn(ctx, player_scene, Vector2(-30000, 30000))
	low.facing = Vector2.RIGHT
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	low._stamina.current = 10.0  # below dodge_cost 30
	var lfi: FrameInput = FrameInput.new()
	lfi.dodge = true
	low.input_override = lfi
	var lx0: float = low.global_position.x
	await ctx.tree.physics_frame
	ctx.check(not low._locomotion._dodging and is_equal_approx(low._stamina.current, 10.0)
			and absf(low.global_position.x - lx0) < 2.0,
		"dodge under cost is refused -- no dash, no spend (stamina " + str(low._stamina.current) + ")",
		"dodge under cost wrongly fired (dodging=" + str(low._locomotion._dodging) + " stamina " + str(low._stamina.current) + " moved " + str(low.global_position.x - lx0) + ")")
	low.input_override = null
	low.queue_free()

	# --- d. I-frames: a hit landing DURING the dash deals 0 damage; after the dash it lands --------
	var iv: Player = _spawn(ctx, player_scene, Vector2(30000, -30000))
	iv.facing = Vector2.RIGHT
	var iv_health: HealthComponent = iv.get_node("HealthComponent") as HealthComponent
	var iv_hurtbox: Hurtbox = iv.get_node("Hurtbox") as Hurtbox
	var foe: Enemy = enemy_scene.instantiate() as Enemy
	foe.stationary = true
	ctx.tree.root.add_child(foe)
	foe.global_position = Vector2(35000, -30000)
	var foe_atk: Hitbox = foe.get_node("AttackHitbox") as Hitbox
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	var ifi: FrameInput = FrameInput.new()
	ifi.dodge = true
	iv.input_override = ifi
	await ctx.tree.physics_frame  # dash active this frame
	ifi.dodge = false
	var hp_before: int = iv_health.current_health
	ctx.check(iv._locomotion._dodging and iv_hurtbox.dodge_invincible,
		"dash raises the dodge i-frames (dodge_invincible true)",
		"dash did not raise dodge i-frames (dodging=" + str(iv._locomotion._dodging) + " inv=" + str(iv_hurtbox.dodge_invincible) + ")")
	iv_hurtbox._on_area_entered(foe_atk)  # a hit mid-dash
	ctx.check(iv_health.current_health == hp_before,
		"a hit during the dash deals 0 damage (i-frames) (HP still " + str(iv_health.current_health) + ")",
		"dash i-frames failed -- player took damage mid-dash (" + str(hp_before) + " -> " + str(iv_health.current_health) + ")")
	for _i in range(15):
		await ctx.tree.physics_frame  # dash ends -> i-frames drop
	ctx.check(not iv._locomotion._dodging and not iv_hurtbox.dodge_invincible,
		"dodge i-frames restored after the dash (dodge_invincible false)",
		"dodge i-frames stuck on after the dash (inv=" + str(iv_hurtbox.dodge_invincible) + ")")
	var hp_after_dash: int = iv_health.current_health
	iv_hurtbox._on_area_entered(foe_atk)  # same hit, now outside i-frames -> lands
	ctx.check(iv_health.current_health < hp_after_dash,
		"a hit AFTER the dash lands normally (i-frames were dodge-only) (" + str(hp_after_dash) + " -> " + str(iv_health.current_health) + ")",
		"post-dash hit did not land (" + str(hp_after_dash) + " -> " + str(iv_health.current_health) + ")")
	iv.input_override = null
	iv.queue_free()
	foe.queue_free()

	# --- e. Phase-through: the dash passes THROUGH a live enemy body and the mask is restored ------
	var ph: Player = _spawn(ctx, player_scene, Vector2(-30000, -30000))
	ph.facing = Vector2.RIGHT
	var blocker: Enemy = enemy_scene.instantiate() as Enemy
	blocker.stationary = true
	ctx.tree.root.add_child(blocker)
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame
	blocker.global_position = ph.global_position + Vector2(20, 0)  # just to the right, bodies near-touching
	# Freeze the blocker's physics so it holds position -- its collision SHAPE stays solid (a
	# non-phased dash would still be blocked by it), but it cannot be shoved along by the overlap,
	# which would otherwise carry it ahead of the player and defeat the "ended past it" read.
	blocker.set_physics_process(false)
	var saved_mask: int = ph.collision_mask
	var pfi: FrameInput = FrameInput.new()
	pfi.move = Vector2.RIGHT
	pfi.dodge = true
	ph.input_override = pfi
	await ctx.tree.physics_frame
	pfi.dodge = false
	for _i in range(15):
		await ctx.tree.physics_frame
	ctx.check(ph.global_position.x > blocker.global_position.x + 5.0,
		"dodge PHASED through the enemy body -- ended past it (player x " + str(int(ph.global_position.x)) + " > enemy x " + str(int(blocker.global_position.x)) + ")",
		"dodge did not phase through the enemy (player x " + str(int(ph.global_position.x)) + " vs enemy x " + str(int(blocker.global_position.x)) + ")")
	ctx.check(ph.collision_mask == saved_mask,
		"collision_mask restored after the dash (mask " + str(ph.collision_mask) + " == " + str(saved_mask) + ")",
		"collision_mask not restored after the dash (mask " + str(ph.collision_mask) + " != " + str(saved_mask) + ")")
	ph.input_override = null
	ph.queue_free()
	blocker.queue_free()
	await ctx.settle_idle()


## Instantiate a magnet-off Player at `at` and add it to root. The caller settles physics frames
## before reading _ready-wired state (inventory, Stamina).
func _spawn(ctx: TestContext, scene: PackedScene, at: Vector2) -> Player:
	var p: Player = scene.instantiate() as Player
	p.pickup_radius = 0.0
	ctx.tree.root.add_child(p)
	p.global_position = at
	return p


## Point a player RIGHT via an injected FrameInput, with sprint held or not. The caller steps the
## shared frame loop; input_override keeps the drive deterministic (no keyboard).
func _drive_right(player: Player, sprint: bool) -> void:
	var fi: FrameInput = FrameInput.new()
	fi.move = Vector2.RIGHT
	fi.sprint = sprint
	player.input_override = fi

# Verified against: Godot 4.7.1 (2026-07-19)
