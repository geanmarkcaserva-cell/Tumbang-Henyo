extends Control
## Pinoy Henyo quiz panel: one question, three choices, a countdown.
## Answer by clicking/tapping a choice or pressing 1/2/3.

signal answered(choice_index: int)
signal timed_out
signal hint_requested ## the Hint button: the game charges tansan and calls eliminate()

const ICON_TANSAN := preload("res://art/ui/hud/icon_tansan.webp")

var _hint_btn: Button
var _hint_used := false
var _tick_shown := -1 ## last whole second that ticked
var _hint_cost := 100

@export var time_limit := 15.0

const LETTERS := "abc"
const COLOR_RIGHT := Color(0.55, 1.0, 0.6)
const COLOR_WRONG := Color(1.0, 0.45, 0.45)

var _time_left := 0.0
var _active := false

@onready var _question_label: Label = %QuestionLabel
@onready var _timer_bar: ProgressBar = %TimerBar
@onready var _feedback: Label = %Feedback
@onready var _buttons: Array[Button] = [%ChoiceA, %ChoiceB, %ChoiceC]


func _ready() -> void:
	visible = false
	UiKit.use_title_font($Panel/HBox/Left/Header) # "Question" caption
	$Panel/HBox/Left/Header.text = "Question"
	$Panel/HBox/Left/Header.add_theme_color_override("font_color", UiKit.ACCENT)
	$Panel.add_theme_stylebox_override("panel", UiKit.box())
	_timer_bar.add_theme_stylebox_override("fill", _bar_box(UiKit.ACCENT))
	_timer_bar.add_theme_stylebox_override("background", _bar_box(Color(1, 1, 1, 0.12)))
	for i in _buttons.size():
		_buttons[i].pressed.connect(_choose.bind(i))
		UiKit.set_fill(_buttons[i], UiKit.BLUE, false) # glass answer cards (answers keep the plain font)
		_buttons[i].add_theme_constant_override("shadow_offset_y", 2)
		UiFx.hookup_button(_buttons[i])
	_build_hint()


## "Hint" with a bottle cap and the price, under the timer.
func _build_hint() -> void:
	_hint_btn = UiKit.button("Hint  100", UiKit.BLUE, 26, Vector2(250, 62))
	_hint_btn.icon = ICON_TANSAN
	_hint_btn.expand_icon = false
	_hint_btn.add_theme_constant_override("icon_max_width", 40)
	_hint_btn.add_theme_constant_override("h_separation", 10)
	_hint_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_hint_btn.tooltip_text = "Crosses out one wrong answer. Costs 100 caps, so studying is cheaper!"
	_hint_btn.focus_mode = Control.FOCUS_NONE
	_hint_btn.pressed.connect(func():
		if _active and not _hint_used:
			hint_requested.emit())
	UiFx.hookup_button(_hint_btn)
	$Panel/HBox/Left.add_child(_hint_btn)


## Show the hint button (shown = false hides it), its price and whether the
## player can pay for it.
func set_hint(shown: bool, cost: int, affordable: bool) -> void:
	_hint_cost = cost
	_hint_btn.visible = shown
	_hint_btn.text = "Hint  %d" % cost
	_hint_btn.disabled = not affordable or _hint_used
	_hint_btn.tooltip_text = "Crosses out one wrong answer for %d caps." % cost if affordable \
			else "You need %d caps for a hint. Study instead!" % cost


## True while a hint can still be bought for the current question.
func can_hint() -> bool:
	return _active and not _hint_used and _hint_btn.visible


## Cross out a wrong choice (bought with a hint).
func eliminate(index: int) -> void:
	_hint_used = true
	_hint_btn.disabled = true
	_hint_btn.text = "Hint used"
	var b := _buttons[index]
	b.disabled = true
	b.modulate = Color(1, 1, 1, 0.28)
	UiFx.shake(b)


func _bar_box(colour: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = colour
	s.set_corner_radius_all(6)
	return s


## Seconds left when the player answered (for scoring later).
func get_time_left() -> float:
	return maxf(_time_left, 0.0)


func ask(question_text: String, choices: Array) -> void:
	_question_label.text = question_text
	for i in _buttons.size():
		_buttons[i].text = "%s)  %s" % [LETTERS[i], choices[i]]
		_buttons[i].disabled = false
		_buttons[i].modulate = Color.WHITE
	_feedback.text = ""
	_hint_used = false
	_time_left = time_limit
	_timer_bar.max_value = time_limit
	_timer_bar.value = time_limit
	_active = true
	var was_open := visible
	visible = true
	# The card springs up, then the three choices pop in one by one.
	if not was_open:
		UiFx.pop($Panel, 0.0, 0.6, 0.5)
		Sfx.play("quiz_open")
	_tick_shown = -1
	for i in _buttons.size():
		UiFx.pop(_buttons[i], 0.12 + i * 0.07, 0.6, 0.45)
	UiFx.pop(_question_label, 0.05, 0.85, 0.4)


## Highlight the right answer (and the wrong pick, if any).
## chosen = -1 means the timer ran out.
func show_result(chosen: int, correct: int, explanation: String) -> void:
	if chosen >= 0 and chosen != correct:
		_buttons[chosen].modulate = COLOR_WRONG
	_buttons[correct].modulate = COLOR_RIGHT
	UiFx.bounce(_buttons[correct], 1.1, 0.6)
	if chosen >= 0 and chosen != correct:
		UiFx.shake(_buttons[chosen])
	UiFx.bounce(_feedback, 1.25, 0.6)
	if chosen < 0:
		Sfx.play("timeout")
	else:
		Sfx.play("correct" if chosen == correct else "wrong")
	if chosen == correct:
		_feedback.text = "Correct!"
	elif chosen < 0:
		_feedback.text = "Time's up! " + explanation
	else:
		_feedback.text = "Mali! " + explanation


func close() -> void:
	_active = false
	visible = false


func _process(delta: float) -> void:
	if not _active:
		return
	_time_left -= delta
	_timer_bar.value = maxf(_time_left, 0.0)
	# The clock ticks through the last 5 seconds, sharper for the last 3.
	var whole := int(ceil(_time_left))
	if whole != _tick_shown and whole <= 5 and whole > 0:
		_tick_shown = whole
		Sfx.play("tick_urgent" if whole <= 3 else "tick")
	if _time_left <= 0.0:
		_active = false
		_lock()
		timed_out.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	if event.is_action_pressed("answer_a"):
		_choose(0)
	elif event.is_action_pressed("answer_b"):
		_choose(1)
	elif event.is_action_pressed("answer_c"):
		_choose(2)
	else:
		return
	get_viewport().set_input_as_handled()


func _choose(index: int) -> void:
	if not _active or _buttons[index].disabled: # crossed out by a hint
		return
	_active = false
	_lock()
	answered.emit(index)


func _lock() -> void:
	for button in _buttons:
		button.disabled = true
	if _hint_btn:
		_hint_btn.disabled = true
