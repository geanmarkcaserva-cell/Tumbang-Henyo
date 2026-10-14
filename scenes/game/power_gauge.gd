extends Control
## Arc-shaped power gauge drawn beside the player: red when weak,
## yellow in the middle, green at full power.

@export var radius := 90.0
@export var thickness := 18.0
@export var arc_degrees := 120.0

var value := 0.0:
	set(v):
		value = clampf(v, 0.0, 1.0)
		queue_redraw()


func _draw() -> void:
	var center := Vector2(0.0, size.y * 0.5)
	var half := deg_to_rad(arc_degrees * 0.5)
	# Background track, bottom (+half) to top (-half), on the right side.
	draw_arc(center, radius, -half, half, 40, Color(0, 0, 0, 0.55), thickness + 6.0, true)
	if value <= 0.0:
		return
	var color := Color(0.95, 0.25, 0.25).lerp(Color(1.0, 0.85, 0.2), minf(value * 2.0, 1.0))
	if value > 0.5:
		color = Color(1.0, 0.85, 0.2).lerp(Color(0.35, 0.95, 0.4), (value - 0.5) * 2.0)
	var top := half - deg_to_rad(arc_degrees) * value
	draw_arc(center, radius, top, half, 40, color, thickness, true)
