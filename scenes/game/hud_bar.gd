class_name HudBar
extends Control
## A rounded HUD meter (Awra, Energy).
##
## - The fill eases toward the real value instead of jumping.
## - Losing some leaves a pale "ghost" chunk that drains away a moment later,
##   so players can see how much they just lost; gaining flashes the bar.
## - Below `low_fraction` the fill turns `low_color` and pulses.
## - `exhausted` (Energy ran dry) greys the fill out with moving stripes until
##   it is usable again.
## - `segments` draws faint notches (every 10 Awra, for example).

@export var fill_color := Color(0.36, 0.78, 1.0)
@export var fill_color_top := Color(0.62, 0.9, 1.0)
@export var low_color := Color(1.0, 0.33, 0.36)
@export var low_fraction := 0.25
@export var segments := 0

var max_value := 100.0
var value := 100.0
var exhausted := false:
	set(v):
		if exhausted != v:
			exhausted = v
			queue_redraw()

var _shown := 100.0 ## what the fill currently draws (eases toward value)
var _ghost := 100.0 ## pale chunk left behind after a loss
var _ghost_hold := 0.0
var _flash := 0.0 ## white glow after a gain or a hit
var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Set the value. Instant (no animation) the first time or when snap is true.
func set_value(v: float, max_v: float, snap: bool = false) -> void:
	max_value = maxf(max_v, 0.001)
	var old := value
	value = clampf(v, 0.0, max_value)
	if snap:
		_shown = value
		_ghost = value
	elif value < old - 0.01:
		_ghost = maxf(_ghost, old)
		_ghost_hold = 0.45
		if old - value > max_value * 0.05: # a real hit, not a trickle
			_flash = 1.0
	elif value > old + max_value * 0.05:
		_flash = 0.8
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	var dirty := false
	if not is_equal_approx(_shown, value):
		_shown = move_toward(_shown, value, maxf(absf(value - _shown) * 10.0, max_value * 0.2) * delta)
		dirty = true
	if _ghost_hold > 0.0:
		_ghost_hold -= delta
	elif _ghost > _shown:
		_ghost = move_toward(_ghost, _shown, max_value * 0.6 * delta)
		dirty = true
	else:
		_ghost = _shown
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 2.5, 0.0)
		dirty = true
	if exhausted or _is_low():
		dirty = true # pulse / stripes animate
	if dirty:
		queue_redraw()


func _is_low() -> bool:
	return value > 0.0 and value / max_value <= low_fraction


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var radius := int(size.y * 0.5)
	# Track: dark glass with a hairline and a soft inner shade.
	_rounded(r.grow(3.0), Color(0, 0, 0, 0.35), radius + 3)
	_rounded(r, Color(0.04, 0.05, 0.09, 0.78), radius, Color(1, 1, 1, 0.12))
	var inner := r.grow(-3.0)
	var inner_radius := int(inner.size.y * 0.5)

	# Ghost (what was just lost).
	var gf := clampf(_ghost / max_value, 0.0, 1.0)
	if gf > 0.0:
		_rounded(_part(inner, gf), Color(1.0, 0.92, 0.82, 0.75), inner_radius)

	# Fill.
	var f := clampf(_shown / max_value, 0.0, 1.0)
	if f > 0.0:
		var bottom := fill_color
		var top := fill_color_top
		if exhausted:
			bottom = Color(0.42, 0.42, 0.46)
			top = Color(0.58, 0.58, 0.62)
		elif _is_low():
			var pulse := 0.5 + 0.5 * sin(_time * 7.0)
			bottom = low_color.lerp(low_color.lightened(0.25), pulse)
			top = low_color.lightened(0.35)
		var fr := _part(inner, f)
		_rounded(fr, bottom, inner_radius)
		# Lighter top half: a simple glossy look.
		var gloss := Rect2(fr.position, Vector2(fr.size.x, fr.size.y * 0.5))
		_rounded(gloss, Color(top, 0.55), inner_radius)
		if exhausted: # slow diagonal stripes = "recharging"
			var step := 18.0
			var off := fmod(_time * 30.0, step)
			var x := fr.position.x - step + off
			while x < fr.end.x:
				var a := Vector2(maxf(x, fr.position.x), fr.end.y)
				var b := Vector2(minf(x + fr.size.y, fr.end.x), fr.position.y)
				draw_line(a, b, Color(1, 1, 1, 0.12), 5.0)
				x += step
		if _flash > 0.0:
			_rounded(fr, Color(1, 1, 1, 0.45 * _flash), inner_radius)

	# Notches.
	if segments > 1:
		for i in range(1, segments):
			var x := inner.position.x + inner.size.x * float(i) / segments
			draw_line(Vector2(x, inner.position.y + 3), Vector2(x, inner.end.y - 3), Color(0, 0, 0, 0.28), 2.0)


## The left `fraction` of a rect, never thinner than its height (keeps the
## rounded ends round when almost empty).
func _part(r: Rect2, fraction: float) -> Rect2:
	var w := maxf(r.size.x * fraction, minf(r.size.y, r.size.x * fraction * 4.0))
	return Rect2(r.position, Vector2(w, r.size.y))


func _rounded(r: Rect2, color: Color, radius: int, border: Color = Color(0, 0, 0, 0)) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(mini(radius, int(r.size.y * 0.5)))
	s.anti_aliasing = true
	if border.a > 0.0:
		s.border_color = border
		s.set_border_width_all(1)
	draw_style_box(s, r)
