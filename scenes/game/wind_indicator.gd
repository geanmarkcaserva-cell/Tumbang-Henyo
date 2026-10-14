extends Control
## Arrow showing which way the wind blows, relative to where the player faces
## (up on screen = forward).

var direction := Vector2.ZERO: ## screen-space, normalized; zero hides the arrow
	set(v):
		direction = v
		queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	draw_circle(center, minf(size.x, size.y) * 0.5, Color(0, 0, 0, 0.45))
	if direction == Vector2.ZERO:
		return
	var length := minf(size.x, size.y) * 0.38
	var tip := center + direction * length
	var tail := center - direction * length
	var side := Vector2(-direction.y, direction.x) * length * 0.35
	var white := Color(1, 1, 1)
	draw_line(tail, tip, white, 5.0, true)
	draw_colored_polygon(PackedVector2Array([tip, tip - direction * length * 0.5 + side, tip - direction * length * 0.5 - side]), white)
