extends Node3D
## Handles one tsinelas throw: hold `throw` to charge (the gauge swings
## up and down), release to launch. While charging, a dashed preview
## shows the flight path, cut short by preview_fraction in later rounds.

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
	mat.albedo_color = Color(1.0, 0.2, 0.35)
	mat.no_depth_test = true
	_preview.material_override = mat


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
	if preview_fraction <= 0.0:
		return
	var p: Vector3 = _player.get_throw_origin()
	var v := _launch_velocity()
	var a := Vector3(0.0, -_gravity, 0.0) + _wind_accel()
	var points: Array[Vector3] = [p]
	var t := 0.0
	while t < preview_max_time:
		t += preview_step
		var next := p + v * t + 0.5 * a * t * t
		points.append(next)
		if next.y <= 0.0:
			break
	var count := int(points.size() * preview_fraction)
	if count < 2:
		return
	# Every other segment gives a dashed line.
	_preview_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(0, count - 1, 2):
		_preview_mesh.surface_add_vertex(points[i])
		_preview_mesh.surface_add_vertex(points[i + 1])
	_preview_mesh.surface_end()


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
