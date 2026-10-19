class_name TouchControls
extends Control
## On-screen controls for phones and touchscreens (Settings > Touch controls).
##
##   Left side   floating joystick: put a thumb down anywhere, drag to move.
##   Right side  drag to look / aim.
##   Buttons     Run:   Jump (big), Sprint (hold), Look back (hold).
##               Throw: one big Throw button: hold to charge, release to throw.
##
## The joystick and buttons feed the normal input actions (move_*, sprint,
## jump, look_back, throw), so the player and throw code work unchanged.
## Touches also produce emulated mouse clicks for the menus; while these
## controls are on, the player and throw code ignore mouse input
## (TouchControls.active) so nothing happens twice.
##
## Without a touchscreen (testing on PC with the setting on) the mouse stands
## in for one finger.

signal look(relative: Vector2) ## drag on the right side, in design pixels

## True while the on-screen controls are in charge of input.
static var active := false

const TINT := Color(1, 1, 1, 0.42)
const FILL := Color(0.02, 0.03, 0.06, 0.32)
const PRESSED := Color(1.0, 0.8, 0.34, 0.55) # UiKit.ACCENT

var context := "none": ## "none", "quiz", "throw" or "run"
	set(v):
		if context != v:
			context = v
			_release_all()
			queue_redraw()
var power := 0.0: ## throw charge 0..1, drawn around the Throw button
	set(v):
		power = v
		if context == "throw":
			queue_redraw()

var _touches := {} ## finger index -> {kind, start, pos}
var _stick_origin := Vector2.ZERO
var _stick_vec := Vector2.ZERO
var _buttons := {} ## name -> {pos, r, kind, icon}
var _down := {} ## button name -> true while held
var _mouse_is_finger := false
var _slipper_icon: Texture2D
var _sprint_icon: Texture2D = preload("res://art/ui/hud/icon_sprint.webp")


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_meta("fx_skip", true) # laid out in real screen pixels, not shrunk with the HUD
	_mouse_is_finger = not DisplayServer.is_touchscreen_available()
	var item := Economy.equipped_slipper_item()
	if item.has("icon") and ResourceLoader.exists(item.icon):
		_slipper_icon = load(item.icon)
	resized.connect(_layout)
	_layout()


func _exit_tree() -> void:
	_release_all()
	active = false


func _process(_delta: float) -> void:
	active = visible
	var screen := get_viewport_rect().size
	if size != screen: # always cover the whole screen (works under a bare CanvasLayer)
		position = Vector2.ZERO
		size = screen
	# Every buttons' visual state follows its finger.
	if not _touches.is_empty():
		queue_redraw()


## Thumb-zone layout, scaled to the screen height.
func _layout() -> void:
	var s := size
	var u := s.y / 1080.0
	_buttons = {
		"jump": {"pos": Vector2(s.x - 210 * u, s.y - 220 * u), "r": 96 * u, "ctx": "run"},
		"sprint": {"pos": Vector2(s.x - 430 * u, s.y - 150 * u), "r": 78 * u, "ctx": "run"},
		"back": {"pos": Vector2(s.x - 200 * u, s.y - 450 * u), "r": 60 * u, "ctx": "run"},
		"throw": {"pos": Vector2(s.x - 250 * u, s.y - 270 * u), "r": 128 * u, "ctx": "throw"},
	}
	queue_redraw()


func _unit() -> float:
	return size.y / 1080.0


## Screen rect of a button (for the tutorial's highlight ring).
func button_rect(id: String) -> Rect2:
	if not visible or not _buttons.has(id):
		return Rect2()
	var b: Dictionary = _buttons[id]
	return Rect2(b.pos - Vector2(b.r, b.r), Vector2(b.r, b.r) * 2.0)


## Screen rect of the joystick's resting spot.
func stick_rect() -> Rect2:
	if not visible:
		return Rect2()
	var u := _unit()
	return Rect2(Vector2(140 * u, size.y - 360 * u), Vector2(220 * u, 220 * u))


# --- Input ------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not visible or context == "none" or context == "quiz":
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_finger_down(event.index, event.position)
		else:
			_finger_up(event.index)
	elif event is InputEventScreenDrag:
		_finger_move(event.index, event.position, event.relative)
	elif _mouse_is_finger:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_finger_down(-1, event.position)
			else:
				_finger_up(-1)
		elif event is InputEventMouseMotion and _touches.has(-1):
			_finger_move(-1, event.position, event.relative)


func _finger_down(index: int, pos: Vector2) -> void:
	var b := _button_at(pos)
	if b != "":
		_touches[index] = {"kind": "button", "name": b}
		_press_button(b)
	elif pos.x < size.x * 0.45 and pos.y > size.y * 0.25:
		_touches[index] = {"kind": "stick"}
		_stick_origin = pos
		_stick_vec = Vector2.ZERO
	elif pos.y > size.y * 0.14: # leave the top strip for the pause button
		_touches[index] = {"kind": "look"}
	queue_redraw()


func _finger_move(index: int, pos: Vector2, relative: Vector2) -> void:
	if not _touches.has(index):
		return
	var t: Dictionary = _touches[index]
	match t.kind:
		"stick":
			var radius := 120.0 * _unit()
			var d := pos - _stick_origin
			if d.length() > radius: # the base follows the thumb past its edge
				_stick_origin = pos - d.limit_length(radius)
				d = pos - _stick_origin
			_stick_vec = d / radius
			_apply_stick()
			queue_redraw()
		"look":
			look.emit(relative / _unit())
		"button":
			if t.name == "throw" or t.name == "sprint": # aim while holding
				look.emit(relative / _unit() * 0.6)


func _finger_up(index: int) -> void:
	if not _touches.has(index):
		return
	var t: Dictionary = _touches[index]
	_touches.erase(index)
	match t.kind:
		"stick":
			_stick_vec = Vector2.ZERO
			_apply_stick()
		"button":
			_release_button(t.name)
	queue_redraw()


func _button_at(pos: Vector2) -> String:
	for id in _buttons:
		var b: Dictionary = _buttons[id]
		if b.ctx == context and pos.distance_to(b.pos) <= b.r * 1.15:
			return id
	return ""


func _apply_stick() -> void:
	var v := _stick_vec
	_set_action("move_left", maxf(-v.x, 0.0))
	_set_action("move_right", maxf(v.x, 0.0))
	_set_action("move_forward", maxf(-v.y, 0.0))
	_set_action("move_back", maxf(v.y, 0.0))


func _set_action(action: String, strength: float) -> void:
	if strength > 0.05:
		Input.action_press(action, clampf(strength, 0.0, 1.0))
	else:
		Input.action_release(action)


func _press_button(id: String) -> void:
	_down[id] = true
	match id:
		"jump":
			Input.action_press("jump")
		"sprint":
			Input.action_press("sprint")
		"back":
			Input.action_press("look_back")
		"throw":
			_send_action("throw", true)


func _release_button(id: String) -> void:
	_down.erase(id)
	match id:
		"jump":
			Input.action_release("jump")
		"sprint":
			Input.action_release("sprint")
		"back":
			Input.action_release("look_back")
		"throw":
			_send_action("throw", false)


## Event-based actions (the throw listens for press/release events).
func _send_action(action: String, pressed: bool) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = pressed
	Input.parse_input_event(e)


func _release_all() -> void:
	for index in _touches.keys():
		_finger_up(index)
	_touches.clear()
	for a in ["move_left", "move_right", "move_forward", "move_back", "sprint", "jump", "look_back"]:
		Input.action_release(a)
	_down.clear()
	_stick_vec = Vector2.ZERO


# --- Drawing ------------------------------------------------------------------

func _draw() -> void:
	if context != "run" and context != "throw":
		return
	var u := _unit()
	# Joystick: a faint resting hint, or the live stick under the thumb.
	var stick_active := false
	for t in _touches.values():
		if t.kind == "stick":
			stick_active = true
	if stick_active:
		var base_r := 120.0 * u
		draw_circle(_stick_origin, base_r, FILL)
		draw_arc(_stick_origin, base_r, 0, TAU, 64, TINT, 3.0 * u, true)
		var knob := _stick_origin + _stick_vec * base_r
		if _stick_vec.length() > 0.1: # glow toward where you're pushing
			var a := _stick_vec.angle()
			draw_arc(_stick_origin, base_r, a - 0.5, a + 0.5, 24, Color(1, 0.8, 0.34, 0.85), 6.0 * u, true)
		draw_circle(knob + Vector2(0, 4 * u), 54 * u, Color(0, 0, 0, 0.25))
		draw_circle(knob, 54 * u, Color(1, 1, 1, 0.82))
		draw_arc(knob, 54 * u, 0, TAU, 48, Color(0, 0, 0, 0.15), 2.0 * u, true)
	else:
		var rest := Vector2(250 * u, size.y - 250 * u)
		draw_arc(rest, 110 * u, 0, TAU, 64, Color(1, 1, 1, 0.18), 3.0 * u, true)
		draw_circle(rest, 44 * u, Color(1, 1, 1, 0.14))
		_chevrons(rest, 78 * u, Color(1, 1, 1, 0.22))

	for id in _buttons:
		var b: Dictionary = _buttons[id]
		if b.ctx != context:
			continue
		var held: bool = _down.has(id)
		var r: float = b.r * (0.93 if held else 1.0)
		var p: Vector2 = b.pos
		draw_circle(p + Vector2(0, 5 * u), r, Color(0, 0, 0, 0.18))
		draw_circle(p, r, PRESSED if held else FILL)
		draw_arc(p, r, 0, TAU, 64, Color(1, 1, 1, 0.75) if held else TINT, 3.0 * u, true)
		match id:
			"jump":
				_chevron_up(p + Vector2(0, -6 * u), r * 0.42, Color.WHITE, 9.0 * u)
				_chevron_up(p + Vector2(0, r * 0.26), r * 0.3, Color(1, 1, 1, 0.55), 7.0 * u)
			"sprint":
				var s := r * 1.25
				draw_texture_rect(_sprint_icon, Rect2(p - Vector2(s, s) * 0.5, Vector2(s, s)), false)
			"back":
				_turn_arrow(p, r * 0.5, Color.WHITE, 6.0 * u)
			"throw":
				if power > 0.0:
					var col := Color(0.95, 0.3, 0.3).lerp(Color(1, 0.85, 0.2), minf(power * 2.0, 1.0))
					if power > 0.5:
						col = Color(1, 0.85, 0.2).lerp(Color(0.4, 0.95, 0.45), (power - 0.5) * 2.0)
					draw_arc(p, r + 12 * u, -PI * 0.5, -PI * 0.5 + TAU * power, 64, col, 12.0 * u, true)
				if _slipper_icon:
					var s := r * 1.15
					draw_texture_rect(_slipper_icon, Rect2(p - Vector2(s, s) * 0.5 + Vector2(0, -8 * u), Vector2(s, s)), false)
				var f := UiKit.title_font()
				var fs := int(30 * u)
				var label := "Release!" if held else "Hold"
				var w := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				draw_string_outline(f, p + Vector2(-w * 0.5, r * 0.72), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(8 * u), UiKit.TEXT_OUTLINE)
				draw_string(f, p + Vector2(-w * 0.5, r * 0.72), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


func _chevron_up(c: Vector2, w: float, col: Color, width: float) -> void:
	draw_polyline(PackedVector2Array([c + Vector2(-w, w * 0.5), c + Vector2(0, -w * 0.5), c + Vector2(w, w * 0.5)]), col, width, true)


func _chevrons(c: Vector2, d: float, col: Color) -> void:
	for a in [0.0, PI * 0.5, PI, PI * 1.5]:
		var dir := Vector2(cos(a), sin(a))
		var side := Vector2(-dir.y, dir.x) * 10.0
		var tip := c + dir * d
		draw_polyline(PackedVector2Array([tip - dir * 10.0 + side, tip, tip - dir * 10.0 - side]), col, 3.0, true)


## A U-turn arrow (look behind you).
func _turn_arrow(c: Vector2, r: float, col: Color, width: float) -> void:
	draw_arc(c, r, -PI * 0.15, PI * 1.15, 32, col, width, true)
	var end := c + Vector2(cos(PI * 1.15), sin(PI * 1.15)) * r
	var d := Vector2(cos(PI * 1.15 + PI * 0.5), sin(PI * 1.15 + PI * 0.5))
	draw_colored_polygon(PackedVector2Array([end + d * r * 0.45, end + Vector2(-d.y, d.x) * r * 0.35, end - Vector2(-d.y, d.x) * r * 0.35]), col)
