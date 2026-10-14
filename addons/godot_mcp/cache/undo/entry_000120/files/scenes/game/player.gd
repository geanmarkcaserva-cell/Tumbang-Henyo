extends CharacterBody3D
## Greybox player: behind-the-back camera, WASD movement, sprint with stamina,
## and a short dash. The round controller turns controls on for the run and
## off for the quiz.

signal stamina_changed(value: float, max_value: float)
signal dash_changed(ready_fraction: float) ## 1 = ready, 0 = just used

@export var walk_speed := 5.0
@export var sprint_speed := 8.0
@export var acceleration := 30.0
@export var mouse_sensitivity := 0.003
@export var max_stamina := 100.0
@export var stamina_drain := 18.0 ## per second while sprinting (about 5.5 s of full sprint)
@export var stamina_regen := 15.0 ## per second while not sprinting
@export var min_pitch_deg := -45.0
@export var max_pitch_deg := 15.0
@export var walk_fov := 70.0
@export var sprint_fov := 78.0

@export_group("Dash")
@export var dash_speed := 17.0
@export var dash_time := 0.18 ## seconds (about 3 m)
@export var dash_cooldown := 1.5
@export var dash_stamina_cost := 15.0 ## taken if available; dashing never needs stamina
@export var dash_fov := 86.0

var controls_enabled := true ## movement and sprint
var look_enabled := true ## mouse look
var sprint_enabled := true ## also gates the dash (off while throwing)
var stamina := 100.0
var _bounds := Rect2() ## x/z area the player must stay inside (empty = no limit)
var _stagger_time := 0.0
var _dash_time_left := 0.0
var _dash_cd := 0.0
var _dash_dir := Vector3.ZERO
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
	add_to_group("player")


## True during the dash burst: tags and tsinelas hits don't count.
func is_dashing() -> bool:
	return _dash_time_left > 0.0


## Knocked off balance (hit by a tsinelas): no control for a moment, pushed back.
func stagger(duration: float, push: Vector3) -> void:
	_stagger_time = duration
	_dash_time_left = 0.0
	velocity.x = push.x
	velocity.z = push.z


## Put the player back at a spawn point, facing down the court.
func respawn(at: Vector3) -> void:
	global_position = at
	velocity = Vector3.ZERO
	_stagger_time = 0.0
	_dash_time_left = 0.0
	_dash_cd = 0.0
	rotation = Vector3.ZERO
	_pivot.rotation = Vector3(_default_pitch, 0.0, 0.0)


## Over-the-shoulder aim camera for the throw (closer and more to the right).
func set_aim_mode(on: bool) -> void:
	if _camera_tween:
		_camera_tween.kill()
	_camera_tween = create_tween().set_parallel().set_trans(Tween.TRANS_SINE)
	_camera_tween.tween_property(_spring, "spring_length", 2.4 if on else 4.0, 0.35)
	_camera_tween.tween_property(_spring, "position:x", 0.8 if on else 0.5, 0.35)


## Keep the player inside an area on the ground. rect.position is (min x, min z),
## rect.size is (width along x, depth along z). Pass Rect2() to remove the limit.
func set_move_bounds(rect: Rect2) -> void:
	_bounds = rect


## The direction the camera looks (used to aim the throw).
func get_aim_basis() -> Basis:
	return _camera.global_basis


## Where the tsinelas leaves the hand: right side, shoulder height.
func get_throw_origin() -> Vector3:
	return global_transform * Vector3(0.35, 1.45, -0.35)


func _unhandled_input(event: InputEvent) -> void:
	if not (controls_enabled or look_enabled):
		return
	if event is InputEventMouseMotion and look_enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
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

	var staggered := _stagger_time > 0.0
	if staggered:
		_stagger_time -= delta
	var input_dir := Vector2.ZERO
	if controls_enabled and not staggered:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)

	# --- Dash ---
	_dash_cd = maxf(_dash_cd - delta, 0.0)
	var can_dash := controls_enabled and sprint_enabled and not staggered and _dash_cd <= 0.0
	if can_dash and Input.is_action_just_pressed("dash"):
		# Dash the way you're steering, or straight ahead if you're not.
		_dash_dir = dir.normalized() if dir.length() > 0.1 else -transform.basis.z
		_dash_time_left = dash_time
		_dash_cd = dash_cooldown
		stamina = maxf(stamina - dash_stamina_cost, 0.0)
	var dashing := _dash_time_left > 0.0
	if dashing:
		_dash_time_left -= delta

	# --- Sprint and stamina ---
	var sprinting := controls_enabled and sprint_enabled and Input.is_action_pressed("sprint") \
			and input_dir.length() > 0.1 and not _exhausted
	if sprinting:
		stamina = maxf(stamina - stamina_drain * delta, 0.0)
		if stamina <= 0.0:
			_exhausted = true
	elif not dashing:
		stamina = minf(stamina + stamina_regen * delta, max_stamina)
		if _exhausted and stamina >= max_stamina * 0.3:
			_exhausted = false

	# --- Move ---
	if dashing:
		velocity.x = _dash_dir.x * dash_speed
		velocity.z = _dash_dir.z * dash_speed
	else:
		var speed := sprint_speed if sprinting else walk_speed
		var accel := acceleration * (0.25 if staggered else 1.0) # a stagger slides you a little
		velocity.x = move_toward(velocity.x, dir.x * speed, accel * delta)
		velocity.z = move_toward(velocity.z, dir.z * speed, accel * delta)
	move_and_slide()
	_apply_bounds()

	stamina_changed.emit(stamina, max_stamina)
	dash_changed.emit(1.0 - _dash_cd / dash_cooldown)

	# Hold look_back to swing the camera around and see who's chasing you.
	# (Not while aiming a throw, or the aim would point backwards.)
	var looking_back := controls_enabled and not _bounds.has_area() and Input.is_action_pressed("look_back")
	_pivot.rotation.y = lerp_angle(_pivot.rotation.y, PI if looking_back else 0.0, 12.0 * delta)

	# Field-of-view kick while sprinting, bigger while dashing.
	var target_fov := dash_fov if dashing else (sprint_fov if sprinting else walk_fov)
	_camera.fov = lerpf(_camera.fov, target_fov, 10.0 * delta)


func _apply_bounds() -> void:
	if not _bounds.has_area():
		return
	var p := global_position
	var clamped_x := clampf(p.x, _bounds.position.x, _bounds.end.x)
	var clamped_z := clampf(p.z, _bounds.position.y, _bounds.end.y)
	if clamped_x != p.x:
		velocity.x = 0.0
	if clamped_z != p.z:
		velocity.z = 0.0
	global_position = Vector3(clamped_x, p.y, clamped_z)
