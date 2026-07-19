class_name Forageable
extends Node2D
## Shared BASE for the "walk over it and press the action key" interactables (design-items.md
## "Interaction 'f'"): the Bush and the Pebble. Unlike an attack-driven Tree/Rock (harvested via a
## Hurtbox), a forageable has NO collision of any kind -- root is a plain Node2D, so the player walks
## straight THROUGH it -- and is collected by the pure-logic Interaction subsystem
## (components/interaction.gd) scanning the "interactables" group while the player stands on it.
##
## The two E4 forageables differ ONLY in their VERB (the HUD prompt) and their YIELDS, so every bit of
## shared mechanism lives here: the group-join in _ready, interact_prompt() returning the exported
## `verb`, and interact() adding a data-driven list of (item, count) yields to the player then freeing
## the node. Each subclass stays THIN -- it authors its own yield exports (the names its tests read) and
## hands them to the base via _forage_yields(), and sets its verb. See world/bush.gd and world/pebble.gd.

## The verb the HUD shows after the action key (the Interaction contract) -- "Harvest" a bush, "Gather"
## a pebble. Each subclass sets its own in _init(); exported so an authored variant could override it.
@export var verb: String = "Forage"

## XP granted to the player for foraging this node (plan-epic1-parts.md Part 1.2, harvest-XP hook). A flat
## TUNING constant shared by every forageable (bush + pebble) -- integer, no Time/OS/RNG -- awarded once
## per forage in interact(). Smallest of the harvest rewards, matching the low-effort forage.
const XP_PER_FORAGE: int = 3


func _ready() -> void:
	# Join the group the Interaction subsystem scans (components/interaction.gd), the same group-lookup
	# contract drops use for the pickup magnet. Pure membership -- a forageable stays a plain Node2D (no
	# Area2D), so this adds no node to the streaming node-count baseline.
	add_to_group("interactables")


## The verb the HUD shows after the action key (the Interaction contract). A bush is harvested, a pebble
## gathered -- each subclass sets `verb` (defaulted in its _init()).
func interact_prompt() -> String:
	return verb


## Collect this forageable (the Interaction contract): add each (item, count) yield to the player's
## inventory via the E3a collect() facade, then remove the node instantly (queue_free). Foraging is
## instant, so an overflowing yield on a FULL inventory is simply dropped -- the node still vanishes
## (simplest of the two design-items.md options; no ground Drop is spawned for the overflow). Null/zero
## yields are guarded so a partially-authored forageable cannot crash the harvest.
func interact(player: Node) -> void:
	for pair in _forage_yields():
		var item: ItemData = pair[0]
		var count: int = pair[1]
		if item != null and count > 0:
			player.collect(item, count)
	# Harvest XP on forage (Part 1.2): award once to the foraging player. We already HAVE the player here
	# (the Interaction subsystem passed it in), so this awards directly -- no "player"-group lookup needed,
	# unlike the attack-driven Tree/Rock. Guarded so a non-player caller cannot crash the harvest.
	if player.has_method("award_xp"):
		player.award_xp(XP_PER_FORAGE)
	queue_free()


## The (item, count) pairs this forageable yields on collect, IN ORDER. Each subclass supplies its own
## from its authored exports (the bush's two, the pebble's one). Override; default none.
func _forage_yields() -> Array:
	return []

# Verified against: Godot 4.7.1 (2026-07-19)
