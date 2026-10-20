class_name Tanod
extends CharacterBody3D
## Round 25 (secret, 7:00 PM): curfew, and the barangay tanods come out in a
## squad of five to catch you before you get home.
##
## Two kinds:
## - THROWER (navy uniform): never stops throwing tsinelas, fast and flat,
##   like Mama but with no break between throws. Keeps chasing while it throws.
## - DASHER (orange vest): chases, throws now and then, and every so often
##   locks on and DASHES at you at a terrible speed. A red strip on the ground
##   shows exactly where the dash will go a moment before it happens; step out
##   of it. Dashes have a long cooldown.
## Touching you (or a dash landing) catches you. Everyone paths around
## houses (ChaseNav) instead of running into walls.

signal caught_player
signal hit_player

enum Kind { THROWER, DASHER }
enum State { WAIT, CHASE, AIM, DASH, RECOVER }

const TSINELAS_SCENE := preload("res://scenes/game/tsinelas.tscn")

const RUN_SPEED := {Kind.THROWER: 6.4, Kind.DASHER: 7.0} ## player walks 5, sprints 8
const ACCEL := 16.0
const TURN_RATE := 4.0
const CATCH_RADIUS := 1.0
const HEAD_START := 1.2
## Throwing (both kinds): seconds between throws and how fast they fly.
## (Throwers were 0.55 - 0.85 s: too much. Now about one every 1.1 - 1.5 s each.)
const THROW_GAP := {Kind.THROWER: Vector2(1.1, 1.5), Kind.DASHER: Vector2(2.8, 3.6)}
const THROW_RANGE := Vector2(3.5, 22.0)
const THROW_SPEED := 25.0 ## m/s along the throw: still faster than a taya's (22)
const AIM_SCATTER := 0.8
const SLIPPER_HIT_RADIUS := 0.24
## Dash (DASHER only).
const DASH_RANGE := Vector2(4.0, 13.0)
const DASH_AIM_TIME := 0.8 ## the red strip shows this long before it goes
const DASH_SPEED := 27.0
const DASH_LENGTH := 15.0
const DASH_WIDTH := 1.7
const DASH_RECOVER := 0.7
const DASH_COOLDOWN := Vector2(4.5, 6.0)

const SPRITE_DIR := "res://art/characters/Tanod"
const NAVY := {"hair": Color(0.1, 0.13, 0.3), "band": Color(1.0, 0.82, 0.25), "skin": Color(0.74, 0.52, 0.38),
		"shirt": Color(0.12, 0.16, 0.36), "accent": Color(1.0, 0.82, 0.25), "pants": Color(0.08, 0.1, 0.22), "feet": Color(0.05, 0.05, 0.06)}
const ORANGE := {"hair": Color(0.1, 0.13, 0.3), "band": Color(1.0, 0.82, 0.25), "skin": Color(0.7, 0.5, 0.36),
		"shirt": Color(1.0, 0.45, 0.08), "accent": Color(0.95, 0.95, 0.85), "pants": Color(0.08, 0.1, 0.22), "feet": Color(0.05, 0.05, 0.06)}
const SHOUTS := ["CURFEW NA!", "TIGIL!", "HOY BATA!", "UWI NA!", "HULI KA!"]

var kind: Kind = Kind.THROWER
var target: CharacterBody3D
var active := false

var _state: State = State.WAIT
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _heading := Vector3.FORWARD
var _speed := 0.0
var _throw_cd := 1.0
var _dash_cd := 2.0
var _timer := 0.0
var _dash_dir := Vector3.FORWARD
var _dash_left := 0.0
var _stun := 0.0
var _memo := {}
var _doll: PaperDoll
var _shout: Label3D
var _shout_t := 9.0
var _strip: MeshInstance3D
var _strip_mat: StandardMaterial3D
var _thrown: Array[Node3D] = []


func _ready() -> void:
	add_to_group("tanod")
	collision_layer = 0
	collision_mask = 1
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.9
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = 0.95
	add_child(cs)

	_doll = PaperDoll.new()
	_doll.pixel_size = 0.1 # grown-ups: a head taller than the kids
	_doll.shadow_radius = 0.5
	add_child(_doll)
	var p: Dictionary = ORANGE if kind == Kind.DASHER else NAVY
	# Sheets in art/characters/Tanod (tanod_thrower_idle.png = front,
	# tanod_thrower_run.png = back; same for the dasher). Edit those to change
	# them; without them they're drawn from the palette.
	var id := "tanod_dasher" if kind == Kind.DASHER else "tanod_thrower"
	if ResourceLoader.exists("%s/%s_idle.png" % [SPRITE_DIR, id]):
		_doll.set_look(PixelArt.character_look({"id": id, "palette": p, "sprite": {"dir": SPRITE_DIR,
			"happy": id + "_idle.png", "pixel_size": 0.1, "cap_height": false}}))
	else:
		_doll.set_textures(PixelArt.character(p), PixelArt.character_back(p))

	_shout = Label3D.new()
	_shout.font = UiKit.title_font()
	_shout.font_size = 96
	_shout.outline_size = 26
	_shout.pixel_size = 0.008
	_shout.modulate = Color(1.0, 0.85, 0.3) if kind == Kind.THROWER else Color(1.0, 0.5, 0.2)
	_shout.outline_modulate = Color(0.1, 0.05, 0.02)
	_shout.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_shout.no_depth_test = true
	_shout.render_priority = 20
	_shout.outline_render_priority = 19
	_shout.position = Vector3(0.0, 3.0, 0.0)
	_shout.text = ""
	add_child(_shout)

	# Night patrol: each tanod carries a flashlight, so you can see them coming
	# (and they light up the ground around them).
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.86, 0.6)
	lamp.light_energy = 1.2
	lamp.omni_range = 4.0
	lamp.position = Vector3(0.0, 1.6, -0.4)
	lamp.shadow_enabled = false
	add_child(lamp)

	# The dash warning: a red strip on the ground.
	_strip = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(DASH_WIDTH, DASH_LENGTH)
	_strip.mesh = plane
	_strip_mat = StandardMaterial3D.new()
	_strip_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_strip_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_strip_mat.albedo_color = Color(1.0, 0.1, 0.08, 0.45)
	_strip_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_strip_mat.no_depth_test = false
	_strip.material_override = _strip_mat
	_strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_strip.top_level = true
	_strip.visible = false
	add_child(_strip)


func setup(player: CharacterBody3D) -> void:
	target = player
	add_collision_exception_with(player)


## Stand at `at` (before the chase), facing the player.
func wait_at(at: Vector3) -> void:
	active = false
	_state = State.WAIT
	clear_thrown()
	global_position = at
	velocity = Vector3.ZERO
	_speed = 0.0
	_strip.visible = false
	_memo.clear()
	if target:
		_heading = _flat(target.global_position - at).normalized()
		_face(_heading)


func start_chase(delay: float = 0.0) -> void:
	active = true
	_state = State.CHASE
	_stun = HEAD_START + delay
	_throw_cd = HEAD_START + delay + randf_range(0.2, 1.0)
	_dash_cd = HEAD_START + delay + randf_range(1.5, 3.0)
	_say(SHOUTS[randi() % 3])


func stop() -> void:
	active = false
	_state = State.WAIT
	_speed = 0.0
	velocity = Vector3.ZERO
	_strip.visible = false


func clear_thrown() -> void:
	for n in _thrown:
		if is_instance_valid(n):
			n.queue_free()
	_thrown.clear()


func _process(delta: float) -> void:
	_shout_t += delta
	var pop := minf(_shout_t / 0.15, 1.0)
	_shout.scale = Vector3.ONE * (0.4 + 0.6 * pop)
	if _shout_t > 1.6:
		_shout.text = ""
	if _strip.visible:
		# Pulses faster as the dash gets closer.
		var k := 1.0 - clampf(_timer / DASH_AIM_TIME, 0.0, 1.0)
		_strip_mat.albedo_color.a = 0.3 + 0.35 * (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.001 * lerpf(10.0, 32.0, k)))


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
	_throw_cd -= delta
	_dash_cd -= delta
	var me := global_position
	var goal := target.global_position
	var dist := _flat(goal - me).length()

	# Caught you (bumping into you, or the dash landing).
	if _stun <= 0.0 and dist <= (CATCH_RADIUS + (0.4 if _state == State.DASH else 0.0)) and absf(goal.y - me.y) < 1.6:
		_catch()
		return

	match _state:
		State.CHASE:
			if _stun <= 0.0 and kind == Kind.DASHER and _dash_cd <= 0.0 \
					and dist >= DASH_RANGE.x and dist <= DASH_RANGE.y and _sees():
				_start_aim()
			else:
				if _stun <= 0.0 and _throw_cd <= 0.0 and dist >= THROW_RANGE.x and dist <= THROW_RANGE.y and _sees():
					_throw()
				var dest := goal
				var nav := ChaseNav.current
				if nav:
					dest = nav.route(self, goal, _memo, delta)
				_run_toward(dest, 0.0 if _stun > 0.0 else RUN_SPEED[kind], delta)
		State.AIM:
			_speed = move_toward(_speed, 0.0, ACCEL * 2.0 * delta)
			velocity.x = _heading.x * _speed
			velocity.z = _heading.z * _speed
			_timer -= delta
			_face(_dash_dir)
			if _timer <= 0.0:
				_strip.visible = false
				_state = State.DASH
				_dash_left = DASH_LENGTH / DASH_SPEED
				Sfx.play_at("throw_heavy", global_position, 4.0, 0.7)
		State.DASH:
			_heading = _dash_dir
			_speed = DASH_SPEED
			velocity.x = _dash_dir.x * DASH_SPEED
			velocity.z = _dash_dir.z * DASH_SPEED
			_dash_left -= delta
			if _dash_left <= 0.0 or (is_on_wall() and _dash_left < DASH_LENGTH / DASH_SPEED - 0.1):
				_state = State.RECOVER
				_timer = DASH_RECOVER
				_speed = 2.0
		State.RECOVER:
			_speed = move_toward(_speed, 0.0, ACCEL * delta)
			velocity.x = _heading.x * _speed
			velocity.z = _heading.z * _speed
			_timer -= delta
			if _timer <= 0.0:
				_dash_cd = randf_range(DASH_COOLDOWN.x, DASH_COOLDOWN.y)
				_memo.clear()
				_state = State.CHASE
	move_and_slide()
	if _state != State.AIM:
		_face(_heading)


func _run_toward(dest: Vector3, max_speed: float, delta: float) -> void:
	var desired := _flat(dest - global_position)
	if desired.length() > 0.05:
		desired = desired.normalized()
		var angle := _heading.signed_angle_to(desired, Vector3.UP)
		var step := TURN_RATE * delta
		_heading = _heading.rotated(Vector3.UP, clampf(angle, -step, step)).normalized()
		max_speed *= lerpf(1.0, 0.45, clampf(absf(angle) / PI, 0.0, 1.0))
	_speed = move_toward(_speed, max_speed, ACCEL * delta)
	velocity.x = _heading.x * _speed
	velocity.z = _heading.z * _speed


## Lock on: the red strip shows where the dash will go (where you're headed).
func _start_aim() -> void:
	_state = State.AIM
	_timer = DASH_AIM_TIME
	var lead := _flat(target.velocity) * 0.25
	_dash_dir = _flat(target.global_position + lead - global_position).normalized()
	if _dash_dir.length() < 0.5:
		_dash_dir = _heading
	_strip.visible = true
	var mid := global_position + _dash_dir * (DASH_LENGTH * 0.5)
	_strip.global_transform = Transform3D(Basis.looking_at(_dash_dir, Vector3.UP), Vector3(mid.x, global_position.y + 0.06, mid.z))
	_say("TIGIL!")
	Sfx.play_at("alert", global_position, 6.0, 0.8)


func _catch() -> void:
	_stun = 2.0
	_speed = 0.0
	_state = State.CHASE
	_strip.visible = false
	_say("") # the HUD banner says it
	_doll.play_happy(1.2)
	caught_player.emit()


func _throw() -> void:
	_throw_cd = randf_range(THROW_GAP[kind].x, THROW_GAP[kind].y)
	var origin := global_transform * Vector3(0.35, 1.7, -0.35)
	var aim := target.global_position + Vector3.UP * 0.05
	var t := clampf(origin.distance_to(aim) / THROW_SPEED, 0.18, 0.8)
	var scatter := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).limit_length(1.0) * AIM_SCATTER
	aim += _flat(target.velocity) * t * 0.6 + scatter
	var g := Vector3(0.0, -_gravity, 0.0)
	var vel := (aim - origin - 0.5 * g * t * t) / t
	var slipper: RigidBody3D = TSINELAS_SCENE.instantiate()
	slipper.target_group = "player"
	slipper.hit_radius = SLIPPER_HIT_RADIUS
	get_parent().add_child(slipper)
	slipper.global_transform = Transform3D(Basis.looking_at(vel.normalized(), Vector3.UP), origin)
	slipper.add_collision_exception_with(self)
	slipper.hit_target.connect(func(_body): hit_player.emit())
	slipper.launch(vel, Vector3.ZERO)
	Sfx.play_at("throw", global_position, 0.0, 0.95)
	_thrown.append(slipper)
	if _thrown.size() > 8: # keep the ground tidy
		var old: Node3D = _thrown.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	if randf() < 0.25:
		_say(SHOUTS.pick_random())


func _sees() -> bool:
	var a := global_position + Vector3.UP * 1.5
	var b := target.global_position + Vector3.UP * 1.0
	var q := PhysicsRayQueryParameters3D.create(a, b, 1, [get_rid(), target.get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _say(text: String) -> void:
	_shout.text = text
	_shout_t = 0.0


func _face(direction: Vector3) -> void:
	if direction.length() > 0.05:
		rotation.y = atan2(-direction.x, -direction.z)


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
