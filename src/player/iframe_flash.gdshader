shader_type canvas_item;

uniform float flash : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	c.rgb = mix(c.rgb, vec3(1.0), flash);
	COLOR = c * COLOR;
}
