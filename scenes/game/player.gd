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
@export var touch_sensitivity := 0.0055 ## radians per design pixel of finger drag
@export var max_stamina := 25.0 ## halved twice (100 -> 50 -> 25): about 1.4 s of full sprint, so spend it carefully
@export var stamina_drain := 18.0 ## per second while sprinting
@export var stamina_regen := 8.0 ## per second while not sprinting (about 3 s to refill)
@export var recover_at := 0.3 ## after running dry, sprint unlocks again at this fraction
@export var min_pitch_deg := -45.0
@export var max_pitch_deg := 15.0
@export var walk_fov := 70.0
@export var sprint_fov := 80.0

@export_group("Jump")
@export var jump_velocity := 5.0 ## about 1.2 m high
@export var jump_boost := 1.6 ## m/s added in the direction you're moving, per jump
@export var max_air_speed := 10.5 ## cap for chained (bunny-hop) jumps
@export var air_control := 0.35 ## steering in the air vs on the ground
@export var fall_gravity_mult := 1.5 ## falls faster than it rises: snappier jumps
@export var jump_energy_cost := 5.0 ## per boosted jump; no energy = jump without boost
@export var coyote_time := 0.12 ## can still jump just after running off an edge
@export var jump_buffer_time := 0.12 ## a press just before landing still jumps

var controls_enabled := true ## movement and sprint
var look_enabled := true ## mouse look
var sprint_enabled := true ## off while throwing
var stamina := 25.0
var _bounds := Rect2() ## x/z area the player must stay inside (empty = no limit)
var _bounds_look_back := false ## Q still works inside _bounds (Mama's round)
var _stagger_time := 0.0
var _camera_tween: Tween
var _exhausted := false
var _coyote := 0.0
var _jump_buffer := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
const STRIDE := 1.7 ## metres per footstep sound at walking pace
var _stride := 0.0

@onready var _pivot: Node3D = $CameraPivot
@onready var _spring: SpringArm3D = $CameraPivot/SpringArm3D
@onready var _camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var _default_pitch: float = $CameraPivot.rotation.x


func _ready() -> void:
	stamina = max_stamina
	_spring.add_excluded_object(get_rid())
	add_to_group("player")
	# Paper-cutout sprite of the character picked in Select character.
	$PaperDoll.set_look(PixelArt.character_look(Economy.find_item("character", Economy.equipped_character)))


## Flip the cutout to the camera and play the happy sheet.
## duration < 0 keeps it up until respawn().
func celebrate(duration: float = 1.2) -> void:
	$PaperDoll.play_happy(duration)


## Out of energy: sprint is locked until the bar refills to `recover_at`.
func is_exhausted() -> bool:
	return _exhausted


## Knocked off balance (hit by a tsinelas): no control for a moment, pushed back.
func stagger(duration: float, push: Vector3) -> void:
	_stagger_time = duration
	velocity.x = push.x
	velocity.z = push.z
	hurt()


## Damage feedback (wrong answer, tsinelas hit): squish and flash red.
func hurt() -> void:
	$PaperDoll.hurt()


## Put the player back at a spawn point, facing down the court.
func respawn(at: Vector3) -> void:
	global_position = at
	velocity = Vector3.ZERO
	_stagger_time = 0.0
	_jump_buffer = 0.0
	$PaperDoll.stop_happy()
	rotation = Vector3.ZERO
	_pivot.rotation = Vector3(_default_pitch, 0.0, 0.0)


## Over-the-shoulder aim camera for the throw (closer and more to the right).
func set_aim_mode(on: bool) -> void:
	$PaperDoll.set_see_through(on) # big-haired characters would block the aim
	if _camera_tween:
		_camera_tween.kill()
	_camera_tween = create_tween().set_parallel().set_trans(Tween.TRANS_SINE)
	_camera_tween.tween_property(_spring, "spring_length", 2.4 if on else 4.0, 0.35)
	_camera_tween.tween_property(_spring, "position:x", 0.8 if on else 0.5, 0.35)


## Keep the player inside an area on the ground. rect.position is (min x, min z),
## rect.size is (width along x, depth along z). Pass Rect2() to remove the limit.
## look_back: allow Q (look behind) inside these bounds. Off for the throw
## zone, where the camera must keep facing the lata.
func set_move_bounds(rect: Rect2, look_back := false) -> void:
	_bounds = rect
	_bounds_look_back = look_back


## The direction the camera looks (used to aim the throw).
func get_aim_basis() -> Basis:
	return _camera.global_basis


## Where the tsinelas leaves the hand: right side, shoulder height.
func get_throw_origin() -> Vector3:
	return global_transform * Vector3(0.35, 1.45, -0.35)


func _unhandled_input(event: InputEvent) -> void:
	if not (controls_enabled or look_enabled):
		return
	if TouchControls.active:
		return # touch drags arrive through touch_look(); ignore their emulated mouse events
	if event is InputEventMouseMotion and look_enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_turn(event.relative * mouse_sensitivity)
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Look with a finger drag on the touch controls (design pixels).
func touch_look(relative: Vector2) -> void:
	if look_enabled:
		_turn(relative * touch_sensitivity)


## Yaw the body, pitch the camera (radians).
func _turn(amount: Vector2) -> void:
	rotate_y(-amount.x)
	_pivot.rotation.x = clampf(_pivot.rotation.x - amount.y,
			deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))


func _physics_process(delta: float) -> void:
	var on_floor := is_on_floor()
	if not on_floor:
		var g := _gravity * (fall_gravity_mult if velocity.y < 0.0 else 1.0)
		velocity.y -= g * delta

	var staggered := _stagger_time > 0.0
	if staggered:
		_stagger_time -= delta
	var input_dir := Vector2.ZERO
	if controls_enabled and not staggered:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)

	# --- Jump (with coyote time and a press buffer) ---
	_coyote = coyote_time if on_floor else _coyote - delta
	_jump_buffer -= delta
	if controls_enabled and not staggered and Input.is_action_just_pressed("jump"):
		_jump_buffer = jump_buffer_time
	var jumped := false
	if _jump_buffer > 0.0 and _coyote > 0.0:
		_jump(dir)
		jumped = true
		Sfx.play("jump", 0.0, 1.0, 0.06)
	var airborne := jumped or not on_floor

	# --- Sprint (energy) ---
	var sprinting := controls_enabled and sprint_enabled and Input.is_action_pressed("sprint") \
			and input_dir.length() > 0.1 and not _exhausted
	if sprinting:
		stamina = maxf(stamina - stamina_drain * delta, 0.0)
		if stamina <= 0.0:
			_exhausted = true
			Sfx.play("exhausted") # out of breath
	else:
		stamina = minf(stamina + stamina_regen * delta, max_stamina)
		if _exhausted and stamina >= max_stamina * recover_at:
			_exhausted = false

	# --- Move ---
	var speed := sprint_speed if sprinting else walk_speed
	var accel := acceleration * (0.25 if staggered else 1.0) # a stagger slides you a little
	if airborne:
		# Keep the jump's momentum: steer weakly, never brake below current speed.
		speed = maxf(speed, Vector2(velocity.x, velocity.z).length())
		accel *= air_control
	velocity.x = move_toward(velocity.x, dir.x * speed, accel * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, accel * delta)
	var fall_speed := -velocity.y
	move_and_slide()
	_apply_bounds()
	_footsteps(delta, on_floor, fall_speed, sprinting)

	stamina_changed.emit(stamina, max_stamina)

	# Hold look_back to swing the camera around and see who's chasing you.
	# (Not while aiming a throw, or the aim would point backwards.)
	var can_look := not _bounds.has_area() or _bounds_look_back
	var looking_back := controls_enabled and can_look and Input.is_action_pressed("look_back")
	_pivot.rotation.y = lerp_angle(_pivot.rotation.y, PI if looking_back else 0.0, 12.0 * delta)

	# Field-of-view kick while sprinting.
	_camera.fov = lerpf(_camera.fov, sprint_fov if sprinting else walk_fov, 10.0 * delta)


## Jump up, plus a little speed the way you're steering (or already moving).
## The boost costs energy and is only given while running (not while aiming
## a throw); chained jumps keep adding up to max_air_speed.
func _jump(dir: Vector3) -> void:
	velocity.y = jump_velocity
	_jump_buffer = 0.0
	_coyote = 0.0
	if not sprint_enabled or _exhausted or stamina < jump_energy_cost:
		return
	var flat := Vector2(velocity.x, velocity.z)
	var push := Vector2(dir.x, dir.z)
	if push.length() < 0.1:
		push = flat # no input: boost along the current motion
	if push.length() < 0.1:
		return # standing still: straight up
	flat = (flat + push.normalized() * jump_boost).limit_length(max_air_speed)
	velocity.x = flat.x
	velocity.z = flat.y
	stamina = maxf(stamina - jump_energy_cost, 0.0)


## Steps on the concrete as you move (quicker and louder when sprinting),
## and a thud when you land from a jump.
func _footsteps(delta: float, was_on_floor: bool, fall_speed: float, sprinting: bool) -> void:
	var on_floor := is_on_floor()
	if on_floor and not was_on_floor and fall_speed > 2.5:
		Sfx.play("land", linear_to_db(clampf(fall_speed / 7.0, 0.4, 1.0)), 1.0, 0.06)
		_stride = 0.0
		return
	if not on_floor:
		return
	var moved := Vector2(velocity.x, velocity.z).length() * delta
	if moved < 0.0005:
		_stride = STRIDE * 0.6 # first step comes quickly after standing still
		return
	_stride += moved
	var stride := STRIDE * (1.35 if sprinting else 1.0)
	if _stride >= stride:
		_stride = 0.0
		Sfx.play("step", -2.0 if sprinting else -5.0, 1.0, 0.08)


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
