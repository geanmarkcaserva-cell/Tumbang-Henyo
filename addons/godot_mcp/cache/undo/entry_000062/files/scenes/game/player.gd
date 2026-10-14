extends CharacterBody3D
## Greybox player: behind-the-back camera, WASD movement, sprint with stamina.
## The round controller turns controls on for the run and off for the quiz.

signal stamina_changed(value: float, max_value: float)

@export var walk_speed := 5.0
@export var sprint_speed := 8.0
@export var acceleration := 30.0
@export var mouse_sensitivity := 0.003
@export var max_stamina := 100.0
@export var stamina_drain := 25.0 ## per second while sprinting
@export var stamina_regen := 15.0 ## per second while not sprinting
@export var min_pitch_deg := -45.0
@export var max_pitch_deg := 15.0
@export var walk_fov := 70.0
@export var sprint_fov := 78.0

var controls_enabled := true ## movement and sprint
var look_enabled := true ## mouse look
var stamina := 100.0
var _camera_tween: Tween
var _exhausted := false
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var _pivot: Node3D = $CameraPivot
@onready var _spring: SpringArm3D = $CameraPivot/SpringArm3D
@onready var _camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var _default_pitch: float = $CameraPivot.rotation.x


func _ready() -> void:
	stamina = max_stamina
	_spring.add_excluded_object(get_rid())


## Put the player back at a spawn point, facing down the court.
func respawn(at: Vector3) -> void:
	global_position = at
	velocity = Vector3.ZERO
	rotation = Vector3.ZERO
	_pivot.rotation = Vector3(_default_pitch, 0.0, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if not controls_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		_pivot.rotation.x = clampf(
			_pivot.rotation.x - event.relative.y * mouse_sensitivity,
			deg_to_rad(min_pitch_deg),
			deg_to_rad(max_pitch_deg)
		)
	elif event.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta

	var input_dir := Vector2.ZERO
	if controls_enabled:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)

	var sprinting := controls_enabled and Input.is_action_pressed("sprint") and input_dir.length() > 0.1 and not _exhausted
	if sprinting:
		stamina = maxf(stamina - stamina_drain * delta, 0.0)
		if stamina <= 0.0:
			_exhausted = true
	else:
		stamina = minf(stamina + stamina_regen * delta, max_stamina)
		if _exhausted and stamina >= max_stamina * 0.3:
			_exhausted = false

	var speed := sprint_speed if sprinting else walk_speed
	velocity.x = move_toward(velocity.x, dir.x * speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, acceleration * delta)
	move_and_slide()

	stamina_changed.emit(stamina, max_stamina)

	# Hold look_back to swing the camera around and see who's chasing you.
	var looking_back := controls_enabled and Input.is_action_pressed("look_back")
	_pivot.rotation.y = lerp_angle(_pivot.rotation.y, PI if looking_back else 0.0, 12.0 * delta)

	# Small field-of-view kick while sprinting.
	_camera.fov = lerpf(_camera.fov, sprint_fov if sprinting else walk_fov, 8.0 * delta)
