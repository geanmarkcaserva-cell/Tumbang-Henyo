extends Node3D
## Minecraft-style beacon over the house the player must reach in the Mama
## round: a tall beam of light (bright core, soft outer glow, light pulses
## running up it) visible from anywhere in the barangay, plus a glowing ring on
## the ground around the house so you know where "there" is.

const HEIGHT := 160.0
var color := Color(0.55, 0.92, 1.0) ## set before adding (Mama: blue; items: gold)

const BEAM_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec3 beam_color : source_color = vec3(0.55, 0.92, 1.0);
uniform float strength = 1.0;
uniform float height = 160.0;
uniform float soft = 2.0;
varying float h;
void vertex() {
	h = VERTEX.y / height + 0.5;
}
void fragment() {
	// Soft edges measured across the beam only (ignoring the up axis), so it
	// stays bright when you look at it from above or below.
	vec3 axis = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	vec3 v = VIEW - axis * dot(VIEW, axis);
	float facing = length(v) > 0.001 ? abs(dot(normalize(NORMAL), normalize(v))) : 1.0;
	float edge = pow(facing, soft);
	float top = 1.0 - smoothstep(0.35, 1.0, h);
	float pulse = 0.82 + 0.18 * sin(h * 220.0 - TIME * 7.0);
	ALBEDO = beam_color * strength * pulse;
	ALPHA = clamp(edge * top, 0.0, 1.0);
}
"""

var footprint_radius := 4.0 ## set before adding: size of the ground ring

var _ring: MeshInstance3D
var _light: OmniLight3D
var _t := 0.0


func _ready() -> void:
	var shader := Shader.new()
	shader.code = BEAM_SHADER
	_add_beam(shader, 0.7, Color(0.92, 1.0, 1.0), 1.3, 1.2) # white-hot core
	_add_beam(shader, 2.4, color, 0.9, 2.2) # coloured glow around it

	# Ground ring around the house.
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = footprint_radius
	torus.outer_radius = footprint_radius + 0.35
	torus.rings = 48
	torus.ring_segments = 4
	_ring.mesh = torus
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(color.r, color.g, color.b, 0.85)
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring.material_override = rm
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.scale = Vector3(1.0, 0.15, 1.0)
	_ring.position.y = 0.08
	add_child(_ring)

	_light = OmniLight3D.new()
	_light.light_color = color
	_light.light_energy = 2.5
	_light.omni_range = footprint_radius + 6.0
	_light.position.y = 2.5
	add_child(_light)


func _add_beam(shader: Shader, radius: float, col: Color, strength: float, soft: float) -> void:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = HEIGHT
	cyl.radial_segments = 12
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	mi.mesh = cyl
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("beam_color", col)
	mat.set_shader_parameter("strength", strength)
	mat.set_shader_parameter("height", HEIGHT)
	mat.set_shader_parameter("soft", soft)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = HEIGHT * 0.5
	# Never culled away: it's the thing you navigate by.
	mi.extra_cull_margin = 16384.0
	add_child(mi)


func _process(delta: float) -> void:
	_t += delta
	var s := 1.0 + 0.06 * sin(_t * 4.0)
	_ring.scale = Vector3(s, 0.15, s)
	_light.light_energy = 2.2 + 0.6 * sin(_t * 4.0)
