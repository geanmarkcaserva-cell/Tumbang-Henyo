// Extra pass for 3D meshes (the thrown tsinelas): adds the enchantment glint
// on top of the normal material. Uses object-space position, so it follows
// the slipper as it spins and needs no UVs.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

#include "res://scenes/game/enchant_glint.gdshaderinc"

uniform float glint_scale = 9.0; // bands per metre

varying vec3 obj_pos;

void vertex() {
	obj_pos = VERTEX;
	VERTEX += NORMAL * 0.002; // sit just above the surface, no z-fighting
}

void fragment() {
	vec2 p = vec2(obj_pos.x + obj_pos.y, obj_pos.z - obj_pos.y) * glint_scale;
	ALBEDO = glint_color.rgb * glint(p, TIME) * glint_strength;
}
