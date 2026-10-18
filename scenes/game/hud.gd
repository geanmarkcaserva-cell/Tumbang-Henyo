extends CanvasLayer
## Greybox HUD: Awra, energy, round, score, tansan, status text, the
## quiz panel, the throw UI (power gauge, crosshair, wind), plus the pause
## menu and the game over panel.
##
## The HUD keeps running while the game is paused (so Esc and the pause
## buttons work); the quiz panel is set back to pausable so its timer stops.

signal pause_requested
signal resume_pressed
signal play_again_pressed
signal main_menu_pressed

@onready var quiz: Control = $QuizPanel
@onready var _awra_bar: ProgressBar = $Margin/VBox/AwraBar
@onready var _awra_label: Label = $Margin/VBox/AwraLabel
@onready var _stamina_bar: ProgressBar = $Margin/VBox/StaminaBar
@onready var _round_label: Label = $RoundLabel
@onready var _status: Label = $Status
@onready var _throw_ui: Control = $ThrowUI
@onready var _power_gauge: Control = $ThrowUI/PowerGauge
@onready var _wind_arrow: Control = $Margin/VBox/WindRow/WindArrow
@onready var _wind_label: Label = $Margin/VBox/WindRow/WindLabel

var _score_label: Label
var _caps_label: Label
var _pause_panel: Control
var _over_panel: Control
var _over_text: Label
var _fade: ColorRect
var _fade_tween: Tween
var _settings_panel: Control
var _last_score := 0
var _last_caps := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	quiz.process_mode = Node.PROCESS_MODE_PAUSABLE
	_throw_ui.visible = false
	$Margin/VBox/Hint.text = "Quiz: click or 1/2/3   |   Throw: mouse aim, hold click to charge, release   |   Run: WASD, hold Shift to sprint (uses Energy), Space jump, Q look back   |   Esc pause"
	$Margin/VBox/StaminaLabel.text = "Energy"
	# Captions and big text in the title font; the controls hint stays plain.
	for l in [_status, _round_label, _awra_label, $Margin/VBox/StaminaLabel, _wind_label]:
		UiKit.use_title_font(l)
	# The bubble letters are thin: small captions get a dark outline and a bit more size.
	for l: Label in [_round_label, _awra_label, $Margin/VBox/StaminaLabel, _wind_label]:
		l.add_theme_color_override("font_outline_color", UiKit.TEXT_OUTLINE)
		l.add_theme_constant_override("outline_size", 8)
		l.add_theme_font_size_override("font_size", l.get_theme_font_size("font_size") + 6)
	_build_score_labels()
	_pause_panel = _build_pause_panel()
	_over_panel = _build_game_over_panel()
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.z_index = 40 # over the game and quiz, under pause / game over (50)
	add_child(_fade)
	_settings_panel = _build_settings_panel()
	UiFx.shrink(self) # a bit smaller than drawn, each piece toward its own edge


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


func set_awra(value: int, max_value: int) -> void:
	_awra_bar.max_value = max_value
	_awra_bar.value = value
	_awra_label.text = "Awra  %d" % value


func set_stamina(value: float, max_value: float) -> void:
	_stamina_bar.max_value = max_value
	_stamina_bar.value = value


func set_round(number: int) -> void:
	_round_label.text = "Round %d" % number


func set_score(value: int) -> void:
	_score_label.text = "Score  %d" % value
	if value > _last_score:
		UiFx.bounce(_score_label, 1.2)
	_last_score = value


func set_caps(value: int) -> void:
	_caps_label.text = "Tansan  %d" % value
	if value > _last_caps and _last_caps > 0:
		UiFx.bounce(_caps_label, 1.2)
	_last_caps = value


func show_status(text: String) -> void:
	var is_new := text != "" and text != _status.text
	_status.text = text
	if is_new:
		UiFx.bounce(_status, 1.22, 0.6)


func show_throw_ui(on: bool) -> void:
	_throw_ui.visible = on
	if not on:
		_power_gauge.value = 0.0


func set_power(value: float) -> void:
	_power_gauge.value = value


## wind: horizontal wind in m/s. view_basis: the player's facing, so the
## arrow points the way the wind blows relative to the screen.
func update_wind(wind: Vector3, view_basis: Basis) -> void:
	var speed := Vector2(wind.x, wind.z).length()
	if speed < 0.05:
		_wind_label.text = "Wind: none"
		_wind_arrow.direction = Vector2.ZERO
		return
	var local := view_basis.inverse() * wind
	_wind_arrow.direction = Vector2(local.x, local.z).normalized()
	_wind_label.text = "Wind: %.1f m/s" % speed


func show_pause(on: bool) -> void:
	var was := _pause_panel.visible or _settings_panel.visible
	_settings_panel.visible = false
	_pause_panel.visible = on
	if on and not was:
		UiFx.pop_in(_pause_panel)


func show_game_over(score: int, rounds: int, caps_earned: int, rank: int, best: int) -> void:
	var lines := [
		"Score:  %d" % score,
		"Rounds cleared:  %d" % rounds,
		"Tansan earned:  %d" % caps_earned,
	]
	if rank == 1:
		lines.append("NEW BEST!")
	elif rank > 0:
		lines.append("#%d on your leaderboard  (best %d)" % [rank, best])
	else:
		lines.append("Best:  %d" % best)
	_over_text.text = "\n".join(lines)
	_over_panel.visible = true
	_status.text = ""
	UiFx.pop_in(_over_panel)


# --- Built in code ----------------------------------------------------------------

func _build_score_labels() -> void:
	_score_label = _corner_label(95, 40)
	_caps_label = _corner_label(150, 36)
	set_score(0)
	set_caps(0)


func _corner_label(top: float, font_size: int) -> Label:
	var l := UiKit.title("", font_size, Color.WHITE, 8)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	l.offset_left = -480.0
	l.offset_right = -40.0
	l.offset_top = top
	add_child(l)
	return l


func _build_pause_panel() -> Control:
	var root := _dim_backdrop()
	var v := _center_panel(root, "Paused")
	var resume := UiKit.button("RESUME", UiKit.BLUE, 52, Vector2(460, 120))
	resume.pressed.connect(func(): resume_pressed.emit())
	v.add_child(resume)
	var settings := UiKit.button("SETTINGS", UiKit.BLUE, 52, Vector2(460, 120))
	settings.pressed.connect(_open_settings)
	v.add_child(settings)
	var menu := UiKit.button("MAIN MENU", UiKit.BLUE, 52, Vector2(460, 120))
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


func _build_game_over_panel() -> Control:
	var root := _dim_backdrop()
	var v := _center_panel(root, "Game over")
	_over_text = UiKit.label("", 42, Color.WHITE, 8)
	_over_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_over_text)
	var again := UiKit.button("PLAY AGAIN", UiKit.GOLD, 52, Vector2(460, 120))
	again.pressed.connect(func(): play_again_pressed.emit())
	v.add_child(again)
	var menu := UiKit.button("MAIN MENU", UiKit.BLUE, 52, Vector2(460, 120))
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
	return v
