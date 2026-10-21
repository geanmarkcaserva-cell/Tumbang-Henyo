extends RigidBody3D
## A thrown tsinelas. Spins end over end, gets pushed by the wind while
## airborne, and emits `settled` once it has come to rest.
##
## The HitZone sphere is a forgiving hitbox: if it touches the lata while
## the tsinelas is still moving fast, the lata gets knocked as if hit
## directly. The real collision shape stays slipper-sized so it lands flat.

signal settled
signal hit_target(body: Node3D) ## the hitbox caught something in target_group

## Which group the forgiving hitbox looks for: "lata" for the player's
## throws, "player" for the taya's throws.
@export var target_group := "lata"
## Radius of the forgiving hitbox. The player's throws get a big one,
## the taya's throws a small one so they're dodgeable.
@export var hit_radius := 0.4

const SETTLE_SPEED := 0.3 ## below this speed (m/s) it counts as still
const SETTLE_TIME := 0.4 ## seconds it must stay still
const MAX_LIFETIME := 5.0
const MIN_HIT_SPEED := 3.0 ## the hitbox only counts while the tsinelas is flying fast
const HIT_PUSH := 0.5 ## multiplier on the tsinelas momentum passed to the lata

var _wind_accel := Vector3.ZERO
var _airborne := false
var _time := 0.0
var _still_time := 0.0
var _done := false
var _has_hit := false
var _hurt_bodies: Array[Node3D] = [] ## tayas this throw already hit

## Trail: the arc the tsinelas has flown, drawn as a fading ribbon.
const TRAIL_MAX_POINTS := 90
const TRAIL_WIDTH := 0.16
const TRAIL_FADE_PER_SEC := 60.0 ## points dropped per second once it lands
const TRAIL_COLOR_PLAYER := Color(1.0, 0.95, 0.55)
const TRAIL_COLOR_TAYA := Color(1.0, 0.25, 0.15)
const TRAIL_COLOR_ENCHANTED := Color(0.72, 0.42, 1.0)
const TRAIL_COLOR_ENCHANTED_ALT := Color(0.37, 0.8, 0.9) ## the slipper's cyan strap
static var _star_texture: Texture2D
var _enchanted := false
var _stars: CPUParticles3D
var _trail_points: Array[Vector3] = []
var _trail_mesh := ImmediateMesh.new()
var _trail_drop := 0.0
var _trail: MeshInstance3D

@onready var _hit_zone: Area3D = $HitZone


func _ready() -> void:
	_trail = MeshInstance3D.new()
	_trail.top_level = true
	_trail.mesh = _trail_mesh
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail.extra_cull_margin = 1000.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_trail.material_override = mat
	add_child(_trail)
	_trail.global_transform = Transform3D.IDENTITY
	# Copy the shape so changing the radius doesn't affect other tsinelas.
	var zone_shape: CollisionShape3D = _hit_zone.get_node("CollisionShape3D")
	var sphere := (zone_shape.shape as SphereShape3D).duplicate() as SphereShape3D
	sphere.radius = hit_radius
	zone_shape.shape = sphere
	_hit_zone.body_entered.connect(_on_hit_zone_body_entered)


func launch(velocity: Vector3, wind_accel: Vector3) -> void:
	linear_velocity = velocity
	# Flip end over end around the slipper's own side axis.
	angular_velocity = global_basis.x * randf_range(-14.0, -9.0) + Vector3.UP * randf_range(-2.0, 2.0)
	_wind_accel = wind_accel
	_airborne = true
	_trail_points = [global_position]
	_trail_drop = 0.0


func _process(delta: float) -> void:
	_update_trail(delta)


## Still in its first flight: hasn't touched the ground (or anything) yet.
## A bullseye needs the lata hit while this is true.
func is_clean() -> bool:
	return _airborne and not _done


## Enchanted tsinelas: a shimmering purple trail that leaves stars in its wake.
func set_enchanted(on: bool) -> void:
	_enchanted = on
	if on and _stars == null:
		_stars = _make_stars()
		add_child(_stars)


func _make_stars() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Stars"
	p.emitting = false
	p.amount = 60
	p.lifetime = 1.0
	p.local_coords = false # stars stay where they were dropped
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.15
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.9
	p.gravity = Vector3(0.0, -0.7, 0.0)
	p.damping_min = 0.5
	p.damping_max = 1.5
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.angular_velocity_min = -240.0
	p.angular_velocity_max = 240.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(0.6, 0.85))
	shrink.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = shrink
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.95, 0.6, 1.0)) # gold sparkle...
	ramp.set_color(1, Color(0.55, 0.4, 1.0, 0.0)) # ...fading to violet
	ramp.add_point(0.45, Color(0.85, 0.55, 1.0, 0.95))
	p.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2(0.22, 0.22)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _star()
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	quad.material = mat
	p.mesh = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## A small pixel-art five-point star, drawn once and shared.
static func _star() -> Texture2D:
	if _star_texture:
		return _star_texture
	var n := 24
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI / 2.0 + i * PI / 5.0
		var r := n * 0.48 if i % 2 == 0 else n * 0.2
		pts.append(Vector2(n / 2.0, n / 2.0) + Vector2(cos(a), sin(a)) * r)
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), pts):
				img.set_pixel(x, y, Color.WHITE)
	_star_texture = ImageTexture.create_from_image(img)
	return _star_texture


func _update_trail(delta: float) -> void:
	var flying := _airborne and linear_velocity.length() > MIN_HIT_SPEED * 0.5
	if _stars:
		_stars.emitting = flying
	if flying:
		if _trail_points.is_empty() or _trail_points[-1].distance_to(global_position) > 0.12:
			_trail_points.append(global_position)
			if _trail_points.size() > TRAIL_MAX_POINTS:
				_trail_points.remove_at(0)
	elif not _trail_points.is_empty():
		# Landed: the trail shrinks away from its oldest end.
		_trail_drop += TRAIL_FADE_PER_SEC * delta
		while _trail_drop >= 1.0 and not _trail_points.is_empty():
			_trail_points.remove_at(0)
			_trail_drop -= 1.0
	_trail_mesh.clear_surfaces()
	var n := _trail_points.size()
	if n < 2:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var eye := cam.global_position
	var base: Color = TRAIL_COLOR_PLAYER if target_group == "lata" else TRAIL_COLOR_TAYA
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in n:
		var p := _trail_points[i]
		var dir := _trail_points[mini(i + 1, n - 1)] - _trail_points[maxi(i - 1, 0)]
		var side := dir.cross(eye - p).normalized()
		var k := float(i) / float(n - 1) # 0 = tail, 1 = head
		var col := base
		col.a = 0.08 + 0.72 * k
		var half := TRAIL_WIDTH * (0.35 + 0.65 * k) * 0.5
		if _enchanted:
			# Shimmer: purple and cyan bands rippling down a wider trail.
			var wave := 0.5 + 0.5 * sin(i * 0.9 - _time * 14.0)
			col = TRAIL_COLOR_ENCHANTED.lerp(TRAIL_COLOR_ENCHANTED_ALT, wave)
			col.a = (0.15 + 0.8 * k) * (0.75 + 0.25 * wave)
			half *= 1.35
		_trail_mesh.surface_set_color(col)
		_trail_mesh.surface_add_vertex(p - side * half)
		_trail_mesh.surface_set_color(col)
		_trail_mesh.surface_add_vertex(p + side * half)
	_trail_mesh.surface_end()


func _physics_process(delta: float) -> void:
	if _done:
		return
	_time += delta
	if get_contact_count() > 0:
		if _airborne: # first touch: slaps the concrete
			Sfx.play_at("slap_ground", global_position, 0.0 if target_group == "lata" else -4.0)
		_airborne = false
	if _airborne:
		apply_central_force(_wind_accel * mass)
	_keep_in_play_area()

	if _time > 0.3 and linear_velocity.length() < SETTLE_SPEED:
		_still_time += delta
	else:
		_still_time = 0.0

	if _still_time > SETTLE_TIME or _time > MAX_LIFETIME or global_position.y < -5.0:
		_done = true
		settled.emit()


## Never leave the barangay: if a slipper somehow gets past the invisible wall
## round the fence, it's put back inside and bounced back in.
func _keep_in_play_area() -> void:
	var root := get_tree().root
	if not root.has_meta("play_area"):
		return
	var area: Rect2 = (root.get_meta("play_area") as Rect2).grow(-0.4)
	var p := global_position
	var v := linear_velocity
	var moved := false
	if p.x < area.position.x or p.x > area.end.x:
		p.x = clampf(p.x, area.position.x, area.end.x)
		v.x = -v.x * 0.5
		moved = true
	if p.z < area.position.y or p.z > area.end.y:
		p.z = clampf(p.z, area.position.y, area.end.y)
		v.z = -v.z * 0.5
		moved = true
	if moved:
		global_position = p
		linear_velocity = v


func _on_hit_zone_body_entered(body: Node3D) -> void:
	# The player's throw caught a taya on the way: it reacts (squish, red flash).
	if target_group == "lata" and body.is_in_group("taya") and not _hurt_bodies.has(body) \
			and linear_velocity.length() >= MIN_HIT_SPEED and body.has_method("hurt"):
		_hurt_bodies.append(body)
		body.hurt()
		Sfx.play_at("bonk", body.global_position)
	if _has_hit or not body.is_in_group(target_group):
		return
	if linear_velocity.length() < MIN_HIT_SPEED:
		return
	_has_hit = true
	if body is RigidBody3D:
		var rigid := body as RigidBody3D
		var push := linear_velocity * mass * HIT_PUSH
		push.y = maxf(push.y, 0.4) # always a little lift so it tips instead of sliding
		rigid.sleeping = false
		# Hit slightly above its middle so it topples over.
		rigid.apply_impulse(push, Vector3(0.0, 0.12, 0.0))
	hit_target.emit(body)
