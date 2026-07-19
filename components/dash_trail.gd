class_name DashTrail
extends RefCounted
## Afterimage "ghost" spawner for the dodge dash (design-controls.md "make the dodge READ as a
## dash"). During a dash, Locomotion calls spawn_ghost() at intervals; each call drops ONE
## lightweight, semi-transparent copy of the player's avatar Body at the player's CURRENT position,
## as a WORLD SIBLING, that then fades to nothing and frees itself -- a receding trail of the player
## along the dash path.
##
## Visual only. A ghost is a plain Polygon2D (no physics body, no group the gameplay reads, no data),
## so it perturbs no combat/streaming state; it self-frees on the fade, so it is leak-free like
## world/drop.gd and components/death_burst.gd. Spawned under the player's PARENT (not the player) so
## it stays put and fades WHERE it was dropped while the player dashes on -- and the player's own
## movement / free never disturbs a dropped ghost.
##
## Deterministic: the fade is a fixed-duration tween, no RNG / no wall-clock, so a headless run
## repeats byte-for-byte. RefCounted (no state) with a static spawn helper -- Locomotion keeps only a
## one-line trigger, and no node is added to any subsystem.

## Fade time for one ghost, in seconds. Short (~0.25s) so the trail is a quick smear, not a lingering
## clone -- and the test's leak-watchdog margin comfortably covers it.
const GHOST_FADE: float = 0.25
## Starting alpha of a ghost (before the fade to 0). Below 1 so each copy reads as a translucent
## afterimage, never mistaken for a second solid player.
const GHOST_ALPHA: float = 0.45


## Drop ONE afterimage of `body` at the player's current position, as a world sibling, and start its
## self-freeing fade. `player` is the CharacterBody2D (source of the world parent + position); `body`
## is the avatar Body Polygon2D whose CURRENT polygon / color / scale.x (the 4-directional look +
## facing flip) the ghost copies at this instant. No-ops safely if the player is not in the tree.
static func spawn_ghost(player: Node2D, body: Polygon2D) -> void:
	if player == null or body == null:
		return
	var world: Node = player.get_parent()
	if world == null:
		return
	var ghost: Polygon2D = Polygon2D.new()
	ghost.polygon = body.polygon
	var tint: Color = body.color
	tint.a = GHOST_ALPHA
	ghost.color = tint
	ghost.scale.x = body.scale.x
	# Sit just behind the player so the live avatar always reads on top of its own trail.
	ghost.z_index = -1
	ghost.add_to_group("dash_ghost")
	world.add_child(ghost)
	ghost.global_position = player.global_position
	# The ghost owns its own fade tween (it is a Node in the tree now): fade the copy out, then free
	# it -- a leak-free transient, no owner to reach back into.
	var tween: Tween = ghost.create_tween()
	tween.tween_property(ghost, "modulate:a", 0.0, GHOST_FADE).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_callback(ghost.queue_free)

# Verified against: Godot 4.7.1 (2026-07-19)
