class_name JoinPanel
extends Control
## Main menu -> Multiplayer. A student types the lobby ID their teacher shows
## (they join under their account's name), and waits in a small waiting room
## (who else is in) until the teacher presses Start. Coming back from a class
## game it shows the live standings.

signal back_pressed


var _form: VBoxContainer
var _wait: VBoxContainer
var _name: Label
var _code: LineEdit
var _status: Label
var _join: Button
var _wait_title: Label
var _wait_sub: Label
var _board: ClassBoard
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(1920, 1080)
	var card := PanelContainer.new()
	card.position = Vector2(470, 110)
	card.custom_minimum_size = Vector2(980, 840)
	card.add_theme_stylebox_override("panel", UiKit.box(UiKit.PANEL_DARK, Color(0.3, 0.3, 0.32), 10, 8))
	add_child(card)
	var stack := Control.new()
	card.add_child(stack)

	# --- Join form ---
	_form = VBoxContainer.new()
	_form.add_theme_constant_override("separation", 14)
	_form.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.add_child(_form)
	_form.add_child(UiKit.title("Multiplayer", 76, Color.WHITE, 14))
	_form.add_child(UiKit.label("Join your teacher's class game.", 32, Color(1, 1, 1, 0.75), 0))
	_form.add_child(UiKit.accent_rule())
	_form.add_child(_gap(8))
	_form.add_child(UiKit.title("Playing as", 34, Color(1, 1, 1, 0.7), 6))
	_name = UiKit.title("", 52, UiKit.ACCENT, 8)
	_form.add_child(_name)
	_form.add_child(UiKit.label("Your account's name. Your teacher sees it on the class board.", 26, Color(1, 1, 1, 0.55), 0))
	_form.add_child(_gap(4))
	_form.add_child(UiKit.title("Lobby ID", 34, Color(1, 1, 1, 0.7), 6))
	_code = _field("K7P-2QX", 72, true)
	_code.max_length = 7
	_code.text_changed.connect(_on_code_changed)
	_code.text_submitted.connect(func(_t2): _on_join())
	_form.add_child(_code)
	_status = UiKit.label("Ask your teacher for the ID. You need to be on the same WiFi.", 28, Color(1, 1, 1, 0.65), 0)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(920, 90)
	_form.add_child(_status)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_form.add_child(fill)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	_form.add_child(row)
	var back := UiKit.button("Back", UiKit.BLUE, 44, Vector2(250, 110))
	back.pressed.connect(func():
		Lobby.close()
		back_pressed.emit())
	row.add_child(back)
	_join = UiKit.button("Join", UiKit.GOLD, 52, Vector2(320, 120))
	_join.pressed.connect(_on_join)
	row.add_child(_join)

	# --- Waiting room / standings ---
	_wait = VBoxContainer.new()
	_wait.add_theme_constant_override("separation", 12)
	_wait.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wait.visible = false
	stack.add_child(_wait)
	_wait_title = UiKit.title("You're in!", 72, Color.WHITE, 14)
	_wait.add_child(_wait_title)
	_wait_sub = UiKit.title("", 36, UiKit.ACCENT, 8)
	_wait_sub.clip_text = true
	_wait_sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_wait_sub.custom_minimum_size = Vector2(920, 0)
	_wait.add_child(_wait_sub)
	_wait.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(920, 520)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_wait.add_child(scroll)
	_board = ClassBoard.new()
	_board.max_rows = 60
	_board.show_scores = false
	_board.custom_minimum_size = Vector2(900, 0)
	scroll.add_child(_board)
	var wfill := Control.new()
	wfill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_wait.add_child(wfill)
	var leave := UiKit.button("Leave", UiKit.BLUE, 44, Vector2(250, 110))
	leave.pressed.connect(func():
		Lobby.close()
		_show_form("You left the lobby."))
	_wait.add_child(leave)

	_load_name()
	Lobby.joined.connect(_on_joined)
	Lobby.join_failed.connect(_on_failed)
	Lobby.left.connect(func(reason): _show_form(reason, true))
	Lobby.match_started.connect(_on_match_started)
	Lobby.match_ended.connect(_refresh_wait)
	Lobby.players_changed.connect(_refresh_wait)


## Called when the panel opens: the form, or the lobby we're already in.
func on_show() -> void:
	if Lobby.is_client() and Lobby.quiz_title != "":
		_show_wait()
	else:
		_load_name() # the account may have changed since last time
		_show_form("")
		_code.grab_focus.call_deferred()


func _process(delta: float) -> void:
	_t += delta
	if _wait.visible and not Lobby.match_on and _wait_title.text == "You're in!":
		# Gentle pulse on "waiting" so it doesn't look frozen.
		_wait_sub.modulate.a = 0.75 + 0.25 * sin(_t * 3.0)


func _on_code_changed(t: String) -> void:
	# Upper-case and put the dash in as they type: K7P2QX -> K7P-2QX.
	var clean := Lobby.normalize_id(t).substr(0, 6)
	var shown := clean if clean.length() <= 3 else clean.substr(0, 3) + "-" + clean.substr(3)
	if shown != t:
		_code.text = shown
		_code.caret_column = shown.length()


func _on_join() -> void:
	if Lobby.normalize_id(_code.text).length() != 6:
		_set_status("A lobby ID has 6 letters and numbers, like K7P-2QX.", Color(1.0, 0.75, 0.4))
		_code.grab_focus()
		return
	_load_name()
	_join.disabled = true
	_join.text = "Looking..."
	_set_status("Looking for lobby %s on this WiFi..." % _code.text, Color(1, 1, 1, 0.8))
	Lobby.join(_code.text, _name.text)


func _on_joined() -> void:
	_show_wait()


func _on_failed(message: String) -> void:
	_show_form(message, true)


func _on_match_started() -> void:
	if not is_visible_in_tree():
		return
	GameManager.start_run(Lobby.quiz_theme)


func _show_form(message: String, is_error: bool = false) -> void:
	_form.visible = true
	_wait.visible = false
	_join.disabled = false
	_join.text = "Join"
	if message != "":
		_set_status(message, Color(1.0, 0.5, 0.45) if is_error else Color(1, 1, 1, 0.75))


func _show_wait() -> void:
	_form.visible = false
	_wait.visible = true
	_refresh_wait()


func _refresh_wait() -> void:
	if not _wait.visible:
		return
	var played := false
	for p in Lobby.players.values():
		if int(p.get("score", 0)) > 0 or p.get("out", false):
			played = true
	if Lobby.match_on:
		_wait_title.text = "Game on!"
		_wait_sub.text = "Lobby %s  -  %s" % [Lobby.pretty_id(), Lobby.quiz_title]
		_board.show_scores = true
	elif played:
		_wait_title.text = "Final standings"
		_wait_sub.text = "Wait here for your teacher's next game."
		_board.show_scores = true
	else:
		_wait_title.text = "You're in!"
		_wait_sub.text = "Lobby %s  -  %s  -  waiting for your teacher to start..." % [Lobby.pretty_id(), Lobby.quiz_title]
		_board.show_scores = false
	_wait_sub.modulate.a = 1.0
	_board.refresh()


func _set_status(text: String, col: Color) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", col)


func _field(placeholder: String, font_size: int, big: bool) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.custom_minimum_size = Vector2(920, 110 if big else 84)
	e.add_theme_font_size_override("font_size", font_size)
	if big:
		e.add_theme_font_override("font", UiKit.title_font())
		e.alignment = HORIZONTAL_ALIGNMENT_CENTER
	for state in ["normal", "focus"]:
		var s := StyleBoxFlat.new()
		s.bg_color = Color(0, 0, 0, 0.35)
		s.border_color = UiKit.ACCENT if state == "focus" else Color(1, 1, 1, 0.18)
		s.set_border_width_all(3 if state == "focus" else 2)
		s.set_corner_radius_all(18)
		s.content_margin_left = 24
		s.content_margin_right = 24
		e.add_theme_stylebox_override(state, s)
	e.add_theme_color_override("font_placeholder_color", Color(1, 1, 1, 0.3))
	return e


func _gap(h: float) -> Control:
	var g := Control.new()
	g.custom_minimum_size = Vector2(0, h)
	return g


func _load_name() -> void:
	var n := Accounts.current_name() if Accounts.has_any() else ""
	_name.text = n if n != "" else "Student"
