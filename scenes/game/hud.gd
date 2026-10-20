extends CanvasLayer
## In-game HUD.
##
##   Top left    Awra (plus icon) and Energy (sneaker icon) bars on a glass card.
##   Top centre  Round pill; under it the wind dial while throwing.
##   Top right   Tansan count (bottle cap), score, pause button.
##   Middle      status text, aim reticle and power gauge (throw).
##   Bottom      contextual key hints on PC; touch controls on phones.
##   Overlays    the coach card (tutorial / one-time tips) with a highlight
##               ring, the quiz panel, pause, settings, game over, fade.
##
## The HUD keeps running while the game is paused (Esc and the pause buttons
## work); the quiz panel and the coach card pause with the game.

signal pause_requested
signal resume_pressed
signal play_again_pressed
signal main_menu_pressed
signal skip_tutorial_pressed
signal choice_made(index: int) ## a button on ask_choice()'s card was pressed

const ICON_AWRA := preload("res://art/ui/hud/icon_awra.webp")
const ICON_SPRINT := preload("res://art/ui/hud/icon_sprint.webp")
const ICON_TANSAN := preload("res://art/ui/hud/icon_tansan.webp")
const ICON_PAUSE := preload("res://art/ui/hud/icon_pause.webp")
const WIND_DIAL := preload("res://scenes/game/wind_indicator.gd")

const AWRA_BLUE := Color(0.25, 0.6, 0.95)
const AWRA_BLUE_TOP := Color(0.62, 0.87, 1.0)
const ENERGY := Color(1.0, 0.68, 0.16)
const ENERGY_TOP := Color(1.0, 0.9, 0.45)
const MAX_WIND := 6.0

@onready var quiz: Control = $QuizPanel
@onready var _status: Label = $Status
@onready var _throw_ui: Control = $ThrowUI
@onready var _power_gauge: Control = $ThrowUI/PowerGauge

var touch: TouchControls
var coach: CoachCard

var _player: Node
var _awra_icon: TextureRect
var _awra_value: Label
var _awra_bar: HudBar
var _energy_icon: TextureRect
var _energy_caption: Label
var _energy_bar: HudBar
var _round_label: Label
var _round_pill: Control
var _caps_label: Label
var _caps_icon: TextureRect
var _score_label: Label
var _pause_button: TextureButton
var _wind_box: Control
var _wind_dial: Control
var _wind_value: Label
var _wind_word: Label
var _hints: HBoxContainer
var _ring: HighlightRing
var _pause_panel: Control
var _pause_skip: Button
var _over_panel: Control
var _over_text: Label
var _over_again: Button
var _over_title: Label
var _fade: ColorRect
var _fade_tween: Tween
var _settings_panel: Control
var _choice_panel: Control
var _choice_title: Label
var _choice_body: Label
var _choice_icons: HBoxContainer
var _choice_buttons: HBoxContainer

var _clock_pill: PanelContainer
var _clock_face: ClockFace
var _clock_label: Label
var _clock_target := -1.0 ## minutes after midnight
var _clock_shown := -1.0
var _clock_tween: Tween
var _boss_box: Control
var _boss_time: Label
var _boss_caption: Label
var _boss_last_sec := -1
var _beacon_marker: BeaconMarker
var _banner: VBoxContainer
var _banner_title: Label
var _banner_sub: Label
var _banner_tween: Tween
var _bull_box: VBoxContainer
var _bull_text: RichTextLabel
var _bull_sub: Label
var _bull_tween: Tween
var _bull_on := false
var _class_pill: Button
var _class_label: Label
var _class_drop: PanelContainer
var _class_board: ClassBoard
var _class_open := false ## dropdown toggled open by a tap
var _tab_held := false

var _context := "none"
var _awra_ready := false
var _last_awra := 0
var _last_score := 0
var _last_caps := 0
var _exhausted := false
var _tutorial_running := false
var _tip_token := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	quiz.process_mode = Node.PROCESS_MODE_PAUSABLE
	_throw_ui.visible = false
	UiKit.use_title_font(_status)
	_status.add_theme_color_override("font_outline_color", UiKit.TEXT_OUTLINE)

	_build_stats()
	_build_round()
	_build_clock()
	_build_top_right()
	_build_wind()
	_build_boss_ui()
	_build_bullseye()
	_build_class_board()
	_build_hints()
	_build_reticle()
	_build_coach()

	touch = TouchControls.new()
	touch.name = "TouchControls"
	touch.look.connect(func(rel: Vector2):
		if _player:
			_player.touch_look(rel))
	add_child(touch)
	_ring = HighlightRing.new()
	add_child(_ring)

	_pause_panel = _build_pause_panel()
	_over_panel = _build_game_over_panel()
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.z_index = 40 # over the game and quiz, under pause / game over (50)
	add_child(_fade)
	_settings_panel = _build_settings_panel()
	_choice_panel = _build_choice_panel()
	UiFx.shrink(self) # a bit smaller than drawn, each piece toward its own edge

	Settings.changed.connect(_apply_touch_setting)
	_apply_touch_setting()
	set_context("none")


## The player, for touch look.
func bind_player(p: Node) -> void:
	_player = p


# --- Context (what the player is doing) -----------------------------------------

## "quiz", "throw", "run" or "none": picks the touch controls and key hints.
func set_context(ctx: String) -> void:
	_context = ctx
	touch.context = ctx
	_wind_box.visible = ctx == "throw"
	_update_hints()


func _apply_touch_setting() -> void:
	touch.visible = Settings.touch_controls
	TouchControls.active = touch.visible
	_update_hints()


func _update_hints() -> void:
	if _hints == null:
		return
	for c in _hints.get_children():
		c.queue_free()
	if touch.visible or _tutorial_running: # the coach card shows the keys then
		_hints.visible = false
		return
	var groups := []
	var move := [Settings.key_name("move_forward"), Settings.key_name("move_left"), Settings.key_name("move_back"), Settings.key_name("move_right")]
	match _context: # the player's own keys (Settings > Controls)
		"throw":
			groups = [[move, "Move"], [["Mouse"], "Aim"], [["Hold " + Settings.key_name("throw")], "Charge, release to throw"]]
		"run":
			groups = [[move, "Run"], [[Settings.key_name("sprint")], "Sprint"], [[Settings.key_name("jump")], "Jump"], [[Settings.key_name("look_back")], "Look back"]]
	_hints.visible = not groups.is_empty()
	for g in groups:
		var chip := _pill(Vector2(0, 58))
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(box)
		for k in g[0]:
			box.add_child(_small_key(k))
		var l := UiKit.label(g[1], 24, Color(1, 1, 1, 0.9), 6)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		box.add_child(l)
		_hints.add_child(chip)


# --- Fades ------------------------------------------------------------------------

## Fade the screen to black. await it to know when it's fully black.
func fade_out(seconds: float = 0.45) -> Signal:
	return _fade_to(1.0, seconds)


## Fade back from black.
func fade_in(seconds: float = 0.45) -> Signal:
	return _fade_to(0.0, seconds)


func _fade_to(alpha: float, seconds: float) -> Signal:
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_STOP) # freezes while paused
	_fade_tween.tween_property(_fade, "color:a", alpha, seconds).set_trans(Tween.TRANS_SINE)
	return _fade_tween.finished


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		pause_requested.emit()
		get_viewport().set_input_as_handled()


# --- Values ---------------------------------------------------------------------

func set_awra(value: int, max_value: int) -> void:
	_awra_bar.set_value(value, max_value, not _awra_ready)
	_awra_value.text = str(value)
	if _awra_ready:
		if value < _last_awra:
			UiFx.shake(_awra_icon, 9.0)
			UiFx.bounce(_awra_value, 1.25, 0.45)
		elif value > _last_awra:
			UiFx.bounce(_awra_icon, 1.25, 0.6)
	var low := float(value) / max_value <= 0.25
	_awra_value.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45) if low else Color.WHITE)
	_last_awra = value
	_awra_ready = true


func set_stamina(value: float, max_value: float) -> void:
	_energy_bar.set_value(value, max_value)
	# Same rule as the player: empty locks sprint until it's 30% full again.
	if value <= 0.01:
		_exhausted = true
	elif value >= max_value * 0.3:
		_exhausted = false
	if _energy_bar.exhausted != _exhausted:
		_energy_bar.exhausted = _exhausted
		_energy_caption.text = "Recharging" if _exhausted else "Energy"
		_energy_caption.add_theme_color_override("font_color", Color(1, 1, 1, 0.55) if _exhausted else Color.WHITE)
		if _exhausted:
			UiFx.shake(_energy_icon, 8.0)


func set_round(number: int, final: bool = false) -> void:
	var text := "Final round" if final else "Round %d" % number
	var changed := _round_label.text != text
	_round_label.text = text
	if final:
		_round_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))
	else:
		_round_label.add_theme_color_override("font_color", Color.WHITE)
	if changed and number > 1:
		UiFx.bounce(_round_pill, 1.25, 0.7)


func set_score(value: int) -> void:
	_score_label.text = _thousands(value)
	if value > _last_score:
		UiFx.bounce(_score_label, 1.2)
	_last_score = value


func set_caps(value: int) -> void:
	_caps_label.text = _thousands(value)
	if value > _last_caps and _last_caps > 0:
		UiFx.bounce(_caps_label, 1.2)
		UiFx.bounce(_caps_icon, 1.3, 0.6)
	_last_caps = value


func show_status(text: String) -> void:
	var is_new := text != "" and text != _status.text
	_status.text = text
	if is_new:
		UiFx.bounce(_status, 1.22, 0.6)


# --- Clock (time of day moves when you score) -------------------------------------

## minutes: time of day in minutes after midnight (8:00 AM = 480).
## The hands sweep to the new time; instant = jump straight there.
func set_clock(minutes: float, instant: bool = false) -> void:
	if is_equal_approx(minutes, _clock_target) and not instant:
		return
	var from := _clock_shown if _clock_shown >= 0.0 else minutes
	_clock_target = minutes
	if _clock_tween:
		_clock_tween.kill()
	if instant or from == minutes:
		_show_clock(minutes)
		return
	_clock_tween = create_tween()
	_clock_tween.tween_method(_show_clock, from, minutes, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	UiFx.bounce(_clock_pill, 1.12, 0.5)


func _show_clock(minutes: float) -> void:
	_clock_shown = minutes
	_clock_face.minutes = minutes
	_clock_label.text = clock_text(minutes)
	# Late afternoon warms up; from 6 PM it's Mama time.
	var col := Color.WHITE
	if minutes >= 18 * 60:
		col = Color(1.0, 0.45, 0.4)
	elif minutes >= 17 * 60 + 40:
		col = Color(1.0, 0.75, 0.4)
	_clock_label.add_theme_color_override("font_color", col)
	_clock_face.accent = col


static func clock_text(minutes: float) -> String:
	var m := int(minutes) % (24 * 60)
	var h := floori(m / 60.0)
	var suffix := "AM" if h < 12 else "PM"
	var h12 := h % 12
	if h12 == 0:
		h12 = 12
	return "%d:%02d %s" % [h12, m % 60, suffix]


# --- Mama's round -------------------------------------------------------------------

## Big centre-screen title, e.g. "6:00 PM" / "Mama's home!".
func show_banner(title: String, subtitle: String, color: Color = UiKit.ACCENT, seconds: float = 2.6) -> void:
	_banner_title.text = title
	Sfx.play("banner")
	_banner_title.add_theme_color_override("font_color", color)
	_banner_sub.text = subtitle
	_banner.visible = true
	_banner.pivot_offset = _banner.size * 0.5
	if _banner_tween:
		_banner_tween.kill()
	_banner.modulate.a = 0.0
	_banner.scale = Vector2.ONE * 1.6
	_banner_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	_banner_tween.set_parallel()
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, 0.18)
	_banner_tween.tween_property(_banner, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tween.chain().tween_interval(seconds)
	_banner_tween.chain().tween_property(_banner, "modulate:a", 0.0, 0.35)
	_banner_tween.chain().tween_callback(func(): _banner.visible = false)


# --- Class game leaderboard ------------------------------------------------------

## Class game (multiplayer): a pill left of the Round pill with your place;
## hold Tab (PC) or tap it (phone) for the leaderboard dropdown.
func enable_class_board() -> void:
	_class_pill.visible = true
	Lobby.players_changed.connect(_update_class_pill)
	_update_class_pill()


func _update_class_pill() -> void:
	var rank := Lobby.my_rank()
	var total := Lobby.players.size()
	_class_label.text = "Class  #%d / %d" % [rank, total] if rank > 0 else "Class"


func _set_class_open(on: bool) -> void:
	if _class_drop.visible == on:
		return
	_class_drop.visible = on
	if on:
		_class_board.refresh()
		_class_drop.pivot_offset = Vector2(_class_drop.size.x * 0.5, 0)
		_class_drop.scale = Vector2(1, 0.85)
		_class_drop.modulate.a = 0.0
		var t := create_tween().set_parallel()
		t.tween_property(_class_drop, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(_class_drop, "modulate:a", 1.0, 0.12)


func _input(event: InputEvent) -> void:
	if _class_pill == null or not _class_pill.visible:
		return
	if event is InputEventKey and not event.echo \
			and (event.keycode == KEY_TAB or event.physical_keycode == KEY_TAB):
		_tab_held = event.pressed
		_set_class_open(_tab_held or _class_open)
		get_viewport().set_input_as_handled()


## Game over in a class game: your place, and no Play again (one run per game).
func set_class_result(rank: int, total: int) -> void:
	if rank > 0:
		_over_text.text += "\nClass rank:  #%d of %d" % [rank, total]
	_over_again.visible = false
	_class_drop.z_index = 52 # over the game over backdrop
	# Off to the left so it sits beside the game over card, not on it.
	_class_drop.offset_left = -900
	_class_drop.offset_right = -280
	_class_drop.offset_top = 240
	_class_drop.offset_bottom = 240
	_class_open = true
	_set_class_open(true)


## BULLSEYE! in shifting rainbow letters, popping in over the slow-motion
## close-up. Runs on real time so it stays snappy while the game is slowed.
func show_bullseye(points: int) -> void:
	_bull_sub.text = "Perfect shot!  +%d" % points
	_bull_box.visible = true
	_bull_on = true
	_bull_box.pivot_offset = _bull_box.size * 0.5
	if _bull_tween:
		_bull_tween.kill()
	_bull_box.modulate.a = 0.0
	_bull_box.scale = Vector2.ONE * 0.2
	_bull_box.rotation = deg_to_rad(-8.0)
	_bull_tween = create_tween().set_ignore_time_scale(true)
	_bull_tween.set_parallel()
	_bull_tween.tween_property(_bull_box, "modulate:a", 1.0, 0.12)
	_bull_tween.tween_property(_bull_box, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_bull_tween.tween_property(_bull_box, "rotation", 0.0, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_bull_tween.chain().tween_interval(1.6)
	_bull_tween.chain().tween_property(_bull_box, "scale", Vector2.ONE * 1.15, 0.3)
	_bull_tween.parallel().tween_property(_bull_box, "modulate:a", 0.0, 0.3)
	_bull_tween.chain().tween_callback(func():
		_bull_box.visible = false
		_bull_on = false)


func _process(_delta: float) -> void:
	if _bull_on:
		_paint_bullseye()
	_status.visible = not _bull_on # the bullseye has the stage


## Each letter its own hue, the rainbow sliding along the word.
func _paint_bullseye() -> void:
	var word := "BULLSEYE!"
	var t := Time.get_ticks_msec() / 1000.0
	var s := "[center]"
	for i in word.length():
		var c := Color.from_hsv(fposmod(t * 0.9 - i * 0.09, 1.0), 0.75, 1.0)
		s += "[color=#%s]%s[/color]" % [c.to_html(false), word[i]]
	_bull_text.text = s + "[/center]"


## The 30 second countdown to reach the beacon house.
func show_boss_timer(on: bool, caption: String = "Reach the light!") -> void:
	_boss_box.visible = on
	_boss_caption.text = caption
	_boss_last_sec = -1
	if on:
		UiFx.pop_in(_boss_box)


func set_boss_time(seconds_left: float) -> void:
	var s := ceili(maxf(seconds_left, 0.0))
	_boss_time.text = "0:%02d" % s if s < 60 else "%d:%02d" % [floori(s / 60.0), s % 60]
	var urgent := seconds_left <= 10.0
	_boss_time.add_theme_color_override("font_color", Color(1.0, 0.38, 0.33) if urgent else Color.WHITE)
	if s != _boss_last_sec:
		if urgent and _boss_last_sec != -1:
			UiFx.bounce(_boss_time, 1.3, 0.35)
		_boss_last_sec = s


## Point at the beacon: a chip over it when on screen, an arrow at the edge
## of the screen when it isn't. at = null hides it.
func set_beacon(at: Variant, from: Node3D = null, color: Color = Color(0.55, 0.92, 1.0)) -> void:
	_beacon_marker.visible = at != null
	if at != null:
		_beacon_marker.world_pos = at
		_beacon_marker.from = from
		_beacon_marker.COL = color


func show_throw_ui(on: bool) -> void:
	_throw_ui.visible = on
	if not on:
		_power_gauge.value = 0.0
		touch.power = 0.0


func set_power(value: float) -> void:
	_power_gauge.value = value
	touch.power = value


## wind: horizontal wind in m/s. view_basis: the player's facing, so the
## arrow points the way the wind blows relative to the screen.
func update_wind(wind: Vector3, view_basis: Basis) -> void:
	var speed := Vector2(wind.x, wind.z).length()
	if speed < 0.05:
		_wind_dial.direction = Vector2.ZERO
		_wind_dial.strength = 0.0
		_wind_value.text = "Calm"
		_wind_word.text = "No wind"
		_wind_word.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
		return
	var local := view_basis.inverse() * wind
	_wind_dial.direction = Vector2(local.x, local.z).normalized()
	_wind_dial.strength = speed / MAX_WIND
	_wind_value.text = "%.1f m/s" % speed
	var word := "Light"
	var col := Color(0.55, 0.9, 1.0)
	if speed >= 4.0:
		word = "Strong"
		col = Color(1.0, 0.55, 0.35)
	elif speed >= 2.0:
		word = "Breezy"
		col = Color(0.85, 0.95, 0.6)
	_wind_word.text = word
	_wind_word.add_theme_color_override("font_color", col)


func show_pause(on: bool) -> void:
	var was := _pause_panel.visible or _settings_panel.visible
	_settings_panel.visible = false
	_pause_skip.visible = _tutorial_running
	_pause_panel.visible = on
	if on and not was:
		UiFx.pop_in(_pause_panel)


func show_game_over(score: int, rounds: int, caps_earned: int, rank: int, best: int, won: bool = false) -> void:
	_over_title.text = "Nakauwi ka na!" if won else "Game over"
	_over_title.add_theme_color_override("font_color", Color(0.62, 0.92, 1.0) if won else Color.WHITE)
	var lines := [
		"Score:  %s" % _thousands(score),
		"Rounds cleared:  %d" % rounds,
		"Tansan earned:  %d" % caps_earned,
	]
	if rank == 1:
		lines.append("NEW BEST!")
	elif rank > 0:
		lines.append("#%d on your leaderboard  (best %s)" % [rank, _thousands(best)])
	else:
		lines.append("Best:  %s" % _thousands(best))
	_over_text.text = "\n".join(lines)
	_over_panel.visible = true
	_status.text = ""
	show_boss_timer(false)
	set_beacon(null)
	_banner.visible = false
	coach.hide_card()
	highlight("")
	set_context("none")
	UiFx.pop_in(_over_panel)


# --- Tutorial / tips ----------------------------------------------------------------

func set_tutorial_running(on: bool) -> void:
	_tutorial_running = on
	_update_hints()


## Point the highlight ring at a piece of the HUD: "awra", "energy", "quiz",
## "power", "wind", "throw_button", "sprint_button", "stick" or "" (off).
func highlight(target: String) -> void:
	_ring.target = target
	_ring.rect_getter = _rect_of


func _rect_of(target: String) -> Rect2:
	match target:
		"awra":
			return _awra_icon.get_global_rect().merge(_awra_bar.get_global_rect())
		"energy":
			return _energy_icon.get_global_rect().merge(_energy_bar.get_global_rect())
		"quiz":
			return (quiz.get_node("Panel") as Control).get_global_rect()
		"power":
			var r := _power_gauge.get_global_rect()
			return Rect2(r.position + Vector2(r.size.x * 0.25, 0), Vector2(r.size.x * 0.75, r.size.y))
		"wind":
			return _wind_box.get_global_rect()
		"throw_button", "sprint_button", "jump_button":
			return touch.button_rect(target.trim_suffix("_button"))
		"stick":
			return touch.stick_rect()
	return Rect2()


## A one-time tip on the coach card that goes away by itself.
func show_tip(title: String, body: String, seconds: float = 5.5) -> void:
	if _tutorial_running:
		return
	_tip_token += 1
	var token := _tip_token
	coach.show_card({"label": "TIP", "title": title, "body": body})
	await get_tree().create_timer(seconds, false).timeout
	if token == _tip_token and not _tutorial_running:
		coach.hide_card()


# --- Built in code ----------------------------------------------------------------

func _build_stats() -> void:
	var card := Panel.new()
	card.position = Vector2(28, 24)
	card.size = Vector2(566, 190)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# No dark card behind the bars: icons, captions and bars sit right on the game.
	card.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	add_child(card)

	_awra_icon = _icon(ICON_AWRA, Vector2(12, 8), Vector2(100, 100))
	card.add_child(_awra_icon)
	var cap := UiKit.title("Awra", 32, Color.WHITE, 8)
	cap.position = Vector2(126, 8)
	card.add_child(cap)
	_awra_value = UiKit.title("100", 44, Color.WHITE, 8)
	_awra_value.position = Vector2(126, 0)
	_awra_value.size = Vector2(418, 54)
	_awra_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	card.add_child(_awra_value)
	_awra_bar = HudBar.new()
	_awra_bar.position = Vector2(126, 58)
	_awra_bar.size = Vector2(420, 36)
	_awra_bar.fill_color = AWRA_BLUE
	_awra_bar.fill_color_top = AWRA_BLUE_TOP
	_awra_bar.segments = 10
	card.add_child(_awra_bar)

	_energy_icon = _icon(ICON_SPRINT, Vector2(22, 110), Vector2(80, 80))
	card.add_child(_energy_icon)
	_energy_caption = UiKit.title("Energy", 28, Color.WHITE, 8)
	_energy_caption.position = Vector2(126, 108)
	card.add_child(_energy_caption)
	_energy_bar = HudBar.new()
	_energy_bar.position = Vector2(126, 148)
	_energy_bar.size = Vector2(340, 24)
	_energy_bar.fill_color = ENERGY
	_energy_bar.fill_color_top = ENERGY_TOP
	_energy_bar.low_fraction = 0.2
	_energy_bar.low_color = Color(1.0, 0.45, 0.2)
	card.add_child(_energy_bar)


func _build_round() -> void:
	_round_pill = _pill(Vector2(300, 74))
	_round_pill.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_round_pill.offset_left = -150
	_round_pill.offset_right = 150
	_round_pill.offset_top = 24
	_round_pill.offset_bottom = 98
	_round_label = UiKit.title("Round 1", 44, Color.WHITE, 8)
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_round_pill.add_child(_round_label)
	add_child(_round_pill)


func _build_top_right() -> void:
	_pause_button = TextureButton.new()
	_pause_button.texture_normal = ICON_PAUSE
	_pause_button.ignore_texture_size = true
	_pause_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	_pause_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_pause_button.offset_left = -118
	_pause_button.offset_right = -30
	_pause_button.offset_top = 22
	_pause_button.offset_bottom = 110
	_pause_button.focus_mode = Control.FOCUS_NONE
	_pause_button.modulate = Color(1, 1, 1, 0.92)
	_pause_button.pressed.connect(func(): pause_requested.emit())
	UiFx.hookup_button(_pause_button)
	add_child(_pause_button)

	var caps := _pill(Vector2(250, 80))
	caps.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	caps.offset_left = -400
	caps.offset_right = -136
	caps.offset_top = 26
	caps.offset_bottom = 106
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_END
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caps.add_child(row)
	_caps_icon = _icon(ICON_TANSAN, Vector2.ZERO, Vector2(70, 70))
	_caps_icon.custom_minimum_size = Vector2(70, 70)
	row.add_child(_caps_icon)
	_caps_label = UiKit.title("0", 44, Color.WHITE, 8)
	_caps_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_caps_label)
	add_child(caps)

	var score := HBoxContainer.new()
	score.alignment = BoxContainer.ALIGNMENT_END
	score.add_theme_constant_override("separation", 14)
	score.mouse_filter = Control.MOUSE_FILTER_IGNORE
	score.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	score.offset_left = -620
	score.offset_right = -36
	score.offset_top = 116
	score.offset_bottom = 186
	var cap := UiKit.title("Score", 30, Color(1, 1, 1, 0.7), 8)
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	score.add_child(cap)
	_score_label = UiKit.title("0", 56, UiKit.ACCENT, 10)
	score.add_child(_score_label)
	add_child(score)


func _build_wind() -> void:
	_wind_box = _pill(Vector2(340, 124))
	_wind_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_wind_box.offset_left = -170
	_wind_box.offset_right = 170
	_wind_box.offset_top = 112
	_wind_box.offset_bottom = 236
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wind_box.add_child(row)
	_wind_dial = WIND_DIAL.new()
	_wind_dial.custom_minimum_size = Vector2(100, 100)
	row.add_child(_wind_dial)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", -4)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	col.add_child(UiKit.title("Wind", 24, Color(1, 1, 1, 0.6), 6))
	_wind_value = UiKit.title("Calm", 40, Color.WHITE, 8)
	col.add_child(_wind_value)
	_wind_word = UiKit.title("No wind", 24, Color(1, 1, 1, 0.55), 6)
	col.add_child(_wind_word)
	_wind_box.visible = false
	add_child(_wind_box)


## Clock pill right of the Round pill: a little clock face and the time.
func _build_clock() -> void:
	# Under the Awra and Energy bars, top left.
	_clock_pill = _pill(Vector2(260, 74))
	_clock_pill.position = Vector2(40, 200)
	_clock_pill.size = Vector2(270, 74)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clock_pill.add_child(row)
	_clock_face = ClockFace.new()
	_clock_face.custom_minimum_size = Vector2(52, 52)
	_clock_face.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_clock_face)
	_clock_label = UiKit.title("8:00 AM", 40, Color.WHITE, 8)
	_clock_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_clock_label)
	add_child(_clock_pill)
	_show_clock(8 * 60)


func _build_boss_ui() -> void:
	# Countdown, where the wind dial sits while throwing.
	_boss_box = _pill(Vector2(340, 120))
	_boss_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_boss_box.offset_left = -170
	_boss_box.offset_right = 170
	_boss_box.offset_top = 112
	_boss_box.offset_bottom = 232
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", -6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_box.add_child(col)
	_boss_caption = UiKit.title("Reach the light!", 26, Color(0.62, 0.93, 1.0), 6)
	_boss_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_boss_caption)
	_boss_time = UiKit.title("0:30", 64, Color.WHITE, 10)
	_boss_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_time.pivot_offset = Vector2(150, 36)
	col.add_child(_boss_time)
	_boss_box.visible = false
	add_child(_boss_box)

	_beacon_marker = BeaconMarker.new()
	_beacon_marker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_beacon_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_beacon_marker.set_meta("fx_skip", true)
	_beacon_marker.visible = false
	add_child(_beacon_marker)

	_banner = VBoxContainer.new()
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	_banner.offset_left = -760
	_banner.offset_right = 760
	_banner.offset_top = -260
	_banner.offset_bottom = 20
	_banner.alignment = BoxContainer.ALIGNMENT_CENTER
	_banner.add_theme_constant_override("separation", -10)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.set_meta("fx_skip", true)
	_banner.z_index = 30
	_banner_title = UiKit.title("6:00 PM", 150, UiKit.ACCENT, 22)
	_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_child(_banner_title)
	_banner_sub = UiKit.title("", 58, Color.WHITE, 12)
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_child(_banner_sub)
	_banner.visible = false
	add_child(_banner)


## Left of the Round pill (mirror of the clock). Hidden outside class games.
func _build_class_board() -> void:
	_class_pill = Button.new()
	_class_pill.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_class_pill.offset_left = -436
	_class_pill.offset_right = -166
	_class_pill.offset_top = 24
	_class_pill.offset_bottom = 98
	_class_pill.focus_mode = Control.FOCUS_NONE
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.03, 0.04, 0.07, 0.55)
	s.border_color = Color(1.0, 0.8, 0.34, 0.55)
	s.set_border_width_all(2)
	s.set_corner_radius_all(37)
	s.shadow_color = Color(0, 0, 0, 0.18)
	s.shadow_size = 10
	for st in ["normal", "hover", "pressed", "focus"]:
		var c := s.duplicate() as StyleBoxFlat
		if st == "hover" or st == "pressed":
			c.bg_color = Color(0.08, 0.09, 0.13, 0.75)
		_class_pill.add_theme_stylebox_override(st, c)
	_class_pill.pressed.connect(func():
		_class_open = not _class_open
		_set_class_open(_class_open or _tab_held))
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_class_pill.add_child(row)
	_class_label = UiKit.title("Class", 34, Color.WHITE, 8)
	_class_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_class_label)
	var chev := Chevron.new()
	chev.custom_minimum_size = Vector2(22, 22)
	chev.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(chev)
	_class_pill.visible = false
	add_child(_class_pill)

	_class_drop = PanelContainer.new()
	_class_drop.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_class_drop.offset_left = -560
	_class_drop.offset_right = 60
	_class_drop.offset_top = 108
	_class_drop.offset_bottom = 108
	_class_drop.add_theme_stylebox_override("panel", UiKit.box(UiKit.PANEL_DARK, Color(0.3, 0.3, 0.32), 10, 8))
	_class_drop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_class_drop.z_index = 46
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_class_drop.add_child(v)
	var head := UiKit.title("Class leaderboard", 36, Color.WHITE, 8)
	v.add_child(head)
	_class_board = ClassBoard.new()
	_class_board.compact = true
	_class_board.max_rows = 8
	_class_board.custom_minimum_size = Vector2(580, 0)
	v.add_child(_class_board)
	var how_to := UiKit.label("Hold Tab anytime to see this (or click the pill)" if not Settings.touch_controls else "Tap the pill to close", 20, Color(1, 1, 1, 0.5), 0)
	v.add_child(how_to)
	_class_drop.visible = false
	add_child(_class_drop)


func _build_bullseye() -> void:
	_bull_box = VBoxContainer.new()
	_bull_box.set_anchors_preset(Control.PRESET_CENTER)
	_bull_box.offset_left = -800
	_bull_box.offset_right = 800
	_bull_box.offset_top = -380
	_bull_box.offset_bottom = -90
	_bull_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_bull_box.add_theme_constant_override("separation", -14)
	_bull_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bull_box.set_meta("fx_skip", true)
	_bull_box.z_index = 32
	_bull_text = RichTextLabel.new()
	_bull_text.bbcode_enabled = true
	_bull_text.fit_content = true
	_bull_text.autowrap_mode = TextServer.AUTOWRAP_OFF
	_bull_text.scroll_active = false
	_bull_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bull_text.custom_minimum_size = Vector2(1600, 0)
	_bull_text.add_theme_font_override("normal_font", UiKit.title_font())
	_bull_text.add_theme_font_size_override("normal_font_size", 180)
	_bull_text.add_theme_constant_override("outline_size", 34)
	_bull_text.add_theme_color_override("font_outline_color", Color(0.08, 0.04, 0.14))
	_bull_text.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	_bull_text.add_theme_constant_override("shadow_offset_y", 10)
	_bull_box.add_child(_bull_text)
	_bull_sub = UiKit.title("Perfect shot!", 56, Color.WHITE, 14)
	_bull_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bull_box.add_child(_bull_sub)
	_bull_box.visible = false
	add_child(_bull_box)
	_paint_bullseye()


func _build_hints() -> void:
	_hints = HBoxContainer.new()
	_hints.alignment = BoxContainer.ALIGNMENT_CENTER
	_hints.add_theme_constant_override("separation", 16)
	_hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hints.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hints.offset_left = -900
	_hints.offset_right = 900
	_hints.offset_top = -92
	_hints.offset_bottom = -34
	_hints.modulate = Color(1, 1, 1, 0.85)
	add_child(_hints)


func _build_reticle() -> void:
	var r := Reticle.new()
	r.set_anchors_preset(Control.PRESET_CENTER)
	r.offset_left = -22
	r.offset_right = 22
	r.offset_top = -22
	r.offset_bottom = 22
	_throw_ui.add_child(r)


func _build_coach() -> void:
	var holder := Control.new()
	holder.name = "CoachLayer"
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.z_index = 45
	add_child(holder)
	coach = CoachCard.new()
	coach.name = "Coach"
	coach.process_mode = Node.PROCESS_MODE_PAUSABLE
	coach.position = Vector2(28, 300) # under the stats and the clock, clear of the aim
	# Sized by hand (it moves between the side and the centre): fixed top-left pivot.
	coach.set_meta("fx_skip", true)
	coach.set_meta("fx_base", Vector2.ONE * UiFx.UI_SCALE)
	coach.set_meta("fx_pivot_locked", true)
	coach.scale = Vector2.ONE * UiFx.UI_SCALE
	coach.pivot_offset = Vector2.ZERO
	holder.add_child(coach)


func _pill(min_size: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.03, 0.04, 0.07, 0.55)
	s.border_color = Color(1, 1, 1, 0.1)
	s.set_border_width_all(1)
	s.set_corner_radius_all(int(min_size.y * 0.5))
	s.content_margin_left = 22
	s.content_margin_right = 26
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	s.shadow_color = Color(0, 0, 0, 0.18)
	s.shadow_size = 10
	p.add_theme_stylebox_override("panel", s)
	p.custom_minimum_size = min_size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _icon(tex: Texture2D, pos: Vector2, sz: Vector2) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.position = pos
	t.size = sz
	t.pivot_offset = sz * 0.5
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


func _small_key(text: String) -> PanelContainer:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.03, 0.04, 0.07, 0.6)
	s.border_color = Color(1, 1, 1, 0.4)
	s.set_border_width_all(2)
	s.border_width_bottom = 4
	s.set_corner_radius_all(8)
	s.content_margin_left = 10
	s.content_margin_right = 10
	p.add_theme_stylebox_override("panel", s)
	p.custom_minimum_size = Vector2(44, 46)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UiKit.label(text, 22, Color.WHITE, 0)
	l.add_theme_font_override("font", UiKit.key_font())
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


static func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


func _build_pause_panel() -> Control:
	var root := _dim_backdrop()
	var v := _center_panel(root, "Paused")
	var resume := UiKit.button("Resume", UiKit.BLUE, 52, Vector2(460, 120))
	resume.pressed.connect(func(): resume_pressed.emit())
	v.add_child(resume)
	var settings := UiKit.button("Settings", UiKit.BLUE, 52, Vector2(460, 120))
	settings.pressed.connect(_open_settings)
	v.add_child(settings)
	_pause_skip = UiKit.button("Skip tutorial", UiKit.BLUE, 52, Vector2(460, 120))
	_pause_skip.pressed.connect(func(): skip_tutorial_pressed.emit())
	_pause_skip.visible = false
	v.add_child(_pause_skip)
	var menu := UiKit.button("Main menu", UiKit.BLUE, 52, Vector2(460, 120))
	menu.pressed.connect(func(): main_menu_pressed.emit())
	v.add_child(menu)
	return root


## Settings from the pause menu: same card as the main menu's.
func _build_settings_panel() -> Control:
	var root := _dim_backdrop()
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := SettingsPanel.new()
	panel.back_pressed.connect(_close_settings)
	center.add_child(panel)
	return root


func _open_settings() -> void:
	_pause_panel.visible = false
	_settings_panel.visible = true
	UiFx.pop_in(_settings_panel)


func _close_settings() -> void:
	_settings_panel.visible = false
	_pause_panel.visible = true
	UiFx.pop_in(_pause_panel)


## A card in the middle of the screen with a question and a row of buttons.
## Wait for the answer with `await choice_made` (the index of the button).
## icons: textures shown in a row above the text (may be empty).
func ask_choice(title: String, body: String, options: Array, icons: Array = []) -> void:
	_choice_title.text = title
	_choice_body.text = body
	for c in _choice_icons.get_children():
		c.queue_free()
	for tex in icons:
		var t := TextureRect.new()
		t.texture = tex
		t.custom_minimum_size = Vector2(96, 96)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		_choice_icons.add_child(t)
	_choice_icons.visible = not icons.is_empty()
	for c in _choice_buttons.get_children():
		c.queue_free()
	for i in options.size():
		var b := UiKit.button(options[i], UiKit.GOLD if i == 0 else UiKit.BLUE, 46, Vector2(420, 116))
		var index := i
		b.pressed.connect(func():
			_choice_panel.visible = false
			choice_made.emit(index))
		_choice_buttons.add_child(b)
	_status.text = ""
	set_context("none")
	_choice_panel.visible = true
	UiFx.pop_in(_choice_panel)


func _build_choice_panel() -> Control:
	var root := _dim_backdrop()
	var v := _center_panel(root, "")
	_choice_title = v.get_child(0)
	_choice_icons = HBoxContainer.new()
	_choice_icons.alignment = BoxContainer.ALIGNMENT_CENTER
	_choice_icons.add_theme_constant_override("separation", 22)
	v.add_child(_choice_icons)
	v.move_child(_choice_icons, 0)
	_choice_body = UiKit.label("", 38, Color(1, 1, 1, 0.9), 6)
	_choice_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_choice_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_choice_body.custom_minimum_size = Vector2(1000, 0)
	v.add_child(_choice_body)
	_choice_buttons = HBoxContainer.new()
	_choice_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_choice_buttons.add_theme_constant_override("separation", 28)
	v.add_child(_choice_buttons)
	return root


func _build_game_over_panel() -> Control:
	var root := _dim_backdrop()
	var v := _center_panel(root, "Game over")
	_over_title = v.get_child(0)
	_over_text = UiKit.label("", 42, Color.WHITE, 8)
	_over_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_over_text)
	var again := UiKit.button("Play again", UiKit.GOLD, 52, Vector2(460, 120))
	again.pressed.connect(func(): play_again_pressed.emit())
	v.add_child(again)
	_over_again = again
	var menu := UiKit.button("Main menu", UiKit.BLUE, 52, Vector2(460, 120))
	menu.pressed.connect(func(): main_menu_pressed.emit())
	v.add_child(menu)
	return root


func _dim_backdrop() -> Control:
	var root := ColorRect.new()
	root.color = Color(0, 0, 0, 0.55)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	root.z_index = 50 # above the quiz panel and every other HUD piece
	add_child(root)
	return root


func _center_panel(root: Control, heading: String) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiKit.box(UiKit.PANEL_DARK, Color(0.3, 0.3, 0.32), 10, 8))
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 28)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(v)
	var title := UiKit.title(heading, 88, Color.WHITE, 14)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var rule := UiKit.accent_rule()
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(rule)
	return v


## Little round clock: hour and minute hands for `minutes` after midnight.
class ClockFace extends Control:
	var minutes := 480.0:
		set(v):
			minutes = v
			queue_redraw()
	var accent := Color.WHITE:
		set(v):
			accent = v
			queue_redraw()

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 2.0
		draw_circle(c, r, Color(1, 1, 1, 0.12))
		draw_arc(c, r, 0, TAU, 40, accent, 3.5, true)
		for i in 12:
			var a := TAU * i / 12.0
			var d := Vector2(sin(a), -cos(a))
			draw_circle(c + d * (r - 6.0), 1.6 if i % 3 else 2.4, Color(1, 1, 1, 0.75))
		var m := fmod(minutes, 60.0)
		var h := fmod(minutes / 60.0, 12.0)
		var ha := TAU * h / 12.0
		var ma := TAU * m / 60.0
		draw_line(c, c + Vector2(sin(ha), -cos(ha)) * r * 0.5, accent, 4.0, true)
		draw_line(c, c + Vector2(sin(ma), -cos(ma)) * r * 0.78, Color.WHITE, 2.5, true)
		draw_circle(c, 3.0, accent)


## Where the beacon house is: a bobbing arrow and distance over it when it's on
## screen, an arrow on the edge of the screen pointing the way when it isn't.
class BeaconMarker extends Control:
	var COL := Color(0.55, 0.92, 1.0)
	const MARGIN := 90.0
	var world_pos := Vector3.ZERO
	var from: Node3D
	var _t := 0.0

	func _process(delta: float) -> void:
		if visible:
			_t += delta
			queue_redraw()

	func _draw() -> void:
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		var vp := get_viewport_rect().size
		var p := world_pos + Vector3.UP * 5.0
		var dist := 0.0
		if from:
			dist = Vector2(world_pos.x - from.global_position.x, world_pos.z - from.global_position.z).length()
		var text := "%d m" % roundi(dist)
		var font := UiKit.title_font()
		var behind := cam.is_position_behind(p)
		var sp := cam.unproject_position(p)
		var area := Rect2(Vector2(MARGIN, MARGIN), vp - Vector2(MARGIN, MARGIN) * 2.0)
		if not behind and area.has_point(sp):
			var bob := sin(_t * 5.0) * 7.0
			var point := sp + Vector2(0, bob)
			var tri := PackedVector2Array([point + Vector2(-20, -26), point + Vector2(20, -26), point])
			draw_colored_polygon(tri, COL)
			draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), Color(0.05, 0.1, 0.15), 3.0, true)
			_text(font, point + Vector2(0, -40), text)
			return
		# Off screen: arrow on the edge, pointing the way.
		var centre := vp * 0.5
		var dir: Vector2
		if behind:
			var local := cam.global_transform.affine_inverse() * p
			dir = Vector2(local.x, -local.y)
			if dir.length() < 0.01:
				dir = Vector2.DOWN
			dir = dir.normalized()
			if absf(dir.y) < 0.5: # mostly to the side: keep it on the side edge
				dir.y = 0.3 * signf(dir.y if dir.y != 0.0 else 1.0)
		else:
			dir = (sp - centre).normalized()
		dir = dir.normalized()
		var tx := INF
		var ty := INF
		if absf(dir.x) > 0.001:
			tx = ((area.end.x if dir.x > 0.0 else area.position.x) - centre.x) / dir.x
		if absf(dir.y) > 0.001:
			ty = ((area.end.y if dir.y > 0.0 else area.position.y) - centre.y) / dir.y
		var at := centre + dir * minf(tx, ty)
		var pulse := 1.0 + 0.08 * sin(_t * 6.0)
		draw_circle(at, 48.0 * pulse, Color(0.03, 0.05, 0.08, 0.7))
		draw_arc(at, 48.0 * pulse, 0, TAU, 40, COL, 3.0, true)
		var side := Vector2(-dir.y, dir.x)
		var tip := at + dir * 34.0
		draw_colored_polygon(PackedVector2Array([tip, at + dir * 8.0 + side * 18.0, at + dir * 8.0 - side * 18.0]), COL)
		_text(font, at + Vector2(0, -6) - dir * 14.0, text, 26)

	func _text(font: Font, centre: Vector2, text: String, size_px: int = 34) -> void:
		var w := 220.0
		var pos := centre + Vector2(-w * 0.5, size_px * 0.35)
		draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, w, size_px, 8, Color(0.04, 0.06, 0.1))
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, w, size_px, Color.WHITE)


## Small down-pointing chevron for the class pill.
class Chevron extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := size.x
		var h := size.y
		draw_polyline(PackedVector2Array([Vector2(w * 0.15, h * 0.35), Vector2(w * 0.5, h * 0.7), Vector2(w * 0.85, h * 0.35)]), UiKit.ACCENT, 4.0, true)


## Aim reticle: a thin ring with a dot.
class Reticle extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		draw_arc(c, 15.0, 0, TAU, 40, Color(0, 0, 0, 0.45), 6.0, true)
		draw_arc(c, 15.0, 0, TAU, 40, Color(1, 1, 1, 0.9), 2.5, true)
		draw_circle(c, 3.5, Color(1, 1, 1, 0.95))


## Pulsing ring around whatever the tutorial is talking about.
class HighlightRing extends Control:
	var target := "":
		set(v):
			target = v
			_t = 0.0
			queue_redraw()
	var rect_getter: Callable
	var _t := 0.0

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_meta("fx_skip", true)
		z_index = 44

	func _process(delta: float) -> void:
		if target != "":
			_t += delta
			queue_redraw()

	func _draw() -> void:
		if target == "" or not rect_getter.is_valid():
			return
		var r: Rect2 = rect_getter.call(target)
		if r.size == Vector2.ZERO:
			return
		var pulse := 0.5 + 0.5 * sin(_t * 5.0)
		var intro := minf(_t / 0.35, 1.0) # shrinks onto the target as it appears
		var grow := 14.0 + pulse * 6.0 + (1.0 - intro) * 60.0
		for i in 3: # soft glow, then the crisp line
			var s := StyleBoxFlat.new()
			s.draw_center = false
			var crisp := i == 2
			s.set_border_width_all(5 if crisp else 10 - i * 3)
			var a := 0.95 if crisp else 0.18
			s.border_color = Color(1.0, 0.8, 0.34, a * intro * (0.75 + 0.25 * pulse))
			s.set_corner_radius_all(22)
			s.anti_aliasing = true
			draw_style_box(s, r.grow(grow + (2 - i) * 5.0))
