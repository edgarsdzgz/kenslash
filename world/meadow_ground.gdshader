// Meadow biome ground (design-environment.md #1, DECIDED: noise shader).
//
// Renders a splotchy grassy meadow into a full-screen background ColorRect that sits on a
// LOW CanvasLayer BEHIND the streamed world + entities. The pattern is anchored to WORLD
// space (not screen space): each fragment reconstructs the world position under it from the
// camera's screen-center + zoom + viewport size (fed as uniforms by streaming_world.gd every
// frame), then samples low-frequency value/FBM noise of THAT world position to blend a green
// palette. So panning the camera scrolls the meadow under the view -- it never shimmers or
// stays put in screen space. Fully DETERMINISTIC: no TIME, no per-pixel randomness beyond the
// value-noise hash of the world coordinate (a subtle wind sway is a future, opt-in nicety).
//
// Layers, cheapest first:
//   * macro FBM   -> large smooth light/dark green variation (kills the flat-gray look).
//   * dirt FBM    -> sparse mid-frequency brown patches (bare earth showing through).
//   * flower value-> rare high-frequency pale specks (flower accents).
shader_type canvas_item;
render_mode unshaded;

// --- World-mapping uniforms (updated per frame from streaming_world.gd) ---------------------
// Camera screen-center in WORLD pixels (Camera2D.get_screen_center_position()).
uniform vec2 cam_center = vec2(0.0, 0.0);
// Camera2D.zoom (higher = more zoomed in; world-per-screen-pixel = 1.0 / zoom).
uniform vec2 cam_zoom = vec2(1.0, 1.0);
// Viewport size in pixels (get_viewport_rect().size).
uniform vec2 viewport_size = vec2(1152.0, 648.0);

// --- Palette uniforms (tunable; defaults from design-environment.md "1. Meadow biome ground") -
uniform vec3 base_green : source_color = vec3(0.36, 0.54, 0.29);
uniform vec3 light_green : source_color = vec3(0.44, 0.63, 0.33);
uniform vec3 dark_green : source_color = vec3(0.29, 0.44, 0.23);
uniform vec3 dirt_color : source_color = vec3(0.48, 0.42, 0.31);
uniform vec3 flower_color : source_color = vec3(0.90, 0.92, 0.70);

// --- Noise frequencies (cycles per world pixel; low = large smooth blobs) -------------------
uniform float macro_freq = 0.0016;
uniform float dirt_freq = 0.010;
uniform float flower_freq = 0.055;

// Hash a 2D lattice point to a scalar in [0, 1) (deterministic value-noise source).
float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

// Bilinear value noise with a smoothstep fade -> smooth blobs, no grid seams.
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// 4-octave fractal Brownian motion for richer, less repetitive variation.
float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * vnoise(p);
		p *= 2.0;
		amp *= 0.5;
	}
	return v;
}

void fragment() {
	// Reconstruct this fragment's WORLD position: screen-center + the pixel offset from the
	// screen middle, converted screen->world by dividing out the camera zoom. This is the
	// world-anchored invariant -- the noise below is sampled in world space, so it scrolls
	// with the world as the camera follows the player.
	vec2 world = cam_center + (SCREEN_UV - vec2(0.5)) * viewport_size / cam_zoom;

	// Macro greens: large smooth light<->dark blend, then nudged toward the base green so the
	// meadow reads as one biome rather than two flat tints.
	float macro = fbm(world * macro_freq);
	vec3 col = mix(dark_green, light_green, smoothstep(0.30, 0.70, macro));
	col = mix(col, base_green, 0.35);

	// Sparse dirt patches: only the high tail of a mid-frequency FBM shows bare earth.
	float dirt = fbm(world * dirt_freq + vec2(31.7, 12.3));
	col = mix(col, dirt_color, smoothstep(0.68, 0.86, dirt) * 0.75);

	// Rare pale flower specks: the very high tail of a high-frequency value field.
	float flower = vnoise(world * flower_freq + vec2(7.1, 91.2));
	col = mix(col, flower_color, smoothstep(0.90, 0.97, flower) * 0.6);

	COLOR = vec4(col, 1.0);
}
