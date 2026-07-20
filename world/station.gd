class_name Station
extends Placeable
## A crafting STATION (plan-epic1-parts.md Part 4.1; plan-core-loop.md Phase 4; design-crafting.md "Track B
## -- Building / crafting"). A recipe that carries a non-empty `station_tag` (RecipeData) can only be crafted
## when a Station carrying that SAME tag is in range of the player; craft-anywhere recipes (station_tag == "")
## ignore stations entirely. This is the PLACE half of "crafting has a place and a gate": the workbench you
## stand near to run a station-gated recipe. (The 'f'-to-open-menu interaction + the craft UI are Part 4.2;
## this part is ONLY the station entity + the in-range tag collection the gate consumes.)
##
## A plain Node2D in the "station" group -- NOT a StaticBody2D. A workbench is a thing you stand NEXT TO to
## craft, not a wall you bump into; making it solid would add a collision body (and its shape) to the
## streaming node-count / orphan baselines for no gameplay gain. It mirrors world/forageable.gd's stance
## exactly: a group-joined Node2D with no collision of any kind, found by a pure-logic group scan rather than
## a physics overlap. (Solidity is an OPTIONAL judgment call the task left open; kept OFF for the minimal
## subtree + the walk-up-to-it feel a forageable already established.)
##
## DECOUPLED FROM CRAFTING. The station knows NOTHING about recipes or inventories; crafting.gd knows NOTHING
## about station nodes. The only bridge is the STATIC tags_in_range() below: a caller (Part 4.2's interaction,
## or a headless test) collects the tags of every station near a position and hands that plain Array[StringName]
## to Crafting.craft(). So the gate adds NOTHING to player.gd and the two systems never import each other's
## state -- crafting stays a pure RefCounted operating on a passed tag list.
##
## DETERMINISM: the tag is a fixed authored @export; tags_in_range is a pure distance compare over the group
## (no Time/OS/RNG, NOTES.md rule), so a headless test asserts exactly which stations are in range. A Station
## is a Node (it lives in the scene), which is correct here and does not touch the RefCounted-component
## discipline the crafting/inventory logic follows.

## The group every Station joins -- the one tags_in_range scans. A StringName const so the join and the scan
## reference the SAME key (never a typo'd string literal in two places).
const GROUP: StringName = &"station"

## A reasonable default reach (px) for "near a station", offered for Part 4.2's interaction + the tests to pass
## as the tags_in_range radius. Two tiles (components/world_scale.gd TILE 40) -- a touch more generous than the
## one-tile harvest reach (components/interaction.gd) because you craft standing BESIDE a workbench, not on top
## of it. tags_in_range takes the radius explicitly, so this is only a shared default, never a hidden constant.
## DOUBLES as the LEVELING reach: level() counts the add-ons within DEFAULT_REACH of the station (Part 4.1).
const DEFAULT_REACH: float = WorldScale.TILE * 2.0

## The maximum number of ADD-ONS that can raise a station's level -- the LEVEL CAP (plan-epic2-parts.md Part 4.1
## "raises the level, capped"). With 2, a station tops out at level 3 (base 1 + up to 2 add-ons in reach); a 3rd
## add-on within reach adds nothing. Authored here so the cap and the derivation live in ONE place (level() below).
const MAX_ADDON_LEVELS: int = 2

## Which crafting station this is -- the tag a station-gated recipe must MATCH to craft in range (RecipeData
## station_tag, e.g. &"forge"). Authored on the scene / set by a streamer/placer before add_child. "" would make
## the station contribute nothing (skipped by tags_in_range); a real station always carries a meaningful tag.
@export var station_tag: StringName = &"forge"

## BUILD COST (build_items / build_counts) is inherited from world/placeable.gd -- the shared recipe-like cost
## every placeable authors on its scene (station.tscn: stone x3 + stick x2). components/builder.gd reads + deducts
## it kind-agnostically. Independent of the station_tag gate -- a PLACED station gates crafting through station_tag
## exactly as a scene-authored one does.


func _ready() -> void:
	# Join the group tags_in_range scans -- the same group-membership contract world/forageable.gd uses for the
	# 'f'-interaction scan. Pure membership on a plain Node2D (no Area2D), so this adds no collision node to the
	# streaming node-count baseline.
	add_to_group(GROUP)


## The persistence contract (world/placeable.gd): a Station persists as a Kind.STATION ADDITION delta whose only
## param is its station_tag. capture_state() flattens the tag to a plain String (serializable -- StringName does
## not survive store_var/JSON cleanly); apply_state() converts it back on reload, BEFORE _ready joins the group, so
## a reloaded station re-gates crafting identically. Byte-identical to the tag round-trip ChunkContent did inline
## before Part 2.1 generalized the path (a missing tag falls back to the scene default &"forge").
func placement_kind() -> int:
	return ChunkData.Kind.STATION


func capture_state() -> Dictionary:
	return {"station_tag": String(station_tag)}


func apply_state(state: Dictionary) -> void:
	station_tag = StringName(state.get("station_tag", "forge"))


## Collect the station tags in range of `world_pos` -- every DISTINCT `station_tag` of a Station within `radius`
## of the position. STATIC + decoupled: a caller (Part 4.2 interaction, or a test) computes this and hands the
## plain Array[StringName] to Crafting.craft() as its `in_range_station_tags`, so crafting never touches a
## station node. Deterministic distance compare (<= radius, the same idiom as components/interaction.gd); tags
## are de-duplicated (two forges nearby contribute one &"forge") and empty-tag stations are skipped. The active
## SceneTree is read via Engine.get_main_loop() (a fixed engine handle, no Time/OS/RNG) so the signature stays
## clean -- no tree/player argument to thread through. Returns [] when nothing is in range (a craft-anywhere
## recipe ignores it anyway).
static func tags_in_range(world_pos: Vector2, radius: float) -> Array[StringName]:
	var out: Array[StringName] = []
	var loop: SceneTree = Engine.get_main_loop() as SceneTree
	if loop == null:
		return out
	for node in loop.get_nodes_in_group(GROUP):
		if not (node is Station):
			continue
		var st: Station = node as Station
		if not is_instance_valid(st) or st.is_queued_for_deletion():
			continue
		if st.station_tag == &"":
			continue
		if world_pos.distance_to(st.global_position) <= radius and not out.has(st.station_tag):
			out.append(st.station_tag)
	return out


## This station's LEVEL (plan-epic2-parts.md Phase 4 Part 4.1 -- "Windrose" proximity leveling). A station starts
## at level 1 and rises by 1 for each StationAddon within DEFAULT_REACH, CAPPED at MAX_ADDON_LEVELS extra levels:
##   level = 1 + min(add-ons in reach, MAX_ADDON_LEVELS)
## DERIVED, never stored -- it recomputes from the add-ons in range every call, so an add-on placed/removed near
## the station is reflected immediately AND nothing level-specific has to persist (the add-ons persist as deltas,
## the level recomputes on reload). Pure integer count over a distance scan (no Time/OS/RNG), so it is exactly
## headless-assertable and deterministic. Reads the add-on group via the STATIC addons_in_range below, so a caller
## with only a Station reference (Part 4.2's tier gate) gets the level with no extra wiring.
func level() -> int:
	return 1 + mini(Station.addons_in_range(global_position, DEFAULT_REACH), MAX_ADDON_LEVELS)


## COUNT the StationAddon placeables within `radius` of `world_pos` -- the pure-logic add-on scan level() derives a
## station's level from. STATIC + decoupled, the add-on analogue of tags_in_range (and the same group-within-radius
## idiom as components/interaction.gd's containers_in_range): a deterministic <= radius distance compare over the
## "station_addon" group (StationAddon.GROUP), reading the active SceneTree via Engine.get_main_loop() (a fixed
## engine handle, no Time/OS/RNG) so no tree/player argument is threaded through. Skips freed/queued nodes
## (is_instance_valid guard) so a just-removed add-on never counts. Returns 0 when none are in reach. It returns the
## RAW count (uncapped) -- level() applies MAX_ADDON_LEVELS -- so a caller that wants the true nearby-add-on count
## (e.g. a test, or a future UI) reads it un-clamped here.
static func addons_in_range(world_pos: Vector2, radius: float) -> int:
	var count: int = 0
	var loop: SceneTree = Engine.get_main_loop() as SceneTree
	if loop == null:
		return count
	for node in loop.get_nodes_in_group(StationAddon.GROUP):
		if not (node is StationAddon):
			continue
		var addon: StationAddon = node as StationAddon
		if not is_instance_valid(addon) or addon.is_queued_for_deletion():
			continue
		if world_pos.distance_to(addon.global_position) <= radius:
			count += 1
	return count

# Verified against: Godot 4.7.1 (2026-07-20)
