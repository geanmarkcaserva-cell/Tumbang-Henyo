extends Node3D
## Round controller: Quiz -> Throw -> Run -> Round clear, with Awra loss
## on a wrong answer or a miss, and game over at 0 Awra.
##
## Debug keys in the Throw state: H = force a hit, M = force a miss.

enum State { QUIZ, THROW, RUN, ROUND_CLEAR, GAME_OVER, TAGGED }

const MAX_AWRA := 100
const AWRA_WRONG := 20
const AWRA_MISS := 15
const AWRA_TAGGED := 25 # used once the taya can tag (step 4)
const AWRA_ROUND_CLEAR := 10
const MISS_GRACE_TIME := 0.6 ## the lata may still be toppling after the tsinelas stops
## Where the player may walk while throwing: behind the throw line (z = 0),
## inside the court sides. Rect2(min x, min z, width, depth).
const THROW_ZONE := Rect2(-8.6, 0.4, 17.2, 6.6)

@export var theme_id := "kasaysayan"

var state: State = State.QUIZ
var awra := MAX_AWRA
var round_number := 1

var _question: Dictionary = {}
var _correct_index := 0
var _wind := Vector3.ZERO

@onready var _player: CharacterBody3D = $Player
@onready var _hud: CanvasLayer = $HUD
@onready var _quiz: Control = $HUD/QuizPanel
@onready var _throw: Node3D = $ThrowController
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
	_throw.power_changed.connect(_hud.set_power)
	_throw.thrown.connect(_on_thrown)
	_throw.settled.connect(_on_tsinelas_settled)
	QuizDatabase.reset_run()
	_hud.set_awra(awra, MAX_AWRA)
	_hud.set_round(round_number)
	_hud.update_wind(Vector3.ZERO, _player.global_basis)
	_enter_quiz()


func _process(_delta: float) -> void:
	if state == State.THROW:
		_hud.update_wind(_wind, _player.global_basis)


func _unhandled_input(event: InputEvent) -> void:
	match state:
		State.THROW:
			if event.is_action_pressed("debug_hit"):
				_debug_throw_hit()
			elif event.is_action_pressed("debug_miss"):
				_on_throw_missed()
		State.GAME_OVER:
			if event.is_action_pressed("restart"):
				get_tree().reload_current_scene()


# --- Difficulty by round (GDD: Difficulty by round) ------------------------

func _wind_max_for_round() -> float:
	if round_number <= 2:
		return 0.0
	elif round_number <= 5:
		return 2.0
	elif round_number <= 9:
		return 4.0
	return 6.0


func _preview_for_round() -> float:
	if round_number <= 2:
		return 1.0
	elif round_number <= 5:
		return 0.5
	elif round_number <= 9:
		return 0.25
	return 0.0


func _roll_wind() -> Vector3:
	var max_speed := _wind_max_for_round()
	if max_speed <= 0.0:
		return Vector3.ZERO
	var angle := randf() * TAU
	return Vector3(cos(angle), 0.0, sin(angle)) * randf_range(max_speed * 0.3, max_speed)


# --- Quiz -------------------------------------------------------------

func _enter_quiz() -> void:
	_set_state(State.QUIZ)
	_set_player_mode(false, false)
	_throw.end()
	_hud.show_throw_ui(false)
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


# --- Throw ----------------------------------------------------------------

func _enter_throw() -> void:
	_set_state(State.THROW)
	_wind = _roll_wind()
	# Walk freely behind the throw line (no sprinting), aim with the mouse.
	_set_player_mode(true, true)
	_player.sprint_enabled = false
	_player.set_move_bounds(THROW_ZONE)
	_player.set_aim_mode(true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_hud.show_throw_ui(true)
	_hud.update_wind(_wind, _player.global_basis)
	_hud.show_status("Tama! Move behind the line, aim, hold click to charge, release")
	_throw.begin(_player, _wind, _preview_for_round())


func _on_thrown() -> void:
	_hud.show_throw_ui(false)
	_hud.show_status("")


func _on_tsinelas_settled() -> void:
	if state != State.THROW:
		return
	await get_tree().create_timer(MISS_GRACE_TIME).timeout
	if state == State.THROW:
		_on_throw_missed()


func _debug_throw_hit() -> void:
	# Knock the lata over as if a tsinelas hit it.
	_lata.sleeping = false
	_lata.apply_central_impulse(Vector3(randf_range(-0.3, 0.3), 0.5, -1.4))
	_lata.apply_torque_impulse(Vector3(-0.08, 0.0, randf_range(-0.03, 0.03)))


func _on_throw_missed() -> void:
	if state != State.THROW:
		return
	_throw.end()
	_hud.show_throw_ui(false)
	_lose_awra(AWRA_MISS)
	if state == State.GAME_OVER:
		return
	_hud.show_status("Sablay! Missed the lata.")
	await get_tree().create_timer(1.2).timeout
	if state == State.THROW:
		_enter_quiz()


func _on_lata_knocked_down() -> void:
	if state == State.THROW:
		_throw.end()
		_enter_run()


# --- Run ----------------------------------------------------------------

func _enter_run() -> void:
	_set_state(State.RUN)
	_set_player_mode(true, true)
	_hud.show_throw_ui(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_hud.show_status("Lata down! Run to the finish line!")


func _on_finish_body_entered(body: Node3D) -> void:
	if state == State.RUN and body == _player:
		_round_clear()


# --- Round clear / Awra / game over --------------------------------------

func _round_clear() -> void:
	_set_state(State.ROUND_CLEAR)
	_set_player_mode(false, false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	awra = mini(awra + AWRA_ROUND_CLEAR, MAX_AWRA)
	_hud.set_awra(awra, MAX_AWRA)
	_hud.show_status("Round %d clear! +%d Awra" % [round_number, AWRA_ROUND_CLEAR])
	await get_tree().create_timer(2.0).timeout
	round_number += 1
	_hud.set_round(round_number)
	_throw.clear_tsinelas()
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
	_throw.end()
	_hud.show_throw_ui(false)
	_set_player_mode(false, false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_hud.show_status("Game over! Rounds cleared: %d\nPress R to play again" % (round_number - 1))


## move: walk/sprint allowed. look: mouse look allowed. Aim camera turns
## off whenever the player isn't in the throw.
func _set_player_mode(move: bool, look: bool) -> void:
	_player.controls_enabled = move
	_player.look_enabled = look
	if state != State.THROW:
		_player.set_aim_mode(false)
		_player.set_move_bounds(Rect2())
		_player.sprint_enabled = true


func _set_state(new_state: State) -> void:
	state = new_state
	print("Round %d: %s" % [round_number, State.keys()[new_state]])
