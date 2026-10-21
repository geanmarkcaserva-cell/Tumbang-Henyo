class_name ClassBoard
extends VBoxContainer
## The class game leaderboard (Lobby.board()): place, name, round, perfect
## shots and score, best first. Gold / silver / bronze for the top three,
## your own row highlighted, students who are out or left dimmed.
## Used big on the teacher's screen and small in the game's dropdown.

const MEDALS := [Color(1.0, 0.82, 0.3), Color(0.86, 0.88, 0.94), Color(0.9, 0.62, 0.42)]

var compact := false ## small rows for the in-game dropdown
var max_rows := 12
var show_scores := true ## false in the waiting room: just names
var empty_text := "No students yet."

var _rows_box: VBoxContainer
var _more: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 6 if compact else 10)
	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 6 if compact else 10)
	_rows_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rows_box)
	_more = UiKit.label("", 22 if compact else 28, Color(1, 1, 1, 0.6), 0)
	_more.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_more)
	Lobby.players_changed.connect(refresh)
	refresh()


func refresh() -> void:
	if _rows_box == null:
		return
	for c in _rows_box.get_children():
		_rows_box.remove_child(c)
		c.queue_free()
	var rows := Lobby.board()
	if rows.is_empty():
		_more.text = empty_text
		return
	# Always show my own row, even when I'm below the cut.
	var shown := rows.slice(0, max_rows)
	var mine := -1
	for i in rows.size():
		if rows[i].me:
			mine = i
	for i in shown.size():
		_rows_box.add_child(_row(i + 1, shown[i]))
	if mine >= max_rows:
		_rows_box.add_child(_row(mine + 1, rows[mine]))
	var not_shown := rows.size() - shown.size() - (1 if mine >= max_rows else 0)
	_more.text = "+%d more" % not_shown if not_shown > 0 else ""


func _row(place: int, p: Dictionary) -> Control:
	var h := 52 if compact else 74
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := StyleBoxFlat.new()
	s.bg_color = Color(1.0, 0.8, 0.34, 0.22) if p.me else Color(1, 1, 1, 0.05)
	s.border_color = UiKit.ACCENT if p.me else Color(1, 1, 1, 0.06)
	s.set_border_width_all(2 if p.me else 1)
	s.set_corner_radius_all(int(h * 0.3))
	s.content_margin_left = 16 if compact else 24
	s.content_margin_right = 18 if compact else 26
	panel.add_theme_stylebox_override("panel", s)
	panel.custom_minimum_size = Vector2(0, h)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12 if compact else 20)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)

	var dim := bool(p.get("out", false)) or bool(p.get("left", false))
	var fs := 26 if compact else 38
	var place_col: Color = MEDALS[place - 1] if place <= 3 and show_scores else Color(1, 1, 1, 0.7)
	var place_l := UiKit.title("-" if p.get("left", false) else str(place), fs + 4, place_col, 6)
	place_l.custom_minimum_size = Vector2(44 if compact else 64, 0)
	place_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	place_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(place_l)

	var name_l := UiKit.label(String(p.name) + ("  (you)" if p.me else ""), fs, Color(1, 1, 1, 0.55) if dim else Color.WHITE, 0)
	name_l.add_theme_font_override("font", UiKit.key_font())
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_l.clip_text = true
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(name_l)

	var tag := ""
	if p.get("left", false):
		tag = "LEFT"
	elif p.get("out", false):
		tag = "OUT"
	if tag != "":
		row.add_child(_chip(tag, Color(1.0, 0.45, 0.42)))

	if show_scores:
		if int(p.get("perfect", 0)) > 0:
			row.add_child(_chip("%d BULLSEYE" % p.perfect if not compact else "%d x" % p.perfect, Color(0.62, 0.9, 1.0)))
		var round_l := UiKit.label("R%d" % int(p.get("round", 1)), fs - 6, Color(1, 1, 1, 0.6), 0)
		round_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(round_l)
		var score_l := UiKit.title(_thousands(int(p.get("score", 0))), fs + 4, UiKit.ACCENT, 6)
		score_l.custom_minimum_size = Vector2(110 if compact else 170, 0)
		score_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		score_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(score_l)
	return panel


func _chip(text: String, col: Color) -> Control:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := StyleBoxFlat.new()
	s.bg_color = Color(col.r, col.g, col.b, 0.16)
	s.border_color = Color(col.r, col.g, col.b, 0.6)
	s.set_border_width_all(1)
	s.set_corner_radius_all(10)
	s.content_margin_left = 10
	s.content_margin_right = 10
	p.add_theme_stylebox_override("panel", s)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := UiKit.label(text, 18 if compact else 22, col, 0)
	l.add_theme_font_override("font", UiKit.key_font())
	p.add_child(l)
	return p


static func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
