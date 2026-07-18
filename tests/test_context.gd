class_name TestContext extends RefCounted
## Shared context for the split Sword Slash smoke suite (see tests/smoke_slash.gd for
## the orchestrator + the rationale behind the split). Holds:
##   * the SceneTree handle (`tree`) so RefCounted modules can await physics frames and
##     reach `root` / `create_timer` without themselves being a SceneTree;
##   * the aggregate pass/fail latch (`all_pass`) and the moved `check()` assertion;
##   * the shared main.tscn refs the ORDERED gameplay modules reuse (test_combat.gd
##     then test_durability_tools.gd run against the SAME instance, in the original leg
##     order, so cross-leg state -- resets, tool equips, positions -- is preserved);
##   * the gameplay strike helpers `slash_target` / `lunge_hit`, called by both the
##     combat and durability modules.
## Each module is `class_name X extends RefCounted` with an awaitable `run(ctx)`; the
## orchestrator does `await mod.run(ctx)`.

var tree: SceneTree
var all_pass: bool = true

# Shared scene refs -- populated ONCE by the orchestrator, reused by the ordered
# gameplay modules (test_combat.gd, then test_durability_tools.gd).
var main: Node
var player: Player
var enemy: Enemy
var dummy: Enemy
var player_health: HealthComponent
var enemy_health: HealthComponent
var dummy_health: HealthComponent
var sword_dura: DurabilityComponent
var axe_dura: DurabilityComponent
var pickaxe_dura: DurabilityComponent


## Assert a condition, printing a [PASS]/[FAIL] line and latching overall status.
func check(cond: bool, pass_msg: String, fail_msg: String) -> void:
	if cond:
		print("[PASS] ", pass_msg)
	else:
		all_pass = false
		print("[FAIL] ", fail_msg)


## Await a single physics frame via the shared tree (so RefCounted modules can step
## physics without being a SceneTree themselves).
func frame() -> void:
	await tree.physics_frame


## Reposition the player, drain any in-flight swing, clear the target's i-frames,
## reset to a clean arc (index 0, no lunge drift), then slash once and settle. Used
## for the repeated armored-dummy hits where a stable, repeatable strike is needed.
func slash_target(player: Player, at: Vector2) -> void:
	for _i in range(30):
		if not player._attacking:
			break
		await tree.physics_frame
	player.global_position = at
	player.facing = Vector2.RIGHT
	player._knockback = Vector2.ZERO
	player._combo_index = 0
	for _i in range(10):  # let the target's i-frame window (0.1s) expire
		await tree.physics_frame
	await player.attack()
	for _i in range(4):
		await tree.physics_frame


## Same shape as slash_target, but forces combo hit 3 (the LUNGE: blade held fixed
## at `dir` for the whole swing window) instead of the arc. Required for a reliable
## hit against a SMALL hurtbox headless -- the HEADLESS TIMING TRAP: an arc-sweep
## tween runs on idle-frame time while Area2D overlap samples on physics frames, so
## against a small target (flesh enemy, r16) the whole sweep can fall between two
## physics samples and silently miss (recipes/health-and-damage.md, and leg a).
func lunge_hit(player: Player, at: Vector2, dir: Vector2) -> void:
	for _i in range(30):
		if not player._attacking:
			break
		await tree.physics_frame
	player.global_position = at
	player.facing = dir
	player._knockback = Vector2.ZERO
	player._combo_index = 2
	for _i in range(10):  # let the target's i-frame window expire
		await tree.physics_frame
	await player.attack()
	for _i in range(4):
		await tree.physics_frame

# Verified against: Godot 4.7.1 (2026-07-17)
