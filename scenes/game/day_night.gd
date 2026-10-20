extends Node
## Late afternoon to night, following the game clock (5:00 PM -> 6:00 PM and
## a little past). Moves the sun down and warms it, then dims it to a cool
## moonlight; shifts the sky from golden hour through a deep orange sunset
## and blue hour to night; darkens the ambient light and fog to match; and
## switches the street-post lamps on as it gets dark.
##
## Works on copies of the court's Environment and sky, so the main menu
## (same court scene) keeps its golden-hour look.

const START_MIN := 17.0 * 60.0 ## 5:00 PM = golden hour (the court as built)
const SPAN_MIN := 60.0 ## 6:00 PM = blue hour
const NIGHT_T := 1.45 ## a little past 6 (Mama's round) = night
const MAX_T := 2.0 ## 7:00 PM (the secret curfew round) = deep night
const BLEND_TIME := 2.5 ## seconds to ease to a new time of day
## Street lamps and post lamps switch on at 5:40 PM (t = 40 / 60), with a
## short warm-up.
const LAMPS_ON_T := 40.0 / 60.0

## Keyframes: t (0 = 5 PM, 1 = 6 PM) -> look.
const KEYS := [
	{"t": 0.0, "top": Color(0.3, 0.38, 0.66), "hor": Color(1.0, 0.62, 0.4), "gbot": Color(0.25, 0.2, 0.18),
		"ghor": Color(0.92, 0.6, 0.42), "sun": Color(1.0, 0.66, 0.42), "sun_e": 1.6, "elev": 17.0,
		"amb": Color(0.86, 0.8, 0.74), "amb_e": 0.7, "fog": Color(0.74, 0.68, 0.66), "sky_e": 1.0, "lamp": 0.0,
		"tint": Color(1.0, 0.97, 0.92)},
	{"t": 0.55, "top": Color(0.22, 0.24, 0.5), "hor": Color(1.0, 0.45, 0.28), "gbot": Color(0.2, 0.14, 0.14),
		"ghor": Color(0.85, 0.42, 0.3), "sun": Color(1.0, 0.48, 0.26), "sun_e": 1.15, "elev": 7.0,
		"amb": Color(0.8, 0.62, 0.6), "amb_e": 0.6, "fog": Color(0.7, 0.5, 0.48), "sky_e": 0.9, "lamp": 0.0,
		"tint": Color(0.9, 0.72, 0.62)},
	{"t": 1.0, "top": Color(0.07, 0.09, 0.24), "hor": Color(0.55, 0.32, 0.4), "gbot": Color(0.06, 0.06, 0.1),
		"ghor": Color(0.3, 0.2, 0.28), "sun": Color(0.55, 0.55, 0.85), "sun_e": 0.35, "elev": 3.0,
		"amb": Color(0.42, 0.44, 0.66), "amb_e": 0.45, "fog": Color(0.22, 0.22, 0.34), "sky_e": 0.6, "lamp": 1.0,
		"tint": Color(0.34, 0.34, 0.5)},
	{"t": NIGHT_T, "top": Color(0.02, 0.03, 0.09), "hor": Color(0.1, 0.11, 0.2), "gbot": Color(0.02, 0.02, 0.04),
		"ghor": Color(0.08, 0.08, 0.14), "sun": Color(0.5, 0.58, 0.9), "sun_e": 0.18, "elev": 25.0,
		"amb": Color(0.3, 0.34, 0.55), "amb_e": 0.38, "fog": Color(0.08, 0.09, 0.15), "sky_e": 0.45, "lamp": 1.0,
		"tint": Color(0.18, 0.2, 0.32)},
	{"t": MAX_T, "top": Color(0.01, 0.015, 0.05), "hor": Color(0.05, 0.06, 0.13), "gbot": Color(0.01, 0.01, 0.03),
		"ghor": Color(0.05, 0.05, 0.1), "sun": Color(0.5, 0.58, 0.9), "sun_e": 0.14, "elev": 35.0,
		"amb": Color(0.26, 0.3, 0.5), "amb_e": 0.34, "fog": Color(0.05, 0.06, 0.11), "sky_e": 0.4, "lamp": 1.0,
		"tint": Color(0.15, 0.17, 0.28)},
]

## Unlit things (the wind leaves) don't react to the sun, so they take this
## colour instead: white-ish by day, dim blue at night.
signal tint_changed(tint: Color)

var tint := Color.WHITE

var _env: Environment
var _sky: ProceduralSkyMaterial
var _sun: DirectionalLight3D
var _sun_yaw := 0.0
var _base_elev := 17.0
var _lamps: Array[OmniLight3D] = []
var _bulbs: Array[StandardMaterial3D] = []
var _t := 0.0
var _target := 0.0


## world_env/sun from the court; posts = where to hang the lamps (may be empty).
func setup(world_env: WorldEnvironment, sun: DirectionalLight3D, posts: Array) -> void:
	_env = world_env.environment.duplicate(true) as Environment
	world_env.environment = _env
	_sky = _env.sky.sky_material as ProceduralSkyMaterial if _env.sky else null
	_sun = sun
	var fwd := -sun.global_basis.z
	_sun_yaw = atan2(fwd.x, fwd.z)
	_base_elev = rad_to_deg(asin(clampf(-fwd.y, -1.0, 1.0))) # 5 PM starts exactly as the court was lit
	for p in posts:
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.78, 0.45)
		lamp.omni_range = 11.0
		lamp.omni_attenuation = 1.4
		lamp.light_energy = 0.0
		lamp.shadow_enabled = false
		lamp.visible = false
		add_child(lamp)
		lamp.global_position = p
		_lamps.append(lamp)


## The barangay's street lamps: a light under each bulb (fading out with
## distance, so only the nearby ones cost anything) and the bulb material to
## make glow. The ones away from the court are skipped in low detail mode.
func add_lamps(spots: Array, bulb: StandardMaterial3D) -> void:
	if bulb:
		_bulbs.append(bulb)
	for p in spots:
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.8, 0.52)
		lamp.omni_range = 9.0
		lamp.omni_attenuation = 1.2
		lamp.light_energy = 0.0
		lamp.shadow_enabled = false
		lamp.distance_fade_enabled = true
		lamp.distance_fade_begin = 38.0
		lamp.distance_fade_length = 10.0
		lamp.visible = false
		add_child(lamp)
		lamp.global_position = p
		var flat := Vector2(p.x, p.z)
		if absf(flat.x) > 15.0 or flat.y > 16.0 or flat.y < -52.0:
			lamp.add_to_group("detail_heavy")
		_lamps.append(lamp)
	_apply(_t)


## Clock time in minutes after midnight.
func set_time(minutes: float, instant: bool = false) -> void:
	_target = clampf((minutes - START_MIN) / SPAN_MIN, 0.0, MAX_T)
	if instant:
		_t = _target
		_apply(_t)


func _process(delta: float) -> void:
	if _env == null or is_equal_approx(_t, _target):
		return
	_t = move_toward(_t, _target, delta / BLEND_TIME * maxf(absf(_target - _t), 0.15))
	_apply(_t)


func _apply(t: float) -> void:
	var a: Dictionary = KEYS[0]
	var b: Dictionary = KEYS[KEYS.size() - 1]
	for i in KEYS.size() - 1:
		if t >= KEYS[i].t and t <= KEYS[i + 1].t:
			a = KEYS[i]
			b = KEYS[i + 1]
			break
	var k := 0.0 if is_equal_approx(a.t, b.t) else clampf((t - a.t) / (b.t - a.t), 0.0, 1.0)
	k = smoothstep(0.0, 1.0, k)
	if _sky:
		_sky.sky_top_color = a.top.lerp(b.top, k)
		_sky.sky_horizon_color = a.hor.lerp(b.hor, k)
		_sky.ground_bottom_color = a.gbot.lerp(b.gbot, k)
		_sky.ground_horizon_color = a.ghor.lerp(b.ghor, k)
		_sky.sky_energy_multiplier = lerpf(a.sky_e, b.sky_e, k)
	_env.ambient_light_color = a.amb.lerp(b.amb, k)
	_env.ambient_light_energy = lerpf(a.amb_e, b.amb_e, k)
	_env.fog_light_color = a.fog.lerp(b.fog, k)
	if _sun:
		_sun.light_color = a.sun.lerp(b.sun, k)
		_sun.light_energy = lerpf(a.sun_e, b.sun_e, k)
		# Sun sinks toward the horizon; past 6 it becomes the moon (higher, cool, dim).
		var elev_a: float = _base_elev if a.t == 0.0 else a.elev
		var elev := deg_to_rad(lerpf(elev_a, b.elev, k))
		var dir := Vector3(sin(_sun_yaw) * cos(elev), -sin(elev), cos(_sun_yaw) * cos(elev))
		_sun.global_basis = Basis.looking_at(dir, Vector3.UP)
	tint = a.tint.lerp(b.tint, k)
	tint_changed.emit(tint)
	var lamp := smoothstep(LAMPS_ON_T - 0.02, LAMPS_ON_T + 0.04, t)
	for l in _lamps:
		l.visible = lamp > 0.01 and not (l.is_in_group("detail_heavy") and Settings.low_detail)
		l.light_energy = lamp * 2.2
	for m in _bulbs:
		m.emission_energy_multiplier = lamp * 4.0
