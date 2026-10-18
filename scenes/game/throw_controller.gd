extends Node3D
## Handles one tsinelas throw: hold `throw` to charge (the gauge swings
## up and down), release to launch. While charging, a thick dashed preview
## shows the flight path and a circle marks where the tsinelas will land.

signal power_changed(value: float)
signal thrown
signal settled ## the thrown tsinelas came to rest

const TSINELAS_SCENE := preload("res://scenes/game/tsinelas.tscn")

@export var min_speed := 8.0
@export var max_speed := 24.0
@export var elevation_deg := 25.0 ## added on top of the camera pitch
@export var charge_cycles_per_sec := 0.8 ## full low-high-low swings per second
@export var wind_factor := 0.6 ## wind (m/s) -> sideways acceleration (m/s^2)
@export var preview_step := 0.03
@export var preview_max_time := 3.0

const DASH_WIDTH := 0.09 ## metres
const DASH_COLOR := Color(1.0, 0.86, 0.2, 0.95)
const DASH_OUTLINE := Color(0.12, 0.05, 0.02, 0.75)
const LANDING_RADIUS := 0.55

var active := false
var power := 0.0
var wind := Vector3.ZERO
var preview_fraction := 1.0

var _player: Node3D
var _charging := false
var _charge_time := 0.0
var _tsinelas: RigidBody3D
var _preview_mesh := ImmediateMesh.new()
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var _preview: MeshInstance3D = $Preview


func _ready() -> void:
	_preview.mesh = _preview_mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.render_priority = 10
	_preview.material_override = mat
	_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_preview.extra_cull_margin = 1000.0


## Start aiming. wind_vec is horizontal wind in m/s.
func begin(player: Node3D, wind_vec: Vector3, preview_frac: float) -> void:
	clear_tsinelas()
	_player = player
	wind = wind_vec
	preview_fraction = preview_frac
	active = true
	_charging = false
	power = 0.0
	power_changed.emit(power)


## Stop aiming without throwing.
func end() -> void:
	active = false
	_charging = false
	_preview_mesh.clear_surfaces()
	power = 0.0
	power_changed.emit(power)


func clear_tsinelas() -> void:
	if is_instance_valid(_tsinelas):
		_tsinelas.queue_free()
	_tsinelas = null


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event.is_action_pressed("throw") and not _charging:
		_charging = true
		_charge_time = 0.0
		get_viewport().set_input_as_handled()
	elif event.is_action_released("throw") and _charging:
		_charging = false
		_launch()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not active or not _charging:
		return
	_charge_time += delta
	power = pingpong(_charge_time * charge_cycles_per_sec * 2.0, 1.0)
	power_changed.emit(power)
	_draw_preview()


func _launch_velocity() -> Vector3:
	var aim: Basis = _player.get_aim_basis()
	var dir := (-aim.z).rotated(aim.x.normalized(), deg_to_rad(elevation_deg)).normalized()
	return dir * lerpf(min_speed, max_speed, power)


func _wind_accel() -> Vector3:
	return Vector3(wind.x, 0.0, wind.z) * wind_factor


func _draw_preview() -> void:
	_preview_mesh.clear_surfaces()
	var p: Vector3 = _player.get_throw_origin()
	var v := _launch_velocity()
	var a := Vector3(0.0, -_gravity, 0.0) + _wind_accel()
	var points: Array[Vector3] = [p]
	var landing := Vector3.ZERO
	var landing_normal := Vector3.UP
	var landed := false
	var space := get_world_3d().direct_space_state
	var exclude: Array[RID] = [(_player as CollisionObject3D).get_rid()]
	var t := 0.0
	while t < preview_max_time:
		t += preview_step
		var next := p + v * t + 0.5 * a * t * t
		# Stop where the flight path meets the ground, a wall or the lata.
		var q := PhysicsRayQueryParameters3D.create(points[-1], next)
		q.exclude = exclude
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			points.append(hit.position)
			landing = hit.position
			landing_normal = hit.normal
			landed = true
			break
		points.append(next)
		if next.y <= 0.0:
			landing = Vector3(next.x, 0.0, next.z)
			landed = true
			break
	var count := points.size()
	if preview_fraction < 1.0:
		count = maxi(int(points.size() * preview_fraction), 2)
	if count < 2:
		return
	var cam := get_viewport().get_camera_3d()
	var eye := cam.global_position if cam else p + Vector3(0, 2, 3)
	_preview_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	# Dashes: a dark outline under a bright core, both camera-facing ribbons.
	for pass_i in 2:
		var width := DASH_WIDTH * (1.8 if pass_i == 0 else 1.0)
		var col := DASH_OUTLINE if pass_i == 0 else DASH_COLOR
		for i in range(0, count - 1, 2):
			_ribbon(points[i], points[i + 1], eye, width, col)
	# Where the tsinelas will land.
	if landed and (preview_fraction >= 1.0 or count >= points.size()):
		_ring(landing + landing_normal * 0.04, landing_normal, LANDING_RADIUS + 0.05, 0.13, DASH_OUTLINE)
		_ring(landing + landing_normal * 0.05, landing_normal, LANDING_RADIUS, 0.07, DASH_COLOR)
		_ring(landing + landing_normal * 0.05, landing_normal, 0.09, 0.09, DASH_COLOR) # centre dot
	_preview_mesh.surface_end()


## One dash: a flat strip from a to b that always faces the camera.
func _ribbon(a: Vector3, b: Vector3, eye: Vector3, width: float, col: Color) -> void:
	var dir := (b - a)
	if dir.length() < 0.001:
		return
	var side := dir.cross(eye - (a + b) * 0.5).normalized() * width * 0.5
	for v in [a - side, a + side, b + side, a - side, b + side, b - side]:
		_preview_mesh.surface_set_color(col)
		_preview_mesh.surface_add_vertex(v)


## A flat ring lying on the surface (normal n) around centre c.
func _ring(c: Vector3, n: Vector3, radius: float, thickness: float, col: Color) -> void:
	var u := n.cross(Vector3.FORWARD if absf(n.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var w := n.cross(u).normalized()
	var r_in := maxf(radius - thickness, 0.0)
	var seg := 28
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var d0 := u * cos(a0) + w * sin(a0)
		var d1 := u * cos(a1) + w * sin(a1)
		for v in [c + d0 * r_in, c + d0 * radius, c + d1 * radius, c + d0 * r_in, c + d1 * radius, c + d1 * r_in]:
			_preview_mesh.surface_set_color(col)
			_preview_mesh.surface_add_vertex(v)


## Colour the thrown tsinelas like the slipper picked in weapon select.
## Enchanted slippers also get the purple glint.
func _tint_equipped_slipper(slipper: Node3D) -> void:
	var item := Economy.equipped_slipper_item()
	var palette: Dictionary = item.palette
	for part in [["Sole", palette.sole], ["Strap", palette.strap]]:
		var mesh := slipper.get_node_or_null(part[0]) as MeshInstance3D
		if mesh:
			var mat := StandardMaterial3D.new()
			mat.albedo_color = part[1]
			mesh.material_override = mat
			if Enchant.is_enchanted(item):
				Enchant.apply_to_mesh(mesh)


func _launch() -> void:
	active = false
	_preview_mesh.clear_surfaces()
	var velocity := _launch_velocity()
	var origin: Vector3 = _player.get_throw_origin()

	_tsinelas = TSINELAS_SCENE.instantiate()
	get_parent().add_child(_tsinelas)
	_tsinelas.global_transform = Transform3D(Basis.looking_at(velocity.normalized(), Vector3.UP), origin)
	_tsinelas.add_collision_exception_with(_player)
	_tint_equipped_slipper(_tsinelas)
	_tsinelas.settled.connect(func(): settled.emit())
	_tsinelas.launch(velocity, _wind_accel())

	power = 0.0
	power_changed.emit(power)
	thrown.emit()
