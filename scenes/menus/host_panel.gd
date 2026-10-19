class_name HostPanel
extends Control
## The teacher's lobby screen (opened from Custom quiz -> Host class game).
## Left: the lobby ID in big letters for the board/projector, how students
## join, and Start / End. Right: who joined, then the live leaderboard.

signal closed

var _id_label: Label
var _quiz_label: Label
var _count_label: Label
var _heading: Label
var _sub: Label
var _start: Button
var _end: Button
var _close: Button
var _board: ClassBoard
var _close_armed := false
var _played := false ## at least one game finished in this lobby
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(1920, 1080)

	# --- Left card: the ID and the controls ---
	var card := PanelContainer.new()
	card.position = Vector2(70, 90)
	card.custom_minimum_size = Vector2(780, 880)
	card.add_theme_stylebox_override("panel", UiKit.box(UiKit.PANEL_DARK, Color(0.3, 0.3, 0.32), 10, 8))
	add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	card.add_child(v)
	v.add_child(UiKit.title("Class game", 72, Color.WHITE, 14))
	_quiz_label = UiKit.title("", 38, UiKit.ACCENT, 8)
	_quiz_label.clip_text = true
	_quiz_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_quiz_label.custom_minimum_size = Vector2(700, 0)
	v.add_child(_quiz_label)
	v.add_child(UiKit.accent_rule())
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 10)
	v.add_child(gap)
	v.add_child(UiKit.title("Lobby ID", 32, Color(1, 1, 1, 0.6), 6))
	_id_label = UiKit.title("---", 150, UiKit.ACCENT, 22)
	_id_label.pivot_offset = Vector2(300, 80)
	v.add_child(_id_label)
	var how := UiKit.label("Students: tap MULTIPLAYER on the main menu and type this ID. They need to be on the same WiFi as this device.", 30, Color(1, 1, 1, 0.85), 0)
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	how.custom_minimum_size = Vector2(700, 0)
	v.add_child(how)
	_count_label = UiKit.title("", 44, Color.WHITE, 8)
	v.add_child(_count_label)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(fill)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	v.add_child(row)
	_close = UiKit.button("Close lobby", UiKit.BLUE, 38, Vector2(300, 110))
	_close.pressed.connect(_on_close)
	row.add_child(_close)
	_start = UiKit.button("Start!", UiKit.GOLD, 52, Vector2(360, 120))
	_start.pressed.connect(_on_start)
	row.add_child(_start)
	_end = UiKit.button("End game", UiKit.GOLD, 48, Vector2(360, 120))
	_end.pressed.connect(_on_end)
	row.add_child(_end)

	# --- Right card: who's in / the leaderboard ---
	var right := PanelContainer.new()
	right.position = Vector2(900, 90)
	right.custom_minimum_size = Vector2(950, 880)
	right.add_theme_stylebox_override("panel", UiKit.box(UiKit.PANEL_DARK, Color(0.3, 0.3, 0.32), 10, 8))
	add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 12)
	right.add_child(rv)
	_heading = UiKit.title("", 60, Color.WHITE, 10)
	rv.add_child(_heading)
	_sub = UiKit.label("", 28, Color(1, 1, 1, 0.65), 0)
	rv.add_child(_sub)
	rv.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(890, 690)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rv.add_child(scroll)
	_board = ClassBoard.new()
	_board.max_rows = 80
	_board.custom_minimum_size = Vector2(870, 0)
	_board.empty_text = "Nobody yet. Share the lobby ID!"
	scroll.add_child(_board)

	Lobby.players_changed.connect(_refresh)
	_refresh()


## Open a lobby for this saved custom set. Returns "" or what went wrong.
func open(set_id: String) -> String:
	var err := Lobby.host(set_id)
	_played = false
	_close_armed = false
	_refresh()
	return err


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	# The ID breathes a little so it reads as "the thing to look at".
	if not Lobby.match_on:
		_id_label.scale = Vector2.ONE * (1.0 + 0.025 * sin(_t * 2.4))


func _active_count() -> int:
	var n := 0
	for p in Lobby.players.values():
		if not p.get("left", false):
			n += 1
	return n


func _refresh() -> void:
	if _id_label == null:
		return
	_id_label.text = Lobby.pretty_id() if Lobby.is_host() else "---"
	_quiz_label.text = Lobby.quiz_title
	var n := _active_count()
	_count_label.text = "%d student%s in" % [n, "" if n == 1 else "s"]
	_start.visible = not Lobby.match_on
	_end.visible = Lobby.match_on
	_start.disabled = n == 0
	_start.text = "New game" if _played else "Start!"
	_board.show_scores = Lobby.match_on or _played
	if Lobby.match_on:
		var out := 0
		for p in Lobby.players.values():
			if p.get("out", false):
				out += 1
		_heading.text = "Live leaderboard"
		_sub.text = "%d playing, %d out. Late joiners start right away." % [n - out, out]
	elif _played:
		_heading.text = "Final standings"
		_sub.text = "Start a new game with the same students, or close the lobby."
	else:
		_heading.text = "Waiting for students..."
		_sub.text = "Names show up here as students join."
	_board.refresh()


func _on_start() -> void:
	_close_armed = false
	_close.text = "Close lobby"
	Lobby.start_match()
	_refresh()


func _on_end() -> void:
	Lobby.end_match()
	_played = true
	_refresh()


## Two presses so a stray tap doesn't drop the whole class.
func _on_close() -> void:
	if not _close_armed and Lobby.players.size() > 0:
		_close_armed = true
		_close.text = "Sure?"
		return
	_close_armed = false
	_close.text = "Close lobby"
	Lobby.close()
	closed.emit()
