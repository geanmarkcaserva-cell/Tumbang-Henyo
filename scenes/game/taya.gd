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
## - its throws scatter by `aim_error` metres;
## - it runs around houses instead of into them (ChaseNav);
## - it jumps like you do: hops over crates and low things in its way, and
##   jumps down off roofs and carts to get back at you;
## - up on a roof out of its reach? It looks around for footholds (crates,
##   carts, fences, a lower roof) and plans a chain of jumps up to you. Only
##   when there's no way up does it wait below and throw up at you.
##
## States: GUARD -> RESET -> CHASE <-> WIND_UP / PICKUP / LUNGE -> RECOVER.

signal lata_reset ## the lata is back in its circle; the chase starts
signal tagged_player
signal hit_player ## one of this taya's tsinelas hit the player

signal fled ## ran into a house and vanished (Mama's round)

enum State { IDLE, GUARD, RESET, CHASE, WIND_UP, PICKUP, LUNGE, RECOVER, FLEE }

const FLEE_SPEED := 7.5
const FLEE_GIVE_UP := 6.0 ## seconds: vanish even if a wall is in the way

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

## Fetching a slipper that's stuck (on a roof, behind a wall, wedged
## somewhere) or getting stuck on the way: after PICKUP_GIVE_UP seconds, or
## PICKUP_STUCK seconds of barely moving, the taya forgets it and pulls out a
## fresh batch, ready to throw again.
const PICKUP_GIVE_UP := 6.0
const PICKUP_STUCK := 2.0
var _pickup_time := 0.0
var _stuck_time := 0.0
var _last_pos := Vector3.ZERO
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _move_dir := Vector3.FORWARD
var _speed := 0.0
var _seen_pos := Vector3.ZERO ## where it last saw the player
var _seen_vel := Vector3.ZERO ## which way the player was moving then
var _look_timer := 0.0
var _seen_y := 0.0 ## how high the player was (on a roof?)
var _memo := {} ## ChaseNav's path cache for this taya

## Jumping (as high as the player: crates, carts, low roofs).
const JUMP_VELOCITY := 7.2 ## the biggest jump: about 2.6 m
const JUMP_REACH := 2.4 ## the highest ledge it tries to get onto
const LOW_HOP := 1.1 ## things this low it hops over even when you're not up there
const JUMP_COOLDOWN := 0.7
const STEP_PROBE := 0.9 ## how far ahead it looks for a ledge
var _jump_cd := 0.0
var _goal_y := 0.0 ## how high where it's running to is

## You're up on a roof it can't jump straight onto: it looks around for
## footholds (crates, carts, fences, posts, a lower roof) and plans a chain
## of jumps from the ground up to where you are, then follows it. With no
## way up, it waits below and throws.
const CLIMB_RANGE := 15.0 ## you're up on something this close: plan a way up
const CLIMB_AREA := 9.0 ## half-size of the square of ground it checks
const CLIMB_GRID := 0.8 ## metres between the spots it checks
const CLIMB_HOP := 2.8 ## the farthest it jumps across (with a run-up)
const CLIMB_REPLAN := 1.0 ## seconds between plans (sooner if you move)
var _climb: Array[Vector3] = [] ## footholds still ahead; the last is where you are
var _climb_t := 0.0
var _climb_for := Vector3.INF ## where you were when it planned

## Standing the lata back up: if it can't get to it (stuck on something),
## it stands it up anyway after this long without getting closer.
const RESET_STUCK := 2.5
var _reset_stuck := 0.0
var _reset_last := Vector3.ZERO

## Carrying the lata back to its circle (see _do_reset).
const PICKUP_TIME := 0.45 ## seconds to bend down and pick it up
const CARRY_SPEED := 0.85 ## of reset_run_speed, with the can in its hands
const SET_DOWN_MIN := 0.6 ## at least this long to set it down at the circle
var _carrying := false
var _carry_t := 0.0 ## seconds since it reached the lata (picking up + carrying)

## Wedged somewhere (under a house's eaves, between walls, behind a crate):
## trying to run but hardly moving. It keeps jumping as it goes after you
## until it breaks free (and the barangay pulls it out of a house it has
## clipped into, the same as you - see game.gd).
const STUCK_SPEED := 0.6 ## m/s: slower than this while trying to run = stuck
const STUCK_JUMP_AFTER := 0.5 ## seconds stuck before it starts jumping
const STUCK_JUMP_EVERY := 0.55 ## seconds between its jumps while stuck
var _stuck_run := 0.0
const STUCK_SIDESTEP := 0.9 ## seconds each stuck jump carries it sideways along the obstacle
var _side_t := 0.0
var _side_dir := Vector3.ZERO
var _side_sign := 1.0
var _side_tries := 0 ## sidesteps the same way in a row (it switches sides after 3)

var _alert: Label3D ## the "!" over its head while it winds up a throw
var _alert_time := 0.0

@onready var _ring: MeshInstance3D = $WarningRing


## GM and Ashiela are a couple. If you play one of them and this taya is
## the other, they chase you with a pixel heart over their head (no
## slippers, no lunges). They can still catch you: then the two of them
## dance together under the heart instead of the usual "Huli ka!".
const COUPLE := {"gm": "ashiela", "ashiela": "gm"}
const SWEET_RANGE := 4.0 ## the heart shows this close
const HEART_TEX := preload("res://art/ui/hud/heart_pixel.png")
const HEART_Y := 2.75

var smitten := false
var _heart: Sprite3D
var _heart_t := 0.0
var _dance_left := 0.0 ## seconds of dancing left after catching their other half
var _cheer_left := 0.0 ## seconds of cheering left (their other half made it home)


## Every taya is one of the barkada: a random hand-drawn playable character
## (never an NPC), all different from the other tayas out while there are
## enough to go round, and never the one you're playing as. {} when there
## are none (then the old red-shirt placeholder).
var skin_id := ""


static func _pick_skin() -> Dictionary:
	var all: Array = Economy.sprite_characters()
	var pool: Array = all.filter(func(c: Dictionary) -> bool: return c.id != Economy.equipped_character)
	if pool.is_empty():
		pool = all
	var used := {}
	for t in (Engine.get_main_loop() as SceneTree).get_nodes_in_group("taya"):
		used[t.get("skin_id")] = true
	var free: Array = pool.filter(func(c: Dictionary) -> bool: return not used.has(c.id))
	if free.is_empty():
		free = pool
	return free.pick_random() if not free.is_empty() else {}


func _ready() -> void:
	add_to_group("taya")
	if elite:
		max_slippers = 3
	_guard_transform = global_transform
	slippers = max_slippers
	var skin := _pick_skin()
	skin_id = skin.get("id", "")
	if skin.is_empty():
		var palette: Dictionary = ELITE_PALETTE if elite else PALETTE
		$PaperDoll.set_textures(PixelArt.character(palette), PixelArt.character_back(palette))
	else:
		$PaperDoll.set_look(PixelArt.character_look(skin))
	smitten = skin_id != "" and COUPLE.get(Economy.equipped_character, "") == skin_id
	_heart = Sprite3D.new()
	_heart.texture = HEART_TEX
	_heart.pixel_size = 0.06 # 9 px wide -> about half a metre
	_heart.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST # crisp pixels
	_heart.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_heart.no_depth_test = true
	_heart.shaded = false
	_heart.render_priority = 10
	_heart.position = Vector3(0.0, HEART_Y, 0.0)
	_heart.visible = false
	add_child(_heart)
	if elite:
		_ring.scale = Vector3.ONE * 2.4 # the fan covers a wider area
	_move_dir = _flat(-global_basis.z).normalized()
	_ring.top_level = true
	_ring.visible = false
	_alert = Label3D.new()
	_alert.text = "!"
	_alert.font_size = 160
	_alert.outline_size = 36
	_alert.pixel_size = 0.0045
	_alert.modulate = Color(1.0, 0.85, 0.1)
	_alert.outline_modulate = Color(0.55, 0.0, 0.0)
	_alert.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_alert.no_depth_test = true
	_alert.fixed_size = false
	_alert.render_priority = 20
	_alert.outline_render_priority = 19
	_alert.position = Vector3(0.0, 2.45, 0.0)
	_alert.visible = false
	add_child(_alert)


func _process(delta: float) -> void:
	if smitten and _player:
		var dancing := _dance_left > 0.0
		var cheering := _cheer_left > 0.0
		if cheering:
			_cheer_left -= delta
		var close := dancing or cheering or (_true_distance() < SWEET_RANGE and state >= State.CHASE and state != State.FLEE)
		if close and not _heart.visible:
			_heart_t = 0.0
		_heart.visible = close
		if close:
			_heart_t += delta
			var pop := minf(_heart_t / 0.2, 1.0)
			if dancing:
				# A bigger, beating heart floating over the two of them.
				_dance_left -= delta
				var mid := (global_position + _player.global_position) * 0.5
				_heart.global_position = mid + Vector3(0.0, HEART_Y + 0.25 + 0.12 * sin(_heart_t * 4.0), 0.0)
				var beat := 1.0 + 0.18 * maxf(sin(_heart_t * 9.0), 0.0)
				_heart.scale = Vector3.ONE * 1.6 * pop * beat
			elif cheering:
				# Beating over their head while they cheer you home!
				_heart.position = Vector3(0.0, HEART_Y + 0.15 + 0.1 * sin(_heart_t * 3.0), 0.0)
				_heart.scale = Vector3.ONE * 1.3 * pop * (1.0 + 0.18 * maxf(sin(_heart_t * 9.0), 0.0))
			else:
				_heart.position = Vector3(0.0, HEART_Y + 0.08 * sin(_heart_t * 3.0), 0.0)
				_heart.scale = Vector3.ONE * (0.4 + 0.6 * pop) * (1.0 + 0.1 * sin(_heart_t * 6.0))
	# The "!" pops in, then pulses until the tsinelas leaves the hand.
	if _alert.visible:
		_alert_time += delta
		var pop := minf(_alert_time / 0.12, 1.0)
		var pulse := 1.0 + 0.12 * sin(_alert_time * 28.0)
		_alert.scale = Vector3.ONE * (0.3 + 0.9 * pop) * pulse


func _show_alert(on: bool) -> void:
	_alert.visible = on
	_alert_time = 0.0


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
	if _gone or state == State.FLEE:
		return # off home for Mama's round
	_clear_thrown()
	_dance_left = 0.0
	_cheer_left = 0.0
	slippers = max_slippers
	global_transform = _guard_transform
	velocity = Vector3.ZERO
	_speed = 0.0
	_lunge_cd = 0.0
	_move_dir = _flat(-global_basis.z).normalized()
	_ring.visible = false
	_show_alert(false)
	state = State.GUARD


## The lata was knocked down: go stand it back up, then chase.
func start_reset() -> void:
	state = State.RESET
	_timer = 0.0
	_reset_stuck = 0.0
	_reset_last = global_position
	_carrying = false
	_carry_t = 0.0


## Another taya stood the lata up: join the chase.
func start_chase() -> void:
	if state == State.GUARD:
		_look_timer = 0.0
		state = State.CHASE


## Hit by the player's tsinelas during the throw: squish and flash red.
## (Only a reaction; it doesn't change what the taya does.)
func hurt() -> void:
	$PaperDoll.hurt()


func stop() -> void:
	if state == State.FLEE:
		return
	state = State.IDLE
	_halt()
	_ring.visible = false
	_show_alert(false)


# --- Mama's round: everyone runs home ------------------------------------------

var _flee_to := Vector3.ZERO
var _flee_reach := 1.0
var _gone := false


## 6 PM: run to `point` (a house) and disappear inside. `reach` = how close
## to the point counts as "home" (about the house's half size).
func flee_to(point: Vector3, reach: float) -> void:
	_clear_thrown()
	_ring.visible = false
	_show_alert(false)
	_flee_to = _flat(point)
	_flee_reach = reach
	_timer = 0.0
	_speed = 0.0
	state = State.FLEE
	_alert.text = "!!"
	_show_alert(true)


func is_gone() -> bool:
	return _gone


## Gone for the round: invisible, no collision, does nothing.
func vanish() -> void:
	_show_alert(false)
	_alert.text = "!"
	state = State.IDLE
	_halt()
	var t := create_tween()
	t.tween_property($PaperDoll, "scale", Vector3(0.05, 1.4, 0.05), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.tween_callback(func():
		visible = false
		$CollisionShape3D.set_deferred("disabled", true)
		process_mode = Node.PROCESS_MODE_DISABLED
		_gone = true
		fled.emit())


## Mama's round is over: back on the court at the guard spot.
func come_back() -> void:
	_gone = false
	process_mode = Node.PROCESS_MODE_INHERIT
	visible = true
	$CollisionShape3D.set_deferred("disabled", false)
	$PaperDoll.scale = Vector3.ONE
	_alert.text = "!"
	return_to_guard()


func _do_flee(delta: float) -> void:
	_timer += delta
	var to := _flee_to - _flat(global_position)
	if to.length() <= _flee_reach or _timer >= FLEE_GIVE_UP or (_timer > 1.0 and is_on_wall() and to.length() < _flee_reach + 3.0):
		vanish()
		return
	_go(_flee_to, FLEE_SPEED, delta)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	_cooldown = maxf(_cooldown - delta, 0.0)
	_lunge_cd = maxf(_lunge_cd - delta, 0.0)
	if _ring_time > 0.0:
		_ring_time -= delta
		if _ring_time <= 0.0 and state != State.WIND_UP:
			_ring.visible = false
	if _player and state >= State.CHASE and state != State.FLEE:
		_look(delta)
	# Pulled off the job while carrying the lata (caught you, round over,
	# Mama...): it goes straight back to its circle, never left floating.
	if _carrying and state != State.RESET:
		_carrying = false
		if is_instance_valid(_lata) and _lata.carried:
			_lata.reset_to_home()

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
		State.FLEE:
			_do_flee(delta)
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

	_jump_cd = maxf(_jump_cd - delta, 0.0)
	if is_on_floor() and state in [State.RESET, State.CHASE, State.PICKUP, State.LUNGE]:
		_try_jump()
		_jump_if_stuck(delta)
	if _side_t > 0.0:
		_side_t -= delta
		velocity.x = _side_dir.x * chase_speed * 0.9
		velocity.z = _side_dir.z * chase_speed * 0.9
	move_and_slide()


# --- Perception ---------------------------------------------------------

## The taya doesn't track you perfectly: it glances at you every so often.
func _look(delta: float) -> void:
	_look_timer -= delta
	if _look_timer <= 0.0:
		_seen_pos = _flat(_player.global_position)
		_seen_vel = _flat(_player.velocity)
		_seen_y = _player.global_position.y
		_look_timer = reaction_time * randf_range(0.7, 1.3)


func _true_distance() -> float:
	return _flat(_player.global_position - global_position).length()


func _can_tag(reach: float) -> bool:
	return _true_distance() <= reach and absf(_player.global_position.y - global_position.y) < 1.5


# --- States -------------------------------------------------------------

## Putting the lata back, like a real taya: run to wherever it ended up,
## pick it up, carry it back to its circle and set it down there. The walk
## back counts toward reset_time, so you get about as long to run as before.
func _do_reset(delta: float) -> void:
	if not _carrying:
		# 1. Run to the lata.
		var to_lata := _flat(_lata.global_position - global_position)
		if to_lata.length() > 0.9 and _timer == 0.0 and not _reset_stuck_now(delta):
			_go(_lata.global_position, reset_run_speed, delta)
			return
		# 2. Bend down and pick it up.
		_halt()
		_face(to_lata)
		_timer += delta
		_carry_t += delta
		if _timer >= PICKUP_TIME:
			_carrying = true
			_lata.carry(true)
			_timer = 0.0
			_reset_stuck = 0.0
			Sfx.play_at("lata_set", global_position, -6.0, 1.3, 0.1)
		return
	_carry_t += delta
	_lata.hold(global_position - global_basis.z * 0.38 + Vector3.UP * 0.95)
	var home: Vector3 = _lata.home()
	var to_home := _flat(home - global_position)
	# 3. Carry it back (stuck on the way: it goes straight home anyway).
	if to_home.length() > 0.55 and _timer == 0.0 and not _reset_stuck_now(delta):
		_go(home, reset_run_speed * CARRY_SPEED, delta)
		return
	# 4. Set it down in its circle.
	_halt()
	_face(to_home if to_home.length() > 0.05 else -global_basis.z)
	_timer += delta
	if _timer >= maxf(reset_time - _carry_t, SET_DOWN_MIN):
		_carrying = false
		_lata.reset_to_home() # upright in the middle of its circle
		# Start the chase with a fresh look at the player.
		_look_timer = 0.0
		state = State.CHASE
		lata_reset.emit()


## Not getting any closer for a while (stuck on something)?
func _reset_stuck_now(delta: float) -> bool:
	if _flat(global_position - _reset_last).length() < reset_run_speed * 0.25 * delta:
		_reset_stuck += delta
	else:
		_reset_stuck = maxf(_reset_stuck - delta * 0.5, 0.0)
	_reset_last = global_position
	return _reset_stuck >= RESET_STUCK


func _do_chase(delta: float) -> void:
	if smitten:
		_follow_sweetly(delta)
		return
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
	_run_after_player(delta)


## Run toward where it predicts you'll be (around houses if need be); if
## you're up on something close by, climb up after you (footholds first).
func _run_after_player(delta: float) -> void:
	if _seen_y > global_position.y + 0.8 and _flat(_seen_pos - global_position).length() < CLIMB_RANGE:
		if _follow_climb(delta):
			return
	else:
		_climb.clear()
	var target := _seen_pos + _seen_vel * chase_lead
	target.y = _seen_y
	_go(target, chase_speed, delta)


## Chasing their other half: no throws and no lunges, but they can catch you.
func _follow_sweetly(delta: float) -> void:
	if _can_tag(tag_distance):
		_tag()
		return
	_run_after_player(delta)


## Their other half (GM / Ashiela) made it past the finish line: they turn
## to you and cheer (happy sheet) under a beating heart, wherever they are.
func cheer_for_player(seconds: float) -> void:
	if not smitten:
		return
	_cheer_left = seconds
	_heart_t = 0.0
	if _player:
		_face(_flat(_player.global_position - global_position))
	$PaperDoll.play_happy(seconds)


## Caught their other half: face them and dance (happy sheet) under the
## heart for `seconds`. The round controller calls it on the catch.
func dance_with_player(seconds: float) -> void:
	_dance_left = seconds
	_heart_t = 0.0
	_face(_flat(_player.global_position - global_position))
	$PaperDoll.play_happy(seconds)


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
	# Failsafe: taking too long, or not getting anywhere.
	_pickup_time += delta
	var moved := _flat(global_position - _last_pos).length()
	_last_pos = global_position
	if moved < chase_speed * 0.25 * delta:
		_stuck_time += delta
	else:
		_stuck_time = maxf(_stuck_time - delta * 0.5, 0.0)
	if _pickup_time >= PICKUP_GIVE_UP or _stuck_time >= PICKUP_STUCK:
		_fresh_batch()
		return
	if not is_instance_valid(_pickup_target):
		# Lost it (fell off the map): pretend to grab a spare.
		slippers = 1
		state = State.CHASE
		return
	var to_slipper := _flat(_pickup_target.global_position - global_position)
	if to_slipper.length() <= 0.9:
		if elite:
			# The elite scoops up its whole set (and its spare) in one go:
			# one slipper back in hand reloads all three.
			_clear_thrown()
			slippers = max_slippers
		else:
			_thrown.erase(_pickup_target)
			_pickup_target.queue_free()
			_pickup_target = null
			slippers += 1
		state = State.CHASE
		return
	_go(_pickup_target.global_position, chase_speed, delta)


func _start_pickup() -> void:
	_pickup_time = 0.0
	_stuck_time = 0.0
	_last_pos = global_position
	_pickup_target = null
	var best := INF
	for slipper in _thrown:
		if is_instance_valid(slipper):
			var d := global_position.distance_to(slipper.global_position)
			if d < best:
				best = d
				_pickup_target = slipper
	state = State.PICKUP


## Gave up on its thrown slippers: they vanish, the taya has a full set again
## (elite: all three) and throws at the first chance.
func _fresh_batch() -> void:
	_clear_thrown()
	_pickup_target = null
	slippers = max_slippers
	_cooldown = 0.0
	_look_timer = 0.0
	state = State.CHASE


# --- Throwing ---------------------------------------------------------------

func _start_wind_up(distance: float) -> void:
	state = State.WIND_UP
	_timer = wind_up_time
	# Aim a bit ahead of where it last saw you heading, with some scatter.
	var flight_time := _flight_time(distance)
	var lead := _seen_vel * (wind_up_time + flight_time) * lead_factor
	var scatter := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).limit_length(1.0) * aim_error
	_throw_target = _seen_pos + lead + scatter + Vector3(0.0, _seen_y + 0.03, 0.0)
	_ring.global_position = _throw_target
	_ring.visible = true
	_show_alert(true)
	Sfx.play_at("alert", global_position, 4.0, 1.0, 0.03) # the "!" warning: a throw is coming


func _throw() -> void:
	_show_alert(false)
	Sfx.play_at("throw", global_position, 0.0, 0.85)
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


## Fast, flat throws: less time to react once the tsinelas leaves the hand.
func _flight_time(distance: float) -> float:
	return clampf(distance / throw_speed, min_flight_time, max_flight_time)


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

## Run to a point, taking the path around houses when one is in the way.
func _go(point: Vector3, speed: float, delta: float) -> void:
	_goal_y = point.y
	var dest := point
	# Up on something (the paths are on the ground), or right below where
	# it's going: straight there, jumping on or off whatever's in the way.
	var up_on_something := global_position.y > _guard_transform.origin.y + 0.5
	var just_above := point.y > global_position.y + 0.6 and _flat(point - global_position).length() < 3.0
	if ChaseNav.current and not up_on_something and not just_above:
		dest = ChaseNav.current.route(self, point, _memo, delta)
	_steer(_flat(dest - global_position), speed, delta)


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


# --- Jumping --------------------------------------------------------------

## Jump onto a ledge in the way (if it's low, or you're up there too), or
## hop down off an edge when where it's going is lower.
func _try_jump() -> void:
	if _jump_cd > 0.0 or _speed < 1.0:
		return
	var feet := global_position.y
	var ledge := _probe_ledge(_move_dir, STEP_PROBE)
	if not ledge.is_empty():
		var h: float = ledge.h
		if h <= LOW_HOP or _goal_y > feet + 0.6:
			_jump(h)
		return
	var ahead := global_position + _move_dir * 0.6 + Vector3.UP * 0.3
	if not _ray(ahead, ahead + Vector3.DOWN * 1.0).is_empty():
		return # solid ground ahead
	if _goal_y < feet - 0.6:
		_jump(0.0) # off the edge with a little hop
	elif not _climb.is_empty() and feet > _guard_transform.origin.y + 0.5:
		_jump(maxf(_goal_y - feet, 0.0) + 0.2) # leap the gap to the next foothold


## Stuck while running after you (or to the lata): keep jumping, a little
## sideways each time so it doesn't keep hitting the same spot.
func _jump_if_stuck(delta: float) -> void:
	var trying := _speed > 1.5
	var moving := _flat(get_real_velocity()).length() > STUCK_SPEED
	if trying and not moving:
		_stuck_run += delta
	else:
		_stuck_run = maxf(_stuck_run - delta * 2.0, 0.0)
		if _stuck_run == 0.0:
			_side_tries = 0 # free again
	if _stuck_run >= STUCK_JUMP_AFTER and _jump_cd <= 0.0:
		# Jump, and slide along the obstacle while in the air (the same way
		# for three tries, then the other way).
		_side_tries += 1
		if not _climb.is_empty():
			# Climbing: always slide toward the next foothold.
			var left := _move_dir.rotated(Vector3.UP, PI * 0.5)
			_side_sign = 1.0 if left.dot(_flat(_climb[0] - global_position)) >= 0.0 else -1.0
		elif _side_tries == 1:
			_side_sign = 1.0 if randf() < 0.5 else -1.0
		elif _side_tries % 3 == 1:
			_side_sign = -_side_sign
		_side_dir = _move_dir.rotated(Vector3.UP, PI * 0.5 * _side_sign)
		_side_t = STUCK_SIDESTEP
		_jump(1.0)
		_jump_cd = STUCK_JUMP_EVERY


func _jump(height: float) -> void:
	var v := sqrt(2.0 * _gravity * (height + 0.45)) if height > 0.0 else 3.2
	velocity.y = minf(v, JUMP_VELOCITY)
	_speed = maxf(_speed, 3.5) # enough run-up to land on it
	velocity.x = _move_dir.x * _speed
	velocity.z = _move_dir.z * _speed
	_jump_cd = 0.25 if not _climb.is_empty() else JUMP_COOLDOWN # climbing: foothold to foothold
	Sfx.play_at("jump", global_position, -4.0, 1.1, 0.08)


## Something to jump onto in `dir` within `reach` metres: {over, h} (where to
## land and how high it is above its feet), or {} if nothing / too high.
func _probe_ledge(dir: Vector3, reach: float) -> Dictionary:
	var feet := global_position.y
	var knee := global_position + Vector3.UP * 0.35
	var hit := _ray(knee, knee + dir * reach)
	if hit.is_empty():
		return {}
	var p: Vector3 = hit.position
	var over := Vector3(p.x, 0.0, p.z) + dir * 0.4
	var high_y := feet + JUMP_REACH + 0.35
	# A wall taller than the jump: no way up here.
	if not _ray(Vector3(global_position.x, high_y, global_position.z), Vector3(over.x, high_y, over.z)).is_empty():
		return {}
	var top := _ray(Vector3(over.x, high_y, over.z), Vector3(over.x, feet + 0.25, over.z))
	if top.is_empty():
		return {}
	var h: float = top.position.y - feet
	if h <= 0.25 or h > JUMP_REACH:
		return {}
	return {"over": Vector3(over.x, top.position.y, over.z), "h": h}


# --- Climbing up to you -------------------------------------------------------

## Head for the next foothold of the plan (planning again every so often).
## False when there's no way up from here.
func _follow_climb(delta: float) -> bool:
	var goal := Vector3(_seen_pos.x, _seen_y, _seen_pos.z)
	_climb_t -= delta
	if _climb_t <= 0.0 or _climb_for.distance_to(goal) > 1.5:
		_climb_t = CLIMB_REPLAN * randf_range(0.85, 1.15)
		_climb_for = goal
		_climb = _plan_climb(goal)
	# Footholds already reached.
	while not _climb.is_empty():
		var c := _climb[0]
		if _flat(c - global_position).length() < 0.8 and absf(c.y - global_position.y) < 0.6:
			_climb.remove_at(0)
		else:
			break
	if _climb.is_empty():
		return false
	var next := _climb[0]
	_goal_y = next.y
	var ground := _guard_transform.origin.y
	if global_position.y < ground + 0.5 and _flat(next - global_position).length() > 3.0 and ChaseNav.current:
		# Still on the ground and far from the first foothold: walk there around houses.
		var dest := ChaseNav.current.route(self, Vector3(next.x, ground, next.z), _memo, delta)
		_steer(_flat(dest - global_position), chase_speed, delta)
	else:
		_steer(_flat(next - global_position), chase_speed, delta)
	return true


## Find a way up to `goal`: every raised surface in a square around it (roof
## tops, crates, carts...) is a spot; a jump links two spots if they're close
## enough and the higher one is within jumping height. Working back from
## your spot gives each spot its number of jumps to you; the plan starts at
## the foothold it can jump onto from the ground (or from where it stands)
## that is quickest overall, and steps down the count to you.
func _plan_climb(goal: Vector3) -> Array[Vector3]:
	var ground := _guard_transform.origin.y
	var feet := global_position.y
	var top_y := maxf(goal.y, feet) + 2.5
	var centre := _flat(goal) * 0.65 + _flat(global_position) * 0.35
	var n := int(CLIMB_AREA * 2.0 / CLIMB_GRID)
	var spots: Array[Vector3] = []
	var cell := {} # Vector2i -> spot index
	for ix in n + 1:
		for iz in n + 1:
			var x := centre.x - CLIMB_AREA + ix * CLIMB_GRID
			var z := centre.z - CLIMB_AREA + iz * CLIMB_GRID
			var hit := _ray(Vector3(x, top_y, z), Vector3(x, ground + 0.3, z))
			if hit.is_empty() or (hit.normal as Vector3).y < 0.6:
				continue # just ground here, or too steep to stand on
			cell[Vector2i(ix, iz)] = spots.size()
			spots.append(hit.position)
	# Your spot: the surface right under you.
	var gi := Vector2i(roundi((goal.x - centre.x + CLIMB_AREA) / CLIMB_GRID), roundi((goal.z - centre.z + CLIMB_AREA) / CLIMB_GRID))
	if not cell.has(gi) or absf(spots[cell[gi]].y - goal.y) > 0.8:
		return []
	var reach := ceili(CLIMB_HOP / CLIMB_GRID)
	# Jumps to you, from every spot (breadth-first from your spot backwards).
	var hops := {}
	hops[cell[gi]] = 0
	var queue: Array[Vector2i] = [gi]
	var head := 0
	while head < queue.size():
		var b_cell := queue[head]
		head += 1
		var b: Vector3 = spots[cell[b_cell]]
		var hb: int = hops[cell[b_cell]]
		for dx in range(-reach, reach + 1):
			for dz in range(-reach, reach + 1):
				var a_cell := b_cell + Vector2i(dx, dz)
				if not cell.has(a_cell) or hops.has(cell[a_cell]):
					continue
				var a: Vector3 = spots[cell[a_cell]]
				if _flat(b - a).length() <= CLIMB_HOP and b.y - a.y <= JUMP_REACH - 0.1:
					hops[cell[a_cell]] = hb + 1
					queue.append(a_cell)
	# Where to start: a foothold it can jump onto from where it is now.
	var start := -1
	var best := INF
	var elevated := feet > ground + 0.5
	for i in hops:
		var s: Vector3 = spots[i]
		var d := _flat(s - global_position).length()
		var ok := (s.y - feet <= JUMP_REACH - 0.1) and (d <= CLIMB_HOP if elevated else s.y - ground <= JUMP_REACH - 0.1)
		if not ok:
			continue
		var score := d + float(hops[i]) * 1.5
		if score < best:
			best = score
			start = i
	if start < 0:
		return []
	# Step down the count: each time the nearest spot one jump closer.
	var plan: Array[Vector3] = [spots[start]]
	var at := start
	while int(hops[at]) > 0:
		var here: Vector3 = spots[at]
		var want: int = hops[at] - 1
		var pick := -1
		var near := INF
		for i in hops:
			if int(hops[i]) != want:
				continue
			var s: Vector3 = spots[i]
			var d := _flat(s - here).length()
			if d <= CLIMB_HOP and s.y - here.y <= JUMP_REACH - 0.1 and d < near:
				near = d
				pick = i
		if pick < 0:
			break
		plan.append(spots[pick])
		at = pick
	return plan


## A ray against the world (houses, crates, the ground), ignoring people
## and loose things.
func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or hit.collider is CharacterBody3D or hit.collider is RigidBody3D:
		return {}
	return hit


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
