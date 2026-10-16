extends Node3D
## All front-end screens, drawn over a live 3D view of the SK Court:
## main menu -> choose game mode -> select character -> select weapon -> run.
## Each panel has its own camera shot; switching panels glides the camera.

## Where the selected character stands on the court for the close-ups.
const PREVIEW_POS := Vector3(4.0, 0.0, -12.0)

const SHOTS := {
	"main": {"pos": Vector3(7.0, 4.2, -2.0), "look": Vector3(-2.5, 1.2, -24.0), "sway": 1.0},
	"mode": {"pos": Vector3(-8.5, 2.6, -11.0), "look": Vector3(4.0, 2.2, -26.0), "sway": 1.0},
	"settings": {"pos": Vector3(0.0, 10.0, 6.0), "look": Vector3(0.0, 0.0, -18.0), "sway": 1.0},
	"credits": {"pos": Vector3(7.0, 2.2, -32.0), "look": Vector3(0.0, 4.5, -43.0), "sway": 1.0},
	# Worm's-eye: a wide lens almost on the ground, right of the (flat) cutout and
	# looking up past it, so its right side looms close and the left recedes.
	"character": {"pos": Vector3(4.5, 0.28, -10.55), "look": Vector3(2.75, 1.15, -12.6), "sway": 0.05, "fov": 80.0},
	"weapon": {"pos": Vector3(3.65, 0.95, -10.3), "look": Vector3(3.55, 0.85, -12.0), "sway": 0.08},
}

## Where Back / Esc goes from each panel.
const BACK_OF := {
	"mode": "main", "settings": "main", "credits": "main",
	"character": "mode", "weapon": "character",
}

const CHARACTER_PIXEL := 0.08 ## metres per pixel: 22 px tall -> 1.76 m
## Lens for shots that don't set their own "fov".
const DEFAULT_FOV := 70.0
const SLIPPER_PIXEL := 0.045

var cam_pos := Vector3.ZERO
var cam_look := Vector3.ZERO
var cam_sway := 1.0
var cam_fov := DEFAULT_FOV

var _time := 0.0
var _tween: Tween
var _panels := {}
var _current := ""
var _selected_theme := ""
var _theme_buttons := {}
var _board_title: Label
var _board_rows: Array[Label] = []
var _continue_btn: Button
var _pickers := {} ## "character" / "weapon" -> picker state
var _char_sprite: Sprite3D
var _char_look := {}
var _custom_id := "" ## custom set open in the editor ("" = new, unsaved)
var _custom_list: VBoxContainer
var _custom_title: LineEdit
var _custom_text: TextEdit
var _custom_status: Label
var _custom_delete: Button
var _delete_armed := false
var _file_dialog: FileDialog
var _help_dialog: AcceptDialog
var _char_state := "idle"
var _char_state_since := 0.0
var _char_happy_left := 0.0
var _slipper_sprite: Sprite3D

@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_preview()
	var ui := CanvasLayer.new()
	add_child(ui)
	_panels["main"] = _build_main(ui)
	_panels["mode"] = _build_mode(ui)
	_panels["character"] = _build_picker(ui, "character", "Select character", "NEXT >",
			func(): _confirm_pick("character", "weapon"))
	_panels["weapon"] = _build_picker(ui, "weapon", "Select weapon...", "GO >",
			func(): _confirm_pick("weapon", ""))
	_panels["settings"] = _build_simple(ui, "Settings", "Audio, graphics, controls and language\nare coming in the polish pass.")
	_panels["credits"] = _build_simple(ui, "Credits", "Tumbang Henyo\n\nGame design, art and code by the Tumbang Henyo team.")
	_select_theme(GameManager.selected_theme)
	_show("main", true)


func _process(delta: float) -> void:
	_time += delta
	# Slow handheld-style drift so the barangay feels alive behind the menu.
	var sway := Vector3(sin(_time * 0.17) * 0.8, sin(_time * 0.11) * 0.25, cos(_time * 0.13) * 0.5) * cam_sway
	_camera.global_position = cam_pos + sway
	_camera.look_at(cam_look, Vector3.UP)
	# The tsinelas floats and wobbles beside the character.
	_slipper_sprite.position.y = 0.78 + sin(_time * 2.4) * 0.04
	_slipper_sprite.rotation.z = deg_to_rad(-28.0 + sin(_time * 1.7) * 6.0)
	_camera.fov = cam_fov
	# The character on the stand loops idle, or happy for a moment after a pick.
	if _char_happy_left > 0.0:
		_char_happy_left -= delta
		if _char_happy_left <= 0.0:
			_set_char_sheet("idle")
	if not _char_look.is_empty():
		var sheet: Dictionary = _char_look[_char_state]
		_char_sprite.frame = int((_time - _char_state_since) * sheet.fps) % _char_sprite.hframes


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		if BACK_OF.has(_current):
			_show(BACK_OF[_current])
	elif _pickers.has(_current):
		if event.is_action_pressed("ui_left") or event.is_action_pressed("move_left"):
			_browse(_current, -1)
		elif event.is_action_pressed("ui_right") or event.is_action_pressed("move_right"):
			_browse(_current, 1)


func _show(panel_id: String, instant: bool = false) -> void:
	_current = panel_id
	for key in _panels:
		_panels[key].visible = key == panel_id
	_slipper_sprite.visible = panel_id == "weapon"
	if _pickers.has(panel_id):
		_open_picker(panel_id)
	var shot: Dictionary = SHOTS[panel_id]
	if _tween:
		_tween.kill()
	var fov: float = shot.get("fov", DEFAULT_FOV)
	if instant:
		cam_pos = shot.pos
		cam_look = shot.look
		cam_sway = shot.sway
		cam_fov = fov
		return
	_tween = create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(self, "cam_pos", shot.pos, 1.2)
	_tween.tween_property(self, "cam_look", shot.look, 1.2)
	_tween.tween_property(self, "cam_sway", shot.sway, 1.2)
	_tween.tween_property(self, "cam_fov", fov, 1.2)


# --- 3D preview on the court ------------------------------------------------------

func _build_preview() -> void:
	var stand := Node3D.new()
	stand.position = PREVIEW_POS
	add_child(stand)
	_char_sprite = _pixel_sprite(CHARACTER_PIXEL)
	stand.add_child(_char_sprite)
	# Soft shadow on the court under the cutout.
	var shadow := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.6
	disc.bottom_radius = 0.6
	disc.height = 0.01
	shadow.mesh = disc
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.1, 0.05, 0.15, 0.3)
	shadow.material_override = mat
	shadow.scale = Vector3(1.3, 1.0, 0.8)
	shadow.position = Vector3(0.15, 0.04, -0.1)
	stand.add_child(shadow)
	_slipper_sprite = _pixel_sprite(SLIPPER_PIXEL)
	_slipper_sprite.position = Vector3(0.45, 0.78, 0.35)
	stand.add_child(_slipper_sprite)
	_set_char_preview(Economy.find_item("character", Economy.equipped_character))
	_slipper_sprite.texture = PixelArt.slipper(Economy.slipper_palette())


## Show a character on the stand: its front sheet (animated if it has frames),
## feet on the ground.
func _set_char_preview(item: Dictionary) -> void:
	_char_look = PixelArt.character_look(item)
	var px: float = _char_look.pixel_size
	_char_sprite.pixel_size = px
	_char_sprite.position = Vector3(0.0, _char_look.frame_h * px * 0.5 - _char_look.foot_pad * px, 0.0)
	_char_happy_left = 0.0
	_set_char_sheet("idle")


func _set_char_sheet(state: String) -> void:
	var sheet: Dictionary = _char_look[state]
	_char_state = state
	_char_state_since = _time
	_char_sprite.frame = 0
	_char_sprite.texture = sheet.texture
	_char_sprite.hframes = maxi(sheet.frames, 1)


## The character on the stand cheers (bought or picked).
func _char_celebrate(seconds: float = 1.6) -> void:
	_char_happy_left = seconds
	_set_char_sheet("happy")


func _pixel_sprite(pixel_size: float) -> Sprite3D:
	var s := Sprite3D.new()
	s.pixel_size = pixel_size
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.shaded = false
	s.double_sided = true
	return s


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
		["QUIT", func(): Transition.quit()],
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
	_board_rows.clear()
	for i in 7:
		var row := UiKit.label("%d    ---" % (i + 1), 44, rank_colors[i] if i < 3 else Color.WHITE, 0)
		v.add_child(row)
		_board_rows.append(row)
	v.add_child(UiKit.label("Your best runs on this device. Online boards come later.", 24, Color(1, 1, 1, 0.65)))

	# Bottom buttons: back, continue (only with a saved run), next.
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
	var next := UiKit.button("NEXT >", UiKit.GOLD, 48, Vector2(320, 110))
	next.pressed.connect(func(): _show("character"))
	row_btns.add_child(next)
	return root


func _select_theme(theme_id: String) -> void:
	_selected_theme = theme_id
	GameManager.selected_theme = theme_id
	for id in _theme_buttons:
		UiKit.set_fill(_theme_buttons[id], UiKit.CYAN, id == theme_id)
	_board_title.text = "Leaderboards  -  %s" % GameManager.theme_name(theme_id)
	_continue_btn.visible = GameManager.has_saved_run(theme_id)
	_fill_board(theme_id)


func _fill_board(theme_id: String) -> void:
	var entries := GameManager.local_board(theme_id)
	for i in _board_rows.size():
		if i < entries.size():
			var e: Dictionary = entries[i]
			_board_rows[i].text = "%d    %s    %d  (R%d)" % [i + 1, e.name, e.score, e.rounds]
		else:
			_board_rows[i].text = "%d    ---" % (i + 1)


# --- Custom quiz (player-made question sets) -----------------------------------

func _build_custom(ui: CanvasLayer) -> Control:
	var root := UiKit.full_rect()
	ui.add_child(root)
	var title := UiKit.label("Custom quiz", 72, Color.WHITE, 16)
	title.position = Vector2(30, 10)
	root.add_child(title)

	# Left: saved sets.
	var left := VBoxContainer.new()
	left.position = Vector2(40, 130)
	left.add_theme_constant_override("separation", 18)
	root.add_child(left)
	var new_btn := UiKit.button("+ NEW SET", UiKit.CYAN, 40, Vector2(540, 96))
	new_btn.pressed.connect(_new_custom)
	left.add_child(new_btn)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 660)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	_custom_list = VBoxContainer.new()
	_custom_list.add_theme_constant_override("separation", 14)
	scroll.add_child(_custom_list)

	# Right: editor.
	var panel := PanelContainer.new()
	panel.position = Vector2(640, 110)
	panel.custom_minimum_size = Vector2(1240, 800)
	panel.add_theme_stylebox_override("panel", UiKit.box(UiKit.PANEL_DARK, Color(0.3, 0.3, 0.32), 10, 4))
	root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	_custom_title = LineEdit.new()
	_custom_title.placeholder_text = "Set name, e.g. Grade 6 Science - Quarter 2"
	_custom_title.custom_minimum_size = Vector2(0, 72)
	_custom_title.add_theme_font_size_override("font_size", 34)
	v.add_child(_custom_title)
	_custom_text = TextEdit.new()
	_custom_text.placeholder_text = CustomQuiz.HELP
	_custom_text.custom_minimum_size = Vector2(0, 500)
	_custom_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_custom_text.add_theme_font_size_override("font_size", 26)
	_custom_text.text_changed.connect(_validate_custom)
	v.add_child(_custom_text)
	_custom_status = UiKit.label("", 26, Color.WHITE, 0)
	_custom_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_custom_status.custom_minimum_size = Vector2(1200, 110)
	v.add_child(_custom_status)
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 20)
	v.add_child(tools)
	var help := UiKit.button("FORMAT HELP", UiKit.BLUE, 30, Vector2(300, 70))
	help.pressed.connect(_show_custom_help)
	tools.add_child(help)
	var open := UiKit.button("OPEN FILE", UiKit.BLUE, 30, Vector2(300, 70))
	open.pressed.connect(_open_custom_file)
	tools.add_child(open)
	_custom_delete = UiKit.button("DELETE", UiKit.BLUE, 30, Vector2(260, 70))
	_custom_delete.pressed.connect(_delete_custom)
	tools.add_child(_custom_delete)

	# Bottom: back, save, play.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.position = Vector2(940, 935)
	root.add_child(row)
	var back := UiKit.button("< BACK", UiKit.BLUE, 44, Vector2(250, 110))
	back.pressed.connect(func(): _show("mode"))
	row.add_child(back)
	var save := UiKit.button("SAVE", UiKit.BLUE, 44, Vector2(250, 110))
	save.pressed.connect(_save_custom)
	row.add_child(save)
	var play := UiKit.button("PLAY >", UiKit.GOLD, 48, Vector2(320, 110))
	play.pressed.connect(_play_custom)
	row.add_child(play)

	# File picker: the phone's/PC's own dialog where available.
	_file_dialog = FileDialog.new()
	_file_dialog.use_native_dialog = true
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.filters = PackedStringArray(["*.txt, *.csv, *.docx ; Question files"])
	_file_dialog.file_selected.connect(_on_custom_file)
	root.add_child(_file_dialog)
	_help_dialog = AcceptDialog.new()
	_help_dialog.title = "Question format"
	_help_dialog.dialog_text = CustomQuiz.HELP
	root.add_child(_help_dialog)
	return root


func _enter_custom() -> void:
	_delete_armed = false
	_refresh_custom_list()
	if _custom_id == "":
		var sets := CustomQuiz.list_sets()
		if sets.is_empty():
			_new_custom()
		else:
			_load_custom(sets[0].id)


func _refresh_custom_list() -> void:
	for c in _custom_list.get_children():
		c.queue_free()
	for s in CustomQuiz.list_sets():
		var b := UiKit.button("%s  (%d)" % [s.title, s.count], UiKit.CYAN, 30, Vector2(540, 84))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		UiKit.set_fill(b, UiKit.CYAN, s.id == _custom_id)
		b.pressed.connect(_load_custom.bind(s.id))
		_custom_list.add_child(b)


func _new_custom() -> void:
	_custom_id = ""
	_custom_title.text = ""
	_custom_text.text = ""
	_delete_armed = false
	_custom_delete.disabled = true
	_validate_custom()
	_refresh_custom_list()


func _load_custom(set_id: String) -> void:
	var data := CustomQuiz.load_text(set_id)
	if data.is_empty():
		return
	_custom_id = set_id
	_custom_title.text = data.title
	_custom_text.text = data.text
	_delete_armed = false
	_custom_delete.disabled = false
	_custom_delete.text = "DELETE"
	_validate_custom()
	_refresh_custom_list()


## Check the text as the player types and say what's ready / what to fix.
func _validate_custom() -> Dictionary:
	var r := CustomQuiz.parse(_custom_text.text)
	var ok: int = r.questions.size()
	var bad: int = r.errors.size()
	var msg := ""
	var color := Color(0.55, 1.0, 0.6)
	if _custom_text.text.strip_edges() == "":
		msg = "Paste or type your questions, or OPEN FILE (.txt, .csv, Word). Tap FORMAT HELP for an example."
		color = Color(1, 1, 1, 0.75)
	elif ok > 0 and bad == 0:
		msg = "%d question%s ready." % [ok, "" if ok == 1 else "s"]
	else:
		color = Color(1.0, 0.82, 0.4) if ok > 0 else Color(1.0, 0.5, 0.45)
		msg = "%d ready, %d to fix:  " % [ok, bad] + "   ".join(r.errors.slice(0, 2))
		if bad > 2:
			msg += "  (+%d more)" % (bad - 2)
	_custom_status.text = msg
	_custom_status.add_theme_color_override("font_color", color)
	return r


func _save_custom() -> bool:
	if _custom_text.text.strip_edges() == "":
		_custom_status.text = "Nothing to save yet."
		return false
	if _custom_title.text.strip_edges() == "":
		_custom_title.text = "My quiz %d" % (CustomQuiz.list_sets().size() + 1)
	_custom_id = CustomQuiz.save_set(_custom_title.text, _custom_text.text, _custom_id)
	_custom_delete.disabled = false
	_refresh_custom_list()
	_validate_custom()
	_custom_status.text += "  Saved."
	return true


func _play_custom() -> void:
	var r := _validate_custom()
	if r.questions.is_empty():
		return
	if not _save_custom():
		return
	CustomQuiz.activate(_custom_id)
	_select_theme(CustomQuiz.theme_id(_custom_id))
	_show("character")


## Two presses: DELETE, then SURE? (like BUY -> CONFIRM).
func _delete_custom() -> void:
	if _custom_id == "":
		return
	if not _delete_armed:
		_delete_armed = true
		_custom_delete.text = "SURE?"
		return
	CustomQuiz.delete_set(_custom_id)
	_custom_delete.text = "DELETE"
	_new_custom()


func _show_custom_help() -> void:
	if _custom_text.text.strip_edges() == "":
		# Empty editor: drop the example in so it can be edited directly.
		var parts := CustomQuiz.HELP.split("\n\n")
		_custom_text.text = "\n\n".join(parts.slice(1, 4))
		_validate_custom()
	else:
		_help_dialog.popup_centered(Vector2i(900, 640))


func _open_custom_file() -> void:
	_file_dialog.popup_centered_ratio(0.7)


func _on_custom_file(path: String) -> void:
	var result := CustomQuiz.read_file(path)
	if result.error != "":
		_custom_status.text = result.error
		_custom_status.add_theme_color_override("font_color", Color(1.0, 0.5, 0.45))
		return
	if _custom_id != "" or _custom_text.text.strip_edges() != "":
		_new_custom()
	_custom_text.text = result.text
	if _custom_title.text == "":
		_custom_title.text = path.get_file().get_basename()
	_validate_custom()


# --- Character / weapon select ----------------------------------------------------

func _build_picker(ui: CanvasLayer, kind: String, heading: String, next_text: String, on_next: Callable) -> Control:
	var root := UiKit.full_rect()
	ui.add_child(root)
	var p := {"items": Economy.catalog("character" if kind == "character" else "slipper"), "index": 0, "confirm": false}

	var title := UiKit.label(heading, 72, Color.WHITE, 16)
	title.position = Vector2(90, 50)
	root.add_child(title)

	p.caps = UiKit.label("", 44, Color(1.0, 0.86, 0.35), 10)
	p.caps.position = Vector2(1440, 60)
	root.add_child(p.caps)

	var panel := PanelContainer.new()
	panel.position = Vector2(80, 210)
	panel.custom_minimum_size = Vector2(620, 700)
	panel.add_theme_stylebox_override("panel", UiKit.box(Color(0.35, 0.35, 0.38, 0.72), Color(0.3, 0.3, 0.32), 10, 4))
	root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	panel.add_child(v)
	p.name = UiKit.label("", 80, Color.WHITE, 12)
	v.add_child(p.name)
	v.add_child(UiKit.label("- " + ("Character" if kind == "character" else "Weapon") + " description", 40, Color.WHITE, 10))
	p.desc = UiKit.label("", 34, Color.WHITE, 6)
	p.desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p.desc.custom_minimum_size = Vector2(560, 0)
	p.desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(p.desc)
	p.status = UiKit.label("", 36, Color(1.0, 0.86, 0.35), 8)
	v.add_child(p.status)
	p.buy = UiKit.button("BUY", UiKit.GOLD, 40, Vector2(400, 100))
	p.buy.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	p.buy.pressed.connect(_on_buy.bind(kind))
	v.add_child(p.buy)

	# Browse arrows on either side of the character.
	var left := UiKit.button("<", UiKit.BLUE, 64, Vector2(120, 120))
	left.position = Vector2(960, 480)
	left.pressed.connect(_browse.bind(kind, -1))
	root.add_child(left)
	var right := UiKit.button(">", UiKit.BLUE, 64, Vector2(120, 120))
	right.position = Vector2(1740, 480)
	right.pressed.connect(_browse.bind(kind, 1))
	root.add_child(right)

	var back := UiKit.button("< BACK", UiKit.BLUE, 44, Vector2(250, 110))
	back.position = Vector2(80, 940)
	back.pressed.connect(func(): _show(BACK_OF[kind]))
	root.add_child(back)
	p.next = UiKit.button(next_text, UiKit.GOLD, 56, Vector2(340, 120))
	p.next.position = Vector2(1540, 920)
	p.next.pressed.connect(on_next)
	root.add_child(p.next)

	_pickers[kind] = p
	return root


## Start the picker on the item that's currently equipped.
func _open_picker(kind: String) -> void:
	var p: Dictionary = _pickers[kind]
	var equipped_id := Economy.equipped("character" if kind == "character" else "slipper")
	for i in p.items.size():
		if p.items[i].id == equipped_id:
			p.index = i
	p.confirm = false
	_refresh_picker(kind)


func _browse(kind: String, step: int) -> void:
	var p: Dictionary = _pickers[kind]
	p.index = wrapi(p.index + step, 0, p.items.size())
	p.confirm = false
	_refresh_picker(kind)


func _refresh_picker(kind: String) -> void:
	var p: Dictionary = _pickers[kind]
	var item: Dictionary = p.items[p.index]
	var owned := Economy.owns(item.id)
	p.name.text = item.name
	p.desc.text = item.desc
	p.caps.text = "Tansan: %d" % Economy.caps
	if owned:
		p.status.text = "Equipped" if Economy.equipped(_slot(kind)) == item.id else "Owned"
	else:
		p.status.text = "Locked  -  %d tansan" % item.price
	p.buy.visible = not owned
	p.buy.disabled = not Economy.can_afford(item.price)
	p.buy.text = ("CONFIRM  -%d" % item.price) if p.confirm else ("BUY  %d" % item.price)
	if p.buy.disabled:
		p.buy.text = "NEED %d MORE" % (item.price - Economy.caps)
	p.next.disabled = not owned

	# Show it on the court; locked items are shown as a dark silhouette.
	var tint := Color.WHITE if owned else Color(0.25, 0.25, 0.3)
	if kind == "character":
		_set_char_preview(item)
		_char_sprite.modulate = tint
	else:
		_slipper_sprite.texture = PixelArt.slipper(item.palette)
		_slipper_sprite.modulate = tint


func _on_buy(kind: String) -> void:
	var p: Dictionary = _pickers[kind]
	var item: Dictionary = p.items[p.index]
	if not p.confirm:
		p.confirm = true # first press asks to confirm
	elif Economy.buy(item.id, item.price):
		p.confirm = false
		Economy.equip(_slot(kind), item.id)
		_refresh_picker(kind)
		if kind == "character":
			_char_celebrate()
		return
	_refresh_picker(kind)


## Equip the shown item and move on (to weapon select, or into the run).
func _confirm_pick(kind: String, next_panel: String) -> void:
	var p: Dictionary = _pickers[kind]
	var item: Dictionary = p.items[p.index]
	if not Economy.owns(item.id):
		return
	Economy.equip(_slot(kind), item.id)
	if kind == "character":
		_char_celebrate() # cheers while the camera moves to weapon select
	if next_panel == "":
		GameManager.start_run(_selected_theme)
	else:
		_show(next_panel)


func _slot(kind: String) -> String:
	return "character" if kind == "character" else "slipper"


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
