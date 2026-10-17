extends Control
## Pinoy Henyo quiz panel: one question, three choices, a countdown.
## Answer by clicking/tapping a choice or pressing 1/2/3.

signal answered(choice_index: int)
signal timed_out

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
	for i in _buttons.size():
		_buttons[i].pressed.connect(_choose.bind(i))


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
	_time_left = time_limit
	_timer_bar.max_value = time_limit
	_timer_bar.value = time_limit
	_active = true
	visible = true


## Highlight the right answer (and the wrong pick, if any).
## chosen = -1 means the timer ran out.
func show_result(chosen: int, correct: int, explanation: String) -> void:
	if chosen >= 0 and chosen != correct:
		_buttons[chosen].modulate = COLOR_WRONG
	_buttons[correct].modulate = COLOR_RIGHT
	Sfx.play("correct" if chosen == correct else "wrong")
	if chosen == correct:
		_feedback.text = "Tama!"
	elif chosen < 0:
		_feedback.text = "Ubos na ang oras! " + explanation
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
	if not _active:
		return
	_active = false
	_lock()
	answered.emit(index)


func _lock() -> void:
	for button in _buttons:
		button.disabled = true
