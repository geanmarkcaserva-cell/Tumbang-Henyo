class_name SkyBodies
extends Node3D
## The sun, the moon and the clouds (art/environment/Sun.png, Moon.png,
## Cloud var 1-3). The sun and the moon sit in the sky
## right where their light comes from, each with a soft glow around it. The
## sun shows by day; as night falls (DayNight sets `night`) it fades and the
## moon takes over.
##
## High quality (Settings) adds light rays: a screen-space pass that streams
## light out from the sun or moon, cut by the houses, posts and trees in front
## of it (the Compatibility renderer has no volumetric fog, so this is how).
##
## Works anywhere with a DirectionalLight3D: the game (with DayNight) and the
## main menu (golden hour, always the sun).

const SUN_TEX := preload("res://art/environment/sky/Sun.png")
const MOON_TEX := preload("res://art/environment/sky/Moon.png")
const RAYS_SHADER := preload("res://scenes/game/light_rays.gdshader")
const CLOUD_SHADER := preload("res://scenes/game/sky_cloud.gdshader") ## dark body, sunlit rim
const DISTANCE := 260.0 ## metres from the camera (the game camera draws up to 300)
const SUN_SIZE := 9.0 ## degrees across (stylised: bigger than the real one)
const MOON_SIZE := 7.0
const GLOW_SCALE := 3.2 ## the glow around them, times their size
## Clouds (art/environment/Cloud var 1-3): curved patches on a sky dome
## centred on the camera, so they are fixed to the world like the sky itself
## (upright, level with the horizon; turning or zooming the camera doesn't
## tilt or slide them). They drift slowly round the dome, a little closer than
## the sun so they can pass in front of it. Hidden in low detail mode.
const CLOUD_TEXTURES := [
	preload("res://art/environment/sky/Cloud var 1.png"),
	preload("res://art/environment/sky/Cloud var 2.png"),
	preload("res://art/environment/sky/Cloud var 3.png"),
]
const CLOUD_COUNT := 12 ## (4 of each picture)
const CLOUD_DISTANCE := 230.0
const CLOUD_SIZE := Vector2(28.0, 46.0) ## degrees across (the picture is square, the cloud a wide strip in it)
const CLOUD_HEIGHT := Vector2(6.0, 30.0) ## degrees above the horizon (the middle of the picture)
const CLOUD_SEGMENTS := Vector2i(10, 6) ## how finely each patch follows the dome
const CLOUD_OPACITY := Vector2(0.50, 0.90) ## each cloud picks its own opacity in this range (0 = invisible, 1 = solid)

var light: DirectionalLight3D
var night := 0.0 ## 0 = the sun is out, 1 = the moon
var sun_tint := Color(1.0, 0.85, 0.65) ## DayNight passes the sunlight's colour
## Cloud colours (DayNight sets them through the evening; these are 5 PM, for the menu):
var cloud_body := Color(0.86, 0.82, 0.86) ## the shaded bulk
var cloud_lit := Color(1.0, 0.9, 0.7) ## the edges facing the sun / moon

var _sun: MeshInstance3D
var _moon: MeshInstance3D
var _sun_glow: MeshInstance3D
var _moon_glow: MeshInstance3D
var _rays_layer: CanvasLayer
var _rays: ShaderMaterial
var _clouds: Array = [] ## {mesh, azimuth, elevation, speed} (radians)


func _ready() -> void:
	top_level = true
	_sun = _disc(SUN_TEX, SUN_SIZE, true) # added on: it glows brighter than the sky
	_moon = _disc(MOON_TEX, MOON_SIZE, false)
	_sun_glow = _disc(_glow_texture(), SUN_SIZE * GLOW_SCALE, true)
	_moon_glow = _disc(_glow_texture(), MOON_SIZE * GLOW_SCALE, true)
	for i in CLOUD_COUNT:
		var tex: Texture2D = CLOUD_TEXTURES[i % CLOUD_TEXTURES.size()]
		var el := deg_to_rad(randf_range(CLOUD_HEIGHT.x, CLOUD_HEIGHT.y))
		_clouds.append({
			"mesh": _cloud_patch(tex, deg_to_rad(randf_range(CLOUD_SIZE.x, CLOUD_SIZE.y)), el),
			"azimuth": (float(i) + randf_range(-0.35, 0.35)) / CLOUD_COUNT * TAU, # spread all round
			"speed": deg_to_rad(randf_range(0.25, 0.6)), # degrees a second, all the same way
			"alpha": randf_range(CLOUD_OPACITY.x, CLOUD_OPACITY.y),
		})
	# Light rays: a full-screen pass over the 3D view, under the HUD.
	_rays_layer = CanvasLayer.new()
	_rays_layer.layer = -1
	add_child(_rays_layer)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rays = ShaderMaterial.new()
	_rays.shader = RAYS_SHADER
	rect.material = _rays
	_rays_layer.add_child(rect)
	_rays_layer.visible = false


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or light == null:
		return
	var eye := cam.global_position
	var to_sky := light.global_basis.z.normalized() # the light shines along -Z: the sun is up +Z
	var at := eye + to_sky * DISTANCE
	var day := 1.0 - clampf(night, 0.0, 1.0)
	for pair in [[_sun, _sun_glow, day], [_moon, _moon_glow, 1.0 - day]]:
		var disc: MeshInstance3D = pair[0]
		var glow: MeshInstance3D = pair[1]
		var a: float = pair[2]
		disc.visible = a > 0.01
		glow.visible = a > 0.01
		disc.global_position = at
		glow.global_position = at + to_sky * 1.0 # just behind the disc
		var tint := Color.WHITE.lerp(sun_tint, 0.45) if disc == _sun else Color(0.92, 0.95, 1.0)
		(disc.material_override as StandardMaterial3D).albedo_color = Color(tint, a)
		var glow_col := sun_tint if disc == _sun else Color(0.6, 0.7, 1.0)
		(glow.material_override as StandardMaterial3D).albedo_color = Color(glow_col, a * (0.55 if disc == _sun else 0.35))
	_update_clouds(eye, delta, to_sky)
	_update_rays(cam, to_sky, day)


func _update_clouds(eye: Vector3, delta: float, to_sky: Vector3) -> void:
	var shown := not Settings.low_detail
	var sun_flat := Vector3(to_sky.x, 0.0, to_sky.z).normalized()
	for c in _clouds:
		var mi: MeshInstance3D = c.mesh
		mi.visible = shown
		if not shown:
			continue
		c.azimuth = fposmod(c.azimuth + c.speed * delta, TAU)
		# The dome moves with the camera (so it's always out of reach, like the
		# sky) but never turns with it: only the drift turns it, round the up axis.
		mi.global_transform = Transform3D(Basis(Vector3.UP, c.azimuth), eye)
		# Where the light is from this cloud: behind it (glows all over) or off
		# to one side (only that edge catches it).
		var facing := Vector3(sin(c.azimuth), 0.0, cos(c.azimuth))
		var right := Vector3(-cos(c.azimuth), 0.0, sin(c.azimuth)) # the viewer's right, looking at it
		var m := mi.material_override as ShaderMaterial
		m.set_shader_parameter("sun_near", smoothstep(-0.2, 1.0, facing.dot(sun_flat)))
		m.set_shader_parameter("sun_side", right.dot(sun_flat))
		m.set_shader_parameter("body_color", cloud_body)
		m.set_shader_parameter("lit_color", cloud_lit)
		m.set_shader_parameter("opacity", c.alpha)


func _update_rays(cam: Camera3D, to_sky: Vector3, day: float) -> void:
	var on := Settings.high_quality
	_rays_layer.visible = on
	if not on:
		return
	var vp := get_viewport().get_visible_rect().size
	var far_point := cam.global_position + to_sky * 1000.0
	# Facing it: full rays; looking away: they fade out.
	var facing := smoothstep(0.05, 0.6, (-cam.global_basis.z).dot(to_sky))
	if cam.is_position_behind(far_point):
		facing = 0.0
	var screen := cam.unproject_position(far_point) / vp if facing > 0.0 else Vector2(0.5, -1.0)
	_rays.set_shader_parameter("light_pos", screen)
	_rays.set_shader_parameter("aspect", vp.x / vp.y)
	var sun_col := Color(sun_tint.r, sun_tint.g * 0.92, sun_tint.b * 0.8)
	var col := sun_col.lerp(Color(0.55, 0.65, 1.0), 1.0 - day)
	_rays.set_shader_parameter("ray_color", Vector3(col.r, col.g, col.b))
	_rays.set_shader_parameter("intensity", facing * lerpf(0.6, 0.45, day))
	# By day the bright sky around the sun shines; at night only the moon does.
	_rays.set_shader_parameter("threshold", lerpf(0.55, 0.72, day))


## A flat card that always faces the camera, unlit and out of the fog.
func _disc(tex: Texture2D, degrees: float, additive: bool) -> MeshInstance3D:
	var quad := QuadMesh.new()
	var s := 2.0 * DISTANCE * tan(deg_to_rad(degrees) * 0.5)
	quad.size = Vector2(s, s)
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.disable_fog = true
	m.disable_receive_shadows = true
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 16384.0
	add_child(mi)
	return mi


## One cloud: a piece of the sky dome (radius CLOUD_DISTANCE) facing +Z, the
## picture `size` radians tall with its middle `elevation` above the horizon.
## Rows follow the horizon, so the cloud stays level wherever you look.
func _cloud_patch(tex: Texture2D, size: float, elevation: float) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Wider in azimuth higher up, so the picture keeps its shape on the dome.
	var span_a := size / maxf(cos(elevation), 0.3)
	var nx := CLOUD_SEGMENTS.x
	var ny := CLOUD_SEGMENTS.y
	for y in ny + 1:
		var v := float(y) / ny
		var e := elevation + size * (0.5 - v) # v = 0 is the top of the picture
		for x in nx + 1:
			var u := float(x) / nx
			var a := span_a * (0.5 - u) # seen from inside, +X is on the left
			st.set_uv(Vector2(u, v))
			st.add_vertex(Vector3(cos(e) * sin(a), sin(e), cos(e) * cos(a)) * CLOUD_DISTANCE)
	for y in ny:
		for x in nx:
			var i := y * (nx + 1) + x
			var j := i + nx + 1
			for k in [i, j, i + 1, i + 1, j, j + 1]:
				st.add_index(k)
	var m := ShaderMaterial.new()
	m.shader = CLOUD_SHADER
	m.set_shader_parameter("tex", tex)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 16384.0
	add_child(mi)
	return mi


## Soft round glow, bright in the middle.
static func _glow_texture() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.9))
	g.set_color(1, Color(1, 1, 1, 0.0))
	g.add_point(0.25, Color(1, 1, 1, 0.35))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	return t
