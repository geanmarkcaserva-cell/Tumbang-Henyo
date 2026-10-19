extends Node3D
## Round controller: Quiz -> Throw -> Run -> Round clear, with Awra loss
## on a wrong answer, a miss, a tsinelas hit or a tag, and game over at 0 Awra.
## Also keeps score (GDD: Scoring), runs the taya squad (1-5 tayas, elites),
## the pause menu and the game over panel.
##
## Debug keys in the Throw state: H = force a hit, M = force a miss.

enum State { QUIZ, THROW, RUN, ROUND_CLEAR, GAME_OVER, TAGGED }

const TAYA_SCENE := preload("res://scenes/game/taya.tscn")
const WIND_LEAVES := preload("res://scenes/game/wind_leaves.gd")
const BULLSEYE_CAM := preload("res://scenes/game/bullseye_cam.gd")
## Bullseye: the round's attack lands with no mistake in the round so far
## (no wrong answer, no miss) and the tsinelas hits the lata before it
## touches the ground or anything else.
const POINTS_BULLSEYE := 150
const QUIZ_TIME := 15.0 ## seconds per question (the tutorial gives more)
## Practice round: the tayas are slower and take longer to stand the lata up.
const TUTORIAL_TAYA_SPEED_RATIO := 0.85
const TUTORIAL_RESET_MULT := 1.8

const MAX_AWRA := 100
const AWRA_WRONG := 20
const AWRA_MISS := 15
const AWRA_TAGGED := 25
const AWRA_SLIPPER_HIT := 10
const AWRA_ROUND_CLEAR := 10
const CAPS_CORRECT := 2 ## tansan per correct answer (GDD: Economy and shop)
const CAPS_ROUND_CLEAR := 10
const CAPS_VICTORY := 50 ## beating Mama's round (the whole game)
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

## Clock: the time of day moves forward whenever you score. Round 1 starts at
## 8:00 AM and round 15 at 6:00 PM, when Mama comes home.
const CLOCK_START := 17.0 * 60.0 ## 5:00 PM: golden hour on the court
const CLOCK_MAMA := 18.0 * 60.0 ## 6:00 PM: Mama comes home (the last round)
const DAY_NIGHT := preload("res://scenes/game/day_night.gd")
const HINT_COST := 100 ## tansan for a hint: steep on purpose, studying is cheaper
const CLOCK_ANSWER_STEP := 0.3 ## share of a round's time for a right answer
const CLOCK_HIT_STEP := 0.3 ## ...and for knocking the lata down
const CLOCK_ROUND_CAP := 0.9 ## the rest of the slice comes with the round clear

## Round 15, Mama's round (see _begin_mama_round).
const MAMA_ROUND := 15
const MAMA_SCRIPT := preload("res://scenes/game/mama.gd")
const BEACON_SCRIPT := preload("res://scenes/game/beacon.gd")
const MAMA_TIME := 30.0 ## seconds to reach the beacon house
const MAMA_WAIT_SPOT := Vector3(4.5, 0.0, -28.0) ## where she glares from during the quiz (off to the side, so she's in view)
const MAMA_HOUSE_DISTANCE := Vector2(60.0, 80.0) ## from the spawn; the court finish is ~36 m
const MAMA_GOAL_MARGIN := 1.8 ## metres around the house that count as "home"
const MAMA_AREA := Rect2(-68.0, -88.0, 136.0, 146.0) ## where you can run in her round
const AWRA_MAMA_CAUGHT := 30
const AWRA_MAMA_LATE := 30
const AWRA_MAMA_HIT := 10
const POINTS_MAMA := 1000

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
var _tut: Tutorial ## only on a first run (until finished or skipped)
var _leaves: Node3D
var _round_progress := 0.0 ## 0..1 through this round's slice of the clock
var _round_clean := true ## no wrong answer or miss yet this round (bullseye still possible)
var _bullseye: Node3D
var perfect_shots := 0
# For achievements (see _round_achievements).
var _streak := 0 ## right answers in a row this run
var _round_hurt := false ## hit or tagged this round
var _round_slipper_hit := false ## a tayas' tsinelas hit you this round
var _mama_hit_round := false ## a hanger or walis hit you in Mama's round

var _mama_on := false ## Mama's round is running
var _mama: CharacterBody3D
var _beacon: Node3D
var _goal: Dictionary = {} ## the house to reach (from Barangay.house_boxes())
var _mama_left := 0.0
var _mama_tick_shown := -1 ## last whole second that ticked
var _sky_cycle: Node ## day_night.gd: the sky follows the clock

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
	Music.play("game")
	theme_id = GameManager.selected_theme
	_lata_home = _lata.global_position
	_player.respawn(_spawn.global_position)
	_player.stamina_changed.connect(_hud.set_stamina)
	_lata.knocked_down.connect(_on_lata_knocked_down)
	_finish.body_entered.connect(_on_finish_body_entered)
	_quiz.answered.connect(_on_quiz_answered)
	_quiz.timed_out.connect(_on_quiz_timed_out)
	_quiz.hint_requested.connect(_on_hint_requested)
	_throw.power_changed.connect(_hud.set_power)
	_throw.thrown.connect(_on_thrown)
	_throw.settled.connect(_on_tsinelas_settled)
	_hud.pause_requested.connect(_on_pause_requested)
	_hud.resume_pressed.connect(_resume)
	_hud.play_again_pressed.connect(func(): Transition.reload())
	_hud.main_menu_pressed.connect(_quit_to_menu)
	Economy.caps_changed.connect(_hud.set_caps)
	_hud.bind_player(_player)

	_hook_taya($Arena/Taya)
	_ensure_tayas()

	_bullseye = BULLSEYE_CAM.new()
	_bullseye.name = "BullseyeCam"
	add_child(_bullseye)
	_bullseye.bullseye.connect(_on_bullseye)

	_leaves = WIND_LEAVES.new()
	_leaves.name = "WindLeaves"
	_leaves.follow = _player
	add_child(_leaves)
	if not Economy.tutorial_done:
		_tut = Tutorial.new()
		_tut.name = "Tutorial"
		add_child(_tut)
		_tut.setup(_hud, _player, _finish)

	QuizDatabase.reset_run()
	Achievements.add_stat("runs")
	if Lobby.in_match():
		# Class game: same seed for everyone, so the questions (and the wind)
		# come in the same order for the whole class.
		seed(Lobby.match_seed)
		_hud.enable_class_board()
		Lobby.match_ended.connect(_on_class_ended)
		Lobby.left.connect(_on_class_left)
	_hud.set_awra(awra, MAX_AWRA)
	_hud.set_round(round_number)
	_hud.set_score(score)
	_hud.set_caps(Economy.caps)
	_hud.update_wind(Vector3.ZERO, _player.global_basis)
	_sky_cycle = DAY_NIGHT.new()
	_sky_cycle.name = "DayNight"
	add_child(_sky_cycle)
	var barangay := _barangay()
	Sfx.start_loop("crickets", -30.0) # louder as it gets dark (_on_sky_tint)
	_sky_cycle.tint_changed.connect(_leaves.set_tint)
	_sky_cycle.tint_changed.connect(_on_sky_tint)
	_sky_cycle.setup($Arena/WorldEnvironment, $Arena/Sun, barangay.lamp_spots() if barangay else [])
	_update_clock(true)
	_begin()


## First run: the tutorial's welcome card, then the first question.
func _begin() -> void:
	if _tut:
		_set_player_mode(false, false) # stand still behind the welcome card
		_hud.set_context("none")
		await _tut.start()
	_enter_quiz()


func _tutorial_on() -> bool:
	return _tut != null and _tut.running


func _exit_tree() -> void:
	Sfx.stop_all_loops() # wind, crickets, charge


## Crickets fade up as the sky darkens (a few at golden hour, a chorus by 6 PM).
func _on_sky_tint(tint: Color) -> void:
	var night := clampf(1.0 - (tint.v - 0.3) / 0.65, 0.0, 1.0)
	Sfx.set_loop("crickets", lerpf(-30.0, -6.0, night))


## Lock the mouse for aiming (not with touch controls: fingers need the cursor free).
func _capture_mouse() -> void:
	if not TouchControls.active:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	if Lobby.is_client():
		_report_class()
	if state == State.THROW:
		_hud.update_wind(_wind, _player.global_basis)
	elif state == State.RUN and _mama_on:
		_mama_tick(delta)


# --- Class game (multiplayer) ---------------------------------------------------------

## Tell the teacher's lobby how this run is going. The live score counts the
## points earned so far this round (banked on round clear) so the board moves
## as students answer and hit. Lobby only sends when something changed.
func _report_class() -> void:
	var live := score + int(round(_round_points * (1.0 + 0.1 * (round_number - 1))))
	if state == State.ROUND_CLEAR or state == State.GAME_OVER:
		live = score
	Lobby.report(live, round_number, awra, state == State.GAME_OVER, perfect_shots)


## The teacher ended the class game: this run is over.
func _on_class_ended() -> void:
	if state == State.GAME_OVER:
		return
	_game_over()
	_hud.show_banner("Time's up!", "Your teacher ended the game.", UiKit.ACCENT, 2.4)


func _on_class_left(reason: String) -> void:
	_hud.show_status("Lost the class lobby: %s Your game goes on solo." % reason)


# --- Clock --------------------------------------------------------------------------

## Time of day in minutes: each round is an equal slice between 8 AM and 6 PM.
func _clock_minutes() -> float:
	var per_round := (CLOCK_MAMA - CLOCK_START) / float(MAMA_ROUND - 1)
	return CLOCK_START + per_round * (round_number - 1 + _round_progress)


## Scored something: the clock ticks forward (never into the next round).
func _advance_clock(step: float) -> void:
	_round_progress = minf(_round_progress + step, CLOCK_ROUND_CAP)
	_update_clock()


## Clock on the HUD and the sky both follow the time of day.
func _update_clock(instant: bool = false) -> void:
	var minutes := _clock_minutes()
	_hud.set_clock(minutes, instant)
	if _sky_cycle:
		_sky_cycle.set_time(minutes, instant)


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


## How much of the aim line to show. The design used to shorten it in later
## rounds (to 0 from round 10); now the full line and landing circle always show.
func _preview_for_round() -> float:
	return 1.0


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
	_hud.set_context("quiz")
	_leaves.set_active(false)
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
	_quiz.time_limit = _tut.quiz_time_limit() if _tutorial_on() else QUIZ_TIME
	_quiz.ask(_question.question, choices)
	# Hints cost real tansan; none in the free practice round.
	_quiz.set_hint(not _tutorial_on(), HINT_COST, Economy.caps >= HINT_COST)
	if _tutorial_on():
		_tut.on_quiz_shown()


func _on_quiz_answered(choice_index: int) -> void:
	if state != State.QUIZ:
		return
	_quiz.show_result(choice_index, _correct_index, _question.explanation)
	if _tutorial_on():
		_tut.on_answer(choice_index == _correct_index)
	if choice_index == _correct_index:
		var points := mini(POINTS_ANSWER_BASE + POINTS_PER_SECOND * int(_quiz.get_time_left()), POINTS_ANSWER_MAX)
		_round_points += points
		_add_caps(CAPS_CORRECT)
		_advance_clock(CLOCK_ANSWER_STEP)
		_streak += 1
		Achievements.unlock("tama")
		Achievements.add_stat("correct_total")
		if _streak >= 10:
			Achievements.unlock("henyo")
		if not _tutorial_on() and _quiz.get_time_left() >= 12.0:
			Achievements.unlock("speed_reader")
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


## Hint: pay 100 tansan to cross out one wrong choice (once per question).
func _on_hint_requested() -> void:
	if state != State.QUIZ or Economy.caps < HINT_COST or not _quiz.can_hint():
		return
	Economy.add_caps(-HINT_COST)
	Economy.save_profile()
	var wrong := [0, 1, 2].filter(func(i): return i != _correct_index)
	_quiz.eliminate(wrong.pick_random())
	Sfx.play("hint")
	_hud.show_status("Hint: one wrong answer crossed out.  -%d tansan" % HINT_COST)


func _on_quiz_timed_out() -> void:
	if state != State.QUIZ:
		return
	_quiz.show_result(-1, _correct_index, _question.explanation)
	if _tutorial_on():
		_tut.on_answer(false)
	_answer_failed()


func _answer_failed() -> void:
	_round_clean = false
	_streak = 0
	_hud.show_status("")
	_player.hurt() # squish + red flash
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
	_wind = Vector3.ZERO if _tutorial_on() else _roll_wind()
	# Walk freely behind the throw line (no sprinting), aim with the mouse.
	_set_player_mode(true, true)
	_player.sprint_enabled = false
	_player.set_move_bounds(THROW_ZONE)
	_player.set_aim_mode(true)
	_capture_mouse()
	_hud.show_throw_ui(true)
	_hud.set_context("throw")
	_hud.update_wind(_wind, _player.global_basis)
	_leaves.set_wind(_wind)
	_leaves.set_active(true)
	if _wind.length() > 0.05: # wind you can hear, stronger = louder
		Sfx.fade_loop("wind", lerpf(-16.0, 0.0, clampf(_wind.length() / 6.0, 0.0, 1.0)), 0.8)
	if _tutorial_on():
		_hud.show_status("")
		_tut.on_throw_begin()
	else:
		_hud.show_status("Tama! Knock down the lata!")
		if _wind.length() > 0.05 and Economy.first_time("wind"):
			_hud.show_tip("Wind!", "The leaves show where it blows. Aim a little into it.", 6.0)
	_throw.begin(_player, _wind, _preview_for_round())


func _on_thrown() -> void:
	_hud.show_throw_ui(false)
	_hud.set_context("none")
	_hud.show_status("")
	if _tutorial_on():
		_tut.on_thrown()
	elif _round_clean:
		var slipper: Node3D = _throw.current_tsinelas()
		if slipper:
			_bullseye.watch(slipper, _lata, _throw._wind_accel())


## A perfect, clean first hit: bonus points and the rainbow BULLSEYE!
## (the slow-motion close-up is BullseyeCam's job).
func _on_bullseye() -> void:
	perfect_shots += 1
	Sfx.play("bullseye")
	_round_points += POINTS_BULLSEYE
	_hud.show_bullseye(POINTS_BULLSEYE)
	Achievements.unlock("bullseye")
	if perfect_shots >= 5:
		Achievements.unlock("sharpshooter")
	if perfect_shots >= 10:
		Achievements.unlock("ten_hit_wonder")


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
	_hud.set_context("none")
	var practice := _tutorial_on()
	_round_clean = false
	_lose_awra(AWRA_MISS)
	if state == State.GAME_OVER:
		return
	Sfx.play("miss")
	_hud.show_status("Sablay! Missed the lata.")
	_player.controls_enabled = false
	if practice:
		_tut.on_miss()
	await _wait(1.6 if practice else 1.2)
	if state == State.THROW:
		if practice:
			_retry_throw() # practice: straight back to the line, no new question
		else:
			_next_attempt()


func _on_lata_knocked_down() -> void:
	if state == State.THROW:
		_round_points += POINTS_HIT
		Sfx.play("voice_tumba") # recorded shout, once the file exists
		_advance_clock(CLOCK_HIT_STEP)
		Achievements.unlock("tumba")
		if _wind.length() >= 4.0:
			Achievements.unlock("windy")
		_throw.end()
		_enter_run()


# --- Run ----------------------------------------------------------------

func _enter_run() -> void:
	if _mama_on:
		_enter_mama_run()
		return
	_set_state(State.RUN)
	_set_player_mode(true, true)
	_hud.show_throw_ui(false)
	_hud.set_context("run")
	_leaves.set_active(false)
	_capture_mouse()
	var practice := _tutorial_on()
	if practice:
		_hud.show_status("")
		_tut.on_run()
	else:
		Sfx.play("voice_takbo")
		var who := "the taya" if _tayas.size() == 1 else "a taya"
		_hud.show_status("Tumba! Run before %s stands the lata back up!" % who)
	var speed_ratio := TUTORIAL_TAYA_SPEED_RATIO if practice else TAYA_SPEED_RATIO
	var reset_time := _lata_reset_time() * (TUTORIAL_RESET_MULT if practice else 1.0)
	for t in _tayas:
		t.configure(_player.walk_speed * speed_ratio, reset_time,
				_taya_reaction_time(), _taya_aim_error())
	# The nearest taya stands the lata up; every other taya goes after the
	# player straight away (the resetter joins once the lata is up).
	var resetter := _nearest_taya_to_lata()
	resetter.start_reset()
	for t in _tayas:
		if t != resetter:
			t.start_chase()


func _on_taya_lata_reset() -> void:
	if state != State.RUN:
		return
	Sfx.play("lata_set")
	for t in _tayas:
		t.start_chase()
	if _tutorial_on():
		_tut.on_lata_up()
	else:
		_hud.show_status("Lata is up! Takbo!")


func _on_hit_by_slipper(from_taya: CharacterBody3D) -> void:
	if state != State.RUN:
		return
	_round_hurt = true
	_round_slipper_hit = true
	Sfx.play("slap", 0.0, 1.0, 0.06)
	Sfx.play("voice_aray")
	var practice := _tutorial_on()
	_lose_awra(AWRA_SLIPPER_HIT)
	if state == State.GAME_OVER:
		return
	var away := _player.global_position - from_taya.global_position
	away.y = 0.0
	_player.stagger(SLIPPER_STAGGER_TIME, away.normalized() * SLIPPER_KNOCKBACK)
	_hud.show_status("Aray!" if practice else "Aray! -%d Awra" % AWRA_SLIPPER_HIT)


func _on_tagged() -> void:
	if state != State.RUN:
		return
	_set_state(State.TAGGED)
	_round_hurt = true
	Sfx.play("tagged")
	Sfx.play("voice_taya_ka")
	_set_player_mode(false, false)
	_hud.set_context("none")
	_stop_tayas()
	var practice := _tutorial_on()
	_lose_awra(AWRA_TAGGED)
	if state == State.GAME_OVER:
		return
	if practice:
		_hud.show_status("Taya ka!")
		_tut.on_tagged()
	else:
		_hud.show_status("Taya ka! -%d Awra" % AWRA_TAGGED)
	await _wait(2.4 if practice else 1.8)
	if state == State.TAGGED:
		if practice:
			_retry_throw()
		else:
			_next_attempt()


func _on_finish_body_entered(body: Node3D) -> void:
	if _mama_on:
		return # in Mama's round the finish is the beacon house
	if state == State.RUN and body == _player:
		_round_clear()


# --- Round clear / Awra / game over --------------------------------------

func _round_clear() -> void:
	_set_state(State.ROUND_CLEAR)
	_set_player_mode(false, false)
	_hud.set_context("none")
	_stop_tayas()
	_player.celebrate(-1.0) # until the next round respawns them
	Sfx.play("round_clear")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_round_achievements()
	awra = mini(awra + AWRA_ROUND_CLEAR, MAX_AWRA)
	_hud.set_awra(awra, MAX_AWRA)
	var gained := int(round((_round_points + POINTS_ROUND_CLEAR) * (1.0 + 0.1 * (round_number - 1))))
	score += gained
	if score >= 10000:
		Achievements.unlock("big_score")
	if score >= 15000:
		Achievements.unlock("legend")
	_round_points = 0
	_hud.set_score(score)
	_add_caps(CAPS_ROUND_CLEAR)
	Economy.save_profile()
	_hud.show_status("Round %d clear!  +%d points  +%d Awra  +%d tansan" % [round_number, gained, AWRA_ROUND_CLEAR, CAPS_ROUND_CLEAR])
	await _wait(2.2)
	if state != State.ROUND_CLEAR:
		return
	if _tutorial_on():
		_hud.show_status("")
		await _tut.on_round_clear() # "You're ready!" card, waits for the player
		if state != State.ROUND_CLEAR:
			return
	# Fade to black, reset everything out of sight, fade back in on the new question.
	await _hud.fade_out(FADE_TIME)
	if state != State.ROUND_CLEAR:
		return
	round_number += 1
	_round_progress = 0.0
	_round_clean = true
	_round_hurt = false
	_round_slipper_hit = false
	_mama_hit_round = false
	_hud.set_round(round_number, round_number == MAMA_ROUND)
	_update_clock()
	_hud.show_status("")
	if _mama_on:
		_end_mama_round() # Mama's calmed down: the tayas come back out
	_reset_field()
	if round_number == MAMA_ROUND:
		_begin_mama_round()
		return
	var joined := _ensure_tayas()
	_enter_quiz()
	if joined > 0:
		var elite_joined: bool = _tayas.back().elite
		_hud.show_status("Round %d: %s" % [round_number, "an ELITE taya joins! (3 tsinelas)" if elite_joined else "another taya joins!"])
		if elite_joined and Economy.first_time("elite"):
			_hud.show_tip("Elite taya", "Elites throw tsinelas at you. Jump to dodge.", 6.0)
		elif not elite_joined and Economy.first_time("squad"):
			_hud.show_tip("Two tayas", "One resets the lata, one chases you. Sprint early!", 6.0)
	await _wait(0.15) # one beat of black so the jump isn't visible
	_hud.fade_in(FADE_TIME)


## Round cleared: hand out what this round earned.
func _round_achievements() -> void:
	Achievements.unlock("takbo")
	if _round_clean and not _round_hurt:
		Achievements.unlock("flawless")
	if not _mama_on:
		if _tayas.size() >= 3 and not _round_slipper_hit:
			Achievements.unlock("untouchable")
		for t in _tayas:
			if t.elite:
				Achievements.unlock("elite")
	else:
		Achievements.unlock("nakauwi")
		if not _mama_hit_round:
			Achievements.unlock("hanger_dodger")
	if awra <= 15 and not _tutorial_on():
		Achievements.unlock("last_breath")


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


## Practice round: after a miss or a tag, back to the line without a new question.
func _retry_throw() -> void:
	var from_state := state
	await _hud.fade_out(FADE_TIME)
	if state != from_state:
		_hud.fade_in(FADE_TIME)
		return
	_hud.show_status("")
	_reset_field()
	_enter_throw()
	await _wait(0.15)
	_hud.fade_in(FADE_TIME)


## Everyone back to their starting spots for the next attempt.
func _reset_field() -> void:
	_bullseye.cancel()
	_throw.clear_tsinelas()
	_player.respawn(_spawn.global_position)
	_lata.reset_to_home()
	for t in _tayas:
		t.return_to_guard()
	if _mama_on:
		_mama.wait_at(MAMA_WAIT_SPOT)
		_beacon.visible = false
		_hud.show_boss_timer(false)
		_hud.set_beacon(null)


func _add_caps(amount: int) -> void:
	if amount > 0:
		Sfx.play("coin", -3.0, 1.0, 0.05)
	_run_caps += amount
	Economy.add_caps(amount)


func _lose_awra(amount: int) -> void:
	if _tutorial_on():
		return # the practice round is free
	awra = maxi(awra - amount, 0)
	_hud.set_awra(awra, MAX_AWRA)
	if awra <= 0:
		_game_over()


## won = made it home in Mama's round (the end of the game).
func _game_over(won: bool = false) -> void:
	_set_state(State.GAME_OVER)
	if not won: # the win already played its fanfare in _victory()
		Sfx.play("game_over")
	Sfx.stop_loop("charge")
	Economy.save_profile() # bank the tansan earned this run
	_quiz.close()
	_bullseye.cancel()
	_throw.end()
	_stop_tayas()
	if _mama:
		_mama.stop()
	_hud.show_throw_ui(false)
	_set_player_mode(false, false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var rounds_cleared := round_number if won else round_number - 1
	var rank := GameManager.submit_score(theme_id, score, rounds_cleared)
	_hud.show_game_over(score, rounds_cleared, _run_caps, rank, GameManager.best_score(theme_id), won)
	if Lobby.is_client():
		_report_class() # final score, marked out
		await get_tree().create_timer(0.6).timeout # let the board catch up
		_hud.set_class_result(Lobby.my_rank(), Lobby.players.size())
		if Lobby.my_rank() == 1 and Lobby.players.size() >= 2:
			Achievements.unlock("class_champ")


# --- Mama's round (round 15, 6:00 PM) ---------------------------------------------
#
# The clock hits 6 PM and Mama comes home with her belt. Every taya runs off
# into a house and disappears. The round still starts with a question and a
# throw (Mama glares from the far end of the court), but once the lata is
# down the finish line is gone: a beam of light marks a house far out in the
# barangay, and you have 30 seconds to get there while Mama chases you,
# throwing hangers and walis. She's faster than you, so use the houses.

## Called on the black screen after round 14 is cleared.
func _begin_mama_round() -> void:
	_mama_on = true
	Achievements.unlock("mamas_home")
	_set_player_mode(false, false)
	_hud.set_context("none")
	var barangay := _barangay()
	if barangay:
		barangay.set_open_world(true)
	if _mama == null:
		_mama = MAMA_SCRIPT.new()
		_mama.name = "Mama"
		_arena.add_child(_mama)
		_mama.setup(_player)
		_mama.caught_player.connect(_on_mama_caught)
		_mama.hit_player.connect(_on_mama_hit)
	_mama.visible = true
	_mama.process_mode = Node.PROCESS_MODE_INHERIT
	_mama.wait_at(MAMA_WAIT_SPOT)
	_goal = _pick_goal_house()
	if _beacon == null:
		_beacon = BEACON_SCRIPT.new()
		_beacon.name = "Beacon"
		_beacon.footprint_radius = maxf(_goal.half.x, _goal.half.y) + MAMA_GOAL_MARGIN * 0.6
		_arena.add_child(_beacon)
	_beacon.global_position = _goal.centre
	_beacon.visible = false
	await _wait(0.15)
	_hud.fade_in(FADE_TIME)
	_hud.show_banner("6:00 PM", "Mama's home!", Color(1.0, 0.42, 0.36), 2.2)
	Sfx.play("bell")
	Sfx.play("mama_sting", -2.0)
	await _wait(0.7)
	_send_tayas_home()
	await _wait(2.4)
	if not _mama_on or state == State.GAME_OVER:
		return
	if Economy.first_time("mama"):
		_hud.show_tip("Mama's round", "Hit the lata, then run to the house with the light in 30 seconds. Mama is faster than you: cut around houses to lose her!", 9.0)
	_enter_quiz()


## Round 16: Mama goes back inside, the tayas come back out.
func _end_mama_round() -> void:
	_mama_on = false
	_goal = {}
	_mama.stop()
	_mama.clear_thrown()
	_mama.visible = false
	_mama.process_mode = Node.PROCESS_MODE_DISABLED
	_beacon.visible = false
	_hud.show_boss_timer(false)
	_hud.set_beacon(null)
	var barangay := _barangay()
	if barangay:
		barangay.set_open_world(false)
	for t in _tayas:
		t.come_back()
	_ensure_tayas()


func _barangay() -> Node:
	return _arena.get_node_or_null("Barangay")


## Every taya runs into one of the houses near it and vanishes.
func _send_tayas_home() -> void:
	var houses: Array = _barangay().house_boxes() if _barangay() else []
	for t in _tayas:
		if houses.is_empty():
			t.vanish()
			continue
		var tp := Vector3(t.global_position.x, 0.0, t.global_position.z)
		houses.sort_custom(func(a, b): return tp.distance_to(a.centre) < tp.distance_to(b.centre))
		var house: Dictionary = houses[randi() % mini(5, houses.size())]
		t.flee_to(house.centre, maxf(house.half.x, house.half.y) + 0.8)


## A random house far out in the barangay (60-80 m from the start; the court's
## finish line is about 36 m away).
func _pick_goal_house() -> Dictionary:
	var houses: Array = _barangay().house_boxes() if _barangay() else []
	if houses.is_empty():
		return {"name": "", "centre": Vector3(0, 0, -70), "half": Vector2(3, 3), "basis": Basis()}
	var start := Vector3(_spawn.global_position.x, 0.0, _spawn.global_position.z)
	var far: Array = houses.filter(func(h):
		var d: float = start.distance_to(h.centre)
		return d >= MAMA_HOUSE_DISTANCE.x and d <= MAMA_HOUSE_DISTANCE.y)
	if far.is_empty():
		houses.sort_custom(func(a, b): return start.distance_to(a.centre) > start.distance_to(b.centre))
		return houses[0]
	return far[randi() % far.size()]


## Lata down in Mama's round: light the beacon and run.
func _enter_mama_run() -> void:
	_set_state(State.RUN)
	_set_player_mode(true, true)
	_player.set_move_bounds(MAMA_AREA, true)
	_hud.show_throw_ui(false)
	_hud.set_context("run")
	_leaves.set_active(false)
	_capture_mouse()
	_beacon.visible = true
	_hud.set_beacon(_goal.centre, _player)
	_mama_left = MAMA_TIME
	_hud.show_boss_timer(true)
	_hud.set_boss_time(_mama_left)
	_hud.show_status("Takbo! Run home to the light!")
	_mama_tick_shown = -1
	Music.play("mama")
	_mama.start_chase()


func _mama_tick(delta: float) -> void:
	_mama_left -= delta
	_hud.set_boss_time(_mama_left)
	# Ticks for the last 10 seconds, sharper for the last 5.
	var whole := int(ceil(_mama_left))
	if whole != _mama_tick_shown and whole <= 10 and whole > 0:
		_mama_tick_shown = whole
		Sfx.play("tick_urgent" if whole <= 5 else "tick")
	if _at_goal():
		_mama_success()
	elif _mama_left <= 0.0:
		_mama_failed(false)


func _at_goal() -> bool:
	if _goal.is_empty():
		return false
	var b: Basis = _goal.basis
	var local: Vector3 = b.inverse() * (_player.global_position - _goal.centre)
	return absf(local.x) <= _goal.half.x + MAMA_GOAL_MARGIN and absf(local.z) <= _goal.half.y + MAMA_GOAL_MARGIN


func _mama_success() -> void:
	_mama.stop()
	_mama.clear_thrown()
	_hud.show_boss_timer(false)
	_hud.set_beacon(null)
	_round_points += POINTS_MAMA
	_victory()


## Home before Mama caught you: Mama's round is the last one, so this wins
## the game. Bank the round like a normal clear, then the victory screen.
func _victory() -> void:
	_set_state(State.ROUND_CLEAR)
	_set_player_mode(false, false)
	_hud.set_context("none")
	_player.celebrate(-1.0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_round_achievements()
	var gained := int(round((_round_points + POINTS_ROUND_CLEAR) * (1.0 + 0.1 * (round_number - 1))))
	score += gained
	_round_points = 0
	_hud.set_score(score)
	_add_caps(CAPS_VICTORY)
	if score >= 10000:
		Achievements.unlock("big_score")
	if score >= 15000:
		Achievements.unlock("legend")
	Sfx.play("victory")
	_hud.show_banner("Nakauwi ka na!", "Mama's not angry anymore.  +%d points" % gained, Color(0.55, 0.92, 1.0), 2.6)
	await _wait(3.4)
	if state == State.ROUND_CLEAR:
		_game_over(true)


func _on_mama_caught() -> void:
	if state == State.RUN and _mama_on:
		_mama_failed(true)


## Caught by Mama, or too late: lose Awra and try the round again.
func _mama_failed(caught: bool) -> void:
	_set_state(State.TAGGED)
	_round_hurt = true
	_set_player_mode(false, false)
	_hud.set_context("none")
	_hud.show_boss_timer(false)
	_hud.set_beacon(null)
	_mama.stop()
	_player.hurt()
	_lose_awra(AWRA_MAMA_CAUGHT if caught else AWRA_MAMA_LATE)
	if state == State.GAME_OVER:
		return
	Sfx.play("palo" if caught else "timeout")
	if caught:
		Sfx.play("voice_mama_palo")
		_hud.show_banner("PALO!", "Mama caught you.  -%d Awra" % AWRA_MAMA_CAUGHT, Color(1.0, 0.42, 0.36), 1.4)
	else:
		_hud.show_banner("Too late!", "Mama's still angry.  -%d Awra" % AWRA_MAMA_LATE, Color(1.0, 0.42, 0.36), 1.4)
	_hud.show_status("")
	await _wait(2.2)
	if state == State.TAGGED:
		_next_attempt()


func _on_mama_hit() -> void:
	if state != State.RUN or not _mama_on:
		return
	_round_hurt = true
	_mama_hit_round = true
	Sfx.play("slap", 0.0, 0.85, 0.06)
	Sfx.play("voice_aray")
	_lose_awra(AWRA_MAMA_HIT)
	if state == State.GAME_OVER:
		return
	var away := _player.global_position - _mama.global_position
	away.y = 0.0
	_player.stagger(SLIPPER_STAGGER_TIME, away.normalized() * SLIPPER_KNOCKBACK)
	_hud.show_status("Aray! -%d Awra" % AWRA_MAMA_HIT)


# --- Pause ----------------------------------------------------------------------

func _on_pause_requested() -> void:
	if state == State.GAME_OVER:
		return
	if get_tree().paused:
		_resume()
	else:
		get_tree().paused = true
		Sfx.play("ui_pause")
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_hud.show_pause(true)


func _resume() -> void:
	_hud.show_pause(false)
	get_tree().paused = false
	if state == State.THROW or state == State.RUN:
		_capture_mouse()


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
	if new_state != State.THROW:
		Sfx.fade_loop("wind", -80.0, 0.8) # wind is only heard on the throw line
		Sfx.stop_loop("charge")
	print("Round %d: %s" % [round_number, State.keys()[new_state]])
