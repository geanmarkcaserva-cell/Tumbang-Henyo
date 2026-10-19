class_name CoachCard
extends PanelContainer
## The glass card the tutorial and the one-time tips talk through.
##
## Coaching cards are short on purpose: a headline, one line of help and the
## controls as keycaps. Decision cards (welcome / done) sit in the middle and
## lay their points out as columns or rows instead of paragraphs.
##
## show_card({
##     "step": 2, "steps": 5,           # "STEP 2 OF 5" + progress dots (optional)
##     "label": "TIP",                  # header text when there is no step (optional)
##     "title": "Aim at the lata",
##     "body": "The circle shows where it lands.",
##     "keys": [["W", "A", "S", "D"], "Move"],   # optional keycaps + caption,
##     "keys2": [["Space"], "Jump"],             #   up to two groups
##     "points": [{"badge": "1", "title": "Answer", "text": "..."}, ...], # or "icon": Texture2D
##     "points_layout": "columns",      # or "rows"
##     "note": "Practice round: no Awra lost.",
##     "buttons": [{"id": "go", "text": "Start", "primary": true}, ...],
##     "skip": true,                    # "Skip tutorial" link in the footer
##     "center": true, "width": 1100,
##     "title_color": Color(...),
## })
## nice() swaps the card to a green tick and "Nice!" when a step is done.

signal button_pressed(id: String)
signal skip_pressed

const GOOD := Color(0.45, 0.95, 0.55)
const SIDE_WIDTH := 820.0

var _box: StyleBoxFlat
var _header: HBoxContainer
var _step: Label
var _dots: StepDots
var _check: Control
var _title: Label
var _body: Label
var _keys: HBoxContainer
var _points: BoxContainer
var _points_holder: Control
var _note: Label
var _footer: HBoxContainer
var _buttons: HBoxContainer
var _skip: Button
var _shown := false
var _centered := false
var _tween: Tween


func _init() -> void:
	_box = StyleBoxFlat.new()
	_box.bg_color = Color(0.03, 0.04, 0.07, 0.84)
	_box.border_color = UiKit.ACCENT
	_box.border_width_top = 5 # a thin accent line along the top
	_box.set_corner_radius_all(26)
	_box.shadow_color = Color(0, 0, 0, 0.35)
	_box.shadow_size = 22
	_box.shadow_offset = Vector2(0, 8)
	_box.content_margin_left = 48
	_box.content_margin_right = 48
	_box.content_margin_top = 34
	_box.content_margin_bottom = 36
	add_theme_stylebox_override("panel", _box)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	set_meta("fx_custom", true) # animates itself

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 20)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)

	# Header: STEP 2 OF 5 ........ o o * o o
	_header = HBoxContainer.new()
	_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_header)
	_step = UiKit.title("", 26, Color(UiKit.ACCENT, 0.85), 0)
	_step.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.add_child(_step)
	_dots = StepDots.new()
	_dots.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_header.add_child(_dots)

	# Headline (with a tick when a step is done).
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 18)
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(title_row)
	_check = CheckMark.new()
	_check.custom_minimum_size = Vector2(60, 60)
	_check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(_check)
	_title = UiKit.title("", 62, Color.WHITE, 10)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(_title)

	_body = UiKit.label("", 36, Color(1, 1, 1, 0.88), 6)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_theme_constant_override("line_spacing", 8)
	v.add_child(_body)

	_points_holder = MarginContainer.new()
	_points_holder.add_theme_constant_override("margin_top", 6)
	_points_holder.add_theme_constant_override("margin_bottom", 6)
	_points_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_points_holder)

	_keys = HBoxContainer.new()
	_keys.add_theme_constant_override("separation", 12)
	_keys.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_keys)

	_note = UiKit.label("", 28, Color(1, 1, 1, 0.6), 4)
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_note)

	# Footer: buttons (decision cards) and/or the quiet Skip link.
	_footer = HBoxContainer.new()
	_footer.add_theme_constant_override("separation", 24)
	v.add_child(_footer)
	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 24)
	_buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_footer.add_child(_buttons)
	_skip = UiKit.text_button("Skip tutorial", 30)
	_skip.add_theme_constant_override("outline_size", 6)
	_skip.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	_skip.pressed.connect(func(): skip_pressed.emit())
	_footer.add_child(_skip)


func show_card(d: Dictionary) -> void:
	_centered = d.get("center", false)
	var width: float = d.get("width", 1100.0 if _centered else SIDE_WIDTH)
	var inner := width - _box.content_margin_left - _box.content_margin_right
	custom_minimum_size = Vector2(width, 0)

	# Header.
	var steps: int = d.get("steps", 0)
	if steps > 0:
		_step.text = "STEP %d OF %d" % [d.get("step", 1), steps]
		_dots.total = steps
		_dots.current = d.get("step", 1)
		_dots.visible = true
	else:
		_step.text = d.get("label", "")
		_dots.visible = false
	_header.visible = _step.text != ""

	# Headline and body.
	_check.visible = false
	_title.text = d.get("title", "")
	_title.custom_minimum_size = Vector2(inner - 80, 0)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if _centered else HORIZONTAL_ALIGNMENT_LEFT
	_title.add_theme_color_override("font_color", d.get("title_color", UiKit.ACCENT if _centered else Color.WHITE))
	_body.text = d.get("body", "")
	_body.custom_minimum_size = Vector2(inner, 0)
	_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if _centered else HORIZONTAL_ALIGNMENT_LEFT
	_body.visible = _body.text != ""

	# Points (welcome / done).
	for c in _points_holder.get_children():
		_points_holder.remove_child(c)
		c.queue_free()
	_points_holder.visible = d.has("points")
	if d.has("points"):
		_build_points(d.points, d.get("points_layout", "columns"), inner)

	# Controls.
	for c in _keys.get_children():
		_keys.remove_child(c)
		c.queue_free()
	for k in ["keys", "keys2"]:
		if d.has(k):
			_add_key_group(d[k][0], d[k][1])
	_keys.visible = d.has("keys")
	_keys.alignment = BoxContainer.ALIGNMENT_CENTER if _centered else BoxContainer.ALIGNMENT_BEGIN

	_note.text = d.get("note", "")
	_note.visible = _note.text != ""

	# Footer.
	for c in _buttons.get_children():
		_buttons.remove_child(c)
		c.queue_free()
	for b in d.get("buttons", []):
		var btn := UiKit.button(b.text, UiKit.GOLD if b.get("primary", false) else UiKit.BLUE, 44, Vector2(360, 110))
		var id: String = b.id
		btn.pressed.connect(func(): button_pressed.emit(id))
		_buttons.add_child(btn)
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER if _centered else BoxContainer.ALIGNMENT_BEGIN
	_skip.visible = d.get("skip", false)
	_footer.visible = d.has("buttons") or _skip.visible
	mouse_filter = Control.MOUSE_FILTER_STOP if _footer.visible else Control.MOUSE_FILTER_IGNORE

	if not has_meta("home"):
		set_meta("home", position)
	if not _shown:
		modulate.a = 0.0 # stays hidden until it's measured and placed, then pops in
	visible = true
	_place.call_deferred(true)


## A step was done: green tick, "Nice!", a little bounce. await it to wait.
func nice(text: String = "Nice!") -> Signal:
	_check.visible = true
	_title.text = text
	_title.add_theme_color_override("font_color", GOOD)
	_body.visible = false
	_keys.visible = false
	_note.visible = false
	_place.call_deferred()
	UiFx.bounce(self, 1.05, 0.45)
	return get_tree().create_timer(0.75, false).timeout


func hide_card() -> void:
	if not _shown:
		return
	_shown = false
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "modulate:a", 0.0, 0.18)
	_tween.tween_property(self, "scale", UiFx.base_of(self) * 0.94, 0.18).set_trans(Tween.TRANS_QUAD)
	_tween.chain().tween_callback(func():
		if not _shown:
			visible = false)


func _open() -> void:
	var was := _shown
	_shown = true
	visible = true
	if _tween:
		_tween.kill()
	modulate.a = 1.0
	if not was:
		UiFx.pop(self, 0.0, 0.75, 0.45)
	else:
		scale = UiFx.base_of(self)
		UiFx.bounce(self, 1.03, 0.35)


func _place(open_after: bool = false) -> void:
	var parent := get_parent() as Control
	if parent == null:
		return
	# Fit the content once the new labels have measured themselves (wrapping
	# labels report a huge height for a frame before they know their width).
	reset_size()
	await get_tree().process_frame
	if not is_inside_tree():
		return
	reset_size()
	if _centered:
		var s := size * UiFx.base_of(self)
		position = ((parent.size - s) * 0.5).round()
	else:
		position = get_meta("home", position)
	if open_after:
		_open()


## Welcome / done: numbered (or icon) columns side by side, or icon rows.
func _build_points(points: Array, layout: String, inner: float) -> void:
	var box: BoxContainer = HBoxContainer.new() if layout == "columns" else VBoxContainer.new()
	box.add_theme_constant_override("separation", 26 if layout == "columns" else 18)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_points_holder.add_child(box)
	var n := points.size()
	for p in points:
		if layout == "columns":
			var col_w := (inner - 26.0 * (n - 1)) / n
			var col := PanelContainer.new()
			var s := StyleBoxFlat.new()
			s.bg_color = Color(1, 1, 1, 0.05)
			s.border_color = Color(1, 1, 1, 0.08)
			s.set_border_width_all(1)
			s.set_corner_radius_all(20)
			s.content_margin_left = 20
			s.content_margin_right = 20
			s.content_margin_top = 24
			s.content_margin_bottom = 26
			col.add_theme_stylebox_override("panel", s)
			col.custom_minimum_size = Vector2(col_w, 0)
			col.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var cv := VBoxContainer.new()
			cv.add_theme_constant_override("separation", 10)
			cv.alignment = BoxContainer.ALIGNMENT_BEGIN # badges line up across columns
			cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
			col.add_child(cv)
			var badge := _badge(p)
			badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			cv.add_child(badge)
			var t := UiKit.title(p.get("title", ""), 40, UiKit.ACCENT, 8)
			t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cv.add_child(t)
			var x := UiKit.label(p.get("text", ""), 28, Color(1, 1, 1, 0.82), 4)
			x.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			x.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			x.custom_minimum_size = Vector2(col_w - 40, 0)
			cv.add_child(x)
			box.add_child(col)
		else:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 24)
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var badge := _badge(p)
			badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(badge)
			var x := UiKit.label(p.get("text", ""), 32, Color(1, 1, 1, 0.9), 4)
			x.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			x.custom_minimum_size = Vector2(inner - 120, 0)
			x.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(x)
			box.add_child(row)


## A round number badge, or the given icon.
func _badge(p: Dictionary) -> Control:
	if p.has("icon"):
		var t := TextureRect.new()
		t.texture = p.icon
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.custom_minimum_size = Vector2(80, 80)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return t
	var b := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = UiKit.ACCENT
	s.set_corner_radius_all(36)
	b.add_theme_stylebox_override("panel", s)
	b.custom_minimum_size = Vector2(72, 72)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UiKit.title(str(p.get("badge", "")), 38, UiKit.TEXT_ON_ACCENT, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	b.add_child(l)
	return b


## Keycaps (or a phrase for touch) followed by a dim caption.
func _add_key_group(keys: Array, caption: String) -> void:
	if _keys.get_child_count() > 0:
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(28, 0)
		_keys.add_child(gap)
	for key in keys:
		_keys.add_child(_keycap(str(key)))
	var l := UiKit.label(caption, 30, Color(1, 1, 1, 0.78), 6)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_keys.add_child(l)


static func _keycap(text: String) -> PanelContainer:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(1, 1, 1, 0.1)
	s.border_color = Color(1, 1, 1, 0.42)
	s.set_border_width_all(2)
	s.border_width_bottom = 6 # key depth
	s.set_corner_radius_all(12)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	p.add_theme_stylebox_override("panel", s)
	p.custom_minimum_size = Vector2(64, 64)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UiKit.label(text, 28, Color.WHITE, 0)
	l.add_theme_font_override("font", UiKit.key_font())
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


## Progress dots: done = white, current = accent pill, upcoming = outline.
class StepDots extends Control:
	var total := 5:
		set(v):
			total = v
			custom_minimum_size = Vector2(total * 30 + 20, 24)
			queue_redraw()
	var current := 1:
		set(v):
			current = v
			queue_redraw()

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(total * 30 + 20, 24)

	func _draw() -> void:
		var x := size.x
		var cy := size.y * 0.5
		for i in range(total - 1, -1, -1): # right to left
			var n := i + 1
			if n == current:
				var w := 40.0
				x -= w
				var s := StyleBoxFlat.new()
				s.bg_color = UiKit.ACCENT
				s.set_corner_radius_all(8)
				draw_style_box(s, Rect2(x, cy - 7, w, 14))
			else:
				x -= 14.0
				var c := Vector2(x + 7, cy)
				if n < current:
					draw_circle(c, 7.0, Color(1, 1, 1, 0.85))
				else:
					draw_arc(c, 6.0, 0, TAU, 20, Color(1, 1, 1, 0.35), 2.0, true)
			x -= 12.0


## A green tick in a ring (drawn, so it doesn't depend on the font).
class CheckMark extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		draw_circle(c, r, Color(0.45, 0.95, 0.55, 0.22))
		draw_arc(c, r - 2.0, 0, TAU, 40, Color(0.45, 0.95, 0.55), 4.0, true)
		draw_polyline(PackedVector2Array([c + Vector2(-r * 0.42, 0.0), c + Vector2(-r * 0.1, r * 0.32), c + Vector2(r * 0.45, -r * 0.3)]), Color(0.45, 0.95, 0.55), 6.0, true)
