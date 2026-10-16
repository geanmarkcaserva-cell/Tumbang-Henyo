extends CharacterBody3D
## Player: behind-the-back camera, WASD movement, and sprint powered by the
## energy (stamina) bar. Sprinting is the player's edge over the tayas: they
## run a little faster than your walk but slower than your sprint, so spend
## energy wisely. The round controller turns controls on for the run and off
## for the quiz.

signal stamina_changed(value: float, max_value: float)

@export var walk_speed := 5.0
@export var sprint_speed := 8.0
@export var acceleration := 30.0
@export var mouse_sensitivity := 0.003
@export var max_stamina := 100.0
@export var stamina_drain := 18.0 ## per second while sprinting (about 5.5 s of full sprint)
@export var stamina_regen := 15.0 ## per second while not sprinting
@export var recover_at := 0.3 ## after running dry, sprint unlocks again at this fraction
@export var min_pitch_deg := -45.0
@export var max_pitch_deg := 15.0
@export var walk_fov := 70.0
@export var sprint_fov := 80.0

var controls_enabled := true ## movement and sprint
var look_enabled := true ## mouse look
var sprint_enabled := true ## off while throwing
var stamina := 100.0
var _bounds := Rect2() ## x/z area the player must stay inside (empty = no limit)
var _stagger_time := 0.0
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
	# Paper-cutout sprite of the character picked in Select character.
	var palette: Dictionary = Economy.find_item("character", Economy.equipped_character).palette
	$PaperDoll.set_textures(PixelArt.character(palette), PixelArt.character_back(palette))


## Out of energy: sprint is locked until the bar refills to `recover_at`.
func is_exhausted() -> bool:
	return _exhausted


## Knocked off balance (hit by a tsinelas): no control for a moment, pushed back.
func stagger(duration: float, push: Vector3) -> void:
	_stagger_time = duration
	velocity.x = push.x
	velocity.z = push.z


## Put the player back at a spawn point, facing down the court.
func respawn(at: Vector3) -> void:
	global_position = at
	velocity = Vector3.ZERO
	_stagger_time = 0.0
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

	# --- Sprint (energy) ---
	var sprinting := controls_enabled and sprint_enabled and Input.is_action_pressed("sprint") \
			and input_dir.length() > 0.1 and not _exhausted
	if sprinting:
		stamina = maxf(stamina - stamina_drain * delta, 0.0)
		if stamina <= 0.0:
			_exhausted = true
	else:
		stamina = minf(stamina + stamina_regen * delta, max_stamina)
		if _exhausted and stamina >= max_stamina * recover_at:
			_exhausted = false

	# --- Move ---
	var speed := sprint_speed if sprinting else walk_speed
	var accel := acceleration * (0.25 if staggered else 1.0) # a stagger slides you a little
	velocity.x = move_toward(velocity.x, dir.x * speed, accel * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, accel * delta)
	move_and_slide()
	_apply_bounds()

	stamina_changed.emit(stamina, max_stamina)

	# Hold look_back to swing the camera around and see who's chasing you.
	# (Not while aiming a throw, or the aim would point backwards.)
	var looking_back := controls_enabled and not _bounds.has_area() and Input.is_action_pressed("look_back")
	_pivot.rotation.y = lerp_angle(_pivot.rotation.y, PI if looking_back else 0.0, 12.0 * delta)

	# Field-of-view kick while sprinting.
	_camera.fov = lerpf(_camera.fov, sprint_fov if sprinting else walk_fov, 10.0 * delta)


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
