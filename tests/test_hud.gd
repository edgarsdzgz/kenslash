class_name TestHud extends RefCounted
## Playable-loop D2 (design-playable-loop.md): the minimal in-game HUD. Instantiates the
## shipped streaming_world.tscn (which hosts + binds the HUD), then proves the HUD READS
## live state and renders it -- health (incl. the signal-less revive caught by the per-frame
## pass), equipped tool + durability across equip/wear/unarmed, and the hotbar highlight
## tracking equipped_index. Presentation only: it asserts the HUD's Label.text / slot color,
## which ARE readable headless (Control nodes exist and _process runs; only RENDERING is
## absent). Self-contained: builds its own streaming_world instance, never touches player.gd.


func run(ctx: TestContext) -> void:
	print("[hud] --- D2 minimal HUD: reflects health / tool+durability / hotbar ---")
	var sw_scene: PackedScene = load("res://world/streaming_world.tscn")
	ctx.check(sw_scene != null,
		"streaming_world.tscn loads (hosts the D2 HUD)",
		"streaming_world.tscn failed to load")
	if sw_scene == null:
		return
	var sw: Node2D = sw_scene.instantiate()
	ctx.tree.root.add_child(sw)
	# Step frames so _ready wiring (hud.bind, component _ready) settles and _process runs.
	await ctx.tree.physics_frame
	await ctx.tree.physics_frame

	var player: Player = sw.get_node("Player") as Player
	var hud: Hud = sw.get_node("HUD") as Hud
	var health: HealthComponent = player.get_node("HealthComponent") as HealthComponent
	ctx.check(hud != null and player != null,
		"HUD + Player present in streaming_world",
		"HUD or Player missing from streaming_world")
	if hud == null or player == null:
		sw.queue_free()
		return

	# --- Health: reflects damage, then the signal-less revive via the per-frame pass ------
	ctx.check(hud.health_text() == "HP %d / %d" % [health.max_health, health.max_health],
		"HUD health readout starts full (" + hud.health_text() + ")",
		"HUD health readout not full at start (" + hud.health_text() + ")")

	var before_hp: int = health.current_health
	health.take_damage(2)
	await ctx.tree.physics_frame
	ctx.check(health.current_health == before_hp - 2 and hud.health_text() == "HP %d / %d" % [health.current_health, health.max_health],
		"HUD health readout dropped after damage (" + hud.health_text() + ")",
		"HUD health readout did not reflect damage (" + hud.health_text() + ")")

	# revive() emits NO signal -- only the per-frame refresh can catch it.
	health.revive()
	await ctx.tree.physics_frame
	ctx.check(health.current_health == health.max_health and hud.health_text() == "HP %d / %d" % [health.max_health, health.max_health],
		"HUD health readout back to full after revive (per-frame pass caught the signal-less revive) (" + hud.health_text() + ")",
		"HUD health readout did not follow revive (" + hud.health_text() + ")")

	# --- Equipped tool + durability: default Sword, switch to Axe, wear, then Unarmed -----
	var sword_dura: DurabilityComponent = player.get_node("SwordDurability") as DurabilityComponent
	ctx.check(hud.tool_text() == "Sword  %d / %d" % [sword_dura.current_durability, sword_dura.max_durability],
		"HUD shows the default equipped Sword + durability (" + hud.tool_text() + ")",
		"HUD equipped-tool readout wrong for default Sword (" + hud.tool_text() + ")")

	# Switch the equipped tool through the player's real equip path (axe is slot 1).
	player.inventory.equip_index(1)
	player._apply_equipped()
	await ctx.tree.physics_frame
	var axe_dura: DurabilityComponent = player.get_node("AxeDurability") as DurabilityComponent
	ctx.check(hud.tool_text() == "Axe  %d / %d" % [axe_dura.current_durability, axe_dura.max_durability],
		"HUD reflects the equip switch to Axe + its durability (" + hud.tool_text() + ")",
		"HUD did not reflect the equip switch to Axe (" + hud.tool_text() + ")")

	# Wear the ACTIVE tool's DurabilityComponent; the per-frame pass shows the drop.
	var dura_before: int = axe_dura.current_durability
	player._active_durability.wear(5)
	await ctx.tree.physics_frame
	ctx.check(axe_dura.current_durability == dura_before - 5 and hud.tool_text() == "Axe  %d / %d" % [axe_dura.current_durability, axe_dura.max_durability],
		"HUD durability number dropped after the active tool wore (" + hud.tool_text() + ")",
		"HUD durability did not drop after wear (" + hud.tool_text() + ")")

	# Equip an EMPTY slot (only 3 tools populated, so slot 3 is empty) -> Unarmed.
	player.inventory.equip_index(3)
	player._apply_equipped()
	await ctx.tree.physics_frame
	ctx.check(hud.tool_text() == "Unarmed",
		"HUD shows 'Unarmed' for an empty equipped slot (" + hud.tool_text() + ")",
		"HUD did not show 'Unarmed' for an empty slot (" + hud.tool_text() + ")")

	# --- Hotbar: correct slot count + glyphs, highlight tracks equipped_index -------------
	ctx.check(hud.hotbar_slot_count() == player.inventory.hotbar_size() and hud.hotbar_slot_count() == 6,
		"HUD hotbar has hotbar_size() slot widgets (" + str(hud.hotbar_slot_count()) + " == 6)",
		"HUD hotbar slot count wrong (" + str(hud.hotbar_slot_count()) + ")")
	ctx.check(hud.slot_glyph_at(0) == "S" and hud.slot_glyph_at(1) == "A" and hud.slot_glyph_at(2) == "P",
		"HUD hotbar tool slots show glyphs S/A/P",
		"HUD hotbar tool glyphs wrong (" + hud.slot_glyph_at(0) + hud.slot_glyph_at(1) + hud.slot_glyph_at(2) + ")")
	ctx.check(hud.slot_glyph_at(3) == "" and hud.slot_glyph_at(4) == "" and hud.slot_glyph_at(5) == "",
		"HUD empty hotbar slots are blank",
		"HUD empty hotbar slots not blank")

	player.inventory.equip_index(0)
	player._apply_equipped()
	await ctx.tree.physics_frame
	ctx.check(hud.highlighted_slot_index() == 0 and player.inventory.equipped_index == 0 and hud.highlighted_count() == 1,
		"HUD highlight is on slot 0 (matches equipped_index) and exactly one slot is highlighted",
		"HUD highlight wrong at slot 0 (idx " + str(hud.highlighted_slot_index()) + ", count " + str(hud.highlighted_count()) + ")")

	player.inventory.equip_index(2)
	player._apply_equipped()
	await ctx.tree.physics_frame
	ctx.check(hud.highlighted_slot_index() == 2 and player.inventory.equipped_index == 2 and hud.highlighted_count() == 1,
		"HUD highlight moved to slot 2 after the equip change (still exactly one highlighted)",
		"HUD highlight did not move to slot 2 (idx " + str(hud.highlighted_slot_index()) + ", count " + str(hud.highlighted_count()) + ")")

	sw.queue_free()
	await ctx.tree.physics_frame

# Verified against: Godot 4.7.1 (2026-07-18)
