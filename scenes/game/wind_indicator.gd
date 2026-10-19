extends Control
## Wind dial: which way the wind blows relative to where the player faces
## (up on screen = forward), and how hard (arrow length, ring fill, colour).

const CALM := Color(1, 1, 1, 0.35)
const BREEZE := Color(0.55, 0.9, 1.0)
const STRONG := Color(1.0, 0.55, 0.35)

var direction := Vector2.ZERO: ## screen-space, normalized; zero = calm
	set(v):
		direction = v
		queue_redraw()
var strength := 0.0: ## 0..1 (1 = the strongest wind in the game)
	set(v):
		strength = clampf(v, 0.0, 1.0)
		queue_redraw()

var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if direction != Vector2.ZERO and is_visible_in_tree():
		_time += delta
		queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var rad := minf(size.x, size.y) * 0.5
	draw_circle(c, rad, Color(0.03, 0.04, 0.07, 0.62))
	draw_arc(c, rad - 1.0, 0.0, TAU, 48, Color(1, 1, 1, 0.12), 2.0, true)
	# Compass ticks; the top one (forward) is longer.
	for i in 8:
		var a := TAU * i / 8.0 - PI * 0.5
		var d := Vector2(cos(a), sin(a))
		var inner := rad * (0.72 if i == 0 else 0.8)
		draw_line(c + d * inner, c + d * (rad - 5.0), Color(1, 1, 1, 0.5 if i == 0 else 0.22), 3.0 if i == 0 else 2.0, true)
	if direction == Vector2.ZERO:
		draw_circle(c, rad * 0.1, CALM)
		return
	var col := BREEZE.lerp(STRONG, smoothstep(0.35, 0.9, strength))
	# Strength ring around the edge.
	draw_arc(c, rad - 4.0, -PI * 0.5, -PI * 0.5 + TAU * strength, 48, col, 5.0, true)
	# Arrow, nudged along its direction like it's being pushed by the wind.
	var length := rad * lerpf(0.45, 0.66, strength)
	var push := direction * sin(_time * 5.0) * rad * 0.04
	var tip := c + direction * length + push
	var tail := c - direction * length * 0.75 + push
	var side := Vector2(-direction.y, direction.x)
	var head := length * 0.42
	draw_line(tail, tip - direction * head * 0.6, Color(0, 0, 0, 0.45), 9.0, true)
	draw_line(tail, tip - direction * head * 0.6, col, 6.0, true)
	var pts := PackedVector2Array([tip, tip - direction * head + side * head * 0.62, tip - direction * head - side * head * 0.62])
	draw_colored_polygon(pts, col)
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), Color(0, 0, 0, 0.35), 2.0, true)
