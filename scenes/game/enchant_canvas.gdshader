// 2D version of the enchantment glint (TextureRect / Sprite2D). 2D isn't
// tone-mapped like the 3D view, so the slipper art keeps its exact colours;
// only the glint is added on top, snapped to the art's pixel grid.
shader_type canvas_item;

#include "res://scenes/game/enchant_glint.gdshaderinc"

varying vec4 tint; // the node's modulate (vertex colour), kept apart from the texture

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec2 size = 1.0 / TEXTURE_PIXEL_SIZE;
	vec2 px = floor(UV * size) / size;
	float g = glint(px * 3.0, TIME);
	COLOR = vec4((c.rgb + glint_color.rgb * g * glint_strength) * tint.rgb, c.a * tint.a);
}
