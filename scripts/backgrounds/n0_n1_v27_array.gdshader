shader_type canvas_item;
render_mode unshaded;
// Transparent V27 planet render, independent of the field and never repeated.
uniform sampler2D planet_frame : filter_nearest, repeat_disable;
uniform float planet_offset_native_px = 0.0;
void fragment() {
	float travel = planet_offset_native_px / 640.0;
	vec2 uv = vec2(UV.x + travel, UV.y);
	COLOR = uv.x <= 1.0 ? texture(planet_frame, uv) : vec4(0.0);
}
