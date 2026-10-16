extends Node3D
## Round controller: Quiz -> Throw -> Run -> Round clear, with Awra loss
## on a wrong answer, a miss, a tsinelas hit or a tag, and game over at 0 Awra.
## Also keeps score (GDD: Scoring), runs the taya squad (1-5 tayas, elites),
## the pause menu and the game over panel.
##
## Debug keys in the Throw state: H = force a hit, M = force a miss.

enum State { QUIZ, THROW, RUN, ROUND_CLEAR, GAME_OVER, TAGGED }

const TAYA_SCENE := preload("res://scenes/game/taya.tscn")

const MAX_AWRA := 100
const AWRA_WRONG := 20
const AWRA_MISS := 15
const AWRA_TAGGED := 25
const AWRA_SLIPPER_HIT := 10
const AWRA_ROUND_CLEAR := 10
const CAPS_CORRECT := 2 ## tansan per correct answer (GDD: Economy and shop)
const CAPS_ROUND_CLEAR := 10
const SLIPPER_STAGGER_TIME := 0.5
const SLIPPER_KNOCKBACK := 4.0
## Every taya (elite too) runs at this multiple of the player's walk speed:
## walking, they slowly catch you; sprinting (energy), you pull away.
const TAYA_SPEED_RATIO := 1.1
const MISS_GRACE_TIME := 0.6 ## the lata may still be toppling after the tsinelas stops
const CELEBRATE_CORRECT := 0.9 ## seconds of the happy sheet after a right answer
const FADE_TIME := 0.45 ## fade to black / back between rounds

## Scoring (GDD): answer points 100 + 10 per second left (max 250), 100 per
## hit, 200 for clearing the round, all multiplied by 1 + 0.1 x (round - 1).
const POINTS_ANSWER_BASE := 100
const POINTS_PER_SECOND := 10
const POINTS_ANSWER_MAX := 250
const POINTS_HIT := 100
const POINTS_ROUND_CLEAR := 200

## Where the player may walk while throwing: behind the throw line (z = -6),
## inside the court sides, and in front of the near hoop's pole (z = +2.76).
## Rect2(min x, min z, width, depth).
const THROW_ZONE := Rect2(-8.6, -5.6, 17.2, 3.6)

## Guard spots for extra tayas, as offsets from the lata.
const TAYA_SPOTS := [Vector3(-1.6, 0, -1.2), Vector3(2.6, 0, 1.6), Vector3(-2.6, 0, 1.6), Vector3(0.0, 0, -2.8)]

var theme_id := "history" ## set from GameManager.selected_theme on start

var state: State = State.QUIZ
var awra := MAX_AWRA
var round_number := 1
var score := 0

var _question: Dictionary = {}
var _correct_index := 0
var _wind := Vector3.ZERO
var _round_points := 0
var _run_caps := 0
var _tayas: Array = []
var _lata_home := Vector3.ZERO

@onready var _player: CharacterBody3D = $Player
@onready var _hud: CanvasLayer = $HUD
@onready var _quiz: Control = $HUD/QuizPanel
@onready var _throw: Node3D = $ThrowController
@onready var _arena: Node3D = $Arena
@onready var _lata: RigidBody3D = $Arena/Lata
@onready var _finish: Area3D = $Arena/FinishLine
@onready var _spawn: Marker3D = $Arena/PlayerSpawn


func _ready() -> void:
	get_tree().paused = false
	theme_id = GameManager.selected_theme
	_lata_home = _lata.global_position
	_player.respawn(_spawn.global_position)
	_player.stamina_changed.connect(_hud.set_stamina)
	_lata.knocked_down.connect(_on_lata_knocked_down)
	_finish.body_entered.connect(_on_finish_body_entered)
	_quiz.answered.connect(_on_quiz_answered)
	_quiz.timed_out.connect(_on_quiz_timed_out)
	_throw.power_changed.connect(_hud.set_power)
	_throw.thrown.connect(_on_thrown)
	_throw.settled.connect(_on_tsinelas_settled)
	_hud.pause_requested.connect(_on_pause_requested)
	_hud.resume_pressed.connect(_resume)
	_hud.play_again_pressed.connect(func(): Transition.reload())
	_hud.main_menu_pressed.connect(_quit_to_menu)
	Economy.caps_changed.connect(_hud.set_caps)

	_hook_taya($Arena/Taya)
	_ensure_tayas()

	QuizDatabase.reset_run()
	_hud.set_awra(awra, MAX_AWRA)
	_hud.set_round(round_number)
	_hud.set_score(score)
	_hud.set_caps(Economy.caps)
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
				Transition.reload()


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


func _taya_reaction_time() -> float: ## seconds between the taya's looks at you
	if round_number <= 2:
		return 0.4
	elif round_number <= 5:
		return 0.32
	elif round_number <= 9:
		return 0.25
	return 0.18


func _taya_aim_error() -> float: ## how far its throws scatter, in metres
	if round_number <= 2:
		return 1.2
	elif round_number <= 5:
		return 0.9
	elif round_number <= 9:
		return 0.6
	return 0.4


func _lata_reset_time() -> float:
	if round_number <= 2:
		return 3.0
	elif round_number <= 5:
		return 2.5
	elif round_number <= 9:
		return 2.0
	return 1.5


## Which tayas play this round: one entry per taya, true = elite.
func _taya_lineup() -> Array:
	if round_number <= 2:
		return [false]
	elif round_number <= 5:
		return [false, false]
	elif round_number <= 9:
		return [false, false, true]
	elif round_number <= 12:
		return [false, false, false, true]
	return [false, false, false, true, true]


func _roll_wind() -> Vector3:
	var max_speed := _wind_max_for_round()
	if max_speed <= 0.0:
		return Vector3.ZERO
	var angle := randf() * TAU
	return Vector3(cos(angle), 0.0, sin(angle)) * randf_range(max_speed * 0.3, max_speed)


# --- Taya squad -----------------------------------------------------------------

## Spawn extra tayas until this round's lineup is on the court.
## Returns how many joined.
func _ensure_tayas() -> int:
	var lineup := _taya_lineup()
	var joined := 0
	for i in range(_tayas.size(), lineup.size()):
		var t: CharacterBody3D = TAYA_SCENE.instantiate()
		t.elite = lineup[i]
		t.position = _lata_home + TAYA_SPOTS[(i - 1) % TAYA_SPOTS.size()]
		t.position.y = 0.0
		t.name = "Taya%d" % (i + 1)
		_arena.add_child(t)
		_hook_taya(t)
		joined += 1
	return joined


func _hook_taya(t: CharacterBody3D) -> void:
	t.setup(_player, _lata)
	t.lata_reset.connect(_on_taya_lata_reset)
	t.tagged_player.connect(_on_tagged)
	t.hit_player.connect(_on_hit_by_slipper.bind(t))
	_tayas.append(t)


func _nearest_taya_to_lata() -> CharacterBody3D:
	var best: CharacterBody3D = _tayas[0]
	for t in _tayas:
		if t.global_position.distance_to(_lata.global_position) < best.global_position.distance_to(_lata.global_position):
			best = t
	return best


func _stop_tayas() -> void:
	for t in _tayas:
		t.stop()


# --- Quiz -------------------------------------------------------------

func _enter_quiz() -> void:
	_set_state(State.QUIZ)
	_set_player_mode(false, false)
	_throw.end()
	_hud.show_throw_ui(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
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
		var points := mini(POINTS_ANSWER_BASE + POINTS_PER_SECOND * int(_quiz.get_time_left()), POINTS_ANSWER_MAX)
		_round_points += points
		_add_caps(CAPS_CORRECT)
		_hud.show_status("+%d" % points)
		await _wait(0.8)
		if state != State.QUIZ:
			return
		# Panel away, then a quick happy turn to the camera before the throw.
		_quiz.close()
		_player.celebrate(CELEBRATE_CORRECT)
		await _wait(CELEBRATE_CORRECT)
		if state == State.QUIZ:
			_enter_throw()
	else:
		_answer_failed()


func _on_quiz_timed_out() -> void:
	if state != State.QUIZ:
		return
	_quiz.show_result(-1, _correct_index, _question.explanation)
	_answer_failed()


func _answer_failed() -> void:
	_hud.show_status("")
	_lose_awra(AWRA_WRONG)
	if state == State.GAME_OVER:
		return
	# Leave the explanation up long enough to read.
	await _wait(2.5)
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
	await _wait(MISS_GRACE_TIME)
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
	_player.controls_enabled = false
	await _wait(1.2)
	if state == State.THROW:
		_next_attempt()


func _on_lata_knocked_down() -> void:
	if state == State.THROW:
		_round_points += POINTS_HIT
		_throw.end()
		_enter_run()


# --- Run ----------------------------------------------------------------

func _enter_run() -> void:
	_set_state(State.RUN)
	_set_player_mode(true, true)
	_hud.show_throw_ui(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var who := "the taya" if _tayas.size() == 1 else "a taya"
	_hud.show_status("Tumba! Run before %s stands the lata back up!" % who)
	for t in _tayas:
		t.configure(_player.walk_speed * TAYA_SPEED_RATIO, _lata_reset_time(),
				_taya_reaction_time(), _taya_aim_error())
	# The nearest taya stands the lata up; the rest wait, then everyone chases.
	_nearest_taya_to_lata().start_reset()


func _on_taya_lata_reset() -> void:
	if state != State.RUN:
		return
	for t in _tayas:
		t.start_chase()
	_hud.show_status("Lata is up! Takbo!")


func _on_hit_by_slipper(from_taya: CharacterBody3D) -> void:
	if state != State.RUN:
		return
	_lose_awra(AWRA_SLIPPER_HIT)
	if state == State.GAME_OVER:
		return
	var away := _player.global_position - from_taya.global_position
	away.y = 0.0
	_player.stagger(SLIPPER_STAGGER_TIME, away.normalized() * SLIPPER_KNOCKBACK)
	_hud.show_status("Aray! -%d Awra" % AWRA_SLIPPER_HIT)


func _on_tagged() -> void:
	if state != State.RUN:
		return
	_set_state(State.TAGGED)
	_set_player_mode(false, false)
	_stop_tayas()
	_lose_awra(AWRA_TAGGED)
	if state == State.GAME_OVER:
		return
	_hud.show_status("Taya ka! -%d Awra" % AWRA_TAGGED)
	await _wait(1.8)
	if state == State.TAGGED:
		_next_attempt()


func _on_finish_body_entered(body: Node3D) -> void:
	if state == State.RUN and body == _player:
		_round_clear()


# --- Round clear / Awra / game over --------------------------------------

func _round_clear() -> void:
	_set_state(State.ROUND_CLEAR)
	_set_player_mode(false, false)
	_stop_tayas()
	_player.celebrate(-1.0) # until the next round respawns them
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	awra = mini(awra + AWRA_ROUND_CLEAR, MAX_AWRA)
	_hud.set_awra(awra, MAX_AWRA)
	var gained := int(round((_round_points + POINTS_ROUND_CLEAR) * (1.0 + 0.1 * (round_number - 1))))
	score += gained
	_round_points = 0
	_hud.set_score(score)
	_add_caps(CAPS_ROUND_CLEAR)
	Economy.save_profile()
	_hud.show_status("Round %d clear!  +%d points  +%d Awra  +%d tansan" % [round_number, gained, AWRA_ROUND_CLEAR, CAPS_ROUND_CLEAR])
	await _wait(2.2)
	if state != State.ROUND_CLEAR:
		return
	# Fade to black, reset everything out of sight, fade back in on the new question.
	await _hud.fade_out(FADE_TIME)
	if state != State.ROUND_CLEAR:
		return
	round_number += 1
	_hud.set_round(round_number)
	_hud.show_status("")
	_reset_field()
	var joined := _ensure_tayas()
	_enter_quiz()
	if joined > 0:
		var elite_joined: bool = _tayas.back().elite
		_hud.show_status("Round %d: %s" % [round_number, "an ELITE taya joins! (3 tsinelas)" if elite_joined else "another taya joins!"])
	await _wait(0.15) # one beat of black so the jump isn't visible
	_hud.fade_in(FADE_TIME)


## After a miss or a tag: fade to black, everyone back to their spots, and
## fade in on the next question.
func _next_attempt() -> void:
	var from_state := state
	await _hud.fade_out(FADE_TIME)
	if state != from_state: # game over or quit meanwhile
		_hud.fade_in(FADE_TIME)
		return
	_hud.show_status("")
	_reset_field()
	_enter_quiz()
	await _wait(0.15)
	_hud.fade_in(FADE_TIME)


## Everyone back to their starting spots for the next attempt.
func _reset_field() -> void:
	_throw.clear_tsinelas()
	_player.respawn(_spawn.global_position)
	_lata.reset_to_home()
	for t in _tayas:
		t.return_to_guard()


func _add_caps(amount: int) -> void:
	_run_caps += amount
	Economy.add_caps(amount)


func _lose_awra(amount: int) -> void:
	awra = maxi(awra - amount, 0)
	_hud.set_awra(awra, MAX_AWRA)
	if awra <= 0:
		_game_over()


func _game_over() -> void:
	_set_state(State.GAME_OVER)
	Economy.save_profile() # bank the tansan earned this run
	_quiz.close()
	_throw.end()
	_stop_tayas()
	_hud.show_throw_ui(false)
	_set_player_mode(false, false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var rounds_cleared := round_number - 1
	var rank := GameManager.submit_score(theme_id, score, rounds_cleared)
	_hud.show_game_over(score, rounds_cleared, _run_caps, rank, GameManager.best_score(theme_id))


# --- Pause ----------------------------------------------------------------------

func _on_pause_requested() -> void:
	if state == State.GAME_OVER:
		return
	if get_tree().paused:
		_resume()
	else:
		get_tree().paused = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_hud.show_pause(true)


func _resume() -> void:
	_hud.show_pause(false)
	get_tree().paused = false
	if state == State.THROW or state == State.RUN:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _quit_to_menu() -> void:
	Economy.save_profile()
	GameManager.go_to_main_menu()


## move: walk/sprint allowed. look: mouse look allowed. Aim camera turns
## off whenever the player isn't in the throw.
func _set_player_mode(move: bool, look: bool) -> void:
	_player.controls_enabled = move
	_player.look_enabled = look
	if state != State.THROW:
		_player.set_aim_mode(false)
		_player.set_move_bounds(Rect2())
		_player.sprint_enabled = true


## Like create_timer, but stops counting while the game is paused.
func _wait(seconds: float) -> Signal:
	return get_tree().create_timer(seconds, false).timeout


func _set_state(new_state: State) -> void:
	state = new_state
	print("Round %d: %s" % [round_number, State.keys()[new_state]])
