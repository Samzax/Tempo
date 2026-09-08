shader_type canvas_item;
render_mode unshaded;
// Only the star field repeats. Transparent planet frames never do.
uniform sampler2D space_field : filter_nearest, repeat_enable;
uniform float source_offset_native_px = 0.0;

const float FIELD_WIDTH = 1928.0;
const float VIEW_WIDTH = 640.0;
const float LOOP_WIDTH = 1288.0;
const float SEAM_BLEND_WIDTH = 160.0;

vec4 sample_field(vec2 canvas_uv, float positive_offset) {
	// Helpers do not inherit fragment built-ins. Every source window coordinate
	// is explicitly bounded positive before sampling Compatibility/OpenGL.
	vec2 field_uv = vec2(
		clamp((canvas_uv.x * VIEW_WIDTH + positive_offset) / FIELD_WIDTH, 0.0, 1.0),
		clamp((canvas_uv.y * 360.0 + 160.0) / 1197.0, 0.0, 1.0)
	);
	return texture(space_field, field_uv);
}

void fragment() {
	float phase = clamp(source_offset_native_px, 0.0, LOOP_WIDTH);
	float blend = smoothstep(LOOP_WIDTH - SEAM_BLEND_WIDTH, LOOP_WIDTH, phase);
	// At the end of the source window this has fully become the start window;
	// the following fposmod wrap therefore has the same sampled content.
	vec4 outgoing = sample_field(UV, phase);
	vec4 incoming = sample_field(UV, max(phase - LOOP_WIDTH, 0.0));
	COLOR = mix(outgoing, incoming, blend);
}
