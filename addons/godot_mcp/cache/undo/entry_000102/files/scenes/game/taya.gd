extends CharacterBody3D
## The taya (the "it"). Guards the lata, stands it back up when it's
## knocked down, then chases the player, throwing its tsinelas and
## trying to tag them.
##
## States: GUARD -> RESET -> CHASE <-> WIND_UP / PICKUP, IDLE when stopped.

signal lata_reset ## the lata is back in its circle; the chase starts
signal tagged_player
signal hit_player ## one of this taya's tsinelas hit the player

enum State { IDLE, GUARD, RESET, CHASE, WIND_UP, PICKUP }

const TSINELAS_SCENE := preload("res://scenes/game/tsinelas.tscn")

@export var chase_speed := 6.4
@export var reset_run_speed := 6.0
@export var reset_time := 3.0 ## seconds spent standing the lata back up
@export var tag_distance := 1.0
@export var throw_min_range := 4.0
@export var throw_max_range := 11.0
@export var wind_up_time := 0.5
@export var throw_cooldown := 1.6
@export var max_slippers := 2
@export var lead_factor := 0.6 ## how much it aims ahead of a moving player (1 = perfect)

var state: State = State.GUARD
var slippers := 2

var _player: CharacterBody3D
var _lata: RigidBody3D
var _guard_transform: Transform3D
var _timer := 0.0
var _cooldown := 0.0
var _ring_time := 0.0
var _throw_target := Vector3.ZERO
var _thrown: Array[RigidBody3D] = []
var _pickup_target: RigidBody3D
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var _ring: MeshInstance3D = $WarningRing


func _ready() -> void:
	_guard_transform = global_transform
	slippers = max_slippers
	_ring.top_level = true
	_ring.visible = false


func setup(player: CharacterBody3D, lata: RigidBody3D) -> void:
	_player = player
	_lata = lata


## Difficulty for this round.
func configure(speed: float, reset_seconds: float) -> void:
	chase_speed = speed
	reset_time = reset_seconds


## Back to the guard spot with full slippers (new round or after a tag).
func return_to_guard() -> void:
	_clear_thrown()
	slippers = max_slippers
	global_transform = _guard_transform
	velocity = Vector3.ZERO
	_ring.visible = false
	state = State.GUARD


## The lata was knocked down: go stand it back up, then chase.
func start_reset() -> void:
	state = State.RESET
	_timer = 0.0


func stop() -> void:
	state = State.IDLE
	velocity = Vector3.ZERO
	_ring.visible = false


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _ring_time > 0.0:
		_ring_time -= delta
		if _ring_time <= 0.0 and state != State.WIND_UP:
			_ring.visible = false

	match state:
		State.IDLE:
			_halt()
		State.GUARD:
			_halt()
			if _player:
				_face(_flat(_player.global_position - global_position))
		State.RESET:
			_do_reset(delta)
		State.CHASE:
			_do_chase()
		State.WIND_UP:
			_halt()
			_face(_flat(_throw_target - global_position))
			_timer -= delta
			if _timer <= 0.0:
				_throw()
				state = State.CHASE
		State.PICKUP:
			_do_pickup()

	move_and_slide()


func _do_reset(delta: float) -> void:
	var to_lata := _flat(_lata.global_position - global_position)
	if to_lata.length() > 0.9 and _timer == 0.0:
		_steer(to_lata, reset_run_speed)
		return
	# At the lata: stand it back up.
	_halt()
	_timer += delta
	if _timer >= reset_time:
		_lata.reset_to_home()
		state = State.CHASE
		lata_reset.emit()


func _do_chase() -> void:
	var to_player := _flat(_player.global_position - global_position)
	var distance := to_player.length()
	if distance <= tag_distance:
		_tag()
		return
	if slippers <= 0:
		_start_pickup()
		return
	if _cooldown <= 0.0 and distance >= throw_min_range and distance <= throw_max_range:
		_start_wind_up(distance)
		return
	_steer(to_player, chase_speed)


func _do_pickup() -> void:
	if _flat(_player.global_position - global_position).length() <= tag_distance:
		_tag()
		return
	if not is_instance_valid(_pickup_target):
		# Lost it (fell off the map): pretend to grab a spare.
		slippers = 1
		state = State.CHASE
		return
	var to_slipper := _flat(_pickup_target.global_position - global_position)
	if to_slipper.length() <= 0.9:
		_thrown.erase(_pickup_target)
		_pickup_target.queue_free()
		_pickup_target = null
		slippers += 1
		state = State.CHASE
		return
	_steer(to_slipper, chase_speed)


func _start_pickup() -> void:
	_pickup_target = null
	var best := INF
	for slipper in _thrown:
		if is_instance_valid(slipper):
			var d := global_position.distance_to(slipper.global_position)
			if d < best:
				best = d
				_pickup_target = slipper
	state = State.PICKUP


func _start_wind_up(distance: float) -> void:
	state = State.WIND_UP
	_timer = wind_up_time
	# Aim a bit ahead of where the player is running, so dodging is possible.
	var flight_time := clampf(distance / 12.0, 0.5, 1.0)
	var lead := _flat(_player.velocity) * (wind_up_time + flight_time) * lead_factor
	_throw_target = _flat(_player.global_position + lead) + Vector3(0.0, 0.03, 0.0)
	_ring.global_position = _throw_target
	_ring.visible = true


func _throw() -> void:
	var origin := global_transform * Vector3(0.35, 1.45, -0.35)
	var flight_time := clampf(origin.distance_to(_throw_target) / 12.0, 0.5, 1.0)
	var g := Vector3(0.0, -_gravity, 0.0)
	# Ballistic launch so it lands on the warning ring.
	var velocity_out := (_throw_target - origin - 0.5 * g * flight_time * flight_time) / flight_time

	var slipper: RigidBody3D = TSINELAS_SCENE.instantiate()
	slipper.target_group = "player"
	slipper.hit_radius = thrown_hit_radius
	get_parent().add_child(slipper)
	slipper.global_transform = Transform3D(Basis.looking_at(velocity_out.normalized(), Vector3.UP), origin)
	slipper.add_collision_exception_with(self)
	slipper.hit_target.connect(func(_body): hit_player.emit())
	slipper.launch(velocity_out, Vector3.ZERO)
	_thrown.append(slipper)

	slippers -= 1
	_cooldown = throw_cooldown
	_ring_time = flight_time + 0.2


func _tag() -> void:
	state = State.IDLE
	_halt()
	tagged_player.emit()


func _clear_thrown() -> void:
	for slipper in _thrown:
		if is_instance_valid(slipper):
			slipper.queue_free()
	_thrown.clear()
	_pickup_target = null


func _steer(direction: Vector3, speed: float) -> void:
	var v := direction.normalized() * speed
	velocity.x = v.x
	velocity.z = v.z
	_face(direction)


func _halt() -> void:
	velocity.x = 0.0
	velocity.z = 0.0


func _face(direction: Vector3) -> void:
	if direction.length() > 0.05:
		rotation.y = atan2(-direction.x, -direction.z)


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
