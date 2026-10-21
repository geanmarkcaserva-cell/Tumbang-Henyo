extends Node3D
## All front-end screens, drawn over a live 3D view of the SK Court:
## main menu -> choose game mode -> select character -> select weapon -> run.
## Each panel has its own camera shot; switching panels glides the camera.

## Character select is a lobby, like Soul Knight's: every playable character
## stands somewhere on the court, idling, and browsing glides the camera over
## to whoever you're looking at. Locked ones stand there too, a little dimmer.
## Where each one stands, left to right as the camera sees them (so < and >
## glide the camera left and right). Proktoy, the starter, stands up front;
## GM and Ashiela stand together at the back: they're a couple. Anyone not
## listed here takes a FREE_SPOT.
const LOBBY_PLACES := {
	"kei": Vector3(-7.0, 0.0, -9.5), "lisa": Vector3(-5.2, 0.0, -23.0), "badette": Vector3(-3.2, 0.0, -12.5),
	"gm": Vector3(-1.6, 0.0, -28.2), "ashiela": Vector3(-0.3, 0.0, -28.8), "migo": Vector3(1.0, 0.0, -13.0),
	"proktoy": Vector3(2.8, 0.0, -6.8), "saisai": Vector3(4.6, 0.0, -24.5),
}
const FREE_SPOTS := [Vector3(-6.5, 0.0, -38.5), Vector3(6.5, 0.0, -38.0), Vector3(-7.5, 0.0, -31.0), Vector3(7.5, 0.0, -17.5)]
## Close-up on a lobby character: camera and look-at point, relative to their
## spot (the look point sits to their left so they stand right of the panel).
const CHAR_CAM := Vector3(1.0, 1.15, 3.0)
const CHAR_LOOK := Vector3(-0.6, 0.95, 0.0)
const CHAR_FOV := 50.0
## Weapon select: just in front of the chosen character, slipper floating beside.
const WEAPON_CAM := Vector3(-0.5, 1.05, 2.7)
const WEAPON_LOOK := Vector3(-0.35, 0.9, 0.0)
const LOCKED_TINT := Color(0.45, 0.45, 0.52)

const SHOTS := {
	"main": {"pos": Vector3(7.0, 4.2, -2.0), "look": Vector3(-2.5, 1.2, -24.0), "sway": 1.0},
	"mode": {"pos": Vector3(-8.5, 2.6, -11.0), "look": Vector3(4.0, 2.2, -26.0), "sway": 1.0},
	"custom": {"pos": Vector3(-9.0, 7.5, -4.0), "look": Vector3(3.0, 0.0, -24.0), "sway": 0.7},
	"settings": {"pos": Vector3(0.0, 10.0, 6.0), "look": Vector3(0.0, 0.0, -18.0), "sway": 1.0},
	"join": {"pos": Vector3(-6.5, 3.4, 1.0), "look": Vector3(1.5, 1.5, -26.0), "sway": 1.0},
	"host": {"pos": Vector3(8.5, 2.4, -6.0), "look": Vector3(-3.0, 2.0, -28.0), "sway": 0.8},
	"achievements": {"pos": Vector3(0.0, 1.6, -34.0), "look": Vector3(0.0, 3.0, -10.0), "sway": 0.8},
	"account": {"pos": Vector3(-7.5, 1.9, -20.0), "look": Vector3(6.0, 2.4, -31.0), "sway": 0.8},
	"collection": {"pos": Vector3(9.0, 5.5, -14.0), "look": Vector3(-14.0, 3.0, -10.0), "sway": 0.8},
	# "character" and "weapon" follow the lobby character: see _shot().
}

## Where Back / Esc goes from each panel.
const BACK_OF := {
	"mode": "main", "settings": "main", "credits": "main", "custom": "mode", "achievements": "main",
	"account": "main", "collection": "main",
	"character": "mode", "weapon": "character",
}

const CHARACTER_PIXEL := 0.08 ## metres per pixel: 22 px tall -> 1.76 m
## Lens for shots that don't set their own "fov".
const DEFAULT_FOV := 70.0

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
var _lobby := {} ## character id -> {root, sprite, look, state, since, happy}
var _focus_id := "" ## the lobby character the camera is on
var _custom_id := "" ## custom set open in the editor ("" = new, unsaved)
var _custom_list: VBoxContainer
var _custom_title: LineEdit
var _custom_text: TextEdit
var _custom_status: Label
var _custom_delete: Button
var _host_panel: HostPanel
var _join_panel: JoinPanel
var _account_panel: AccountPanel
var _ach_panel: AchievementsPanel
var _collection_panel: CollectionPanel
var _team := [] ## credits: {member, root, sprite, look, phase} for each team member
var _credit_i := 0 ## 0 = the whole team, 1.. = one member
var _credit_auto := 0.0 ## seconds until the next member
var _credit_card := {}
const CREDIT_STEP := 6.5 ## seconds on each member before moving on
## Credits: the whole team, from the street south of them.
const TEAM_SHOT := {"pos": Vector3(-16.6, 3.0, -28.4), "look": Vector3(-17.9, 0.8, -36.6), "sway": 0.2, "fov": 72.0}
## Close-up on one member (relative to their spot): straight on, them right of the card.
const TEAM_CAM := Vector3(0.3, 1.15, 2.8)
const TEAM_LOOK := Vector3(-0.7, 0.95, 0.0)
var _ach_back := "main" ## achievements opened from the main menu or from an account card
var _account_chip: Button
var _delete_armed := false
var _file_dialog: FileDialog
var _help_dialog: AcceptDialog
var _ai_dialog: AcceptDialog
## The slipper in weapon select is drawn in 2D (over the court) so its
## pixel art keeps its exact colours; the 3D view's tone mapping would
## darken and wash it out.
var _slipper_icon: TextureRect
var _logo: TextureRect
const SLIPPER_ICON_SCALE := 14.0 ## screen pixels per art pixel
const SLIPPER_ICON_CENTER := Vector2(1500, 560)

@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Music.play("menu")
	# No taya guarding the lata out here: the lobby is the barkada's.
	var taya := get_node_or_null("Arena/Taya")
	if taya:
		taya.queue_free()
	_build_lobby()
	_build_team()
	var ui := CanvasLayer.new()
	add_child(ui)
	_panels["main"] = _build_main(ui)
	_panels["mode"] = _build_mode(ui)
	_panels["custom"] = _build_custom(ui)
	_panels["character"] = _build_picker(ui, "character", "Select character", "Next",
			func(): _confirm_pick("character", "weapon"))
	_panels["weapon"] = _build_picker(ui, "weapon", "Select weapon", "Go!",
			func(): _confirm_pick("weapon", ""))
	_panels["settings"] = _build_settings(ui)
	_panels["credits"] = _build_credits(ui)
	_panels["join"] = _build_join(ui)
	_panels["host"] = _build_host(ui)
	_panels["achievements"] = _build_achievements(ui)
	_panels["account"] = _build_account(ui)
	_panels["collection"] = _build_collection(ui)
	# A bit smaller than the layouts were drawn, each piece toward its own edge.
	for key in _panels:
		UiFx.shrink(_panels[key])
	_select_theme(GameManager.selected_theme)
	# Back from a class game: straight to the lobby screen.
	if Lobby.is_host():
		_show("host", true)
	elif Lobby.is_client():
		_show("join", true)
	elif not Accounts.has_any():
		_show("account", true) # first launch: make an account before anything else
	else:
		_show("main", true)


func _process(delta: float) -> void:
	_time += delta
	# Slow handheld-style drift so the barangay feels alive behind the menu.
	var sway := Vector3(sin(_time * 0.17) * 0.8, sin(_time * 0.11) * 0.25, cos(_time * 0.13) * 0.5) * cam_sway
	_camera.global_position = cam_pos + sway
	_camera.look_at(cam_look, Vector3.UP)
	# The tsinelas floats and wobbles beside the character.
	if _slipper_icon:
		_slipper_icon.position.y = SLIPPER_ICON_CENTER.y - _slipper_icon.size.y * 0.5 + sin(_time * 2.4) * 10.0
		_slipper_icon.rotation = deg_to_rad(-28.0 + sin(_time * 1.7) * 6.0)
	_camera.fov = cam_fov
	# Everyone in the lobby loops idle; happy for a moment after a pick.
	for id in _lobby:
		var c: Dictionary = _lobby[id]
		if c.happy > 0.0:
			c.happy -= delta
			if c.happy <= 0.0:
				_set_sheet(id, "idle")
		var sheet: Dictionary = c.look[c.state]
		var spr: Sprite3D = c.sprite
		spr.frame = int((_time - float(c.since)) * sheet.fps) % spr.hframes
	for t in _team:
		var ts: Sprite3D = t.sprite
		ts.frame = int(_time * float(t.look.idle.fps) + float(t.phase)) % ts.hframes
	if _current == "credits" and _panels["credits"].visible:
		_credit_auto -= delta
		if _credit_auto <= 0.0:
			_credit_go(1)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		if _current == "account" and (_account_panel.cancel() or not Accounts.has_any()):
			return # closed the name box, or there's no account to go back with yet
		if BACK_OF.has(_current) and not (_current == "custom" and _custom_text.has_focus()):
			_show(_back_of(_current))


## Left/right browse in character and weapon select. Taken here, before the
## buttons see them, so the arrow keys don't just move the button focus.
func _input(event: InputEvent) -> void:
	if _current == "credits" and _panels["credits"].visible:
		if event.is_action_pressed("ui_left") or event.is_action_pressed("move_left"):
			_credit_go(-1)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_right") or event.is_action_pressed("move_right"):
			_credit_go(1)
			get_viewport().set_input_as_handled()
		return
	if not _pickers.has(_current) or not _panels[_current].visible:
		return
	if event.is_action_pressed("ui_left") or event.is_action_pressed("move_left"):
		_browse(_current, -1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("move_right"):
		_browse(_current, 1)
		get_viewport().set_input_as_handled()


## Back from character select returns to the custom editor when a custom
## set was picked.
func _back_of(panel_id: String) -> String:
	if panel_id == "character" and CustomQuiz.is_custom(_selected_theme):
		return "custom"
	if panel_id == "achievements":
		return _ach_back
	return BACK_OF[panel_id]


func _show(panel_id: String, instant: bool = false) -> void:
	var changed := panel_id != _current
	_current = panel_id
	if panel_id == "custom":
		_enter_custom()
	elif panel_id == "join":
		_join_panel.on_show()
	elif panel_id == "achievements":
		_ach_panel.refresh() # may be another account's trophies since last time
	elif panel_id == "account":
		_account_panel.refresh()
	elif panel_id == "collection":
		_collection_panel.refresh()
	if changed:
		for t in _team:
			(t.tag as Node3D).visible = true
	if panel_id == "credits" and changed:
		_credit_i = 0
		_credit_auto = 3.0 # a moment on the whole team, then the first close-up
		_fill_credit()
	for key in _panels:
		_panels[key].visible = key == panel_id
	if _pickers.has(panel_id):
		_open_picker(panel_id)
	if changed and not instant:
		Sfx.play("ui_whoosh") # the camera glides to the next spot on the court
	if changed:
		# The new panel springs in piece by piece; the logo drops in on its own.
		UiFx.pop_in(_panels[panel_id], 0.05)
		if panel_id == "main":
			UiFx.logo_intro(_logo, 0.0)
	_glide(_shot(panel_id), instant)


## The camera shot for a panel: fixed ones from SHOTS; character and weapon
## select look at the lobby character in focus.
func _shot(panel_id: String) -> Dictionary:
	if panel_id == "character" or panel_id == "weapon":
		if _focus_id == "" or not _lobby.has(_focus_id):
			_focus_id = Economy.equipped_character if _lobby.has(Economy.equipped_character) else _lobby.keys()[0]
		var at: Vector3 = (_lobby[_focus_id].root as Node3D).position
		if panel_id == "character":
			return {"pos": at + CHAR_CAM, "look": at + CHAR_LOOK, "sway": 0.06, "fov": CHAR_FOV}
		return {"pos": at + WEAPON_CAM, "look": at + WEAPON_LOOK, "sway": 0.08}
	if panel_id == "credits":
		if _credit_i == 0 or _credit_i > _team.size():
			return TEAM_SHOT
		var spot: Vector3 = (_team[_credit_i - 1].root as Node3D).position
		return {"pos": spot + TEAM_CAM, "look": spot + TEAM_LOOK, "sway": 0.06, "fov": CHAR_FOV}
	return SHOTS[panel_id]


func _glide(shot: Dictionary, instant: bool = false) -> void:
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

func _build_lobby() -> void:
	var items: Array = Economy.catalog("character")
	var free := 0
	for i in items.size():
		var item: Dictionary = items[i]
		var root := Node3D.new()
		root.name = "Lobby_" + item.id
		if LOBBY_PLACES.has(item.id):
			root.position = LOBBY_PLACES[item.id]
		else:
			root.position = FREE_SPOTS[free % FREE_SPOTS.size()]
			free += 1
		add_child(root)
		var spr := _pixel_sprite(CHARACTER_PIXEL)
		spr.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y # always faces the camera
		root.add_child(spr)
		# Soft shadow on the court under the cutout.
		var shadow := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 0.5
		disc.bottom_radius = 0.5
		disc.height = 0.01
		shadow.mesh = disc
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.1, 0.05, 0.15, 0.3)
		shadow.material_override = mat
		shadow.position = Vector3(0.0, 0.04, 0.0)
		shadow.add_to_group("blob_shadow") # only in low detail mode (Settings)
		root.add_child(shadow)
		var look := PixelArt.character_look(item)
		var px: float = look.pixel_size
		spr.pixel_size = px
		spr.position = Vector3(0.0, look.frame_h * px * 0.5 - look.foot_pad * px, 0.0)
		_lobby[item.id] = {"root": root, "sprite": spr, "look": look, "state": "", "since": 0.0, "happy": 0.0}
		_set_sheet(item.id, "idle")
	_tint_lobby()
	_focus_id = Economy.equipped_character if _lobby.has(Economy.equipped_character) else ""
	# The new FINISH pad at the end of the court here too.
	var strip := get_node_or_null("Arena/Geometry/FinishStrip") as Node3D
	var finish := get_node_or_null("Arena/FinishLine") as Node3D
	if strip and finish:
		strip.visible = false
		var gate := FinishGate.new()
		add_child(gate)
		gate.global_position = Vector3(finish.global_position.x, 0.0, finish.global_position.z)


func _lobby_x(id: String) -> float:
	return (_lobby[id].root as Node3D).position.x if _lobby.has(id) else 999.0


## Owned characters in full colour, locked ones a little dimmer.
func _tint_lobby() -> void:
	for id in _lobby:
		(_lobby[id].sprite as Sprite3D).modulate = Color.WHITE if Economy.owns(id) else LOCKED_TINT


## Show a slipper floating beside the character in weapon select, in its
## exact colours, with the enchantment glint when it has one.
func _set_slipper_preview(item: Dictionary) -> void:
	var tex := PixelArt.slipper_texture(item)
	_slipper_icon.texture = tex
	_slipper_icon.size = Vector2(tex.get_size()) * SLIPPER_ICON_SCALE
	_slipper_icon.pivot_offset = _slipper_icon.size * 0.5
	_slipper_icon.position = SLIPPER_ICON_CENTER - _slipper_icon.size * 0.5
	Enchant.apply_to_canvas(_slipper_icon, Enchant.is_enchanted(item))


## Look at a character in the lobby (glides the camera there in character select).
func _set_char_preview(item: Dictionary) -> void:
	if not _lobby.has(item.id):
		return
	var changed: bool = item.id != _focus_id
	_focus_id = item.id
	if changed and _current == "character":
		_glide(_shot("character"))


func _set_sheet(id: String, state: String) -> void:
	var c: Dictionary = _lobby[id]
	var sheet: Dictionary = c.look[state]
	c.state = state
	c.since = _time
	var spr: Sprite3D = c.sprite
	spr.frame = 0
	spr.texture = sheet.texture
	spr.hframes = maxi(sheet.frames, 1)


## The character in focus cheers (bought or picked).
func _char_celebrate(seconds: float = 1.6) -> void:
	if not _lobby.has(_focus_id):
		return
	_lobby[_focus_id].happy = seconds
	_set_sheet(_focus_id, "happy")


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

	var logo := UiKit.logo(900)
	logo.position = Vector2(110, 150)
	logo.set_meta("fx_custom", true)
	root.add_child(logo)
	_logo = logo

	# A soft dark fade from the right edge keeps the text readable over the bright court.
	# (It runs past the layout's right edge so ultrawide screens get it right up to their edge.)
	var fade_grad := Gradient.new()
	fade_grad.set_color(0, Color(0, 0, 0, 0))
	fade_grad.set_color(1, Color(0, 0, 0, 0.6))
	fade_grad.add_point(0.47, Color(0, 0, 0, 0.52))
	var fade_tex := GradientTexture2D.new()
	fade_tex.gradient = fade_grad
	fade_tex.fill_from = Vector2(0, 0)
	fade_tex.fill_to = Vector2(1, 0)
	var fade := TextureRect.new()
	fade.texture = fade_tex
	fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fade.stretch_mode = TextureRect.STRETCH_SCALE
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	fade.offset_left = -900
	fade.offset_right = 1000
	fade.offset_top = -600 # also covers taller screens
	fade.offset_bottom = 600
	fade.set_meta("fx_skip", true)
	root.add_child(fade)

	# Plain text menu, right-aligned, no boxes: the court behind does the talking.
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.position = Vector2(1300, 215) # eight entries: start a little higher
	col.custom_minimum_size = Vector2(540, 0)
	root.add_child(col)
	var entries := [
		["Start", func(): _show("mode")],
		["Multiplayer", func(): _show("join")],
		["Account", func(): _show("account")],
		["Achievements", func():
			_ach_back = "main"
			_show("achievements")],
		["Collection", func(): _show("collection")],
		["Settings", func(): _show("settings")],
		["Credits", func(): _show("credits")],
		["Quit", func(): Transition.quit()],
	]
	for e in entries:
		var b := UiKit.text_button(e[0], 76)
		b.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		b.pressed.connect(e[1])
		col.add_child(b)

	# Who's playing: the account's badge and name, top right. Tap to manage.
	_account_chip = UiKit.button("", UiKit.BLUE, 50, Vector2(420, 112))
	_account_chip.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_account_chip.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_account_chip.add_theme_constant_override("h_separation", 18)
	_account_chip.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_account_chip.position = Vector2(1440, 50)
	_account_chip.size = Vector2(420, 88)
	_account_chip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_account_chip.pressed.connect(func(): _show("account"))
	root.add_child(_account_chip)
	Accounts.changed.connect(_update_account_chip)
	_update_account_chip()
	return root


func _update_account_chip() -> void:
	var a := Accounts.current()
	_account_chip.visible = not a.is_empty()
	if a.is_empty():
		return
	_account_chip.text = a.name
	_account_chip.icon = AccountPanel.avatar_texture(a, 60)


# --- Choose game mode -----------------------------------------------------------

func _build_mode(ui: CanvasLayer) -> Control:
	var root := UiKit.full_rect()
	ui.add_child(root)

	var title := UiKit.title("Choose gamemode", 76, Color.WHITE, 16)
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
		var b := UiKit.button(t.name, UiKit.CYAN, 64, Vector2(700, 150))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_select_theme.bind(t.id))
		list.add_child(b)
		_theme_buttons[t.id] = b
	# Player-made question sets.
	var custom := UiKit.button("Custom +", UiKit.BLUE, 64, Vector2(700, 150))
	custom.alignment = HORIZONTAL_ALIGNMENT_LEFT
	custom.pressed.connect(func(): _show("custom"))
	list.add_child(custom)

	# Leaderboard panel.
	var board := PanelContainer.new()
	board.position = Vector2(940, 110)
	board.custom_minimum_size = Vector2(930, 790)
	board.add_theme_stylebox_override("panel", UiKit.box(UiKit.PANEL_DARK, Color(0.3, 0.3, 0.32), 10, 4))
	root.add_child(board)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	board.add_child(v)
	v.add_child(UiKit.title("Leaderboards", 60, Color.WHITE, 8))
	# The theme's name under the heading, in the accent colour (long names are cut).
	_board_title = UiKit.title("", 46, UiKit.ACCENT, 6)
	_board_title.clip_text = true
	_board_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_board_title.custom_minimum_size = Vector2(860, 0)
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
	var back := UiKit.button("Back", UiKit.BLUE, 44, Vector2(250, 110))
	back.pressed.connect(func(): _show("main"))
	row_btns.add_child(back)
	_continue_btn = UiKit.button("Continue", UiKit.BLUE, 44, Vector2(300, 110))
	_continue_btn.pressed.connect(func(): GameManager.start_run(_selected_theme))
	row_btns.add_child(_continue_btn)
	var next := UiKit.button("Next", UiKit.GOLD, 48, Vector2(320, 110))
	next.pressed.connect(func(): _show("character"))
	row_btns.add_child(next)
	return root


func _select_theme(theme_id: String) -> void:
	_selected_theme = theme_id
	GameManager.selected_theme = theme_id
	for id in _theme_buttons:
		UiKit.set_fill(_theme_buttons[id], UiKit.CYAN, id == theme_id)
	_board_title.text = GameManager.theme_name(theme_id)
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
	var title := UiKit.title("Custom quiz", 76, Color.WHITE, 16)
	title.position = Vector2(30, 10)
	root.add_child(title)

	# Left: saved sets.
	var left := VBoxContainer.new()
	left.position = Vector2(40, 130)
	left.add_theme_constant_override("separation", 18)
	root.add_child(left)
	var new_btn := UiKit.button("+ New set", UiKit.BLUE, 40, Vector2(540, 96))
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
	var help := UiKit.button("Format help", UiKit.BLUE, 26, Vector2(232, 70))
	help.pressed.connect(_show_custom_help)
	tools.add_child(help)
	var ai := UiKit.button("AI prompt", UiKit.BLUE, 26, Vector2(232, 70))
	ai.pressed.connect(_show_ai_prompt)
	tools.add_child(ai)
	var open := UiKit.button("Open file", UiKit.BLUE, 26, Vector2(232, 70))
	open.pressed.connect(_open_custom_file)
	tools.add_child(open)
	var paste := UiKit.button("Paste", UiKit.BLUE, 26, Vector2(232, 70))
	paste.pressed.connect(_paste_custom)
	tools.add_child(paste)
	_custom_delete = UiKit.button("Delete", UiKit.BLUE, 26, Vector2(200, 70))
	_custom_delete.pressed.connect(_delete_custom)
	tools.add_child(_custom_delete)

	# Bottom: back, save, play.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.position = Vector2(640, 935)
	root.add_child(row)
	var back := UiKit.button("Back", UiKit.BLUE, 44, Vector2(250, 110))
	back.pressed.connect(func(): _show("mode"))
	row.add_child(back)
	var save := UiKit.button("Save", UiKit.BLUE, 44, Vector2(250, 110))
	save.pressed.connect(_save_custom)
	row.add_child(save)
	# Teachers: open a class lobby with this set; students join from Multiplayer.
	var host := UiKit.button("Host class", UiKit.BLUE, 44, Vector2(300, 110))
	host.pressed.connect(_host_custom)
	row.add_child(host)
	var play := UiKit.button("Play", UiKit.GOLD, 48, Vector2(320, 110))
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

	# AI PROMPT: a ready prompt for ChatGPT / Claude / Gemini that makes the AI
	# answer in this exact format. Selectable, and COPY puts it on the clipboard.
	_ai_dialog = AcceptDialog.new()
	_ai_dialog.title = "Make questions with an AI"
	_ai_dialog.ok_button_text = "COPY PROMPT"
	var ai_box := VBoxContainer.new()
	ai_box.add_theme_constant_override("separation", 10)
	_ai_dialog.add_child(ai_box)
	var steps := Label.new()
	steps.text = "1. Tap COPY PROMPT.\n2. Open ChatGPT, Claude or Gemini, paste the prompt and add your notes (or attach the file).\n3. Got a quiz.txt file? Download it and tap OPEN FILE.  Got a code block? Tap its Copy button, then PASTE here.\nCheck the questions before you play!"
	steps.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	steps.custom_minimum_size = Vector2(1040, 0) # wrapping labels need a width or they grow tall
	steps.add_theme_font_size_override("font_size", 22)
	ai_box.add_child(steps)
	var prompt_view := TextEdit.new()
	prompt_view.text = CustomQuiz.AI_PROMPT
	prompt_view.editable = false
	prompt_view.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	prompt_view.custom_minimum_size = Vector2(1040, 480)
	prompt_view.add_theme_font_size_override("font_size", 20)
	ai_box.add_child(prompt_view)
	var copy_btn := _ai_dialog.get_ok_button()
	copy_btn.custom_minimum_size = Vector2(360, 72)
	copy_btn.add_theme_font_size_override("font_size", 30)
	_ai_dialog.confirmed.connect(_copy_ai_prompt)
	root.add_child(_ai_dialog)
	return root


func _show_ai_prompt() -> void:
	_ai_dialog.popup_centered(Vector2i(1100, 820))


func _copy_ai_prompt() -> void:
	DisplayServer.clipboard_set(CustomQuiz.AI_PROMPT)
	_custom_status.text = "Prompt copied! Paste it into ChatGPT, Claude or Gemini with your notes, then copy the answer and tap PASTE."
	_custom_status.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))


## Put the clipboard into the editor (long-press paste is awkward on phones).
func _paste_custom() -> void:
	var clip := DisplayServer.clipboard_get()
	if clip.strip_edges() == "":
		_custom_status.text = "The clipboard is empty. Copy the questions first."
		_custom_status.add_theme_color_override("font_color", Color(1.0, 0.5, 0.45))
		return
	# The clipboard may change line endings, so look for the prompt's opening line.
	if clip.contains(CustomQuiz.AI_PROMPT.get_slice("\n", 0)):
		_custom_status.text = "That's still the prompt. Paste it into the AI first, then copy the AI's answer."
		_custom_status.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
		return
	if _custom_text.text.strip_edges() == "":
		_custom_text.text = clip
	else:
		_custom_text.text = _custom_text.text.strip_edges() + "\n\n" + clip # add to the set
	_validate_custom()


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
	_custom_delete.text = "Delete"
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
	if _validate_custom().questions.size() > 0:
		Achievements.unlock("quiz_maker")
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


## Open a class lobby for the set in the editor (saved first).
func _host_custom() -> void:
	var r := _validate_custom()
	if r.questions.is_empty():
		_custom_status.text = "Add some questions first, then host your class."
		_custom_status.add_theme_color_override("font_color", Color(1.0, 0.5, 0.45))
		return
	if not _save_custom():
		return
	var err := _host_panel.open(_custom_id)
	if err != "":
		_custom_status.text = err
		_custom_status.add_theme_color_override("font_color", Color(1.0, 0.5, 0.45))
		return
	_show("host")


# --- Multiplayer: class lobby screens -------------------------------------------

func _build_join(ui: CanvasLayer) -> Control:
	var root := UiKit.full_rect()
	ui.add_child(root)
	_join_panel = JoinPanel.new()
	_join_panel.back_pressed.connect(func(): _show("main"))
	root.add_child(_join_panel)
	return root


func _build_achievements(ui: CanvasLayer) -> Control:
	var root := UiKit.full_rect()
	ui.add_child(root)
	_ach_panel = AchievementsPanel.new()
	_ach_panel.back_pressed.connect(func(): _show(_ach_back))
	root.add_child(_ach_panel)
	return root


func _build_collection(ui: CanvasLayer) -> Control:
	var root := UiKit.full_rect()
	ui.add_child(root)
	_collection_panel = CollectionPanel.new()
	_collection_panel.back_pressed.connect(func(): _show("main"))
	root.add_child(_collection_panel)
	return root


func _build_account(ui: CanvasLayer) -> Control:
	var root := UiKit.full_rect()
	ui.add_child(root)
	_account_panel = AccountPanel.new()
	_account_panel.back_pressed.connect(func(): _show("main"))
	_account_panel.achievements_pressed.connect(func():
		_ach_back = "account"
		_show("achievements"))
	root.add_child(_account_panel)
	# The first account was just made: carry on to the menu.
	_account_panel.welcomed.connect(func(): _show("main"))
	return root


func _build_host(ui: CanvasLayer) -> Control:
	var root := UiKit.full_rect()
	ui.add_child(root)
	_host_panel = HostPanel.new()
	_host_panel.closed.connect(func(): _show("custom"))
	root.add_child(_host_panel)
	return root


## Two presses: DELETE, then SURE? (like BUY -> CONFIRM).
func _delete_custom() -> void:
	if _custom_id == "":
		return
	if not _delete_armed:
		_delete_armed = true
		_custom_delete.text = "Sure?"
		return
	CustomQuiz.delete_set(_custom_id)
	_custom_delete.text = "Delete"
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
	var items: Array = Economy.catalog("character" if kind == "character" else "slipper").duplicate()
	if kind == "character":
		# Browse left to right across the lobby, the way the camera sees it.
		items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return _lobby_x(a.id) < _lobby_x(b.id))
	var p := {"items": items, "index": 0, "confirm": false}
	if kind != "character":
		_slipper_icon = TextureRect.new()
		_slipper_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_slipper_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_slipper_icon.stretch_mode = TextureRect.STRETCH_SCALE
		_slipper_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_slipper_icon.set_meta("fx_skip", true) # positioned and spun every frame in _process
		root.add_child(_slipper_icon)

	var title := UiKit.title(heading, 76, Color.WHITE, 16)
	title.position = Vector2(90, 50)
	root.add_child(title)

	p.caps = UiKit.title("", 46, Color.WHITE, 10)
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
	p.name = UiKit.title("", 84, Color.WHITE, 12)
	v.add_child(p.name)
	v.add_child(UiKit.title(("Character" if kind == "character" else "Weapon") + " description", 40, Color.WHITE, 8))
	p.desc = UiKit.label("", 34, Color.WHITE, 6)
	p.desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p.desc.custom_minimum_size = Vector2(560, 0)
	p.desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(p.desc)
	if kind != "character":
		# Wind resistance: five pips and a number (or "Immune").
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		v.add_child(row)
		var cap := UiKit.title("Wind resistance", 32, Color.WHITE, 6)
		cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(cap)
		p.pips = []
		for i in 5:
			var pip := ColorRect.new()
			pip.custom_minimum_size = Vector2(30, 22)
			pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(pip)
			p.pips.append(pip)
		p.wind = UiKit.title("", 32, UiKit.ACCENT, 6)
		p.wind.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(p.wind)
	p.status = UiKit.title("", 40, Color.WHITE, 8)
	v.add_child(p.status)
	p.buy = UiKit.button("Buy", UiKit.GOLD, 40, Vector2(400, 100))
	p.buy.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	p.buy.pressed.connect(_on_buy.bind(kind))
	v.add_child(p.buy)

	# Browse arrows on either side of the character.
	var left := UiKit.button("<", UiKit.BLUE, 64, Vector2(104, 134))
	left.position = Vector2(790, 480) # clear of the character on the stand
	left.pressed.connect(_browse.bind(kind, -1))
	root.add_child(left)
	var right := UiKit.button(">", UiKit.BLUE, 64, Vector2(104, 134))
	right.position = Vector2(1740, 480)
	right.pressed.connect(_browse.bind(kind, 1))
	root.add_child(right)
	p.left = left
	p.right = right

	var back := UiKit.button("Back", UiKit.BLUE, 44, Vector2(250, 110))
	back.position = Vector2(80, 940)
	back.pressed.connect(func(): _show(_back_of(kind)))
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
	if kind == "character":
		# The lobby is laid out left to right: > always pans right, < left,
		# stopping at either end (no jumping back across the court).
		var to := clampi(p.index + step, 0, p.items.size() - 1)
		if to == p.index:
			UiFx.bounce(p.left if step < 0 else p.right, 0.9)
			return
		p.index = to
	else:
		p.index = wrapi(p.index + step, 0, p.items.size())
	p.confirm = false
	_refresh_picker(kind)
	UiFx.bounce(p.name, 1.12)
	if kind != "character":
		UiFx.bounce(_slipper_icon, 1.2, 0.6)


func _refresh_picker(kind: String) -> void:
	var p: Dictionary = _pickers[kind]
	var item: Dictionary = p.items[p.index]
	var owned := Economy.owns(item.id)
	p.name.text = item.name
	# A character's story is a reward: it only shows once they're yours.
	if kind == "character" and not owned:
		p.desc.text = "Locked. Buy %s to read their story." % item.name
		p.desc.modulate = Color(1, 1, 1, 0.55)
	else:
		p.desc.text = item.desc
		p.desc.modulate = Color.WHITE
	if p.has("pips"):
		var resist := float(item.get("wind_resist", 0.0))
		var filled := roundi(resist * 5.0)
		for i in p.pips.size():
			(p.pips[i] as ColorRect).color = UiKit.ACCENT if i < filled else Color(1, 1, 1, 0.18)
		p.wind.text = "Immune" if resist >= 1.0 else "%d%%" % roundi(resist * 100.0)
	p.caps.text = "Caps: %d" % Economy.caps
	if owned:
		p.status.text = "Equipped" if Economy.equipped(_slot(kind)) == item.id else "Owned"
	else:
		p.status.text = "Locked  %d caps" % item.price
	var ready := Economy.requirement_met(item.id)
	p.buy.visible = not owned
	p.buy.disabled = not ready or not Economy.can_afford(item.price)
	p.buy.text = ("Confirm  -%d" % item.price) if p.confirm else ("Buy  %d" % item.price)
	if not ready:
		p.buy.text = Economy.requirement_text(item.id)
	elif p.buy.disabled:
		p.buy.text = "Need %d more" % (item.price - Economy.caps)
	p.next.disabled = not owned
	if kind == "character":
		(p.left as Button).modulate.a = 0.35 if p.index == 0 else 1.0
		(p.right as Button).modulate.a = 0.35 if p.index == p.items.size() - 1 else 1.0

	# Characters: the camera goes to them in the lobby. Slippers: locked ones
	# are shown as a dark silhouette.
	var tint := Color.WHITE if owned else Color(0.25, 0.25, 0.3)
	if kind == "character":
		_tint_lobby()
		_set_char_preview(item)
	else:
		_set_slipper_preview(item)
		_slipper_icon.modulate = tint


func _on_buy(kind: String) -> void:
	var p: Dictionary = _pickers[kind]
	var item: Dictionary = p.items[p.index]
	if not p.confirm:
		p.confirm = true # first press asks to confirm
	elif Economy.buy(item.id, item.price):
		Sfx.play("ui_buy") # ka-ching
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
	Sfx.play("ui_equip")
	if kind == "character":
		_char_celebrate() # cheers while the camera moves to weapon select
	if next_panel == "":
		GameManager.start_run(_selected_theme)
	else:
		_show(next_panel)


func _slot(kind: String) -> String:
	return "character" if kind == "character" else "slipper"


# --- Settings / credits ---------------------------------------------------------

func _build_settings(ui: CanvasLayer) -> Control:
	var root := UiKit.full_rect()
	ui.add_child(root)
	var panel := SettingsPanel.new()
	panel.position = Vector2(530, 150)
	panel.back_pressed.connect(func(): _show("main"))
	root.add_child(panel)
	return root


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
	v.add_child(UiKit.title(heading, 76, Color.WHITE, 12))
	v.add_child(UiKit.accent_rule())
	var text := UiKit.label(body, 36)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(text)
	var back := UiKit.button("Back", UiKit.BLUE, 44, Vector2(250, 110))
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(func(): _show("main"))
	v.add_child(back)
	return root


# --- Credits: the team -------------------------------------------------------------

## The team stands together west of the court, each with a name tag.
func _build_team() -> void:
	for m: Dictionary in Team.present():
		var root := Node3D.new()
		root.name = "Team_" + String(m.id)
		root.position = m.spot
		add_child(root)
		var look := PixelArt.single_sheet_look(Team.sheet(m))
		var px: float = look.pixel_size
		var spr := _pixel_sprite(px)
		spr.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		spr.texture = look.idle.texture
		spr.hframes = maxi(look.idle.frames, 1)
		spr.position = Vector3(0.0, look.frame_h * px * 0.5 - look.foot_pad * px, 0.0)
		root.add_child(spr)
		var shadow := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 0.45
		disc.bottom_radius = 0.45
		disc.height = 0.01
		shadow.mesh = disc
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.1, 0.05, 0.15, 0.3)
		shadow.material_override = mat
		shadow.position = Vector3(0.0, 0.04, 0.0)
		root.add_child(shadow)
		var tag := NameTag.new()
		tag.text = m.nick
		tag.position.y = PixelArt.MAX_HEIGHT + 0.3
		root.add_child(tag)
		_team.append({"member": m, "root": root, "sprite": spr, "look": look, "tag": tag, "phase": randf() * 3.0})


## Credits screen: a card on the left (minimal, boxed), the camera on the
## person it's about. Starts on the whole team, then one by one.
func _build_credits(ui: CanvasLayer) -> Control:
	var root := UiKit.full_rect()
	ui.add_child(root)
	var heading := UiKit.title("Credits", 76, Color.WHITE, 16)
	heading.position = Vector2(90, 50)
	root.add_child(heading)

	var card := PanelContainer.new()
	card.position = Vector2(80, 210)
	card.custom_minimum_size = Vector2(640, 660)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.04, 0.05, 0.08, 0.82)
	box.border_color = Color(1, 1, 1, 0.1)
	box.set_border_width_all(1)
	box.border_width_left = 6
	box.border_color = UiKit.ACCENT
	box.set_corner_radius_all(18)
	box.content_margin_left = 40
	box.content_margin_right = 40
	box.content_margin_top = 34
	box.content_margin_bottom = 36
	box.shadow_color = Color(0, 0, 0, 0.35)
	box.shadow_size = 16
	card.add_theme_stylebox_override("panel", box)
	root.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	card.add_child(v)
	var kicker := UiKit.label("", 26, UiKit.ACCENT, 0)
	kicker.add_theme_font_override("font", UiKit.key_font())
	v.add_child(kicker)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 16)
	v.add_child(name_row)
	var who := UiKit.title("", 60, Color.WHITE, 8)
	who.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	who.custom_minimum_size = Vector2(380, 0)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(who)
	var nick := PanelContainer.new()
	var nb := StyleBoxFlat.new()
	nb.bg_color = Color(UiKit.ACCENT, 0.16)
	nb.border_color = Color(UiKit.ACCENT, 0.7)
	nb.set_border_width_all(2)
	nb.set_corner_radius_all(30)
	nb.content_margin_left = 20
	nb.content_margin_right = 20
	nb.content_margin_top = 6
	nb.content_margin_bottom = 6
	nick.add_theme_stylebox_override("panel", nb)
	nick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(nick)
	var nick_l := UiKit.label("", 30, UiKit.ACCENT, 0)
	nick_l.add_theme_font_override("font", UiKit.key_font())
	nick.add_child(nick_l)
	var rule := ColorRect.new()
	rule.color = Color(1, 1, 1, 0.12)
	rule.custom_minimum_size = Vector2(0, 2)
	v.add_child(rule)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(list)

	# Prev / count / next at the foot of the card, Back below it.
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 18)
	v.add_child(nav)
	var prev := UiKit.button("<", UiKit.BLUE, 48, Vector2(96, 84))
	prev.pressed.connect(_credit_go.bind(-1))
	nav.add_child(prev)
	var count := UiKit.title("", 40, Color.WHITE, 8)
	count.custom_minimum_size = Vector2(150, 0)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nav.add_child(count)
	var next := UiKit.button(">", UiKit.BLUE, 48, Vector2(96, 84))
	next.pressed.connect(_credit_go.bind(1))
	nav.add_child(next)

	var back := UiKit.button("Back", UiKit.BLUE, 44, Vector2(250, 110))
	back.position = Vector2(80, 940)
	back.pressed.connect(func(): _show("main"))
	root.add_child(back)
	_credit_card = {"card": card, "kicker": kicker, "who": who, "nick": nick, "nick_l": nick_l, "list": list, "count": count}
	return root


func _credit_go(step: int) -> void:
	var n := _team.size() + 1
	_credit_i = posmod(_credit_i + step, n)
	_credit_auto = CREDIT_STEP if _credit_i > 0 else 3.5
	_fill_credit()
	_glide(_shot("credits"))
	Sfx.play("ui_whoosh")


func _fill_credit() -> void:
	if _credit_card.is_empty():
		return
	var c := _credit_card
	for child in (c.list as VBoxContainer).get_children():
		child.queue_free()
	(c.count as Label).text = "%d / %d" % [_credit_i + 1, _team.size() + 1]
	var lines: Array = []
	# Close-ups show only that person's name tag (the others would crowd the card).
	for k in _team.size():
		(_team[k].tag as Node3D).visible = _credit_i == 0 or _credit_i == k + 1
	if _credit_i == 0 or _credit_i > _team.size():
		c.kicker.text = "MADE BY"
		c.who.text = "The Tumbang Henyo team"
		c.nick.visible = false
		for t in _team:
			lines.append("%s  \u00b7  %s" % [t.member.nick, t.member.title])
	else:
		var m: Dictionary = _team[_credit_i - 1].member
		c.kicker.text = String(m.title).to_upper()
		c.who.text = m.name
		c.nick.visible = true
		c.nick_l.text = m.nick
		lines = m.roles
	for line in lines:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		var dot := ColorRect.new()
		dot.color = UiKit.ACCENT
		dot.custom_minimum_size = Vector2(8, 8)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(dot)
		row.add_child(UiKit.label(line, 32, Color(1, 1, 1, 0.88), 0))
		(c.list as VBoxContainer).add_child(row)
	# Text fades in; the card itself stays put (its size never changes).
	for node in [c.kicker, c.who, c.nick, c.list]:
		var ci := node as CanvasItem
		ci.modulate.a = 0.0
		create_tween().tween_property(ci, "modulate:a", 1.0, 0.3)
