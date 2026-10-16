extends Node3D
## Main menu and game mode select, drawn over a live 3D view of the SK Court.
## Each panel has its own camera shot; switching panels glides the camera.
## Character and weapon select will slot in here as more panels.

const SHOTS := {
	"main": {"pos": Vector3(7.0, 4.2, -2.0), "look": Vector3(-2.5, 1.2, -24.0)},
	"mode": {"pos": Vector3(-8.5, 2.6, -11.0), "look": Vector3(4.0, 2.2, -26.0)},
	"settings": {"pos": Vector3(0.0, 10.0, 6.0), "look": Vector3(0.0, 0.0, -18.0)},
	"credits": {"pos": Vector3(7.0, 2.2, -32.0), "look": Vector3(0.0, 4.5, -43.0)},
}

var cam_pos := Vector3.ZERO
var cam_look := Vector3.ZERO

var _time := 0.0
var _tween: Tween
var _panels := {}
var _selected_theme := ""
var _theme_buttons := {}
var _board_title: Label
var _board_rows: Array[Label] = []
var _continue_btn: Button

@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var ui := CanvasLayer.new()
	add_child(ui)
	_panels["main"] = _build_main(ui)
	_panels["mode"] = _build_mode(ui)
	_panels["settings"] = _build_simple(ui, "Settings", "Audio, graphics, controls and language\nare coming in the polish pass.")
	_panels["credits"] = _build_simple(ui, "Credits", "Tumbang Henyo\n\nGame design, art and code by the Tumbang Henyo team.")
	_select_theme(GameManager.selected_theme)
	_show("main", true)


func _process(delta: float) -> void:
	_time += delta
	# Slow handheld-style drift so the barangay feels alive behind the menu.
	var sway := Vector3(sin(_time * 0.17) * 0.8, sin(_time * 0.11) * 0.25, cos(_time * 0.13) * 0.5)
	_camera.global_position = cam_pos + sway
	_camera.look_at(cam_look, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if (event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")) and not _panels["main"].visible:
		_show("main")


func _show(panel_id: String, instant: bool = false) -> void:
	for key in _panels:
		_panels[key].visible = key == panel_id
	var shot: Dictionary = SHOTS[panel_id]
	if _tween:
		_tween.kill()
	if instant:
		cam_pos = shot.pos
		cam_look = shot.look
		return
	_tween = create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(self, "cam_pos", shot.pos, 1.2)
	_tween.tween_property(self, "cam_look", shot.look, 1.2)


# --- Main menu ----------------------------------------------------------------

func _build_main(ui: CanvasLayer) -> Control:
	var root := UiKit.full_rect()
	ui.add_child(root)

	var logo := UiKit.label("Logo", 120, Color.WHITE, 18)
	logo.position = Vector2(240, 150)
	root.add_child(logo)
	var title := UiKit.label("Tumbang\n      Henyo", 96, Color(0.1, 0.08, 0.06), 0)
	title.add_theme_color_override("font_outline_color", Color.WHITE)
	title.add_theme_constant_override("outline_size", 16)
	title.position = Vector2(120, 340)
	root.add_child(title)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 36)
	col.position = Vector2(1280, 135)
	root.add_child(col)
	var entries := [
		["START", func(): _show("mode")],
		["SETTINGS", func(): _show("settings")],
		["CREDITS", func(): _show("credits")],
		["QUIT", func(): get_tree().quit()],
	]
	for e in entries:
		var b := UiKit.button(e[0], UiKit.BLUE, 64, Vector2(540, 140))
		b.pressed.connect(e[1])
		col.add_child(b)
	return root


# --- Choose game mode -----------------------------------------------------------

func _build_mode(ui: CanvasLayer) -> Control:
	var root := UiKit.full_rect()
	ui.add_child(root)

	var title := UiKit.label("Choose gamemode", 72, Color.WHITE, 16)
	title.position = Vector2(30, 10)
	root.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(40, 130)
	scroll.size = Vector2(780, 800)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 34)
	list.custom_minimum_size = Vector2(720, 0)
	scroll.add_child(list)
	for t in GameManager.THEMES:
		var b := UiKit.button(t.name.to_upper(), UiKit.CYAN, 72, Vector2(700, 160))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_select_theme.bind(t.id))
		list.add_child(b)
		_theme_buttons[t.id] = b

	# Leaderboard panel.
	var board := PanelContainer.new()
	board.position = Vector2(940, 110)
	board.custom_minimum_size = Vector2(930, 790)
	board.add_theme_stylebox_override("panel", UiKit.box(UiKit.PANEL_DARK, Color(0.3, 0.3, 0.32), 10, 4))
	root.add_child(board)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	board.add_child(v)
	_board_title = UiKit.label("Leaderboards", 60, Color.WHITE, 0)
	v.add_child(_board_title)
	v.add_child(HSeparator.new())
	var rank_colors := [Color(1.0, 0.85, 0.35), Color(0.85, 0.85, 0.9), Color(0.85, 0.7, 0.75)]
	for i in 7:
		var row := UiKit.label("%d    ---" % (i + 1), 44, rank_colors[i] if i < 3 else Color.WHITE, 0)
		v.add_child(row)
		_board_rows.append(row)
	v.add_child(UiKit.label("Online scores appear here once the leaderboard is live.", 24, Color(1, 1, 1, 0.65)))

	# Bottom buttons: back, continue (only with a saved run), play.
	var row_btns := HBoxContainer.new()
	row_btns.add_theme_constant_override("separation", 24)
	row_btns.position = Vector2(940, 935)
	root.add_child(row_btns)
	var back := UiKit.button("< BACK", UiKit.BLUE, 44, Vector2(250, 110))
	back.pressed.connect(func(): _show("main"))
	row_btns.add_child(back)
	_continue_btn = UiKit.button("CONTINUE", UiKit.BLUE, 44, Vector2(300, 110))
	_continue_btn.pressed.connect(func(): GameManager.start_run(_selected_theme))
	row_btns.add_child(_continue_btn)
	var play := UiKit.button("PLAY >", UiKit.GOLD, 48, Vector2(320, 110))
	play.pressed.connect(func(): GameManager.start_run(_selected_theme))
	row_btns.add_child(play)
	return root


func _select_theme(theme_id: String) -> void:
	_selected_theme = theme_id
	GameManager.selected_theme = theme_id
	for id in _theme_buttons:
		UiKit.set_fill(_theme_buttons[id], UiKit.CYAN, id == theme_id)
	_board_title.text = "Leaderboards  -  %s" % GameManager.theme_name(theme_id)
	_continue_btn.visible = GameManager.has_saved_run(theme_id)


# --- Settings / credits placeholders -------------------------------------------

func _build_simple(ui: CanvasLayer, heading: String, body: String) -> Control:
	var root := UiKit.full_rect()
	ui.add_child(root)
	var panel := PanelContainer.new()
	panel.position = Vector2(560, 220)
	panel.custom_minimum_size = Vector2(800, 520)
	panel.add_theme_stylebox_override("panel", UiKit.box(UiKit.PANEL_DARK, Color(0.3, 0.3, 0.32), 10, 4))
	root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 30)
	panel.add_child(v)
	v.add_child(UiKit.label(heading, 72, Color.WHITE, 12))
	var text := UiKit.label(body, 36)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(text)
	var back := UiKit.button("< BACK", UiKit.BLUE, 44, Vector2(250, 110))
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(func(): _show("main"))
	v.add_child(back)
	return root
