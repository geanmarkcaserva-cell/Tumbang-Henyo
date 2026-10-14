extends Node3D
## Round controller: Quiz -> Throw -> Run -> Round clear, with Awra loss
## on a wrong answer or a miss, and game over at 0 Awra.
##
## The throw is a placeholder until step 2: in the Throw state press
## H to simulate a hit or M to simulate a miss.

enum State { QUIZ, THROW, RUN, ROUND_CLEAR, GAME_OVER }

const MAX_AWRA := 100
const AWRA_WRONG := 20
const AWRA_MISS := 15
const AWRA_TAGGED := 25 # used once the taya can tag (step 4)
const AWRA_ROUND_CLEAR := 10

@export var theme_id := "kasaysayan"

var state: State = State.QUIZ
var awra := MAX_AWRA
var round_number := 1

var _question: Dictionary = {}
var _correct_index := 0

@onready var _player: CharacterBody3D = $Player
@onready var _hud: CanvasLayer = $HUD
@onready var _quiz: Control = $HUD/QuizPanel
@onready var _lata: RigidBody3D = $Arena/Lata
@onready var _finish: Area3D = $Arena/FinishLine
@onready var _spawn: Marker3D = $Arena/PlayerSpawn


func _ready() -> void:
	_player.respawn(_spawn.global_position)
	_player.stamina_changed.connect(_hud.set_stamina)
	_lata.knocked_down.connect(_on_lata_knocked_down)
	_finish.body_entered.connect(_on_finish_body_entered)
	_quiz.answered.connect(_on_quiz_answered)
	_quiz.timed_out.connect(_on_quiz_timed_out)
	QuizDatabase.reset_run()
	_hud.set_awra(awra, MAX_AWRA)
	_hud.set_round(round_number)
	_enter_quiz()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match state:
		State.THROW:
			if event.keycode == KEY_H:
				_debug_throw_hit()
			elif event.keycode == KEY_M:
				_on_throw_missed()
		State.GAME_OVER:
			if event.keycode == KEY_R:
				get_tree().reload_current_scene()


# --- Quiz -------------------------------------------------------------

func _enter_quiz() -> void:
	_set_state(State.QUIZ)
	_player.controls_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_hud.show_status("")
	_question = QuizDatabase.next_question(theme_id, "easy")
	if _question.is_empty():
		push_error("No questions found for theme '%s'" % theme_id)
		return
	# Shuffle the choices so players learn answers, not letter positions.
	var order := [0, 1, 2]
	order.shuffle()
	var choices := []
	for i in order:
		choices.append(_question.choices[i])
	_correct_index = order.find(_question.answer)
	_quiz.ask(_question.question, choices)


func _on_quiz_answered(choice_index: int) -> void:
	if state != State.QUIZ:
		return
	_quiz.show_result(choice_index, _correct_index, _question.explanation)
	if choice_index == _correct_index:
		await get_tree().create_timer(0.8).timeout
		if state == State.QUIZ:
			_quiz.close()
			_enter_throw()
	else:
		_answer_failed()


func _on_quiz_timed_out() -> void:
	if state != State.QUIZ:
		return
	_quiz.show_result(-1, _correct_index, _question.explanation)
	_answer_failed()


func _answer_failed() -> void:
	_lose_awra(AWRA_WRONG)
	if state == State.GAME_OVER:
		return
	# Leave the explanation up long enough to read.
	await get_tree().create_timer(2.5).timeout
	if state == State.QUIZ:
		_quiz.close()
		_enter_quiz()


# --- Throw (placeholder until step 2) -------------------------------------

func _enter_throw() -> void:
	_set_state(State.THROW)
	_hud.show_status("Tama! Throw placeholder: press H = hit, M = miss")


func _debug_throw_hit() -> void:
	# Knock the lata over as if a tsinelas hit it.
	_lata.apply_central_impulse(Vector3(randf_range(-0.3, 0.3), 0.5, -1.4))
	_lata.apply_torque_impulse(Vector3(-0.08, 0.0, randf_range(-0.03, 0.03)))


func _on_throw_missed() -> void:
	if state != State.THROW:
		return
	_lose_awra(AWRA_MISS)
	if state == State.GAME_OVER:
		return
	_hud.show_status("Sablay! Missed the lata.")
	await get_tree().create_timer(1.2).timeout
	if state == State.THROW:
		_enter_quiz()


func _on_lata_knocked_down() -> void:
	if state == State.THROW:
		_enter_run()


# --- Run ----------------------------------------------------------------

func _enter_run() -> void:
	_set_state(State.RUN)
	_player.controls_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_hud.show_status("Lata down! Run to the finish line!")


func _on_finish_body_entered(body: Node3D) -> void:
	if state == State.RUN and body == _player:
		_round_clear()


# --- Round clear / Awra / game over --------------------------------------

func _round_clear() -> void:
	_set_state(State.ROUND_CLEAR)
	_player.controls_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	awra = mini(awra + AWRA_ROUND_CLEAR, MAX_AWRA)
	_hud.set_awra(awra, MAX_AWRA)
	_hud.show_status("Round %d clear! +%d Awra" % [round_number, AWRA_ROUND_CLEAR])
	await get_tree().create_timer(2.0).timeout
	round_number += 1
	_hud.set_round(round_number)
	_player.respawn(_spawn.global_position)
	_lata.reset_to_home()
	_enter_quiz()


func _lose_awra(amount: int) -> void:
	awra = maxi(awra - amount, 0)
	_hud.set_awra(awra, MAX_AWRA)
	if awra <= 0:
		_game_over()


func _game_over() -> void:
	_set_state(State.GAME_OVER)
	_quiz.close()
	_player.controls_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_hud.show_status("Game over! Rounds cleared: %d\nPress R to play again" % (round_number - 1))


func _set_state(new_state: State) -> void:
	state = new_state
	print("Round %d: %s" % [round_number, State.keys()[new_state]])
