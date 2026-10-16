extends CharacterBody3D
## The taya (the "it"). Guards the lata, stands it back up when it's
## knocked down, then chases the player, throwing its tsinelas and
## trying to tag them.
##
## It chases like a person, not a homing missile:
## - it only re-checks where you are every `reaction_time` seconds, and runs
##   toward where it *predicts* you'll be, so a sudden change of direction fools it;
## - it has momentum: limited turn speed, and sharp turns cost speed;
## - up close it commits to a lunge in a straight line - sidestep and it misses,
##   then stumbles briefly;
## - its throws scatter by `aim_error` metres.
##
## States: GUARD -> RESET -> CHASE <-> WIND_UP / PICKUP / LUNGE -> RECOVER.

signal lata_reset ## the lata is back in its circle; the chase starts
signal tagged_player
signal hit_player ## one of this taya's tsinelas hit the player

enum State { IDLE, GUARD, RESET, CHASE, WIND_UP, PICKUP, LUNGE, RECOVER }

const TSINELAS_SCENE := preload("res://scenes/game/tsinelas.tscn")
const MAX_WINDING_AT_ONCE := 2 ## so five tayas feel like pressure, not a firing squad
const ELITE_FAN_SPREAD := 1.3 ## metres between the elite's three tsinelas

## Placeholder sprite colours: red shirt + white headband; the elite cheater
## wears a dark shirt and a red headband.
const PALETTE := {"hair": Color(0.1, 0.08, 0.07), "skin": Color(0.78, 0.56, 0.42), "shirt": Color(0.82, 0.16, 0.16),
		"accent": Color(1, 1, 1), "pants": Color(0.15, 0.15, 0.3), "feet": Color(0.95, 0.95, 0.95), "band": Color(0.97, 0.97, 0.97)}
const ELITE_PALETTE := {"hair": Color(0.1, 0.08, 0.07), "skin": Color(0.72, 0.5, 0.36), "shirt": Color(0.16, 0.16, 0.2),
		"accent": Color(0.9, 0.12, 0.12), "pants": Color(0.1, 0.1, 0.12), "feet": Color(0.9, 0.12, 0.12), "band": Color(0.92, 0.1, 0.1)}

## Elite taya: carries 3 tsinelas (it cheats with a spare) and throws all
## three at once in a fan.
@export var elite := false

## Same for every taya, elite included: a bit faster than the player's walk,
## slower than their sprint (the round controller sets it from the player).
@export var chase_speed := 5.5
@export var reset_run_speed := 5.5
@export var reset_time := 3.0 ## seconds spent standing the lata back up
@export var tag_distance := 0.8

@export_group("Human-like chasing")
@export var reaction_time := 0.35 ## seconds between looks at the player
@export var turn_speed_deg := 200.0 ## max turning speed while running
@export var acceleration := 16.0
@export var chase_lead := 0.45 ## seconds it predicts ahead of where it last saw you going
@export var lunge_range := 2.2
@export var lunge_speed_mult := 1.6
@export var lunge_time := 0.35
@export var lunge_recover_time := 0.6
@export var lunge_cooldown := 1.2

@export_group("Throwing")
@export var throw_min_range := 4.0
@export var throw_max_range := 11.0
@export var wind_up_time := 0.45 ## warning ring shows this long before the throw
@export var throw_speed := 22.0 ## metres per second along the throw (was 12)
@export var min_flight_time := 0.28
@export var max_flight_time := 0.55
@export var throw_cooldown := 2.2
@export var max_slippers := 2
@export var lead_factor := 0.4 ## how much it aims ahead of a moving player (1 = perfect)
@export var thrown_hit_radius := 0.22 ## small hitbox so a moving player can dodge
@export var aim_error := 1.0 ## random scatter of its throws, in metres

var state: State = State.GUARD
var slippers := 2

var _player: CharacterBody3D
var _lata: RigidBody3D
var _guard_transform: Transform3D
var _timer := 0.0
var _cooldown := 0.0
var _lunge_cd := 0.0
var _ring_time := 0.0
var _throw_target := Vector3.ZERO
var _thrown: Array[RigidBody3D] = []
var _pickup_target: RigidBody3D
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _move_dir := Vector3.FORWARD
var _speed := 0.0
var _seen_pos := Vector3.ZERO ## where it last saw the player
var _seen_vel := Vector3.ZERO ## which way the player was moving then
var _look_timer := 0.0

@onready var _ring: MeshInstance3D = $WarningRing


func _ready() -> void:
	add_to_group("taya")
	if elite:
		max_slippers = 3
	_guard_transform = global_transform
	slippers = max_slippers
	var palette: Dictionary = ELITE_PALETTE if elite else PALETTE
	$PaperDoll.set_textures(PixelArt.character(palette), PixelArt.character_back(palette))
	if elite:
		_ring.scale = Vector3.ONE * 2.4 # the fan covers a wider area
	_move_dir = _flat(-global_basis.z).normalized()
	_ring.top_level = true
	_ring.visible = false


func setup(player: CharacterBody3D, lata: RigidBody3D) -> void:
	_player = player
	_lata = lata


## Difficulty for this round.
func configure(speed: float, reset_seconds: float, reaction: float = 0.35, scatter: float = 1.0) -> void:
	chase_speed = speed
	reset_time = reset_seconds
	reaction_time = reaction
	aim_error = scatter


## Back to the guard spot with full slippers (new round or after a tag).
func return_to_guard() -> void:
	_clear_thrown()
	slippers = max_slippers
	global_transform = _guard_transform
	velocity = Vector3.ZERO
	_speed = 0.0
	_lunge_cd = 0.0
	_move_dir = _flat(-global_basis.z).normalized()
	_ring.visible = false
	state = State.GUARD


## The lata was knocked down: go stand it back up, then chase.
func start_reset() -> void:
	state = State.RESET
	_timer = 0.0


## Another taya stood the lata up: join the chase.
func start_chase() -> void:
	if state == State.GUARD:
		_look_timer = 0.0
		state = State.CHASE


func stop() -> void:
	state = State.IDLE
	_halt()
	_ring.visible = false


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	_cooldown = maxf(_cooldown - delta, 0.0)
	_lunge_cd = maxf(_lunge_cd - delta, 0.0)
	if _ring_time > 0.0:
		_ring_time -= delta
		if _ring_time <= 0.0 and state != State.WIND_UP:
			_ring.visible = false
	if _player and state >= State.CHASE:
		_look(delta)

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
			_do_chase(delta)
		State.WIND_UP:
			_brake(delta)
			_face(_flat(_throw_target - global_position))
			_timer -= delta
			if _timer <= 0.0:
				_throw()
				state = State.CHASE
		State.PICKUP:
			_do_pickup(delta)
		State.LUNGE:
			_do_lunge(delta)
		State.RECOVER:
			# Stumbling after a missed lunge.
			_speed = move_toward(_speed, 0.0, acceleration * 2.0 * delta)
			velocity.x = _move_dir.x * _speed
			velocity.z = _move_dir.z * _speed
			_timer -= delta
			if _timer <= 0.0:
				_lunge_cd = lunge_cooldown
				state = State.CHASE

	move_and_slide()


# --- Perception ---------------------------------------------------------

## The taya doesn't track you perfectly: it glances at you every so often.
func _look(delta: float) -> void:
	_look_timer -= delta
	if _look_timer <= 0.0:
		_seen_pos = _flat(_player.global_position)
		_seen_vel = _flat(_player.velocity)
		_look_timer = reaction_time * randf_range(0.7, 1.3)


func _true_distance() -> float:
	return _flat(_player.global_position - global_position).length()


func _can_tag(reach: float) -> bool:
	return _true_distance() <= reach


# --- States -------------------------------------------------------------

func _do_reset(delta: float) -> void:
	var to_lata := _flat(_lata.global_position - global_position)
	if to_lata.length() > 0.9 and _timer == 0.0:
		_steer(to_lata, reset_run_speed, delta)
		return
	# At the lata: stand it back up.
	_halt()
	_timer += delta
	if _timer >= reset_time:
		_lata.reset_to_home()
		# Start the chase with a fresh look at the player.
		_look_timer = 0.0
		state = State.CHASE
		lata_reset.emit()


func _do_chase(delta: float) -> void:
	if _can_tag(tag_distance):
		_tag()
		return
	if slippers <= 0:
		_start_pickup()
		return
	var to_seen := _seen_pos - _flat(global_position)
	var seen_distance := to_seen.length()
	if _cooldown <= 0.0 and seen_distance >= throw_min_range and seen_distance <= throw_max_range \
			and _winding_count() < MAX_WINDING_AT_ONCE:
		_start_wind_up(seen_distance)
		return
	# Close and lined up with where it thinks you are: commit to a lunge.
	if _lunge_cd <= 0.0 and _true_distance() <= lunge_range and seen_distance > 0.01 \
			and _move_dir.dot(to_seen.normalized()) > 0.85:
		state = State.LUNGE
		_timer = lunge_time
		return
	# Run toward where it predicts you'll be.
	var target := _seen_pos + _seen_vel * chase_lead
	_steer(target - _flat(global_position), chase_speed, delta)


func _do_lunge(delta: float) -> void:
	# Committed: straight ahead, no turning.
	_speed = chase_speed * lunge_speed_mult
	velocity.x = _move_dir.x * _speed
	velocity.z = _move_dir.z * _speed
	if _can_tag(tag_distance + 0.2):
		_tag()
		return
	_timer -= delta
	if _timer <= 0.0:
		state = State.RECOVER
		_timer = lunge_recover_time
		_speed = chase_speed * 0.3


func _do_pickup(delta: float) -> void:
	if _can_tag(tag_distance):
		_tag()
		return
	if not is_instance_valid(_pickup_target):
		# Lost it (fell off the map): pretend to grab a spare.
		slippers = 1
		state = State.CHASE
		return
	var to_slipper := _flat(_pickup_target.global_position - global_position)
	if to_slipper.length() <= 0.9:
		if elite:
			# The elite scoops up its whole set (and its spare) in one go.
			_clear_thrown()
			slippers = max_slippers
		else:
			_thrown.erase(_pickup_target)
			_pickup_target.queue_free()
			_pickup_target = null
			slippers += 1
		state = State.CHASE
		return
	_steer(to_slipper, chase_speed, delta)


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


# --- Throwing ---------------------------------------------------------------

func _start_wind_up(distance: float) -> void:
	state = State.WIND_UP
	_timer = wind_up_time
	# Aim a bit ahead of where it last saw you heading, with some scatter.
	var flight_time := _flight_time(distance)
	var lead := _seen_vel * (wind_up_time + flight_time) * lead_factor
	var scatter := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).limit_length(1.0) * aim_error
	_throw_target = _seen_pos + lead + scatter + Vector3(0.0, 0.03, 0.0)
	_ring.global_position = _throw_target
	_ring.visible = true


func _throw() -> void:
	var origin := global_transform * Vector3(0.35, 1.45, -0.35)
	var flight_time := _flight_time(origin.distance_to(_throw_target))
	if elite:
		# Fan of up to three: centre, left and right of the ring.
		var side := _flat(_throw_target - origin).cross(Vector3.UP).normalized() * ELITE_FAN_SPREAD
		var targets := [_throw_target, _throw_target + side, _throw_target - side]
		for i in mini(slippers, 3):
			_spawn_slipper(origin, targets[i], flight_time)
		slippers = 0
	else:
		_spawn_slipper(origin, _throw_target, flight_time)
		slippers -= 1
	_cooldown = throw_cooldown
	_ring_time = flight_time + 0.2


func _spawn_slipper(origin: Vector3, target: Vector3, flight_time: float) -> void:
	var g := Vector3(0.0, -_gravity, 0.0)
	# Ballistic launch so it lands on the target.
	var velocity_out := (target - origin - 0.5 * g * flight_time * flight_time) / flight_time
	var slipper: RigidBody3D = TSINELAS_SCENE.instantiate()
	slipper.target_group = "player"
	slipper.hit_radius = thrown_hit_radius
	get_parent().add_child(slipper)
	slipper.global_transform = Transform3D(Basis.looking_at(velocity_out.normalized(), Vector3.UP), origin)
	slipper.add_collision_exception_with(self)
	slipper.hit_target.connect(func(_body): hit_player.emit())
	slipper.launch(velocity_out, Vector3.ZERO)
	_thrown.append(slipper)


## How many tayas are winding up a throw right now.
func _winding_count() -> int:
	var n := 0
	for t in get_tree().get_nodes_in_group("taya"):
		if t.state == State.WIND_UP:
			n += 1
	return n


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


# --- Movement helpers -----------------------------------------------------

## Run toward a direction with momentum: limited turning, and sharp turns
## cost speed (so juking the taya makes it swing wide).
func _steer(direction: Vector3, speed: float, delta: float) -> void:
	if direction.length() < 0.05:
		_brake(delta)
		return
	var desired := direction.normalized()
	var angle := _move_dir.signed_angle_to(desired, Vector3.UP)
	var max_step := deg_to_rad(turn_speed_deg) * delta
	_move_dir = _move_dir.rotated(Vector3.UP, clampf(angle, -max_step, max_step)).normalized()
	var turn_penalty := 1.0 - clampf(absf(angle) / PI, 0.0, 1.0) * 0.6
	_speed = move_toward(_speed, speed * turn_penalty, acceleration * delta)
	velocity.x = _move_dir.x * _speed
	velocity.z = _move_dir.z * _speed
	_face(_move_dir)


func _brake(delta: float) -> void:
	_speed = move_toward(_speed, 0.0, acceleration * 1.5 * delta)
	velocity.x = _move_dir.x * _speed
	velocity.z = _move_dir.z * _speed


func _halt() -> void:
	_speed = 0.0
	velocity.x = 0.0
	velocity.z = 0.0


func _face(direction: Vector3) -> void:
	if direction.length() > 0.05:
		rotation.y = atan2(-direction.x, -direction.z)


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
