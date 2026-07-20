class_name StationAddon
extends Placeable
## A placeable STATION ADD-ON (plan-epic2-parts.md Phase 4 Part 4.1 -- "Windrose" proximity station leveling).
## The THIRD placeable (after the crafting Station and the storage Container), and the first whose PURPOSE is to
## LEVEL a nearby Station rather than to be stood beside and operated: a Station derives its level() from the COUNT
## of add-ons within its reach (capped at Station.MAX_ADDON_LEVELS), so dropping add-ons around a workbench visibly
## upgrades it (campfire -> workshop). Part 4.1 is ONLY the add-on ENTITY + the level() derivation + persistence;
## wiring the level into a recipe TIER gate is Part 4.2 (this add-on stays decoupled from crafting for now).
##
## Rides the SAME kind-agnostic build + streaming-delta path a Station / StorageContainer does (the path Part 2.1
## generalized, resolving the reviewer-flagged place_station hardcoding): it differs ONLY in its placement_kind()
## (Kind.ADDON) and its own small build cost (station_addon.tscn: wood x2, a cheap upgrade part). components/
## builder.gd reads + deducts that cost kind-agnostically; ChunkManager.register_placement records it as a
## Kind.ADDON delta; ChunkContent.spawn() re-creates it on reload -- NONE of them special-cased for the add-on.
##
## STATELESS IDENTITY. An add-on carries NO per-instance params, so capture_state()/apply_state() stay the
## Placeable base's no-ops (it round-trips as pure identity: kind + position). The station LEVEL it contributes is
## NOT stored anywhere -- it is DERIVED on demand from the add-ons in range, so an add-on that persists as a delta
## is all that is needed: on reload it re-joins the "station_addon" group in _ready and re-contributes its +1, and
## every station in range RECOMPUTES the same level with nothing level-specific to serialize.
##
## A plain Node2D in the "station_addon" group (no collision) -- like Station/Container/Forageable, a thing you
## place in the world, not a wall you bump into, so it adds no collision node to the streaming node-count / orphan
## baselines. DETERMINISM: build cost + persistence are pure data (authored exports + empty state) and the level it
## feeds is a pure integer count (no Time/OS/RNG), so a placement round-trips byte-identically and level() is
## exactly headless-assertable.

## The group every StationAddon joins -- the one Station.addons_in_range scans to derive a station's level. A
## StringName const so the join and the scan reference the SAME key (never a typo'd string literal in two places),
## mirroring Station.GROUP and StorageContainer.GROUP.
const GROUP: StringName = &"station_addon"

## BUILD COST (build_items / build_counts) is inherited from world/placeable.gd -- the shared recipe-like cost every
## placeable authors on its scene (station_addon.tscn: wood x2). components/builder.gd reads + deducts it kind-
## agnostically, exactly as it does a Station's stone+stick or a Container's wood.


func _ready() -> void:
	# Join the group Station.addons_in_range scans -- the same pure group-membership contract Station ("station")
	# and StorageContainer ("container") use. Membership on a plain Node2D (no Area2D), so this adds no collision
	# node to the streaming node-count baseline.
	add_to_group(GROUP)


## The persistence contract (world/placeable.gd): an add-on persists as a Kind.ADDON ADDITION delta, the twin of a
## Station's STATION delta and a Container's CONTAINER delta. It carries NO extra params -- capture_state()/
## apply_state() stay the base no-ops (an add-on is pure identity: kind + position). Overriding ONLY placement_kind()
## is the WHOLE subclass; the kind-agnostic spawn/capture/skip path (ChunkContent + ChunkManager + ChunkData.
## is_addition_kind) does everything else, so the add-on rides the exact delta path STATION/CONTAINER already do.
func placement_kind() -> int:
	return ChunkData.Kind.ADDON

# Verified against: Godot 4.7.1 (2026-07-20)
