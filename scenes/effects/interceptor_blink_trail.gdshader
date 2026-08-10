shader_type canvas_item;

uniform vec4 tint_color : source_color = vec4(1.0);

void fragment() {
	vec4 modulation = COLOR;
	vec4 sampled = texture(TEXTURE, UV);
	float luminance = dot(sampled.rgb, vec3(0.2126, 0.7152, 0.0722));
	float white_core = smoothstep(0.72, 0.94, luminance);
	vec3 tinted = sampled.rgb * tint_color.rgb;
	COLOR = vec4(mix(tinted, vec3(1.0), white_core), sampled.a) * modulation;
}
