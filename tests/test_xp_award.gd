class_name TestXpAward extends RefCounted
## XP AWARD HOOKS + HUD readout (plan-epic1-parts.md Phase 1, Part 1.2). Part 1.1 proved the Progression
## component banks XP/level/points deterministically; THIS module proves the gameplay HOOKS feed it the
## right integer awards and the HUD reflects the result. It exercises every award seam end to end:
##   * KILL       -- an enemy's death (enemy.gd _on_died) grants its exact xp_reward to the player;
##   * FELL       -- felling a tree (tree.gd _on_broke) grants exactly XP_PER_FELL, ONCE;
##   * MINE       -- N affecting mines on a rock (rock.gd) grant exactly N * XP_PER_MINE (one per chip);
##   * FORAGE     -- foraging (forageable.gd interact) grants exactly XP_PER_FORAGE to the picker;
##   * BOUNDARY   -- a scripted forage sequence CROSSES the level-2 threshold and banks the right points;
##   * HUD        -- the HUD's level/xp line reflects the live progression (readout value, not pixels).
##
## Determinism: every award is an integer CONSTANT (no Time/OS/RNG), so each leg asserts an EXACT value.
## The kill/fell/mine hooks resolve the recipient through the "player" group (single-player: the local
## player) exactly as the game does, so those legs read that SAME group-resolved player and assert the
## DELTA -- robust to whatever XP that shared player already banked in earlier legs. The forage/boundary
## legs use fresh REMOTE players (forageable.interact awards the passed-in player directly, so the target
## is fully controlled). Self-contained: own holders/players/enemies/harvestables at a remote region,
## freed per leg. Registered in tests/smoke_slash.gd, mirroring tests/test_progression.gd.

## Remote region for this module's own nodes, clear of every other self-contained module's coords
## (test_progression uses 52000; harvest uses <=1000; this sits far past them).
const BASE: Vector2 = Vector2(60000, 0)

const ENEMY_SCENE: PackedScene = preload("res://enemy/enemy.tscn")
const TREE_SCENE: PackedScene = preload("res://world/tree.tscn")
const ROCK_SCENE: PackedScene = preload("res://world/rock.tscn")
const PEBBLE_SCENE: PackedScene = preload("res://world/pebble.tscn")
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")


func run(ctx: TestContext) -> void:
	print("[xp-award] --- Part 1.2: kill / fell / mine / forage XP hooks + level-boundary + HUD readout ---")
	await _kill_leg(ctx)
	await _fell_leg(ctx)
	await _mine_leg(ctx)
	await _forage_leg(ctx)
	await _boundary_leg(ctx)
	await _hud_leg(ctx)


## KILL: an enemy that dies grants its exact xp_reward to the player resolved through the "player" group
## (the same group enemy.gd _on_died awards through). `died` fires synchronously inside take_damage and the
## award runs before any await in _on_died, so the XP is banked the instant the lethal blow lands.
func _kill_leg(ctx: TestContext) -> void:
	var holder: Node2D = Node2D.new()
	ctx.tree.root.add_child(holder)
	var enemy: Enemy = ENEMY_SCENE.instantiate() as Enemy
	holder.add_child(enemy)
	enemy.global_position = BASE
	await ctx.tree.physics_frame

	var gp: Player = ctx.tree.get_first_node_in_group("player") as Player
	var reward: int = enemy.xp_reward
	var before: int = gp._progression.xp if gp != null else -1
	var eh: HealthComponent = enemy.get_node("HealthComponent") as HealthComponent
	eh.take_damage(eh.current_health)  # guaranteed lethal -> died -> _on_died awards synchronously
	ctx.check(gp != null and gp._progression.xp == before + reward and reward == 20,
		"killing an enemy grants its exact xp_reward (%d) to the player's progression (%d -> %d)" % [reward, before, gp._progression.xp if gp != null else -1],
		"kill XP wrong (before %d after %d reward %d)" % [before, gp._progression.xp if gp != null else -1, reward])

	holder.queue_free()
	await ctx.tree.physics_frame


## FELL: felling a tree (integrity -> 0 -> _on_broke) grants exactly XP_PER_FELL, ONCE, to the group
## player. The wood-burst is deferred by the fall animation, but the XP is awarded on the felling frame,
## so we read it immediately after driving integrity to 0. XP_PER_FELL is read straight off tree.gd's
## script constant map (tree.gd has no class_name -- `Tree` collides with Godot's native control).
func _fell_leg(ctx: TestContext) -> void:
	var holder: Node2D = Node2D.new()
	ctx.tree.root.add_child(holder)
	var tree_node: StaticBody2D = TREE_SCENE.instantiate() as StaticBody2D
	holder.add_child(tree_node)
	tree_node.global_position = BASE + Vector2(1000, 0)
	await ctx.tree.physics_frame

	var fell_xp: int = int(tree_node.get_script().get_script_constant_map()["XP_PER_FELL"])
	var gp: Player = ctx.tree.get_first_node_in_group("player") as Player
	var before: int = gp._progression.xp if gp != null else -1
	var tree_mat: DurabilityComponent = tree_node.get_node("Material") as DurabilityComponent
	tree_mat.wear(tree_mat.current_durability)  # integrity -> 0 -> felled -> award once
	ctx.check(gp != null and gp._progression.xp == before + fell_xp and fell_xp == 15,
		"felling a tree grants exactly XP_PER_FELL (%d) once (%d -> %d)" % [fell_xp, before, gp._progression.xp if gp != null else -1],
		"tree-fell XP wrong (before %d after %d fell_xp %d)" % [before, gp._progression.xp if gp != null else -1, fell_xp])

	holder.queue_free()
	await ctx.tree.physics_frame


## MINE: each AFFECTING mine chips a stone AND grants XP_PER_MINE (fired in _on_integrity_changed, the
## mine-to-0 hit included), so N mines on an integrity-N rock grant exactly N * XP_PER_MINE to the group
## player. A Band-C whiff never reaches that hook, so it grants no XP either (covered by the yield gate).
func _mine_leg(ctx: TestContext) -> void:
	var holder: Node2D = Node2D.new()
	ctx.tree.root.add_child(holder)
	var rock_node: Rock = ROCK_SCENE.instantiate() as Rock
	holder.add_child(rock_node)
	rock_node.global_position = BASE + Vector2(2000, 0)
	await ctx.tree.physics_frame

	var gp: Player = ctx.tree.get_first_node_in_group("player") as Player
	var before: int = gp._progression.xp if gp != null else -1
	var rock_mat: DurabilityComponent = rock_node.get_node("Material") as DurabilityComponent
	var n_hits: int = rock_mat.current_durability  # integrity N
	for _i in range(n_hits):
		rock_mat.wear(1)
		await ctx.tree.physics_frame
	var expected: int = n_hits * Rock.XP_PER_MINE
	ctx.check(gp != null and gp._progression.xp == before + expected and Rock.XP_PER_MINE == 5,
		"mining a rock grants XP_PER_MINE (%d) per affecting mine -- %d mines banked %d (%d -> %d)" % [Rock.XP_PER_MINE, n_hits, expected, before, gp._progression.xp if gp != null else -1],
		"rock-mine XP wrong (before %d after %d expected +%d)" % [before, gp._progression.xp if gp != null else -1, expected])

	holder.queue_free()
	await ctx.tree.physics_frame


## FORAGE: foraging grants XP_PER_FORAGE to the PICKER. forageable.interact(player) awards the passed-in
## player directly (no group lookup -- the Interaction subsystem already has the player), so this leg uses
## a FRESH remote player and asserts its exact XP gain from a single pebble gather.
func _forage_leg(ctx: TestContext) -> void:
	var holder: Node2D = Node2D.new()
	ctx.tree.root.add_child(holder)
	var player: Player = PLAYER_SCENE.instantiate() as Player
	player.pickup_radius = 0.0  # inert like the other remote players
	holder.add_child(player)
	player.global_position = BASE + Vector2(3000, 0)
	await ctx.settle_idle()
	await ctx.tree.physics_frame

	var forage_xp: int = Forageable.XP_PER_FORAGE
	var before: int = player._progression.xp
	var pebble: Pebble = PEBBLE_SCENE.instantiate() as Pebble
	holder.add_child(pebble)
	pebble.global_position = player.global_position
	await ctx.tree.physics_frame
	pebble.interact(player)  # gather -> collect the stone + award XP_PER_FORAGE to THIS player
	await ctx.tree.physics_frame
	ctx.check(player._progression.xp == before + forage_xp and forage_xp == 3,
		"foraging a pebble grants exactly XP_PER_FORAGE (%d) to the picker (%d -> %d)" % [forage_xp, before, player._progression.xp],
		"forage XP wrong (before %d after %d forage_xp %d)" % [before, player._progression.xp, forage_xp])

	holder.queue_free()
	await ctx.tree.physics_frame


## BOUNDARY: a scripted sequence of REAL forage awards crosses the level-2 threshold (100 xp) and banks
## the right points. With XP_PER_FORAGE=3 the first crossing lands at 34 forages -> 102 xp -> level 2,
## which must bank exactly +1 talent + +1 blueprint (one qualifying level-up, Track A + Track B). Driven
## on a fresh controlled player so the accumulation starts from a known 0. Proves the hooks integrate with
## the Progression curve across a boundary, not just a single flat award.
func _boundary_leg(ctx: TestContext) -> void:
	var holder: Node2D = Node2D.new()
	ctx.tree.root.add_child(holder)
	var player: Player = PLAYER_SCENE.instantiate() as Player
	player.pickup_radius = 0.0
	holder.add_child(player)
	player.global_position = BASE + Vector2(4000, 0)
	await ctx.settle_idle()
	await ctx.tree.physics_frame

	var forage_xp: int = Forageable.XP_PER_FORAGE
	var guard: int = 0
	while player._progression.level < 2 and guard < 100:
		var pebble: Pebble = PEBBLE_SCENE.instantiate() as Pebble
		holder.add_child(pebble)
		pebble.interact(player)  # +XP_PER_FORAGE each, through the real forage hook
		await ctx.tree.physics_frame
		guard += 1

	var crossed_xp: int = guard * forage_xp  # exact xp at the first crossing (34 * 3 = 102)
	ctx.check(player._progression.level == 2 and player._progression.xp == crossed_xp
			and player._progression.talent_points == 1 and player._progression.blueprint_points == 1,
		"a scripted forage sequence crossed the level-2 boundary (%d forages -> %d xp) and banked exactly 1 talent + 1 blueprint" % [guard, crossed_xp],
		"boundary crossing banked wrong (L%d xp%d T%d B%d after %d forages)" % [player._progression.level, player._progression.xp, player._progression.talent_points, player._progression.blueprint_points, guard])

	holder.queue_free()
	await ctx.tree.physics_frame


## HUD: the HUD's level/xp line reflects the live Progression (readout value + structure, not rendered
## pixels -- Control nodes exist and _process runs headless; only rendering is absent). Uses the shipped
## streaming_world.tscn (which hosts + binds the HUD), drives the bound player's XP directly across a
## level-up, and asserts the HUD text follows via its per-frame read (the player never pushes into the HUD).
func _hud_leg(ctx: TestContext) -> void:
	var sw_scene: PackedScene = load("res://world/streaming_world.tscn")
	ctx.check(sw_scene != null, "streaming_world.tscn loads (hosts the level/xp HUD readout)", "streaming_world.tscn failed to load")
	if sw_scene == null:
		return
	var sw: Node2D = sw_scene.instantiate() as Node2D
	ctx.tree.root.add_child(sw)
	var player: Player = sw.get_node("Player") as Player
	player.pickup_radius = 0.0  # presentation test, not pickup -- suppress the origin-litter magnet
	await ctx.settle_idle()
	await ctx.settle_idle()

	var hud: Hud = sw.get_node("HUD") as Hud
	ctx.check(hud != null and hud.level_text() == "Lv 1  XP 0",
		"HUD level/xp readout starts at 'Lv 1  XP 0' (\"" + (hud.level_text() if hud != null else "<null>") + "\")",
		"HUD level/xp readout not at the fresh default (\"" + (hud.level_text() if hud != null else "<null>") + "\")")

	# Award 100 xp -> exactly the level-2 threshold; the per-frame HUD pass shows the new level + xp.
	player.award_xp(100)
	await ctx.settle_idle()
	ctx.check(player._progression.level == 2 and hud.level_text() == "Lv 2  XP 100",
		"HUD level/xp readout follows the award across a level-up (\"" + hud.level_text() + "\")",
		"HUD level/xp readout did not reflect the award (\"" + hud.level_text() + "\")")

	sw.queue_free()
	await ctx.settle_idle()

# Verified against: Godot 4.7.1 (2026-07-19)
