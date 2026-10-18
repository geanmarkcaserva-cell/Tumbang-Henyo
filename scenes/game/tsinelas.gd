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

## Trail: the arc the tsinelas has flown, drawn as a fading ribbon.
const TRAIL_MAX_POINTS := 90
const TRAIL_WIDTH := 0.16
const TRAIL_FADE_PER_SEC := 60.0 ## points dropped per second once it lands
const TRAIL_COLOR_PLAYER := Color(1.0, 0.95, 0.55)
const TRAIL_COLOR_TAYA := Color(1.0, 0.25, 0.15)
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


func _update_trail(delta: float) -> void:
	var flying := _airborne and linear_velocity.length() > MIN_HIT_SPEED * 0.5
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
		_airborne = false
	if _airborne:
		apply_central_force(_wind_accel * mass)

	if _time > 0.3 and linear_velocity.length() < SETTLE_SPEED:
		_still_time += delta
	else:
		_still_time = 0.0

	if _still_time > SETTLE_TIME or _time > MAX_LIFETIME or global_position.y < -5.0:
		_done = true
		settled.emit()


func _on_hit_zone_body_entered(body: Node3D) -> void:
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
