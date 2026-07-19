class_name TestProgression extends RefCounted
## Progression component + deterministic level curve (plan-core-loop.md Phase 1, Part 1.1; the "spine").
## Proves the CHARACTER-data XP/level model (components/progression.gd) is pure, deterministic integer
## math and that the TWO currencies bank by their two separate Icarus rules (design-multiplayer.md):
##   * the level curve is DETERMINISTIC -- the same xp yields the same level twice, with no Time/RNG;
##   * crossing each documented threshold increments the level by exactly one;
##   * every level-up banks the EXACT talent + blueprint counts (1 each here), and a multi-level jump
##     banks the correct CUMULATIVE totals (award depends only on the level reached, not on the path);
##   * the TALENT_LEVEL_CAP holds -- talent points STOP at the cap (Track A, level-gated/capped) while
##     blueprint points KEEP accruing (Track B continues).
## Also checks a fresh player carries a wired `_progression` at the default state (level 1, no points).
## Self-contained: the currency math needs no scene (pure component instances); the wiring leg builds
## its own holder + player at a REMOTE coord, frees it, and touches no shared game state. Registered in
## tests/smoke_slash.gd, mirroring tests/test_elevation.gd.

## Remote region for the wiring leg, clear of every other self-contained module's coords.
const HOME: Vector2 = Vector2(52000, 0)


func run(ctx: TestContext) -> void:
	print("[progression] --- deterministic level curve + two-currency banking (talent cap holds) ---")
	_curve_tests(ctx)
	_award_tests(ctx)
	await _wiring_leg(ctx)


## PURE curve tests -- no scene, no await. The documented thresholds (BASE_XP=100, XP_STEP=20):
## level 1 -> 0, 2 -> 100, 3 -> 220, 4 -> 360, 5 -> 520, 6 -> 700.
func _curve_tests(ctx: TestContext) -> void:
	var p: Progression = Progression.new()

	# Fresh state: level 1, zero xp, zero banked points.
	ctx.check(p.xp == 0 and p.level == 1 and p.talent_points == 0 and p.blueprint_points == 0,
		"fresh Progression: xp 0, level 1, talent 0, blueprint 0",
		"fresh Progression not at the default state (xp %d level %d T %d B %d)" % [p.xp, p.level, p.talent_points, p.blueprint_points])

	# level_for_xp is a pure function of xp -- exact boundaries at each documented threshold.
	ctx.check(p.level_for_xp(0) == 1 and p.level_for_xp(99) == 1,
		"level_for_xp: 0..99 xp -> level 1 (below the level-2 threshold of 100)",
		"level_for_xp did not stay level 1 below 100 xp")
	ctx.check(p.level_for_xp(100) == 2 and p.level_for_xp(219) == 2,
		"level_for_xp: 100..219 xp -> level 2 (threshold 100, next at 220)",
		"level_for_xp wrong across the level-2 band")
	ctx.check(p.level_for_xp(220) == 3 and p.level_for_xp(360) == 4 and p.level_for_xp(520) == 5 and p.level_for_xp(700) == 6,
		"level_for_xp hits each documented threshold exactly (220->3, 360->4, 520->5, 700->6)",
		"level_for_xp missed a documented threshold")

	# DETERMINISM: the same xp yields the same level, twice, with no state between calls.
	ctx.check(p.level_for_xp(521) == p.level_for_xp(521) and p.level_for_xp(521) == 5,
		"level curve is deterministic: level_for_xp(521) == level_for_xp(521) == 5 (same xp -> same level)",
		"level curve was not deterministic for xp 521")

	# Two independently-fed instances that reach the SAME total xp land on the SAME level + points --
	# award depends only on the xp/level reached, never on how it arrived (path-independence).
	var a: Progression = Progression.new()
	var b: Progression = Progression.new()
	a.add_xp(700)                 # one big jump to the level-6 threshold
	b.add_xp(360); b.add_xp(340)  # two adds summing to 700
	ctx.check(a.level == b.level and a.level == 6 and a.xp == b.xp and a.xp == 700
			and a.talent_points == b.talent_points and a.blueprint_points == b.blueprint_points,
		"same total xp -> same level + same banked points regardless of the add path (both level 6)",
		"progression diverged by add path (a: L%d T%d B%d / b: L%d T%d B%d)" % [a.level, a.talent_points, a.blueprint_points, b.level, b.talent_points, b.blueprint_points])


## Point-award tests -- crossing thresholds one at a time, a multi-level jump, and the talent cap.
func _award_tests(ctx: TestContext) -> void:
	# Cross each threshold in turn: every single level-up banks exactly +1 talent and +1 blueprint.
	var p: Progression = Progression.new()
	p.add_xp(100)  # -> level 2
	ctx.check(p.level == 2 and p.talent_points == 1 and p.blueprint_points == 1,
		"crossing to level 2 increments level and banks exactly 1 talent + 1 blueprint",
		"level-2 crossing wrong (L%d T%d B%d)" % [p.level, p.talent_points, p.blueprint_points])
	p.add_xp(120)  # 100 -> 220 -> level 3
	ctx.check(p.level == 3 and p.talent_points == 2 and p.blueprint_points == 2,
		"crossing to level 3 increments level and banks another 1 talent + 1 blueprint (T2 B2)",
		"level-3 crossing wrong (L%d T%d B%d)" % [p.level, p.talent_points, p.blueprint_points])

	# XP that does NOT cross a threshold banks nothing and does not move the level.
	p.add_xp(50)   # 220 -> 270, still below 360
	ctx.check(p.level == 3 and p.talent_points == 2 and p.blueprint_points == 2 and p.xp == 270,
		"sub-threshold XP accrues to xp but does not level up or bank points (still L3 T2 B2, xp 270)",
		"sub-threshold XP wrongly leveled/banked (L%d T%d B%d xp %d)" % [p.level, p.talent_points, p.blueprint_points, p.xp])

	# MULTI-LEVEL jump from level 1 straight to level 6 banks EACH crossed level once: 5 of each.
	var j: Progression = Progression.new()
	j.add_xp(700)  # level 1 -> 6 in one call (crosses levels 2,3,4,5,6)
	ctx.check(j.level == 6 and j.talent_points == 5 and j.blueprint_points == 5,
		"a multi-level add_xp (1 -> 6) banks the cumulative 5 talent + 5 blueprint (one per level)",
		"multi-level jump banked wrong totals (L%d T%d B%d)" % [j.level, j.talent_points, j.blueprint_points])

	# TALENT CAP: talent points are level-gated + capped (Track A); blueprint points continue (Track B).
	# TALENT_LEVEL_CAP is 50, so levels 2..50 grant talent (49 points), while blueprint keeps going.
	# `_threshold` mirrors the documented curve so the test can land on an EXACT level past the cap.
	var cap_level: int = Progression.TALENT_LEVEL_CAP  # 50
	var over: Progression = Progression.new()
	over.add_xp(_threshold(cap_level + 1))  # push to exactly level 51 (cap+1)
	ctx.check(over.level == cap_level + 1,
		"pushed progression to level %d (one past the talent cap of %d)" % [cap_level + 1, cap_level],
		"failed to reach level %d (got %d)" % [cap_level + 1, over.level])
	ctx.check(over.talent_points == cap_level - 1,
		"talent points capped at %d (levels 2..%d only) -- Track A is level-gated + capped" % [cap_level - 1, cap_level],
		"talent points not capped at %d (got %d)" % [cap_level - 1, over.talent_points])
	ctx.check(over.blueprint_points == cap_level,
		"blueprint points reached %d (levels 2..%d) -- Track B kept accruing past the talent cap" % [cap_level, cap_level + 1],
		"blueprint points did not keep accruing past the cap (got %d)" % over.blueprint_points)

	# One more level past the cap: talent stays put, blueprint still climbs (the two never entangle).
	var before_talent: int = over.talent_points
	over.add_xp(_threshold(cap_level + 2) - over.xp)  # advance exactly one more level
	ctx.check(over.level == cap_level + 2 and over.talent_points == before_talent and over.blueprint_points == cap_level + 1,
		"leveling past the cap again banks blueprint (+1) but NO talent (stays %d) -- currencies stay decoupled" % before_talent,
		"post-cap level-up entangled the currencies (L%d T%d B%d)" % [over.level, over.talent_points, over.blueprint_points])


## Player-wiring leg: a fresh player carries a wired `_progression` at the default state, and driving
## its component through the SAME public API banks correctly on the instance the player actually owns.
func _wiring_leg(ctx: TestContext) -> void:
	var player_scene: PackedScene = load("res://player/player.tscn")
	ctx.check(player_scene != null, "player.tscn loads (progression wiring)", "player.tscn failed to load")
	if player_scene == null:
		return

	var holder: Node2D = Node2D.new()
	ctx.tree.root.add_child(holder)
	var player: Player = player_scene.instantiate() as Player
	player.pickup_radius = 0.0  # inert like the other remote players; nothing to grab out here
	holder.add_child(player)
	player.global_position = HOME

	await ctx.settle_idle()
	await ctx.tree.physics_frame

	ctx.check(player._progression != null and player._progression.level == 1
			and player._progression.xp == 0 and player._progression.talent_points == 0
			and player._progression.blueprint_points == 0,
		"a fresh player carries a wired _progression at the default state (level 1, no xp, no points)",
		"player _progression missing or not at the default state")

	# Drive the player's OWN progression instance through the public API -- proves the wiring reaches a
	# live, mutable component (mirrors how the elevation leg drives player._elevation.set_z directly).
	player._progression.add_xp(220)  # level 1 -> 3
	ctx.check(player._progression.level == 3 and player._progression.talent_points == 2
			and player._progression.blueprint_points == 2,
		"driving the player's own _progression banks on the wired instance (220 xp -> L3 T2 B2)",
		"the player's wired _progression did not bank correctly (L%d T%d B%d)" % [player._progression.level, player._progression.talent_points, player._progression.blueprint_points])

	holder.queue_free()
	await ctx.tree.physics_frame


## Cumulative XP to REACH level `n`, mirroring the documented Progression curve (BASE_XP=100, XP_STEP=20)
## so this test can feed the EXACT xp that lands on a chosen level past the talent cap without reaching
## into the component's privates. Independent restatement of the formula -- if the curve is ever retuned
## the constants here must move in lockstep, which is the point (the test pins the documented numbers).
func _threshold(n: int) -> int:
	if n <= 1:
		return 0
	return Progression.BASE_XP * (n - 1) + Progression.XP_STEP * ((n - 1) * (n - 2) / 2)

# Verified against: Godot 4.7.1 (2026-07-19)
