class_name TestDurabilityTools extends RefCounted
## Integration legs j-r (+ the body-facing leg s) on the SAME shared main.tscn instance,
## run AFTER test_combat.gd so the original leg order and cross-leg state are preserved:
##   j. PICKAXE mines the SOFT rock (Band A, 0 wear) then mines it out; k. PICKAXE on
##   OBSIDIAN wears 4 (Band C) but cannot mine it; m. SWORD whiffs on the TREE (Gate 1:
##   NONE != CHOP); n. PICKAXE whiffs on the TREE (MINE != CHOP); o. AXE chops + fells
##   the TREE (Band A); p. SWORD whiffs on OBSIDIAN (NONE != MINE); l. a broken tool
##   gates further wear/damage; r. inventory & hotbar integration on the real player
##   (auto-populate order, equip-by-index -> _apply_equipped, unarmed fallback);
##   s. body-facing flip (side_facing ignores pure up/down, aim does not).
## Split out of the former monolithic tests/smoke_slash.gd (CONVENTIONS.md Rule 1).


func run(ctx: TestContext) -> void:
	var player: Player = ctx.player
	var main: Node = ctx.main
	var dummy: Enemy = ctx.dummy
	var dummy_health: HealthComponent = ctx.dummy_health
	var sword_dura: DurabilityComponent = ctx.sword_dura
	var axe_dura: DurabilityComponent = ctx.axe_dura
	var pickaxe_dura: DurabilityComponent = ctx.pickaxe_dura
	# --- j. RETCON: PICKAXE equipped -- SOFT rock. Gate 1 now blocks the sword
	# entirely (harvest_type NONE != required MINE), so mining moves to the pickaxe.
	# hardness 6 vs pickaxe power 7: over=-1 <= 0 -> Band A -> weapon_wear 0, affects
	# true (mineable at zero tool wear). A second slash mines it out (destroyed).
	player.equip_tool(Player.PICKAXE_DATA)
	var soft_rock: Node2D = main.get_node("SoftRock") as Node2D
	var soft_mat: DurabilityComponent = soft_rock.get_node("Material") as DurabilityComponent
	var obs_rock: Node2D = main.get_node("ObsidianRock") as Node2D
	obs_rock.global_position = Vector2(3000, 3000)  # keep it clear of the soft-rock check
	soft_rock.global_position = Vector2.ZERO
	var soft_integ_before: int = soft_mat.current_durability
	var pickaxe_before_soft: int = pickaxe_dura.current_durability
	# Rock body is solid on the `world` layer; -40 keeps the player body clear of it
	# while the blade still reaches the Hurtbox.
	await ctx.slash_target(player, Vector2(-40, 0))
	var soft_integ_after: int = soft_mat.current_durability
	var pickaxe_after_soft: int = pickaxe_dura.current_durability
	ctx.check(soft_integ_after == soft_integ_before - 2,
		"pickaxe mined the soft rock -- integrity dropped (" + str(soft_integ_before) + " -> " + str(soft_integ_after) + ")",
		"soft rock integrity wrong (" + str(soft_integ_before) + " -> " + str(soft_integ_after) + ")")
	ctx.check(pickaxe_after_soft == pickaxe_before_soft,
		"pickaxe took 0 wear mining the soft rock (Band A, still " + str(pickaxe_after_soft) + ")",
		"soft-rock pickaxe wear wrong (expected unchanged, " + str(pickaxe_before_soft) + " -> " + str(pickaxe_after_soft) + ")")
	# Second slash mines it out (integrity 2 -> 0 -> destroyed / queue_free).
	await ctx.slash_target(player, Vector2(-40, 0))
	await ctx.tree.physics_frame  # let the deferred queue_free resolve
	ctx.check(not is_instance_valid(soft_rock),
		"soft rock destroyed at 0 integrity (mined out)",
		"soft rock not destroyed after mining to 0")

	# --- k. RETCON: PICKAXE still equipped -- OBSIDIAN. hardness 12 vs power 7:
	# over=5 > threshold 3 -> Band C -> weapon_wear 4, affects false (too hard even
	# for the pickaxe -- integrity untouched).
	var obs_mat: DurabilityComponent = obs_rock.get_node("Material") as DurabilityComponent
	obs_rock.global_position = Vector2.ZERO
	var obs_integ_before: int = obs_mat.current_durability
	var pickaxe_before_obs: int = pickaxe_dura.current_durability
	await ctx.slash_target(player, Vector2(-40, 0))
	var obs_integ_after: int = obs_mat.current_durability
	var pickaxe_after_obs: int = pickaxe_dura.current_durability
	ctx.check(obs_integ_after == obs_integ_before,
		"obsidian NOT mineable even by the pickaxe -- integrity unchanged (" + str(obs_integ_before) + ")",
		"obsidian integrity wrongly changed (" + str(obs_integ_before) + " -> " + str(obs_integ_after) + ")")
	ctx.check(pickaxe_after_obs == pickaxe_before_obs - 4,
		"pickaxe wore 4 on obsidian (Band C) (" + str(pickaxe_before_obs) + " -> " + str(pickaxe_after_obs) + ")",
		"obsidian pickaxe wear wrong (expected -4, " + str(pickaxe_before_obs) + " -> " + str(pickaxe_after_obs) + ")")

	# --- m. SWORD equipped: attacking the TREE is a total whiff -- Gate 1: the
	# sword's harvest_type NONE != the tree's required_harvest CHOP. No chop on the
	# tree, no wear on the sword.
	obs_rock.global_position = Vector2(3000, 3000)  # keep it clear of the tree checks
	# (both Hurtboxes are 40x40 at the same nominal spot; overlapping them would let
	# a hit on one co-detect the other)
	player.equip_tool(Player.SWORD_DATA)
	var tree: Node2D = main.get_node("Tree") as Node2D
	var tree_mat: DurabilityComponent = tree.get_node("Material") as DurabilityComponent
	tree.global_position = Vector2.ZERO
	var tree_integ_before_sword: int = tree_mat.current_durability
	var sword_before_tree: int = sword_dura.current_durability
	await ctx.slash_target(player, Vector2(-40, 0))
	ctx.check(tree_mat.current_durability == tree_integ_before_sword,
		"sword whiffs on the tree -- integrity unchanged (" + str(tree_integ_before_sword) + ")",
		"sword wrongly chopped the tree (" + str(tree_integ_before_sword) + " -> " + str(tree_mat.current_durability) + ")")
	ctx.check(sword_dura.current_durability == sword_before_tree,
		"sword took 0 wear whiffing on the tree (still " + str(sword_dura.current_durability) + ")",
		"sword wrongly wore whiffing on the tree (" + str(sword_before_tree) + " -> " + str(sword_dura.current_durability) + ")")

	# --- n. PICKAXE equipped: attacking the TREE is also a whiff (Gate 1: MINE !=
	# CHOP) -- wrong tool for this resource.
	player.equip_tool(Player.PICKAXE_DATA)
	var tree_integ_before_pick: int = tree_mat.current_durability
	var pickaxe_before_tree: int = pickaxe_dura.current_durability
	await ctx.slash_target(player, Vector2(-40, 0))
	ctx.check(tree_mat.current_durability == tree_integ_before_pick,
		"pickaxe whiffs on the tree -- integrity unchanged (" + str(tree_integ_before_pick) + ")",
		"pickaxe wrongly chopped the tree (" + str(tree_integ_before_pick) + " -> " + str(tree_mat.current_durability) + ")")
	ctx.check(pickaxe_dura.current_durability == pickaxe_before_tree,
		"pickaxe took 0 wear whiffing on the tree (still " + str(pickaxe_dura.current_durability) + ")",
		"pickaxe wrongly wore whiffing on the tree (" + str(pickaxe_before_tree) + " -> " + str(pickaxe_dura.current_durability) + ")")

	# --- o. AXE equipped: chops the tree. hardness 3 vs axe power 5: over=-2 <= 0 ->
	# Band A -> weapon_wear 0, affects true. Two more hits fell it (integrity 6,
	# wear_taken 2 -> 3 hits to destroy).
	player.equip_tool(Player.AXE_DATA)
	var tree_integ_before_axe: int = tree_mat.current_durability
	var axe_before_tree: int = axe_dura.current_durability
	await ctx.slash_target(player, Vector2(-40, 0))
	ctx.check(tree_mat.current_durability == tree_integ_before_axe - 2,
		"axe chopped the tree -- integrity dropped (" + str(tree_integ_before_axe) + " -> " + str(tree_mat.current_durability) + ")",
		"axe did not chop the tree (" + str(tree_integ_before_axe) + " -> " + str(tree_mat.current_durability) + ")")
	ctx.check(axe_dura.current_durability == axe_before_tree,
		"axe took 0 wear chopping the tree (Band A, still " + str(axe_dura.current_durability) + ")",
		"axe wrongly wore chopping the tree (" + str(axe_before_tree) + " -> " + str(axe_dura.current_durability) + ")")
	await ctx.slash_target(player, Vector2(-40, 0))
	await ctx.slash_target(player, Vector2(-40, 0))
	var tree_watchdog: SceneTreeTimer = ctx.tree.create_timer(2.0)
	while is_instance_valid(tree) and tree_watchdog.time_left > 0.0:
		await ctx.tree.physics_frame
	ctx.check(not is_instance_valid(tree),
		"tree felled after repeated axe chops (destroyed)",
		"tree not felled within watchdog")

	# --- p. SWORD equipped: attacking the OBSIDIAN rock is a total whiff -- Gate 1:
	# harvest_type NONE != required MINE. No integrity change, no sword wear.
	obs_rock.global_position = Vector2.ZERO  # bring it back now that the tree is felled
	player.equip_tool(Player.SWORD_DATA)
	var obs_integ_before_sword: int = obs_mat.current_durability
	var sword_before_obs_whiff: int = sword_dura.current_durability
	await ctx.slash_target(player, Vector2(-40, 0))
	ctx.check(obs_mat.current_durability == obs_integ_before_sword,
		"sword whiffs on the obsidian rock -- integrity unchanged (" + str(obs_integ_before_sword) + ")",
		"sword wrongly affected obsidian (" + str(obs_integ_before_sword) + " -> " + str(obs_mat.current_durability) + ")")
	ctx.check(sword_dura.current_durability == sword_before_obs_whiff,
		"sword took 0 wear whiffing on obsidian (still " + str(sword_dura.current_durability) + ")",
		"sword wrongly wore whiffing on obsidian (" + str(sword_before_obs_whiff) + " -> " + str(sword_dura.current_durability) + ")")

	# --- l. A broken (active) tool gates further wear/damage -----------------
	# In play the blade breaks from accumulated wear; here we force durability to 0
	# deterministically, then prove attack() no-ops (no HP damage, no further wear).
	dummy.global_position = Vector2.ZERO
	player.global_position = Vector2(-30, 0)
	player.facing = Vector2.RIGHT
	player._knockback = Vector2.ZERO
	player._combo_index = 0
	for _i in range(30):
		if not player._attacking:
			break
		await ctx.tree.physics_frame
	for _i in range(10):
		await ctx.tree.physics_frame
	var dummy_hp_pre_break: int = dummy_health.current_health
	sword_dura.wear(sword_dura.current_durability)  # drive to 0 -> emits broke
	await ctx.tree.physics_frame
	ctx.check(player._sword_broken,
		"sword broke latched the gate (_sword_broken true)",
		"sword break did not latch the gate")
	player.attack()
	for _i in range(20):
		await ctx.tree.physics_frame
	ctx.check(dummy_health.current_health == dummy_hp_pre_break and player._combo_index == 0,
		"broken sword gated the attack (no HP damage, no swing)",
		"broken sword still acted (hp " + str(dummy_hp_pre_break) + " -> " + str(dummy_health.current_health) + " combo " + str(player._combo_index) + ")")

	# --- r. Inventory & hotbar integration on the REAL player (design-inventory.md):
	# auto-populate order at _ready(), equip-by-index driving the Sword Hitbox via
	# _apply_equipped(), and the unarmed fallback when the equipped slot is empty.
	ctx.check(player.inventory.item_at(0) == Player.SWORD_DATA
			and player.inventory.item_at(1) == Player.AXE_DATA
			and player.inventory.item_at(2) == Player.PICKAXE_DATA
			and player.inventory.item_at(3) == null and player.inventory.item_at(4) == null
			and player.inventory.item_at(14) == null,
		"player auto-populated at _ready(): sword,axe,pickaxe -> slots 0-2; 3-14 empty",
		"player inventory auto-populate order wrong: " + str(player.inventory.slots))

	player.inventory.equip_index(1)
	player._apply_equipped()
	ctx.check(player._sword.atk == Player.AXE_DATA.atk
			and player._sword.power == Player.AXE_DATA.power
			and player._sword.harvest_type == Player.AXE_DATA.harvest_type,
		"equip_index(1) + _apply_equipped() switched the Sword Hitbox to the axe's stats (atk " + str(Player.AXE_DATA.atk) + ", harvest CHOP)",
		"equip-by-index to axe did not apply axe stats (atk=" + str(player._sword.atk) + " harvest=" + str(player._sword.harvest_type) + ")")
	# Equip also swaps the Blade SILHOUETTE to this tool's shape (presentation; the Hitbox is
	# unchanged). The axe carries its broad-head outline.
	ctx.check(player._blade.polygon == Player.AXE_DATA.blade_shape and not Player.AXE_DATA.blade_shape.is_empty(),
		"equipping the axe swapped the Blade to the axe silhouette (" + str(player._blade.polygon.size()) + " pts)",
		"axe silhouette not applied to the Blade (" + str(player._blade.polygon) + ")")

	player.inventory.equip_index(3)  # an EMPTY slot -- equips "nothing"
	player._apply_equipped()
	ctx.check(player._sword.atk == Player.UNARMED_ATK and player._sword.durability == null
			and player._sword.harvest_type == Harvest.Type.NONE,
		"equipping an EMPTY slot applies the unarmed fallback (atk " + str(Player.UNARMED_ATK) + ", no durability, no harvest)",
		"unarmed fallback wrong (atk=" + str(player._sword.atk) + " durability=" + str(player._sword.durability) + " harvest=" + str(player._sword.harvest_type) + ")")
	# Unarmed restores the DEFAULT rectangle blade -- never leaves the axe's outline behind.
	ctx.check(player._blade.polygon == Equipment.DEFAULT_BLADE_SHAPE,
		"the unarmed fist restored the default rectangle blade",
		"unarmed did not restore the default blade shape (" + str(player._blade.polygon) + ")")

	# Restore the default (sword, slot 0) so nothing downstream is affected.
	player.inventory.equip_index(0)
	player._apply_equipped()
	ctx.check(player._blade.polygon == Player.SWORD_DATA.blade_shape and not Player.SWORD_DATA.blade_shape.is_empty(),
		"re-equipping the sword swapped the Blade to the sword silhouette",
		"sword silhouette not applied on re-equip (" + str(player._blade.polygon) + ")")

	# --- s. Four-facing avatar: side_facing ignores pure up/down, aim does not, AND
	# the Body swaps shape (D-shape sideways, RECTANGLE up/down) with a DOWN-only face.
	# Drives the player via input_override (FrameInput), not real keys, so this is
	# deterministic. `facing` (sword aim, full direction) must update on EVERY non-zero
	# input including pure vertical; `side_facing` (Body left/right flip) must update ONLY
	# when the input has an x component, holding through any pure up/down press. The Avatar
	# (components/avatar.gd) then maps facing -> {D-shape+flip, rectangle, rectangle+face}.
	player.global_position = Vector2(2000, -2000)  # clear of every other entity
	var side_shape: PackedVector2Array = player._avatar.side_shape  # authored D-shape (L/R look)
	var vert_shape: PackedVector2Array = player._avatar.vert_shape   # bbox rectangle (up/down look)
	var drive: FrameInput = FrameInput.new()

	# Facing RIGHT: side_facing 1, scale +1 (unflipped), D-shape body, NO face.
	drive.move = Vector2.RIGHT
	player.input_override = drive
	await ctx.tree.physics_frame
	ctx.check(player.side_facing == 1 and is_equal_approx(player._body.scale.x, 1.0)
			and player._body.polygon == side_shape and not player._face.visible,
		"facing right: side_facing=1, Body scale.x=+1 (unflipped), D-shape body, no face",
		"facing right wrong (side_facing=" + str(player.side_facing) + " scale.x=" + str(player._body.scale.x) + " face=" + str(player._face.visible) + ")")

	# Facing LEFT: side_facing -1, scale -1 (mirrored), still the D-shape, NO face.
	drive.move = Vector2.LEFT
	await ctx.tree.physics_frame
	ctx.check(player.side_facing == -1 and is_equal_approx(player._body.scale.x, -1.0)
			and player._body.polygon == side_shape and not player._face.visible,
		"facing left: side_facing=-1, Body scale.x=-1 (horizontally mirrored, no y shift), D-shape, no face",
		"facing left wrong (side_facing=" + str(player.side_facing) + " scale.x=" + str(player._body.scale.x) + " face=" + str(player._face.visible) + ")")

	# Pure UP (away from viewer): aim tracks UP; side_facing UNCHANGED (no x); Body becomes the
	# RECTANGLE, scale reset to +1 (a back has no left/right), and NO face is shown.
	drive.move = Vector2.UP
	await ctx.tree.physics_frame
	ctx.check(player.facing == Vector2.UP and player.side_facing == -1,
		"pure UP updates aim (facing == UP) but leaves side_facing at -1 (no x component)",
		"pure UP aim/side_facing wrong (facing=" + str(player.facing) + " side_facing=" + str(player.side_facing) + ")")
	ctx.check(player._body.polygon == vert_shape and is_equal_approx(player._body.scale.x, 1.0)
			and not player._face.visible,
		"facing UP: Body is the RECTANGLE (vert shape), scale.x=+1 (no flip), NO face (looking away)",
		"facing UP wrong (polygon==vert? " + str(player._body.polygon == vert_shape) + " scale.x=" + str(player._body.scale.x) + " face=" + str(player._face.visible) + ")")

	# Pure DOWN (toward viewer): aim tracks DOWN; side_facing still UNCHANGED; Body is the
	# RECTANGLE and the FACE is SHOWN (it is looking at the screen).
	drive.move = Vector2.DOWN
	await ctx.tree.physics_frame
	ctx.check(player.facing == Vector2.DOWN and player.side_facing == -1,
		"pure DOWN updates aim (facing == DOWN) but leaves side_facing at -1 (no x component)",
		"pure DOWN aim/side_facing wrong (facing=" + str(player.facing) + " side_facing=" + str(player.side_facing) + ")")
	ctx.check(player._body.polygon == vert_shape and is_equal_approx(player._body.scale.x, 1.0)
			and player._face.visible,
		"facing DOWN: Body is the RECTANGLE (vert shape) AND the face IS shown (looking at the viewer)",
		"facing DOWN wrong (polygon==vert? " + str(player._body.polygon == vert_shape) + " scale.x=" + str(player._body.scale.x) + " face=" + str(player._face.visible) + ")")

	# Diagonal (up-right): has an x component, so it flips side_facing back to right AND (|x|==|y|
	# tie -> horizontal branch) restores the D-shape, no face.
	drive.move = Vector2(1, -1).normalized()
	await ctx.tree.physics_frame
	ctx.check(player.side_facing == 1 and is_equal_approx(player._body.scale.x, 1.0)
			and player._body.polygon == side_shape and not player._face.visible,
		"diagonal up-right flips side_facing to 1 (has an x component) and restores the D-shape, no face",
		"diagonal up-right wrong (side_facing=" + str(player.side_facing) + " scale.x=" + str(player._body.scale.x) + " face=" + str(player._face.visible) + ")")

	player.input_override = null  # release the seam back to real input

	# --- s2. Enemy four-facing avatar (drive the surviving DUMMY, since ctx.enemy is freed
	# after the combat death leg). Make it non-stationary so its _physics_process runs the
	# facing/avatar pass, place the shared player directly above/below it so _facing points
	# UP vs DOWN (x==0 -> the vertical branches), step one physics frame, and assert the
	# Body swapped to its (bigger, bbox-derived) rectangle with the face hidden UP / shown DOWN.
	var dummy_vert: PackedVector2Array = dummy._avatar.vert_shape
	var dummy_face: Polygon2D = dummy.get_node("Body/Face") as Polygon2D
	var dummy_was_stationary: bool = dummy.stationary
	dummy.stationary = false

	# Enemy facing UP: player above the dummy (smaller y) -> _facing == UP, no face.
	dummy.global_position = Vector2(2500, -2500)
	dummy._move_velocity = Vector2.ZERO
	dummy._knockback = Vector2.ZERO
	player.global_position = dummy.global_position + Vector2(0, -100)
	await ctx.tree.physics_frame
	ctx.check(dummy._body.polygon == dummy_vert and not dummy_face.visible,
		"enemy facing UP: Body is the RECTANGLE (its own bbox rectangle) and NO face is shown",
		"enemy facing UP wrong (polygon==vert? " + str(dummy._body.polygon == dummy_vert) + " face=" + str(dummy_face.visible) + " facing=" + str(dummy._facing) + ")")

	# Enemy facing DOWN: player below the dummy (larger y) -> _facing == DOWN, face SHOWN.
	dummy.global_position = Vector2(2500, -2500)
	dummy._move_velocity = Vector2.ZERO
	dummy._knockback = Vector2.ZERO
	player.global_position = dummy.global_position + Vector2(0, 100)
	await ctx.tree.physics_frame
	ctx.check(dummy._body.polygon == dummy_vert and dummy_face.visible,
		"enemy facing DOWN: Body is the RECTANGLE AND the face IS shown (looking at the viewer)",
		"enemy facing DOWN wrong (polygon==vert? " + str(dummy._body.polygon == dummy_vert) + " face=" + str(dummy_face.visible) + " facing=" + str(dummy._facing) + ")")

	dummy.stationary = dummy_was_stationary  # restore the training-dummy hold

# Verified against: Godot 4.7.1 (2026-07-18)
