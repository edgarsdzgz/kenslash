class_name TestGround extends RefCounted
## Meadow biome ground (design-environment.md #1, DECIDED: a noise shader) -- STRUCTURAL leg.
## Instantiates the shipped streaming_world.tscn and proves the ground background is wired the
## way the design requires: a background node exists, it draws BEHIND the world content (a LOW
## CanvasLayer, negative `layer`), and it carries a ShaderMaterial whose shader IS the meadow
## shader with a palette uniform set. Headless CANNOT read rendered pixels, so this asserts the
## node/material STRUCTURE only -- never a sampled colour. Self-contained: builds its own
## streaming_world instance, frees it at the end, and touches no game state.


func run(ctx: TestContext) -> void:
	print("[ground] --- meadow ground: background shader layer behind the world ---")
	var sw_scene: PackedScene = load("res://world/streaming_world.tscn")
	ctx.check(sw_scene != null,
		"streaming_world.tscn loads (hosts the meadow ground layer)",
		"streaming_world.tscn failed to load")
	if sw_scene == null:
		return
	var sw: Node2D = sw_scene.instantiate()
	ctx.tree.root.add_child(sw)
	await ctx.settle_idle()

	# The ground lives on a CanvasLayer whose negative `layer` draws it BEHIND the default
	# layer-0 world content (ChunkManager + entities) -- so the meadow is a backdrop, never over.
	var ground_layer: CanvasLayer = sw.get_node_or_null("GroundLayer") as CanvasLayer
	ctx.check(ground_layer != null and ground_layer.layer < 0,
		"ground background is a CanvasLayer BEHIND the world (layer " + str(ground_layer.layer if ground_layer != null else 0) + " < 0)",
		"ground CanvasLayer missing or not behind the world content")

	# The background is a full-rect ColorRect carrying a ShaderMaterial whose shader is the
	# meadow shader -- the noise-shader biome technique the design DECIDED on.
	var ground: ColorRect = sw.get_node_or_null("GroundLayer/Ground") as ColorRect
	var mat: ShaderMaterial = ground.material as ShaderMaterial if ground != null else null
	var shader_ok: bool = mat != null and mat.shader != null \
		and mat.shader.resource_path == "res://world/meadow_ground.gdshader"
	ctx.check(shader_ok,
		"ground ColorRect carries a ShaderMaterial running meadow_ground.gdshader",
		"ground ShaderMaterial/shader not wired to meadow_ground.gdshader")

	# A palette uniform is set (the meadow greens, not gray) -- proves the material is configured,
	# not a bare default shader. We assert presence/type only, never a rendered colour.
	var base_green: Variant = mat.get_shader_parameter("base_green") if mat != null else null
	ctx.check(base_green is Color,
		"ground material sets the base_green palette uniform (" + str(base_green) + ")",
		"ground material base_green palette uniform not set")

	sw.queue_free()
	await ctx.tree.physics_frame

# Verified against: Godot 4.7.1 (2026-07-19)
