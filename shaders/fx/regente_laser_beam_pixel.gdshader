// Candidate only: pixel-safe sampling for the V3 laser tiles.
// Import settings: repeat enabled for beam-active; filter = nearest for all V3 textures.
shader_type canvas_item;

void fragment() {
    vec2 texel = 1.0 / vec2(textureSize(TEXTURE, 0));
    vec2 snapped_uv = (floor(UV / texel) + vec2(0.5)) * texel;
    COLOR = texture(TEXTURE, snapped_uv);
}
