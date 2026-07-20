class_name Hud
extends CanvasLayer
## Minimal in-game HUD for the playable loop (design-playable-loop.md D2). PRESENTATION ONLY: it
## READS live player/inventory/health/stamina/durability state and renders it -- owns NO game state,
## mutates nothing, adds NO signals to player.gd (patterns/game-code-organization.md: "the HUD
## subscribes, never polls game logic into itself"). Placeholder styling (ColorRect slots + Labels).
##
## Update strategy: per-frame READS are correct here (not "polling logic"). Health also connects to
## HealthComponent.damaged for the exact damage frame, but revive()/heal() emit nothing and the tool
## / durability / equipped_index / stamina have no HUD-facing signal (player.gd is at its line cap),
## so a light per-frame refresh of a few STATE values is the clean way to catch them.
##
## The HOTBAR sub-system (slot widgets + item-name selection popup) lives in its own HotbarPanel
## script (ui/hotbar_panel.gd), attached to the Hotbar node. This Hud binds the player into that
## panel and delegates build/refresh to it, then FORWARDS the panel's read-only queries so the
## headless HUD test is unchanged (CONVENTIONS.md Rule 1: both files stay under the line cap).

## Weight readout tints (design-weight.md "HUD"): one per encumbrance TIER, parallel to
## Inventory.Encumbrance -- white under capacity, then yellow -> orange -> red as it worsens.
const WEIGHT_TIER_COLORS: Array[Color] = [
	Color(1.0, 1.0, 1.0, 1.0),    ## NORMAL -- white (under capacity).
	Color(1.0, 0.85, 0.3, 1.0),   ## OVER   -- yellow.
	Color(1.0, 0.6, 0.2, 1.0),    ## SUPER  -- orange.
	Color(1.0, 0.35, 0.3, 1.0),   ## ULTRA  -- red.
]
## Tier NAME appended to the weight readout when encumbered (parallel to the tier enum); NORMAL is "".
const WEIGHT_TIER_NAMES: Array[String] = ["", "Overencumbered", "Superencumbered", "Ultraencumbered"]
## Stamina bar tints (design-controls.md): the normal fill, and a warning red once the player is
## low on stamina (< 25%) -- the stamina meter's parallel to the health bar.
const STAMINA_COLOR: Color = Color(0.3, 0.75, 0.95, 1.0)
const STAMINA_LOW_COLOR: Color = Color(0.9, 0.25, 0.2, 1.0)
## Stamina GHOST BAR (consumption highlight, Street-Fighter-style): seconds for a FULL-bar red
## "just-spent" gap to drain away. The ghost eases toward the front bar at 1.0 / this per second,
## so any smaller spend catches up proportionally faster. Time-based (delta), deterministic headless.
const STAMINA_GHOST_CATCHUP: float = 0.4

var _player: Player = null
var _health: HealthComponent = null
## The stamina ghost's current fill (0..1). Follows the front bar instantly on a REGEN (snap up,
## no red), but LAGS behind on a SPEND -- easing down over STAMINA_GHOST_CATCHUP so the red
## trailing chunk between the front bar and the ghost is visible while it shrinks.
var _stamina_ghost_value: float = 1.0

@onready var _health_label: Label = $Backdrop/Column/HealthLabel
@onready var _health_bar: ProgressBar = $Backdrop/Column/HealthBar
@onready var _stamina_bar: ProgressBar = $Backdrop/Column/StaminaBar
## Red ghost/trailing bar drawn BEHIND the front stamina bar (same rect, show_behind_parent), so
## the front bar's transparent background lets the lingering red show through on a spend.
@onready var _stamina_ghost_bar: ProgressBar = $Backdrop/Column/StaminaBar/StaminaGhost
@onready var _tool_label: Label = $Backdrop/Column/ToolLabel
## Carried-weight readout below the tool label (design-weight.md "HUD"); refreshed each frame.
@onready var _weight_label: Label = $Backdrop/Column/WeightLabel
## Level + XP readout (plan-epic1-parts.md Part 1.2): the progression spine's HUD line, refreshed each
## frame from the player's Progression via the read-only facade -- the player never pushes into the HUD.
@onready var _level_label: Label = $Backdrop/Column/LevelLabel
## The hotbar row lives in its OWN bottom-center anchor (Minecraft-style), separate from the
## top-left health/tool Backdrop. A CenterContainer anchored to the bottom edge keeps it
## horizontally centered and re-centers automatically on window resize -- no manual math. The
## Hotbar node carries the HotbarPanel script that owns the slot widgets + selection popup.
@onready var _hotbar: HotbarPanel = $HotbarAnchor/HotbarPanel/Hotbar
## Interaction prompt (E4, design-items.md "Interaction 'f'"): shown just above the hotbar when
## the player stands on an interactable (a bush), reading player.interaction_prompt() each frame;
## hidden when nothing is in reach. Presentation only -- the interaction lives in player.gd.
@onready var _prompt_label: Label = $PromptLabel
## Item-name selection popup (Change 2): shown just ABOVE the interaction prompt (a bit higher y
## so the two never overlap), it names the item in the newly-selected hotbar slot, held then
## faded out. Presentation only -- driven by the HotbarPanel (which owns the popup logic).
@onready var _selection_label: Label = $SelectionLabel
## Minimal craft menu (plan-epic1-parts.md Part 4.2): hosted here on the HUD/CanvasLayer (never the streamed
## chunk path). The per-frame pass polls the player's interaction for an 'f'-near-a-station open request and
## toggles this menu open/closed -- the HUD PULLS the request, the player never pushes into the UI. The menu
## reads the player's sheet/inventory + runs Crafting; the HUD only opens/closes it.
@onready var _craft_menu: CraftMenu = $CraftMenu
## Minimal container transfer panel (plan-epic2-parts.md Phase 2 Part 2.3): the craft menu's sibling, hosted here on
## the HUD/CanvasLayer (never the streamed chunk path). The per-frame pass polls the player's interaction for an
## 'f'-near-a-container open request and manages the open panel with the SAME hardened ordering as the craft menu --
## the HUD PULLS the request, the player never pushes into the UI. Only ONE of the two panels is ever open at once.
@onready var _container_panel: ContainerPanel = $ContainerPanel


## Point the HUD at the live player: store the ref, subscribe to the health damage EVENT, bind the
## hotbar panel (which builds its slot widgets + seeds the selection trackers), and do an initial
## full refresh. Called by streaming_world.gd _ready once the player exists. Safe to call once.
func bind(player: Player) -> void:
	_player = player
	_health = player.get_node("HealthComponent") as HealthComponent
	if _health != null and not _health.damaged.is_connected(_on_player_damaged):
		_health.damaged.connect(_on_player_damaged)
	_hotbar.bind(_player, _selection_label)
	_refresh(0.0)


## Light per-frame refresh so signal-less changes (revive/heal, equip/cycle, wear) show up
## without any new player signal. Guarded: no-ops until bound / if the player was freed. delta
## drives the stamina ghost bar's time-based catch-up ease.
func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	_refresh(delta)


## Damage EVENT hook (HealthComponent.damaged). The per-frame pass also refreshes health,
## but the signal keeps the readout responsive on the exact frame damage lands.
func _on_player_damaged(_amount: int, _current: int) -> void:
	_refresh_health()


func _refresh(delta: float) -> void:
	_refresh_health()
	_refresh_stamina(delta)
	_refresh_tool()
	_refresh_weight()
	_refresh_level()
	_hotbar.refresh()
	_refresh_prompt()
	_refresh_craft_menu()
	_refresh_container_panel()


## Carried-weight readout (design-weight.md REVISION 1 "HUD"): "Wt <carried> / <capacity>" with
## each side auto-scaled g vs kg by _fmt_grams, and -- when encumbered -- the TIER NAME appended
## (e.g. "Wt 60 kg / 50 kg  Overencumbered") with a per-tier warning tint (white -> yellow ->
## orange -> red). The tier is owned by the Inventory (encumbrance_tier()); the HUD only maps
## int -> name/tint. Presentation only -- state reads, no game logic added.
func _refresh_weight() -> void:
	var inv: Inventory = _player.inventory
	var tier: int = inv.encumbrance_tier()
	var text: String = "Wt %s / %s" % [_fmt_grams(inv.total_weight()), _fmt_grams(inv.carry_capacity)]
	if tier != Inventory.Encumbrance.NORMAL:
		text += "  " + WEIGHT_TIER_NAMES[tier]
	_weight_label.text = text
	_weight_label.modulate = WEIGHT_TIER_COLORS[tier]


## Auto g/kg formatter for a gram weight (design-weight.md REVISION 1): under 1000 g shows whole
## grams ("800 g", rounded); 1000 g+ shows kg with up to one decimal, its trailing ".0" trimmed so
## round values read clean (1000 -> "1 kg", 1500 -> "1.5 kg", 5100 -> "5.1 kg"). Godot's % has no
## %g, so the decimal is built via "%.1f" then the ".0" tail is stripped by hand.
func _fmt_grams(g: float) -> String:
	if g < 1000.0:
		return "%d g" % roundi(g)
	var text: String = "%.1f" % (g / 1000.0)
	if text.ends_with(".0"):
		text = text.substr(0, text.length() - 2)
	return text + " kg"


## Interaction prompt (E4): if the player has a nearby interactable, show "[<key>] <verb>" just
## above the hotbar, where <key> is whatever key is currently bound to the_action_button (derived
## from the InputMap, so a rebind updates the prompt for free); otherwise hide the label.
func _refresh_prompt() -> void:
	var prompt: String = _player.interaction_prompt()
	if prompt == "":
		_prompt_label.text = ""
		_prompt_label.visible = false
		return
	_prompt_label.text = "[%s] %s" % [_action_key_text(), prompt]
	_prompt_label.visible = true


## Craft menu open/close driver (plan-epic1-parts.md Part 4.2): the HUD MANAGES the open menu each frame so it can
## never get stuck and its station gate is always judged against LIVE station presence. Fixed ordering:
##   1. An 'f'-near-a-station open REQUEST takes priority -- consume it and TOGGLE: if the menu is already open,
##      close it (a second 'f' by the station still toggles closed) and RETURN; otherwise open it with the
##      player's live CharacterSheet + Inventory and the tags that came with the request.
##   2. Otherwise, if the menu is OPEN, re-scan the station tags in range RIGHT NOW: if EMPTY (walked away / the
##      station streamed out) auto-dismiss with close() -- never stuck; else feed the current tags via set_tags so
##      is_craftable + craft evaluate against the station actually present, not the stale snapshot from open().
## The HUD reaches into the player-owned interaction (like it reads _stamina / _active_durability) and re-derives
## live station presence with Station.tags_in_range; the player/interaction never reach into this UI. Guarded
## until the interaction exists.
func _refresh_craft_menu() -> void:
	if _player._interaction == null:
		return
	if _player._interaction.craft_open_pending():
		var tags: Array[StringName] = _player._interaction.consume_craft_open()
		if _craft_menu.is_open:
			_craft_menu.close()
		else:
			_container_panel.close()  # only ONE panel (craft OR container) open at a time -- opening one closes the other
			_craft_menu.open(_player.character(), _player.inventory, tags, _craft_stores())
		return
	if _craft_menu.is_open:
		var live_tags: Array[StringName] = Station.tags_in_range(_player.global_position, Station.DEFAULT_REACH)
		if live_tags.is_empty():
			_craft_menu.close()
		else:
			_craft_menu.set_extra_stores(_craft_stores())  # refresh chest sources first (no repaint)...
			_craft_menu.set_tags(live_tags)                 # ...then set_tags repaints once with both fresh


## The in-range container STORES the open craft menu may source inputs from (Epic 2 Part 3.1 craft-from-storage):
## the Inventory of every StorageContainer within Interaction.CONTAINER_REACH of the player, via the SAME shared
## group-within-radius scan the container-open 'f' uses (Interaction.containers_in_range), so is_craftable lights
## up + a craft consumes from nearby chests. LIVE store refs (never copies) so a craft actually drains them. Empty
## when no chest is near -- the menu then behaves exactly as Epic 1 (inventory-only). The player never reaches
## into the UI; the HUD PULLS these each frame, mirroring the live-tags re-scan.
func _craft_stores() -> Array[Inventory]:
	var stores: Array[Inventory] = []
	for box in Interaction.containers_in_range(_player.global_position, Interaction.CONTAINER_REACH):
		if box.store != null:
			stores.append(box.store)
	return stores


## Container transfer panel open/close driver (plan-epic2-parts.md Phase 2 Part 2.3): the HUD MANAGES the open panel
## each frame with the SAME hardened ordering as _refresh_craft_menu so it can never get STUCK and never acts on a
## container the player already left. Fixed ordering:
##   1. An 'f'-near-a-container open REQUEST takes priority -- consume it and TOGGLE: if the panel is already open,
##      close it (a second 'f' by the container toggles closed) and RETURN; otherwise close the craft menu (only
##      ONE panel open at a time) and open the panel bound to the requested container + the player's live inventory.
##   2. Otherwise, if the panel is OPEN, check the BOUND container's LIVE proximity: if it was freed or the player
##      walked farther than Interaction.CONTAINER_REACH from it, AUTO-DISMISS with close() -- never stuck, and a
##      transfer can never run against a container the player left. (The store is read live on every deposit/
##      withdraw, so unlike the craft menu's station gate there is no stale snapshot to refresh -- only the reach.)
## The HUD reaches into the player-owned interaction (like _refresh_craft_menu) and re-derives live proximity with
## the same CONTAINER_REACH the interaction scans; the player/interaction never reach into this UI. Guarded until
## the interaction exists.
func _refresh_container_panel() -> void:
	if _player._interaction == null:
		return
	if _player._interaction.container_open_pending():
		var box: StorageContainer = _player._interaction.consume_container_open()
		if _container_panel.is_open:
			_container_panel.close()
		elif box != null:
			_craft_menu.close()  # only ONE panel (craft OR container) open at a time -- opening one closes the other
			_container_panel.open(box, _player.inventory)
		return
	if _container_panel.is_open:
		var bound: StorageContainer = _container_panel.bound_container()
		if bound == null or not is_instance_valid(bound) \
				or _player.global_position.distance_to(bound.global_position) > Interaction.CONTAINER_REACH:
			_container_panel.close()


## Human-readable key currently bound to the_action_button: the first InputEventKey's keycode
## (physical preferred, since the action is authored physical) as a label. "?" if none is bound.
func _action_key_text() -> String:
	for ev in InputMap.action_get_events("the_action_button"):
		if ev is InputEventKey:
			var k: InputEventKey = ev as InputEventKey
			var code: int = k.physical_keycode if k.physical_keycode != 0 else k.keycode
			return OS.get_keycode_string(code)
	return "?"


## Level + XP readout (plan-epic1-parts.md Part 1.2): poll the player's Progression each frame via the
## read-only facade and render a single legible line "Lv <level>  XP <xp>". Presentation only -- the XP
## award hooks live in the gameplay path (enemy kills / harvest), never here; the HUD only reads.
func _refresh_level() -> void:
	var sheet: CharacterSheet = _player.character()
	_level_label.text = "Lv %d  XP %d" % [sheet.level(), sheet.xp()]


func _refresh_health() -> void:
	if _health == null:
		return
	var cur: int = _health.current_health
	var mx: int = _health.max_health
	_health_label.text = "HP %d / %d" % [cur, mx]
	_health_bar.max_value = mx
	_health_bar.value = cur


## Stamina bar (design-controls.md): the FRONT bar fills from player.stamina_ratio() (0..1) and
## snaps instantly, warning-tinted (self_modulate, so the tint does NOT cascade onto the ghost
## child) when player.stamina_low(). Behind it, the GHOST bar (consumption highlight): on a SPEND
## the ratio drops below the ghost, so the ghost eases DOWN toward it over STAMINA_GHOST_CATCHUP --
## leaving a shrinking red "just-spent" chunk between the two; on a REGEN (ratio >= ghost) the ghost
## SNAPS UP with the front so a refill shows no red gap. Time-based via delta (deterministic
## headless). Presentation only -- the pool lives in the player's Stamina component.
func _refresh_stamina(delta: float) -> void:
	var ratio: float = _player.stamina_ratio()
	_stamina_bar.max_value = 1.0
	_stamina_bar.value = ratio
	_stamina_bar.self_modulate = STAMINA_LOW_COLOR if _player.stamina_low() else STAMINA_COLOR
	if ratio < _stamina_ghost_value:
		_stamina_ghost_value = move_toward(_stamina_ghost_value, ratio, delta / STAMINA_GHOST_CATCHUP)
	else:
		_stamina_ghost_value = ratio
	_stamina_ghost_bar.max_value = 1.0
	_stamina_ghost_bar.value = _stamina_ghost_value


## Equipped-tool readout: the tool's display_name + its active DurabilityComponent's
## current/max, or "Unarmed" when the equipped slot is empty. Reads inventory.equipped_tool()
## for the name/empty state and the player's private _active_durability for the wear numbers
## (both kept in sync by the player's _apply_equipped() chokepoint; the HUD only reads them).
func _refresh_tool() -> void:
	var tool: ToolData = _player.inventory.equipped_tool()
	if tool == null:
		_tool_label.text = "Unarmed"
		return
	var dura: DurabilityComponent = _player._active_durability
	if dura != null:
		_tool_label.text = "%s  %d / %d" % [tool.display_name, dura.current_durability, dura.max_durability]
	else:
		_tool_label.text = tool.display_name


# --- Read-only presentation queries (for the headless HUD test) -----------------------

func health_text() -> String:
	return _health_label.text


## The stamina bar fill (0..1) currently shown -- for the headless HUD test.
func stamina_bar_ratio() -> float:
	return _stamina_bar.value


## Whether the stamina bar is in the low/warning tint -- for the headless HUD test. Reads
## self_modulate (the front bar's own tint; modulate is kept white so it does not cascade the
## warning colour onto the red ghost child behind it).
func stamina_bar_low() -> bool:
	return _stamina_bar.self_modulate == STAMINA_LOW_COLOR


## The stamina GHOST bar's current fill (0..1) -- the trailing/red "just-spent" value. Right after
## a spend it reads HIGHER than stamina_bar_ratio() (the red chunk), then eases down to meet it;
## on a regen it tracks the front. For the headless HUD test's ghost-bar assertions.
func stamina_ghost_ratio() -> float:
	return _stamina_ghost_bar.value


## The interaction prompt currently SHOWN (e.g. "[F] Harvest"), or "" when the label is hidden.
## Reads the rendered text so a test sees exactly what a player would (E4).
func prompt_text() -> String:
	return _prompt_label.text if _prompt_label.visible else ""


func tool_text() -> String:
	return _tool_label.text


## The hosted craft menu (plan-epic1-parts.md Part 4.2), for the headless test to assert the 'f'-near-a-station
## open opened it + listed the right recipes. Read-only handle; the HUD owns opening/closing it.
func craft_menu() -> CraftMenu:
	return _craft_menu


## The hosted container transfer panel (plan-epic2-parts.md Phase 2 Part 2.3), for the headless test to assert the
## 'f'-near-a-container open opened it + listed the container's contents and the player inventory. Read-only handle;
## the HUD owns opening/closing it (and keeps only ONE of it and the craft menu open at a time).
func container_panel() -> ContainerPanel:
	return _container_panel


## The level + XP readout currently SHOWN (e.g. "Lv 2  XP 120"), for the headless HUD/XP test.
func level_text() -> String:
	return _level_label.text


## The carried-weight readout currently SHOWN (e.g. "Wt 5.1 kg / 50 kg"), for the headless HUD test.
func weight_text() -> String:
	return _weight_label.text


## Whether the weight readout is in ANY over-capacity warning state (tier past NORMAL) -- for the
## headless HUD test. True once the player is Over/Super/Ultra-encumbered (not the normal white).
func weight_over() -> bool:
	return _weight_label.modulate != WEIGHT_TIER_COLORS[Inventory.Encumbrance.NORMAL]


## The current encumbrance TIER shown by the readout (Inventory.Encumbrance, 0..3), forwarded from
## the live inventory so the HUD test can assert the tier without parsing the string.
func weight_tier() -> int:
	return _player.inventory.encumbrance_tier()


# --- Hotbar queries: thin forwarders to the HotbarPanel so the HUD test is unchanged ----------

## The item-name selection popup currently SHOWN, or "" once it has faded/hidden (HotbarPanel owns it).
func selection_text() -> String:
	return _hotbar.selection_text()


func hotbar_slot_count() -> int:
	return _hotbar.hotbar_slot_count()


func slot_glyph_at(i: int) -> String:
	return _hotbar.slot_glyph_at(i)


func slot_icon_point_count(i: int) -> int:
	return _hotbar.slot_icon_point_count(i)


func slot_icon_visible(i: int) -> bool:
	return _hotbar.slot_icon_visible(i)


func slot_icon_color(i: int) -> Color:
	return _hotbar.slot_icon_color(i)


func slot_count_at(i: int) -> int:
	return _hotbar.slot_count_at(i)


func highlighted_slot_index() -> int:
	return _hotbar.highlighted_slot_index()


func highlighted_count() -> int:
	return _hotbar.highlighted_count()

# Verified against: Godot 4.7.1 (2026-07-20)
