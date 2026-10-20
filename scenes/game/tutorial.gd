class_name Tutorial
extends Node
## First-run guided round. Teaches by doing: each step waits for the player
## to actually do the thing (move, aim, charge, throw, run, sprint), ticks it
## off with a "Nice!" and moves on. The practice round is forgiving: no Awra
## is lost, the time limit is longer, a miss or a tag goes straight back to the
## throw, and the tayas are slower.
##
## Copy rule: a headline plus one short line, and the controls as keycaps.
## Anything longer belongs on the welcome or done card.
##
## The round controller (game.gd) calls the on_*() hooks; the tutorial talks
## through the HUD's coach card and highlight ring, and puts a beacon over
## the finish line. Keyboard or touch wording follows Settings > Touch controls.
## Finished or skipped: Economy.tutorial_done is saved; "Replay tutorial" in
## Settings clears it.

signal finished ## completed or skipped; the normal game carries on
signal _answered(id: String)

enum Step { WELCOME, QUIZ, MOVE, AIM, CHARGE, FLYING, RUN, SPRINT, DODGE, DONE }

const TOTAL := 5
const QUIZ_TIME := 30.0
const OOPS := Color(1.0, 0.62, 0.52)
const ICON_AWRA := preload("res://art/ui/hud/icon_awra.webp")
const ICON_TANSAN := preload("res://art/ui/hud/icon_tansan.webp")
const ICON_SPRINT := preload("res://art/ui/hud/icon_sprint.webp")

var running := false
var step: Step = Step.WELCOME

var _hud: CanvasLayer
var _player: CharacterBody3D
var _finish: Node3D
var _marker: Node3D
var _step_time := 0.0
var _move_start := Vector3.ZERO
var _last_aim := Vector3.ZERO
var _aim_turned := 0.0
var _busy := false ## a "Nice!" is showing; don't advance underneath it
var _retry := false ## the next throw is a second try (short card)
var _lata_up := false


func _exit_tree() -> void:
	Achievements.paused = false # quit to the menu mid-tutorial


func setup(hud: CanvasLayer, player: CharacterBody3D, finish: Node3D) -> void:
	_hud = hud
	_player = player
	_finish = finish


## Show the welcome card. await it: returns when the player starts or skips.
func start() -> void:
	running = true
	Achievements.paused = true # practice round: nothing unlocks
	_hud.set_tutorial_running(true)
	_hud.coach.button_pressed.connect(func(id: String): _answered.emit(id))
	_hud.coach.skip_pressed.connect(skip)
	_hud.skip_tutorial_pressed.connect(skip)
	_hud.coach.show_card({
		"center": true,
		"label": "QUICK TUTORIAL",
		"title": "Welcome to Tumbang Henyo!",
		"body": "Three steps, one practice round.",
		"points": [
			{"badge": "1", "title": "Answer", "text": "Earn your throw"},
			{"badge": "2", "title": "Throw", "text": "Knock down the lata"},
			{"badge": "3", "title": "Run", "text": "Reach the finish line"},
		],
		"note": "Practice round: no Awra lost",
		"buttons": [{"id": "go", "text": "Start", "primary": true}, {"id": "skip", "text": "Skip"}],
	})
	var choice: String = await _answered
	if choice == "skip":
		skip()
	else:
		_hud.coach.hide_card()


## Same as clicking a card button (used by automated tests).
func press(id: String) -> void:
	_answered.emit(id)


## Stop the tutorial for good (from the welcome card, a card's Skip link or
## the pause menu).
func skip() -> void:
	if not running:
		return
	_finish_up()


func quiz_time_limit() -> float:
	return QUIZ_TIME


func _touch() -> bool:
	return TouchControls.active


## A coaching card for step n: headline, one short line, controls.
## kb / touch: the controls hint for keyboard or the line for touch screens.
func _coach(n: int, title: String, body: String, kb: Dictionary = {}, touch_line: String = "", extra: Dictionary = {}) -> void:
	var card := {"step": n, "steps": TOTAL, "skip": true, "title": title, "body": body}
	if _touch():
		if touch_line != "":
			card.body = touch_line
	else:
		card.merge(kb)
	card.merge(extra, true)
	_hud.coach.show_card(card)


# --- Hooks from the round controller ---------------------------------------------

func on_quiz_shown() -> void:
	if not running:
		return
	_go(Step.QUIZ)
	_coach(1, "Answer the question", "Faster answers score more.",
			{"keys": [[Settings.key_name("answer_a"), Settings.key_name("answer_b"), Settings.key_name("answer_c")], "or click an answer"]}, "Tap an answer. Faster scores more.")
	_hud.highlight("quiz")


func on_answer(correct: bool) -> void:
	if not running:
		return
	_hud.highlight("")
	if correct:
		await _nice("Correct!")
		if running and step == Step.QUIZ:
			_hud.coach.hide_card()
	else:
		_coach(1, "Not quite!", "Wrong answers cost Awra. Free in practice.", {}, "",
				{"title_color": OOPS})
		_hud.highlight("awra")


func on_throw_begin() -> void:
	if not running:
		return
	_lata_up = false
	if _retry:
		_go(Step.CHARGE)
		_coach(4, "Try again", "Aim, charge, release.", _charge_keys(), "Aim, then hold and release Throw.")
		_hud.highlight("throw_button" if _touch() else "power")
		return
	_go(Step.MOVE)
	_move_start = _player.global_position
	_coach(2, "Step up to the line", "Walk up behind the yellow line.",
			{"keys": [_move_keys(), "Move"]}, "Drag on the left side to move.")
	_hud.highlight("stick" if _touch() else "")


func on_thrown() -> void:
	if not running:
		return
	_hud.highlight("")
	if step == Step.CHARGE or step == Step.AIM or step == Step.MOVE:
		_go(Step.FLYING)
		await _nice("Nice throw!")
		if running and step == Step.FLYING:
			_hud.coach.hide_card()


func on_miss() -> void:
	if not running:
		return
	_retry = true
	_go(Step.FLYING)
	_coach(4, "So close!", "Misses cost Awra. Free in practice.", {}, "", {"title_color": OOPS})


func on_run() -> void:
	if not running:
		return
	_go(Step.RUN)
	_show_marker(true)
	_coach(5, "Tumba! Run!", "Reach the glowing finish line.",
			{"keys": [_move_keys(), "Run"]}, "Use the joystick to run to the light.")
	_hud.highlight("")


func on_lata_up() -> void:
	_lata_up = true
	if running and (step == Step.RUN or step == Step.SPRINT):
		_show_dodge()


func on_tagged() -> void:
	if not running:
		return
	_retry = true
	_show_marker(false)
	_go(Step.FLYING)
	_hud.highlight("")
	_coach(5, "Tagged!", "Tags cost Awra. Back to the line!", {}, "", {"title_color": OOPS})


## The practice round is cleared. await it: returns when the player is ready.
func on_round_clear() -> void:
	if not running:
		return
	_go(Step.DONE)
	_show_marker(false)
	_hud.coach.show_card({
		"center": true,
		"label": "TUTORIAL COMPLETE",
		"title": "You're ready!",
		"points_layout": "rows",
		"points": [
			{"icon": ICON_AWRA, "text": "Mistakes cost Awra. At zero, it's game over."},
			{"icon": ICON_TANSAN, "text": "Clear rounds to earn tansan for new looks."},
			{"icon": ICON_SPRINT, "text": "Later rounds bring wind and more tayas."},
		],
		"buttons": [{"id": "done", "text": "Let's play!", "primary": true}],
		"width": 1000.0,
	})
	_hud.highlight("")
	await _answered
	_finish_up()
	# Training is over now, so this is the first one that can unlock.
	Achievements.unlock("first_steps")


# --- Step logic ---------------------------------------------------------------------

func _process(delta: float) -> void:
	if not running or _busy:
		return
	_step_time += delta
	match step:
		Step.MOVE:
			var moved := Vector2(_player.global_position.x - _move_start.x, _player.global_position.z - _move_start.z).length()
			if moved > 1.2 or (_step_time > 8.0 and moved > 0.3):
				_step_done(_enter_aim)
		Step.AIM:
			var aim: Vector3 = -_player.get_aim_basis().z
			_aim_turned += _last_aim.angle_to(aim)
			_last_aim = aim
			if _aim_turned > 0.45 or _step_time > 7.0:
				_step_done(_enter_charge)
		Step.RUN:
			if _step_time > 1.8:
				_enter_sprint()
		Step.SPRINT:
			if _player.stamina < _player.max_stamina * 0.75:
				_busy = true
				await _nice("That's it!")
				_busy = false
				if running and step == Step.SPRINT:
					if _lata_up:
						_show_dodge()
					else:
						_hud.coach.hide_card()
						_hud.highlight("")
						_go(Step.DODGE) # waits for the lata to come up
		Step.DODGE:
			if _step_time > 6.0 and _lata_up:
				_hud.coach.hide_card()


func _enter_aim() -> void:
	_go(Step.AIM)
	_last_aim = -_player.get_aim_basis().z
	_aim_turned = 0.0
	_coach(3, "Aim at the lata", "The circle shows where it lands.",
			{"keys": [["Mouse"], "Aim"]}, "Drag on the right side to aim.")
	_hud.highlight("")


func _enter_charge() -> void:
	_go(Step.CHARGE)
	_coach(4, "Charge and throw", "Let go near the top for power.", _charge_keys(),
			"Hold Throw, let go near the top.")
	_hud.highlight("throw_button" if _touch() else "power")


## The player's movement keys (Settings > Controls), in W A S D order.
func _move_keys() -> Array:
	return [Settings.key_name("move_forward"), Settings.key_name("move_left"),
			Settings.key_name("move_back"), Settings.key_name("move_right")]


func _charge_keys() -> Dictionary:
	return {"keys": [["Hold " + Settings.key_name("throw")], "Charge"], "keys2": [["Release"], "Throw"]}


func _enter_sprint() -> void:
	_go(Step.SPRINT)
	_coach(5, "Sprint!", "Faster than the taya, but it uses Energy.",
			{"keys": [[Settings.key_name("sprint")], "Hold to sprint"]}, "Hold the shoe button to sprint.")
	_hud.highlight("energy")


func _show_dodge() -> void:
	_go(Step.DODGE)
	_coach(5, "The taya is coming!", "Don't get tagged.",
			{"keys": [[Settings.key_name("jump")], "Jump"], "keys2": [[Settings.key_name("look_back")], "Look back"]}, "Jump to dodge. Don't get tagged!")
	_hud.highlight("")


func _step_done(next: Callable) -> void:
	_busy = true
	await _nice()
	_busy = false
	if running:
		next.call()


func _nice(text: String = "Nice!") -> Signal:
	return _hud.coach.nice(text)


func _go(s: Step) -> void:
	step = s
	_step_time = 0.0


func _finish_up() -> void:
	running = false
	Achievements.paused = false
	Economy.tutorial_done = true
	Economy.save_profile()
	_hud.set_tutorial_running(false)
	_hud.highlight("")
	_hud.coach.hide_card()
	_show_marker(false)
	_answered.emit("skip") # releases a welcome card still waiting
	finished.emit()


# --- Finish line beacon ---------------------------------------------------------

func _show_marker(on: bool) -> void:
	if on and _marker == null and _finish:
		_marker = _make_marker()
		_finish.get_parent().add_child(_marker)
		var p := _finish.global_position
		_marker.global_position = Vector3(p.x, 0.0, p.z) # on the ground under the finish area
	if _marker:
		_marker.visible = on


func _make_marker() -> Node3D:
	var root := Node3D.new()
	root.name = "TutorialBeacon"
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1.0, 0.82, 0.3)
	var beam_mat := glow.duplicate() as StandardMaterial3D
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.albedo_color = Color(1.0, 0.85, 0.35, 0.22)
	beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# A soft column of light you can spot from across the court...
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.45
	cyl.bottom_radius = 0.6
	cyl.height = 7.0
	beam.mesh = cyl
	beam.material_override = beam_mat
	beam.position.y = 3.5
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(beam)
	# ...and a bobbing arrow pointing down at the line.
	var arrow := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.55
	cone.bottom_radius = 0.0
	cone.height = 0.9
	arrow.mesh = cone
	arrow.material_override = glow
	arrow.position.y = 2.6
	arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(arrow)
	var t := arrow.create_tween().set_loops()
	t.tween_property(arrow, "position:y", 3.1, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(arrow, "position:y", 2.6, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var spin := arrow.create_tween().set_loops()
	spin.tween_property(arrow, "rotation:y", TAU, 2.0).from(0.0)
	return root
