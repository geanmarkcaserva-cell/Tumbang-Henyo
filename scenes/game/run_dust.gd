class_name RunDust
extends Node3D
## Dust puffs kicked up by feet (art/environment/run smoke var 1-3): a trail
## behind the player and the tayas while they run on the ground, a puff when
## they jump and a little burst when they land. Each puff plays the smoke
## sequence as it ages - var 1 (a dense puff), var 2 (breaking up into
## bubbles), var 3 (a last small wisp) - while it grows, drifts up a touch
## and fades. Sprinting kicks up bigger ones. The puffs take the time of
## day's light (set_tint), and low detail mode makes half as many.

const SEQUENCE := [
	preload("res://art/environment/fx/run smoke var 1.png"),
	preload("res://art/environment/fx/run smoke var 2.png"),
	preload("res://art/environment/fx/run smoke var 3.png"),
]
const FRAME_ENDS := [0.33, 0.66] ## share of a puff's life where it switches to var 2, then var 3
const POOL := 48 ## puffs alive at once (the oldest is reused)
const STEP := 0.8 ## metres run between puffs
const MIN_SPEED := 2.2 ## m/s: slower than this (walking about) leaves no trail
const SIZE := 0.9 ## metres across, at a normal run
const ALPHA := 0.95 ## how solid a fresh puff is
const SPRINT_SPEED := 7.0 ## m/s: from here on the puffs are bigger
const LIFE := Vector2(0.5, 0.75) ## seconds a puff lasts
const RISE := 0.3 ## metres it drifts up while fading
const LAND_FALL := 4.0 ## m/s: landing faster than this kicks up a burst

var player: Node3D ## set by the game; the tayas are found by their group

var _puffs: Array = [] ## {sprite, age, life, size, from}
var _next := 0
var _bodies := {} ## body -> {last, run, air, fall}
var _tint := Color.WHITE


func _ready() -> void:
	top_level = true
	for i in POOL:
		var s := Sprite3D.new()
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.pixel_size = 1.0 / 700.0 # the pictures are 700 px: scale = metres
		s.shaded = false
		s.double_sided = true
		s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		s.visible = false
		add_child(s)
		_puffs.append({"sprite": s, "age": 0.0, "life": 0.0, "size": SIZE, "from": Vector3.ZERO})


## The time of day's light (DayNight.tint_changed): dimmer, bluer puffs at night.
func set_tint(c: Color) -> void:
	_tint = c.lerp(Color.WHITE, 0.25)


func _physics_process(delta: float) -> void:
	var feet: Array = []
	if is_instance_valid(player):
		feet.append(player)
	for t in get_tree().get_nodes_in_group("taya"):
		if t.visible and not (t.has_method("is_gone") and t.is_gone()):
			feet.append(t)
	for b in feet:
		_watch(b as CharacterBody3D, delta)
	for b in _bodies.keys():
		if not is_instance_valid(b):
			_bodies.erase(b)


func _process(delta: float) -> void:
	for p in _puffs:
		var s: Sprite3D = p.sprite
		if not s.visible:
			continue
		p.age += delta
		var k: float = p.age / p.life
		if k >= 1.0:
			s.visible = false
			continue
		var frame := 0 if k < FRAME_ENDS[0] else (1 if k < FRAME_ENDS[1] else 2)
		if s.texture != SEQUENCE[frame]:
			s.texture = SEQUENCE[frame]
		var grow := 0.45 + 0.75 * (1.0 - pow(1.0 - k, 2.0)) # pops up, then spreads out
		s.scale = Vector3.ONE * p.size * grow
		s.global_position = (p.from as Vector3) + Vector3.UP * (RISE * k + p.size * grow * 0.35)
		s.modulate = Color(_tint, ALPHA * (1.0 - k * k))


func _watch(b: CharacterBody3D,_delta: float) -> void:
	if b == null:
		return
	var st: Dictionary = _bodies.get(b, {})
	if st.is_empty():
		st = {"last": b.global_position, "run": 0.0, "air": false, "fall": 0.0}
		_bodies[b] = st
	var pos := b.global_position
	var on_floor := b.is_on_floor()
	var flat := Vector3(b.velocity.x, 0.0, b.velocity.z)
	var speed := flat.length()
	var dir := flat / speed if speed > 0.01 else Vector3.ZERO
	if on_floor and st.air:
		# Landing: a burst, bigger the harder it came down.
		if st.fall >= LAND_FALL:
			var n := 3 if Settings.low_detail else 5
			for i in n:
				var a := TAU * i / n + randf() * 0.5
				_puff(pos + Vector3(cos(a), 0.0, sin(a)) * 0.35, SIZE * randf_range(0.8, 1.1))
	elif not on_floor and not st.air and b.velocity.y > 1.0:
		_puff(pos - dir * 0.2, SIZE * 1.1) # jumping off
	if on_floor and speed >= MIN_SPEED:
		st.run += _flat(pos - (st.last as Vector3)).length()
		var step := STEP * (2.0 if Settings.low_detail else 1.0)
		if st.run >= step:
			st.run = 0.0
			var big := clampf(remap(speed, MIN_SPEED, SPRINT_SPEED, 0.8, 1.35), 0.8, 1.35)
			var side := dir.cross(Vector3.UP) * randf_range(-0.15, 0.15)
			_puff(pos - dir * 0.3 + side, SIZE * big * randf_range(0.85, 1.15))
	else:
		st.run = 0.0
	st.fall = 0.0 if on_floor else maxf(-b.velocity.y, 0.0) # how fast it's coming down
	st.air = not on_floor
	st.last = pos


func _puff(at: Vector3, size: float) -> void:
	var p: Dictionary = _puffs[_next]
	_next = (_next + 1) % _puffs.size()
	var s: Sprite3D = p.sprite
	s.texture = SEQUENCE[0]
	s.flip_h = randf() < 0.5
	p.age = 0.0
	p.life = randf_range(LIFE.x, LIFE.y)
	p.size = size
	p.from = at + Vector3.UP * 0.02
	s.scale = Vector3.ONE * size * 0.45
	s.global_position = p.from
	s.modulate = Color(_tint, ALPHA)
	s.visible = true


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
