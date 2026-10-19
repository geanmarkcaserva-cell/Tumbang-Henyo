class_name Mama
extends CharacterBody3D
## Round 15 boss: it's 6 PM and Mama is home, belt in hand.
##
## She's much faster than the player but runs like a freight train: wide
## turns, and she slows down for sharp ones. When a house blocks her view she
## follows the player's own footsteps around it, so breaking line of sight
## and cutting tight corners round the houses is how you shake her.
## She throws hangers and walis tambo (brooms) without ever running out.

signal caught_player
signal hit_player

const PROJECTILE := preload("res://scenes/game/boss_projectile.gd")

const RUN_SPEED := 8.4 ## sees you: full speed (player walks 5, sprints 8)
const SEARCH_SPEED := 6.2 ## lost sight: follows your footsteps
const HEAD_START := 1.3 ## seconds she spends yelling before she runs
const ACCEL := 14.0
const TURN_RATE := 2.6 ## rad/s at full speed: about a 3.5 m turning circle
const CATCH_RADIUS := 1.1
const THROW_COOLDOWN := Vector2(1.4, 2.1)
const THROW_RANGE := Vector2(4.0, 26.0)
const WINDUP := 0.35 ## slows down and raises the arm before each throw
const STUN_AFTER_CATCH := 2.0
const TRAIL_STEP := 0.8
const TRAIL_MAX := 300
const PROJECTILE_SPEED := 17.0
const AIM_SCATTER := 0.7
## Shout text -> her recorded line (drop the files into art/Audio/sfx).
const SHOUT_VOICES := {
	"HOY! HALIKA DITO!": "voice_mama_halika",
	"HOY!": "voice_mama_hoy",
	"HALIKA DITO!": "voice_mama_halika",
	"LAGOT KA!": "voice_mama_lagot",
	"UWI NA!": "voice_mama_uwi",
}

## The sprite: 18 x 30, belt raised over her head. Two front frames (belt
## swinging), one from behind.
const FRONT_A := [
	"..............KK..",
	"...............KK.",
	"...............KK.",
	"..............KK..",
	"............GKK...",
	"............SS....",
	".....RHHR...SS....",
	"....HHHHHH..SS....",
	"...HHHHHHHH.SS....",
	"...HSSSSSSH.SS....",
	"...BSSSSSSB.SS....",
	"...SBSSSSBS.SS....",
	"...SEESSEES.SS....",
	"...SSSSSSSS.SS....",
	"....SSMMSS..SS....",
	"....SSMMSS..SS....",
	".....SSSS..SS.....",
	"...DDDDDDDDDD.....",
	"..DDdDDDDdDDD.....",
	".SDDDDDdDDDDD.....",
	".SDdDDDDDDdDD.....",
	".SDDDDdDDDDDD.....",
	".SDDdDDDDdDDD.....",
	"..DDDDDDDDDDD.....",
	"..DDdDDDdDDDD.....",
	"..DDDDDDDDDDD.....",
	"..ddddddddddd.....",
	"...LL.....LL......",
	"...LL.....LL......",
	"..FFF.....FFF.....",
]
## Frame B only changes the top rows: the belt flicks straight up.
const FRONT_B_TOP := [
	"...........KK.....",
	"...........KK.....",
	"............KK....",
	"............KK....",
	"............GG....",
]
const BACK := [
	"..............KK..",
	"...............KK.",
	"...............KK.",
	"..............KK..",
	"............GKK...",
	"............SS....",
	".....RHHR...SS....",
	"....HHHHHH..SS....",
	"...HHHHHHHH.SS....",
	"...HHHHHHHH.SS....",
	"...HHHHHHHH.SS....",
	"...HHHHHHHH.SS....",
	"...HHHHHHHH.SS....",
	"...SHHHHHHS.SS....",
	"....SSSSSS..SS....",
	"....SSSSSS..SS....",
	".....SSSS..SS.....",
	"...DDDDDDDDDD.....",
	"..DDDDDDDDDDD.....",
	".SDDDDDDDDDDD.....",
	".SDDdDDDDdDDD.....",
	".SDDDDDDDDDDD.....",
	".SDDDDdDDDDDD.....",
	"..DDDDDDDDDDD.....",
	"..DDdDDDDDdDD.....",
	"..DDDDDDDDDDD.....",
	"..ddddddddddd.....",
	"...LL.....LL......",
	"...LL.....LL......",
	"..FFF.....FFF.....",
]
const COLORS := {
	"H": Color(0.12, 0.09, 0.08), "R": Color(1.0, 0.47, 0.7), "S": Color(0.8, 0.59, 0.45),
	"L": Color(0.8, 0.59, 0.45), "E": Color(0.12, 0.05, 0.05), "B": Color(0.1, 0.05, 0.04),
	"M": Color(0.51, 0.06, 0.08), "D": Color(0.84, 0.31, 0.53), "d": Color(1.0, 0.84, 0.31),
	"F": Color(0.2, 0.59, 0.9), "K": Color(0.43, 0.24, 0.1), "G": Color(0.94, 0.78, 0.24),
}

var target: CharacterBody3D
var active := false

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _heading := Vector3.FORWARD
var _speed := 0.0
var _trail: Array[Vector3] = []
var _trail_idx := 0
var _sees := false
var _look_timer := 0.0
var _shortcut_timer := 0.0
var _throw_cd := 1.5
var _windup := 0.0
var _stun := 0.0
var _next_kind := 0
var _stuck_time := 0.0
var _doll: PaperDoll
var _shout: Label3D
var _shout_t := 0.0
var _thrown: Array[Node3D] = []


func _ready() -> void:
	add_to_group("mama")
	collision_layer = 0 # nothing bumps into her; she still slides along houses
	collision_mask = 1
	var shape := CapsuleShape3D.new()
	shape.radius = 0.45
	shape.height = 2.0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = 1.0
	add_child(cs)

	_doll = PaperDoll.new()
	_doll.shadow_radius = 0.6
	_doll.hop_height = 0.22
	add_child(_doll)
	_doll.set_look(_build_look())

	_shout = Label3D.new()
	_shout.text = "MAMA!"
	_shout.font = UiKit.title_font()
	_shout.font_size = 120
	_shout.outline_size = 30
	_shout.pixel_size = 0.008
	_shout.modulate = Color(1.0, 0.32, 0.28)
	_shout.outline_modulate = Color(0.18, 0.02, 0.02)
	_shout.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_shout.no_depth_test = true
	_shout.render_priority = 20
	_shout.outline_render_priority = 19
	_shout.position = Vector3(0.0, 3.25, 0.0)
	add_child(_shout)


func _build_look() -> Dictionary:
	var a := PixelArt._image(FRONT_A, COLORS)
	var rows_b := FRONT_A.duplicate()
	for i in FRONT_B_TOP.size():
		rows_b[i] = FRONT_B_TOP[i]
	var b := PixelArt._image(rows_b, COLORS)
	var w := a.get_width()
	var front := Image.create(w * 2, a.get_height(), false, Image.FORMAT_RGBA8)
	front.blit_rect(a, Rect2i(0, 0, w, a.get_height()), Vector2i(0, 0))
	front.blit_rect(b, Rect2i(0, 0, w, a.get_height()), Vector2i(w, 0))
	var back := PixelArt._image(BACK, COLORS)
	var front_tex := ImageTexture.create_from_image(front)
	var sheet := {"texture": front_tex, "frames": 2, "fps": 7.0}
	return {"idle": sheet, "happy": sheet,
		"run": {"texture": ImageTexture.create_from_image(back), "frames": 1, "fps": 0.0},
		"frame_h": FRONT_A.size(), "foot_pad": 0, "pixel_size": 0.088}


func setup(player: CharacterBody3D) -> void:
	target = player
	add_collision_exception_with(player)


## Stand still at `at`, glaring at the player (before the chase).
func wait_at(at: Vector3) -> void:
	active = false
	clear_thrown()
	global_position = at
	velocity = Vector3.ZERO
	_speed = 0.0
	_stun = 0.0
	_windup = 0.0
	_trail.clear()
	_trail_idx = 0
	if target:
		_heading = _flat(target.global_position - at).normalized()
		_face(_heading)


func start_chase() -> void:
	active = true
	_sees = true
	_look_timer = 0.0
	_throw_cd = HEAD_START + 0.6
	_stun = HEAD_START # winds up first: a moment to get going
	_shout_now("HOY! HALIKA DITO!")


func stop() -> void:
	active = false
	_speed = 0.0
	velocity = Vector3.ZERO


func clear_thrown() -> void:
	for p in _thrown:
		if is_instance_valid(p):
			p.queue_free()
	_thrown.clear()


func _process(delta: float) -> void:
	# The shout pops in and pulses, then settles.
	_shout_t += delta
	var pop := minf(_shout_t / 0.15, 1.0)
	var pulse := 1.0 + 0.1 * sin(_shout_t * 18.0) * exp(-_shout_t * 1.5)
	_shout.scale = Vector3.ONE * (0.4 + 0.6 * pop) * pulse


func _shout_now(text: String) -> void:
	_shout.text = text
	_shout_t = 0.0
	# Her voice, once recorded (art/Audio/sfx/voice_mama_*.wav; silent until then).
	var voice: String = SHOUT_VOICES.get(text, "")
	if voice != "":
		Sfx.play_at(voice, global_position, 6.0, 1.0, 0.0)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0
	if not active or target == null:
		_speed = move_toward(_speed, 0.0, ACCEL * delta)
		velocity.x = _heading.x * _speed
		velocity.z = _heading.z * _speed
		if target:
			_face(_flat(target.global_position - global_position))
		move_and_slide()
		return

	_stun = maxf(_stun - delta, 0.0)
	var me := global_position
	var goal := target.global_position

	# --- Can she see you? (checked ten times a second) ---
	_look_timer -= delta
	if _look_timer <= 0.0:
		_look_timer = 0.1
		var saw := _sees
		_sees = _clear_line(me + Vector3.UP * 1.4, goal + Vector3.UP * 1.0)
		if _sees:
			_trail.clear()
			_trail_idx = 0
		elif saw:
			_trail = [goal] # where she last saw you
			_trail_idx = 0
	# Your footsteps since she lost sight of you.
	if not _sees:
		if _trail.is_empty() or _trail.back().distance_to(goal) > TRAIL_STEP:
			_trail.append(goal)
			if _trail.size() > TRAIL_MAX:
				_trail.pop_front()
				_trail_idx = maxi(_trail_idx - 1, 0)
		# Skip ahead along the footsteps when a later one is in plain view.
		_shortcut_timer -= delta
		if _shortcut_timer <= 0.0:
			_shortcut_timer = 0.25
			var checks := 0
			for k in range(_trail.size() - 1, _trail_idx, -1):
				if checks >= 5:
					break
				checks += 1
				if _clear_line(me + Vector3.UP * 1.0, _trail[k] + Vector3.UP * 0.6):
					_trail_idx = k
					break

	var dest := goal
	if not _sees and _trail_idx < _trail.size():
		dest = _trail[_trail_idx]
		if _flat(dest - me).length() < 1.3:
			_trail_idx = mini(_trail_idx + 1, _trail.size() - 1)

	# --- Caught you ---
	if _stun <= 0.0 and _flat(goal - me).length() <= CATCH_RADIUS and absf(goal.y - me.y) < 1.6:
		_stun = STUN_AFTER_CATCH
		_speed = 0.0
		_shout_now("") # the HUD banner says it
		_doll.play_happy(1.4)
		caught_player.emit()

	# --- Throwing ---
	_throw_cd -= delta
	var dist := _flat(goal - me).length()
	if _windup > 0.0:
		_windup -= delta
		if _windup <= 0.0:
			_throw()
	elif _sees and _stun <= 0.0 and _throw_cd <= 0.0 and dist >= THROW_RANGE.x and dist <= THROW_RANGE.y:
		_windup = WINDUP

	# --- Running: momentum, wide turns ---
	var desired := _flat(dest - me)
	var max_speed := RUN_SPEED if _sees else SEARCH_SPEED
	if _windup > 0.0:
		max_speed *= 0.45
	if _stun > 0.0:
		max_speed = 0.0
	if desired.length() > 0.05:
		desired = desired.normalized()
		var angle := _heading.signed_angle_to(desired, Vector3.UP)
		# Slower = tighter turns.
		var rate := TURN_RATE * lerpf(3.0, 1.0, clampf(_speed / RUN_SPEED, 0.0, 1.0))
		var step := rate * delta
		_heading = _heading.rotated(Vector3.UP, clampf(angle, -step, step)).normalized()
		max_speed *= lerpf(1.0, 0.35, clampf(absf(angle) / PI, 0.0, 1.0))
	_speed = move_toward(_speed, max_speed, ACCEL * delta)
	velocity.x = _heading.x * _speed
	velocity.z = _heading.z * _speed
	move_and_slide()
	_face(_heading)

	# Scraping along a wall: turn along it, toward where she wants to go.
	if is_on_wall() and _speed > 1.0:
		var n := _flat(get_wall_normal()).normalized()
		var along := n.cross(Vector3.UP).normalized()
		if along.dot(desired) < 0.0:
			along = -along
		_heading = _heading.slerp(along, 0.5).normalized()
		_stuck_time += delta
		if _stuck_time > 0.8: # wedged in a corner: back off sideways
			_heading = (along + n).normalized()
			_stuck_time = 0.0
	else:
		_stuck_time = maxf(_stuck_time - delta, 0.0)


func _throw() -> void:
	if target == null:
		return
	var origin := global_position + Vector3.UP * 2.3
	var aim := target.global_position + Vector3.UP * 0.9
	var t := clampf(origin.distance_to(aim) / PROJECTILE_SPEED, 0.3, 1.3)
	# Leads you a bit, with some scatter.
	var lead := _flat(target.velocity) * t * 0.7
	var scatter := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).limit_length(1.0) * AIM_SCATTER
	aim += lead + scatter
	var g := Vector3(0.0, -PROJECTILE.GRAVITY, 0.0)
	var vel := (aim - origin - 0.5 * g * t * t) / t
	Sfx.play_at("throw_heavy", global_position, 2.0)
	var p = PROJECTILE.new()
	p.kind = _next_kind
	_next_kind = 1 - _next_kind
	get_parent().add_child(p)
	p.launch(origin, vel, target, [get_rid()])
	p.hit_target.connect(func(): hit_player.emit())
	var alive: Array[Node3D] = []
	for n in _thrown:
		if is_instance_valid(n):
			alive.append(n)
	alive.append(p)
	_thrown = alive
	_throw_cd = randf_range(THROW_COOLDOWN.x, THROW_COOLDOWN.y)
	_shout_now(["HOY!", "HALIKA DITO!", "LAGOT KA!", "UWI NA!"].pick_random())


func _clear_line(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, 1, [get_rid(), target.get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _face(direction: Vector3) -> void:
	if direction.length() > 0.05:
		rotation.y = atan2(-direction.x, -direction.z)


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
