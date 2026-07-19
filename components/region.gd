class_name Region
extends RefCounted
## Inside/outside region flag FOUNDATION (design-environment.md #3). An entity (the player now)
## carries a region state -- OUTSIDE by default -- that a RegionTrigger (world/region_trigger.gd)
## flips to INSIDE on entry and back to OUTSIDE on exit. This is ONLY the flag + the enter/exit
## wiring: later phases swap roof-fade / lighting / music off `changed`, but NONE of that is built
## now. RefCounted, NOT a Node, like the other subsystems, so it never perturbs the streaming
## node-count / orphan baselines.

## The two region states. INSIDE = under a roof / in a cave/building; OUTSIDE = the open world (default).
enum State { OUTSIDE, INSIDE }

## Emitted whenever the region actually changes -- the foundation hook a future roof-fade / lighting /
## music listener will subscribe to. Nothing subscribes yet.
signal changed(state: State)

## Current region. Starts OUTSIDE. Public so a test / future listener can read it directly.
var state: State = State.OUTSIDE


## Flip to INSIDE (true) or OUTSIDE (false). Idempotent: re-entering the same state emits nothing, so
## overlapping triggers do not spam `changed`.
func set_inside(inside: bool) -> void:
	var next: State = State.INSIDE if inside else State.OUTSIDE
	if next == state:
		return
	state = next
	changed.emit(state)


## Convenience predicate the future roof / lighting code (and the test) reads.
func is_inside() -> bool:
	return state == State.INSIDE

# Verified against: Godot 4.7.1 (2026-07-19)
