shader_type canvas_item;

// Vertical base gradient (top → middle → bottom)
uniform vec3 deep_top : source_color = vec3(0.078, 0.030, 0.040);
uniform vec3 deep_mid : source_color = vec3(0.040, 0.016, 0.016);
uniform vec3 deep_btm : source_color = vec3(0.012, 0.004, 0.004);

// Warm radial glow (top-left)
uniform vec3 warm_glow : source_color = vec3(0.85, 0.32, 0.18);
uniform float warm_glow_strength : hint_range(0.0, 1.0) = 0.32;
uniform vec2 warm_glow_pos = vec2(0.30, 0.25);
uniform float warm_glow_radius : hint_range(0.05, 1.5) = 0.55;

// Deep blob (bottom-right)
uniform vec3 deep_blob : source_color = vec3(0.157, 0.039, 0.031);
uniform float deep_blob_strength : hint_range(0.0, 1.0) = 0.70;
uniform vec2 deep_blob_pos = vec2(0.78, 0.85);
uniform float deep_blob_radius : hint_range(0.05, 1.5) = 0.55;

// Drifting fog
uniform float fog_speed : hint_range(0.0, 0.5) = 0.015;
uniform float fog_strength : hint_range(0.0, 0.5) = 0.10;
uniform vec3 fog_tint : source_color = vec3(0.20, 0.13, 0.09);

// Vignette
uniform float vignette_inner : hint_range(0.0, 1.0) = 0.30;
uniform float vignette_outer : hint_range(0.1, 1.5) = 0.85;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.85;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

void fragment() {
	vec2 uv = UV;

	// Vertical base gradient (mirrors CSS linear-gradient(180deg, top 0%, mid 60%, btm 100%))
	vec3 base;
	if (uv.y < 0.6) {
		base = mix(deep_top, deep_mid, uv.y / 0.6);
	} else {
		base = mix(deep_mid, deep_btm, (uv.y - 0.6) / 0.4);
	}

	// Top-left warm radial glow (additive)
	float dw = length(uv - warm_glow_pos);
	float warm_t = 1.0 - smoothstep(0.0, warm_glow_radius, dw);
	base += warm_glow * warm_t * warm_glow_strength;

	// Bottom-right deep blob (tints toward deep_blob)
	float dd = length(uv - deep_blob_pos);
	float deep_t = 1.0 - smoothstep(0.0, deep_blob_radius, dd);
	base = mix(base, deep_blob, deep_t * deep_blob_strength);

	// Slow drifting fog
	float n = noise(uv * vec2(2.0, 1.5) + vec2(TIME * fog_speed, TIME * fog_speed * 0.35));
	base += fog_tint * n * fog_strength;

	// Vignette (multiplicative darkening toward edges)
	float vd = length(uv - vec2(0.5));
	float vig_t = smoothstep(vignette_inner, vignette_outer, vd);
	base = mix(base, vec3(0.0), vig_t * vignette_strength);

	COLOR = vec4(base, 1.0);
}
