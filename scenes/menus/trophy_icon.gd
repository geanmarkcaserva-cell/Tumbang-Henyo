class_name TrophyIcon
extends Control
## A trophy cup drawn in code, in the achievement's tier colour (bronze,
## silver, gold), on a round badge with soft light rays. Locked = grey.

const TIERS := {
	"bronze": Color(0.86, 0.56, 0.34),
	"silver": Color(0.82, 0.86, 0.94),
	"gold": Color(1.0, 0.8, 0.3),
	"platinum": Color(0.62, 0.92, 1.0), ## the hardest ones: icy blue-white
}

var tier := "gold":
	set(v):
		tier = v
		queue_redraw()
var locked := false:
	set(v):
		locked = v
		queue_redraw()
var spin := true ## slowly turning light rays (the popup); off in lists

var _t := 0.0
var _o := Vector2.ZERO
var _k := 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if spin and not locked and is_visible_in_tree():
		_t += delta
		queue_redraw()


## A point in the 100 x 100 drawing box, in control pixels.
func _p(x: float, y: float) -> Vector2:
	return _o + Vector2(x, y) * _k


func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := size * 0.5
	var r := s * 0.5
	var col: Color = TIERS.get(tier, TIERS.gold)
	if locked:
		col = Color(0.42, 0.44, 0.5)
	var dark := col.darkened(0.55)

	# Badge: dark disc, light rays, tier-coloured ring.
	draw_circle(c, r, Color(0.06, 0.07, 0.1, 0.95))
	if not locked:
		for i in 12:
			var a := _t * 0.6 + TAU * i / 12.0
			var d := Vector2(cos(a), sin(a))
			var d2 := Vector2(cos(a + 0.16), sin(a + 0.16))
			draw_colored_polygon(PackedVector2Array([c, c + d * r * 0.92, c + d2 * r * 0.92]),
					Color(col.r, col.g, col.b, 0.13))
	draw_arc(c, r - s * 0.03, 0, TAU, 48, col, s * 0.05, true)

	_k = s / 100.0
	_o = c - Vector2(50, 50) * _k
	# Handles.
	draw_arc(_p(31, 38), 10 * _k, PI * 0.5, PI * 1.5, 16, col, 4.5 * _k, true)
	draw_arc(_p(69, 38), 10 * _k, -PI * 0.5, PI * 0.5, 16, col, 4.5 * _k, true)
	# Bowl: flat top, rounded bottom.
	var bowl := PackedVector2Array([_p(29, 24), _p(71, 24)])
	for i in range(0, 11):
		var a := PI * i / 10.0
		bowl.append(_p(50 + cos(a) * 21, 40 + sin(a) * 19))
	draw_colored_polygon(bowl, col)
	# Shine on the bowl.
	draw_colored_polygon(PackedVector2Array([_p(35, 27), _p(41, 27), _p(39, 48), _p(35, 44)]),
			Color(1, 1, 1, 0.35 if not locked else 0.12))
	# Stem and base.
	draw_rect(Rect2(_p(46, 58), Vector2(8, 10) * _k), col)
	draw_rect(Rect2(_p(37, 67), Vector2(26, 6) * _k), col)
	draw_rect(Rect2(_p(33, 73), Vector2(34, 7) * _k), dark)
	if not locked:
		# Star on the cup.
		var star := PackedVector2Array()
		for i in 10:
			var a := -PI * 0.5 + i * PI / 5.0
			var rr := 7.5 if i % 2 == 0 else 3.2
			star.append(_p(50 + cos(a) * rr, 38 + sin(a) * rr))
		draw_colored_polygon(star, Color(1, 1, 1, 0.92))
	else:
		# A little padlock instead.
		var lock_col := Color(0.18, 0.19, 0.24)
		draw_rect(Rect2(_p(44, 36), Vector2(12, 10) * _k), lock_col)
		draw_arc(_p(50, 36), 4.5 * _k, PI, TAU, 10, lock_col, 2.5 * _k, true)
