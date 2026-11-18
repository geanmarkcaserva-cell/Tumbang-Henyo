class_name TouchScroll
extends Node
## Finger scrolling for a ScrollContainer (added to every one by
## GameManager, see attach()). Godot only drag-scrolls a list when the touch
## lands on empty space, so lists full of buttons (accounts, quiz sets, the
## collection...) wouldn't move under a finger. This takes the drag wherever
## it starts:
## - past a small dead zone, the drag scrolls the list (both ways if the list
##   scrolls both ways) and keeps gliding a little after the finger lifts;
## - once a drag starts, the button under the finger is let go, so a scroll
##   never counts as a tap;
## - the scroll bars get thicker, rounded grab handles that are easy to hit.
## The mouse wheel and the bars themselves work as before.

const DEADZONE := 14.0 ## screen pixels before a touch becomes a drag
const FRICTION := 5.0 ## how fast the glide slows down (per second)
const MIN_GLIDE := 40.0 ## px/s: slower than this, the glide stops
const BAR_WIDTH := 18.0

var _scroll: ScrollContainer
var _finger := -1 ## the touch index being tracked (-1 = none)
var _start := Vector2.ZERO
var _dragging := false
var _velocity := Vector2.ZERO ## in the list's own units per second
var _last_t := 0


## Give `scroll` finger scrolling (once). Lists can opt out with the meta
## "no_touch_scroll".
static func attach(scroll: ScrollContainer) -> void:
	if scroll.has_meta("no_touch_scroll") or scroll.has_node("TouchScroll"):
		return
	var t := TouchScroll.new()
	t.name = "TouchScroll"
	scroll.add_child(t, false, Node.INTERNAL_MODE_BACK)


func _ready() -> void:
	_scroll = get_parent() as ScrollContainer
	process_mode = Node.PROCESS_MODE_ALWAYS # lists in the pause menu too
	# This does the touch dragging; the container's own would double it.
	_scroll.scroll_deadzone = 1000000
	_style_bar(_scroll.get_v_scroll_bar(), true)
	_style_bar(_scroll.get_h_scroll_bar(), false)
	set_process(false)


func _input(event: InputEvent) -> void:
	if not _scroll.is_visible_in_tree():
		_finger = -1
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			if _finger == -1 and _scroll.get_global_rect().has_point(event.position):
				_finger = event.index
				_start = event.position
				_dragging = false
				_velocity = Vector2.ZERO
				_last_t = Time.get_ticks_usec()
				set_process(false)
		elif event.index == _finger:
			_finger = -1
			if _dragging:
				_dragging = false
				set_process(_velocity.length() > MIN_GLIDE) # glide on
	elif event is InputEventScreenDrag and event.index == _finger:
		if not _dragging and (event.position - _start).length() > DEADZONE:
			_dragging = true
			_let_go_of_buttons()
		if _dragging:
			var step := _to_local(event.relative)
			_move(-step)
			var now := Time.get_ticks_usec()
			var dt := maxf((now - _last_t) / 1000000.0, 0.001)
			_last_t = now
			_velocity = _velocity.lerp(-step / dt, 0.5)
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_move(_velocity * delta)
	_velocity *= maxf(1.0 - FRICTION * delta, 0.0)
	if _velocity.length() < MIN_GLIDE:
		set_process(false)


## Screen pixels -> the list's own units (the menus are scaled).
func _to_local(screen: Vector2) -> Vector2:
	var s := _scroll.get_global_transform_with_canvas().get_scale()
	return Vector2(screen.x / maxf(s.x, 0.001), screen.y / maxf(s.y, 0.001))


func _move(by: Vector2) -> void:
	if _scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		_scroll.scroll_vertical = int(_scroll.scroll_vertical + by.y)
	if _scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		_scroll.scroll_horizontal = int(_scroll.scroll_horizontal + by.x)


## A drag started on a button: let go of it, so lifting the finger doesn't
## press it. (Disabling a button drops its half-done press; it's enabled
## again straight away.)
func _let_go_of_buttons() -> void:
	var held: Array[BaseButton] = []
	_collect_buttons(_scroll, held)
	for b in held:
		b.disabled = true
	for b in held:
		b.set_deferred("disabled", false)


func _collect_buttons(node: Node, out: Array[BaseButton]) -> void:
	for c in node.get_children():
		if c is BaseButton and not c.disabled:
			out.append(c)
		_collect_buttons(c, out)


func _style_bar(bar: ScrollBar, vertical: bool) -> void:
	if bar == null:
		return
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.06)
	track.set_corner_radius_all(int(BAR_WIDTH * 0.5))
	if vertical:
		track.content_margin_left = BAR_WIDTH * 0.5
		track.content_margin_right = BAR_WIDTH * 0.5
	else:
		track.content_margin_top = BAR_WIDTH * 0.5
		track.content_margin_bottom = BAR_WIDTH * 0.5
	bar.add_theme_stylebox_override("scroll", track)
	bar.add_theme_stylebox_override("scroll_focus", track)
	for key in ["grabber", "grabber_highlight", "grabber_pressed"]:
		var g := StyleBoxFlat.new()
		g.bg_color = UiKit.ACCENT if key != "grabber" else Color(1.0, 0.8, 0.34, 0.75)
		g.set_corner_radius_all(int(BAR_WIDTH * 0.5))
		bar.add_theme_stylebox_override(key, g)
