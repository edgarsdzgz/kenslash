class_name Projectile
extends Hitbox
## A REUSABLE moving projectile (design-enemies.md "Shared tech -- Projectile"): a small Area2D that
## travels in a straight line and damages whatever its strike lands on. Built for the Spitter's ranged
## shot NOW, but deliberately generic -- future ranged enemies and an eventual player bow/thrown weapon
## reuse it verbatim by calling setup() with a different direction/speed/atk (and, for a player weapon,
## a different collision layer authored on its own scene). Nothing here is Spitter-specific.
##
## IT IS A Hitbox (components/hitbox.gd) by inheritance, so it carries the SAME `atk` + `knockback`
## strike data an enemy's contact AttackHitbox does, and the PLAYER's Hurtbox resolves it through the
## exact same one-way Hitbox->Hurtbox path (hurtbox.gd `_on_area_entered` casts the incoming Area2D to
## Hitbox). That is why the scene sits on collision_layer 32 -- the SAME ENEMY-ATTACK layer the contact
## AttackHitbox uses (enemy.tscn / charger.tscn) -- so the player's Hurtbox (mask 32) detects+damages it
## with NO change to the player or any existing scene. `durability`/`power` stay 0/null: like fists, a
## projectile never wears a weapon, so the Hurtbox skips System 2 and applies pure ATK-vs-DEF HP.
##
## CULLED like a world object (world/drop.gd): it is BOUNDED and LEAK-FREE. It queue_free()s on ANY of
## -- hitting the player (its body_entered fires on the player body layer; the player's Hurtbox has
## already resolved the damage on layer 32 that same tick), exceeding `max_range` of travel, or
## exceeding `max_lifetime`. Deterministic: it moves by a fixed velocity each PHYSICS frame with no RNG
## and no Time-of-day, so the headless suite steps it exactly.
##
## Detection wiring: the root Area2D is BOTH monitorable (layer 32 -> the player's Hurtbox sees it) AND
## monitoring (mask 2 = the player BODY layer -> its own body_entered fires so it can self-despawn on a
## hit). Enemies live on layer 4, absent from mask 2, so a shot never despawns on a friendly body.

## Max straight-line travel in px before it culls itself (out of relevance). Bounds a shot that never
## hits anything -- the projectile analogue of drop.gd's lifetime cap. Tunable per spawn if needed.
@export var max_range: float = 900.0
## Hard lifetime cap in seconds -- a second, time-based cull so a near-zero-speed shot still despawns.
@export var max_lifetime: float = 6.0

## Straight-line velocity (px/sec), set once by setup(); the shot never re-homes.
var _velocity: Vector2 = Vector2.ZERO
## Distance travelled so far, accumulated per physics frame -- drives the range cull.
var _travelled: float = 0.0
## Seconds alive while loaded (same "age only while a node" logic as drop.gd) -- drives the time cull.
var _age: float = 0.0
## Latched the instant it is spent, so a hit + a same-frame cull cannot double-free.
var _spent: bool = false

@onready var _body: Polygon2D = $Body


func _ready() -> void:
	# Join a group so tests (and any future cleanup pass) can enumerate live shots with one query --
	# the same group-membership contract drops/enemies use. Pure membership; adds no node.
	add_to_group("projectiles")
	# Self-despawn on contact with the PLAYER body (layer 2, our mask). The player's own Hurtbox
	# independently resolves this projectile's atk on layer 32 that same tick -- so the hit registers
	# AND the shot vanishes.
	body_entered.connect(_on_body_entered)


## Aim + arm the shot, then let _physics_process fly it. `direction` is normalised here (a zero
## direction defaults to RIGHT so a mis-call still travels rather than sitting live forever). `p_atk`
## and `p_knockback` become the Hitbox strike data the player's Hurtbox reads. `tint` colours the body
## so different callers (a violet Spitter shot now, a future arrow) read distinct. Callable directly.
func setup(direction: Vector2, speed: float, p_atk: int, p_knockback: float = 0.0, tint: Color = Color(0.62, 0.35, 0.95, 1.0)) -> void:
	var dir: Vector2 = direction
	if dir.length() > 0.001:
		dir = dir.normalized()
	else:
		dir = Vector2.RIGHT
	_velocity = dir * speed
	atk = p_atk
	knockback = p_knockback
	rotation = dir.angle()
	if _body != null:
		_body.color = tint


## Fly straight on the FIXED physics step (deterministic for the headless suite), accumulate travel +
## age, and cull once either bound is exceeded. Bails while spent so a freed shot never re-counts.
func _physics_process(delta: float) -> void:
	if _spent:
		return
	var step: Vector2 = _velocity * delta
	global_position += step
	_travelled += step.length()
	_age += delta
	if _travelled >= max_range or _age >= max_lifetime:
		_despawn()


## Player-body contact: the player's Hurtbox has already resolved the hit on layer 32 this tick, so the
## shot's job is done -- cull it. `_body_node` is unused (any body on our mask is the player).
func _on_body_entered(_body_node: Node2D) -> void:
	_despawn()


## Single cull path -- latch spent (so a hit + a same-frame range/lifetime cull cannot double-free) and
## queue_free. queue_free is deferred; _spent gates every re-entry until the node is actually gone.
func _despawn() -> void:
	if _spent:
		return
	_spent = true
	queue_free()

# Verified against: Godot 4.7.1 (2026-07-19)
