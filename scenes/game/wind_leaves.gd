extends Node3D
## Leaves blowing through the whole barangay in windy rounds, so players can
## read the wind at a glance: they drift the way it blows, faster and in
## bigger numbers the stronger it is, tumbling and fluttering as they go.
##
## Like a volume of particles: the leaves fill the map from street level up
## to the rooftops, gusts roll through them along the wind, and one that blows
## off the edge of the map comes back in on the other side. Leaves that end
## their life fade out and new ones fade in somewhere else (half of them
## around you, so the air near you is never empty).
##
## When they show:
## - throw: background only. Half as many, and none near you, so nothing
##   flutters between you and the lata while you aim.
## - run: all of them, near you too, until the next question.
## - quiz: hidden. Low detail mode (Settings): never.
##
## The leaves are the two pixel-art leaves in art/sk_court ("Leaf var 1/2",
## exported from the .aseprite files next to them), drawn as flat cards, one
## MultiMesh per picture (a few hundred leaves cost about two draw calls).

const LEAF_TEXTURES := [
	preload("res://art/sk_court/Leaf var 1.png"),
	preload("res://art/sk_court/Leaf var 2.png"),
]
## Where the leaf sits on its 20x20 canvas (pixels): the card shows only this.
const LEAF_RECT := Rect2(7, 5, 6, 9)
const CANVAS := 20.0

const MAP_RECT := Rect2(-68.0, -88.0, 136.0, 146.0) ## the fenced map (same as Barangay)
const LOW := 0.8 ## leaves fly between these heights (metres)
const HIGH := 10
const MIN_LEAVES := 100 ## in a light breeze...
const MAX_LEAVES := 450 ## ...up to this many in the strongest wind
const MAX_WIND := 6.0 ## m/s, the strongest wind the rounds roll
## Throw view: no leaves closer to you than CLEAR_NEAR (fading in by CLEAR_FAR).
const CLEAR_NEAR := 10.0
const CLEAR_FAR := 16.0
const NEAR_SHARE := 0.5 ## of new leaves start within NEAR_RADIUS of you...
const NEAR_RADIUS := 35.0 ## ...and the rest anywhere on the map
const CAMERA_CLEAR := 2.5 ## leaves this close to the camera fade out (no giant leaf in your face)
## Light tints over the leaf's own colours: fresh, sun-dried and autumn ones.
const COLOURS := [Color(1, 1, 1), Color(1, 1, 1), Color(1.0, 0.95, 0.75), Color(1.0, 0.8, 0.6), Color(0.9, 1.0, 0.85)]
const BASE_TINT := Color(0.92, 0.92, 0.92)

var wind := Vector3.ZERO
var follow: Node3D ## the player (the throw view keeps leaves away from them)

var _mats: Array[StandardMaterial3D] = []
var _mms: Array[MultiMesh] = [] ## one per leaf picture
# One entry per leaf (packed arrays: a few hundred leaves stay cheap).
var _pos := PackedVector3Array()
var _axis := PackedVector3Array()
var _col := PackedColorArray()
var _spin := PackedFloat32Array()
var _angle := PackedFloat32Array()
var _phase := PackedFloat32Array()
var _size := PackedFloat32Array()
var _speed := PackedFloat32Array()
var _age := PackedFloat32Array()
var _life := PackedFloat32Array()
var _pic := PackedInt32Array()
var _fade := 0.0 ## 0..1, all leaves together (fade in/out with the wind)
var _target_fade := 0.0
var _bg := 0.0 ## 0..1: how far into the throw view (background leaves only)
var _target_bg := 0.0
var _time := 0.0


func _ready() -> void:
	top_level = true
	var card := QuadMesh.new() # the leaf's own shape (6x9 px), 1 unit tall
	card.size = Vector2(LEAF_RECT.size.x / LEAF_RECT.size.y, 1.0)
	for tex in LEAF_TEXTURES:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = card
		mm.instance_count = MAX_LEAVES
		mm.visible_instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.custom_aabb = AABB(Vector3(MAP_RECT.position.x, 0.0, MAP_RECT.position.y) - Vector3.ONE * 2.0,
				Vector3(MAP_RECT.size.x, HIGH, MAP_RECT.size.y) + Vector3.ONE * 4.0)
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = tex
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST # crisp pixels
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = 0.5
		mat.vertex_color_use_as_albedo = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		# Only the leaf part of the canvas.
		mat.uv1_scale = Vector3(LEAF_RECT.size.x / CANVAS, LEAF_RECT.size.y / CANVAS, 1.0)
		mat.uv1_offset = Vector3(LEAF_RECT.position.x / CANVAS, LEAF_RECT.position.y / CANVAS, 0.0)
		# Unlit: a leaf seen from behind against the sun would otherwise turn
		# into a dark blob.
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = BASE_TINT
		mmi.material_override = mat
		_mats.append(mat)
		_mms.append(mm)
		add_child(mmi)
	_pos.resize(MAX_LEAVES)
	_axis.resize(MAX_LEAVES)
	_col.resize(MAX_LEAVES)
	_spin.resize(MAX_LEAVES)
	_angle.resize(MAX_LEAVES)
	_phase.resize(MAX_LEAVES)
	_size.resize(MAX_LEAVES)
	_speed.resize(MAX_LEAVES)
	_age.resize(MAX_LEAVES)
	_life.resize(MAX_LEAVES)
	_pic.resize(MAX_LEAVES)
	for i in MAX_LEAVES:
		_new_leaf(i)
		_age[i] = randf() * _life[i] # mid-life, so they don't all fade in together


## The leaves are unlit, so the day/night cycle darkens them by hand.
func set_tint(c: Color) -> void:
	for m in _mats:
		m.albedo_color = Color(BASE_TINT.r * c.r, BASE_TINT.g * c.g, BASE_TINT.b * c.b)


## New wind for this throw. Zero wind: the leaves settle away.
func set_wind(w: Vector3) -> void:
	wind = Vector3(w.x, 0.0, w.z)
	if wind.length() <= 0.05:
		_target_fade = 0.0


## Show the leaves (throw: background_only, run: all) or hide them (quiz).
func set_active(on: bool, background_only: bool = false) -> void:
	_target_fade = 1.0 if on and wind.length() > 0.05 else 0.0
	_target_bg = 1.0 if background_only else 0.0


## A fresh leaf in the map's air: half of them somewhere around you (where
## you can see them), the rest anywhere on the map.
func _new_leaf(i: int) -> void:
	var y := LOW + (HIGH - LOW) * pow(randf(), 1.6) # more of them low down
	if follow and randf() < NEAR_SHARE:
		var c := follow.global_position
		var at := Vector2(c.x, c.z) + Vector2.from_angle(randf() * TAU) * NEAR_RADIUS * sqrt(randf())
		at.x = clampf(at.x, MAP_RECT.position.x, MAP_RECT.end.x)
		at.y = clampf(at.y, MAP_RECT.position.y, MAP_RECT.end.y)
		_pos[i] = Vector3(at.x, y, at.y)
	else:
		_pos[i] = Vector3(randf_range(MAP_RECT.position.x, MAP_RECT.end.x), y,
				randf_range(MAP_RECT.position.y, MAP_RECT.end.y))
	_axis[i] = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
	_spin[i] = randf_range(2.0, 6.0) * (1.0 if randf() < 0.5 else -1.0)
	_angle[i] = randf() * TAU
	_phase[i] = randf() * TAU
	_size[i] = randf_range(0.2, 0.3)
	_speed[i] = randf_range(0.75, 1.25)
	_col[i] = COLOURS[randi() % COLOURS.size()]
	_pic[i] = randi() % LEAF_TEXTURES.size()
	_age[i] = 0.0
	_life[i] = randf_range(6.0, 12.0)


func _process(delta: float) -> void:
	_time += delta
	var off := Settings.low_detail
	_fade = move_toward(_fade, 0.0 if off else _target_fade, delta * 1.2)
	_bg = move_toward(_bg, _target_bg, delta * 2.0)
	if _fade <= 0.0:
		for mm in _mms:
			mm.visible_instance_count = 0
		return
	var k := clampf(wind.length() / MAX_WIND, 0.0, 1.0)
	var count := int(lerpf(MIN_LEAVES, MAX_LEAVES, k))
	var dir := wind.normalized() if wind.length() > 0.01 else Vector3.RIGHT
	var side := Vector3(-dir.z, 0.0, dir.x)
	var cam := get_viewport().get_camera_3d()
	var eye := cam.global_position if cam else Vector3(0, 1000, 0)
	var me := follow.global_position if follow else Vector3(0, 1000, 0)
	var used: Array[int] = []
	used.resize(_mms.size())
	used.fill(0)
	for i in count:
		_age[i] += delta
		if _age[i] > _life[i]:
			_new_leaf(i)
		var p := _pos[i]
		var t := _time + _phase[i]
		# Gusts roll through the volume along the wind.
		var gust := 1.0 + 0.3 * sin(_time * 0.9 - p.dot(dir) * 0.06) + 0.12 * sin(t * 2.3)
		var v := wind * gust * _speed[i]
		v += side * sin(t * 1.7) * 0.6 # sway across the wind
		v.y = sin(t * 2.4) * 0.5 - 0.08 # bob, slowly sinking
		if p.y < LOW:
			v.y = absf(v.y) + 0.3 # skim back up off the ground
		p += v * delta
		# Blown off one side of the map: back in on the other.
		p.x = MAP_RECT.position.x + fposmod(p.x - MAP_RECT.position.x, MAP_RECT.size.x)
		p.z = MAP_RECT.position.y + fposmod(p.z - MAP_RECT.position.y, MAP_RECT.size.y)
		p.y = minf(p.y, HIGH)
		_pos[i] = p
		_angle[i] += _spin[i] * delta * (0.6 + 0.4 * gust)
		# Size: grow in, shrink out, the overall fade, and the view rules.
		var s := _size[i] * _fade * clampf(minf(_age[i] / 0.8, 1.0) * minf((_life[i] - _age[i]) / 1.0, 1.0), 0.0, 1.0)
		if _bg > 0.0:
			var away := Vector2(p.x - me.x, p.z - me.z).length()
			var keep := smoothstep(CLEAR_NEAR, CLEAR_FAR, away) * (0.0 if i % 2 else 1.0)
			s *= lerpf(1.0, keep, _bg)
		s *= smoothstep(1.0, CAMERA_CLEAR, p.distance_to(eye))
		if s < 0.01:
			continue
		var b := Basis(_axis[i], _angle[i]) * Basis(Vector3.UP, _phase[i])
		var pic := _pic[i]
		var slot := used[pic]
		used[pic] = slot + 1
		_mms[pic].set_instance_transform(slot, Transform3D(b.scaled(Vector3.ONE * s), p))
		_mms[pic].set_instance_color(slot, _col[i])
	for m in _mms.size():
		_mms[m].visible_instance_count = used[m]
