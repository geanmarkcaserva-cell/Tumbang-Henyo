extends Node
## Demo bot for filming the intro video (NOT part of the game).
## Started by demo_start.tscn in a separate process that Godot's Movie Maker
## records (--write-movie). Plays one scenario, then quits.
## Scenario comes from the command line: ++ --demo=<menu|round1|round3|squad|mama>

enum S { QUIZ, THROW, RUN, ROUND_CLEAR, GAME_OVER, TAGGED }

var scenario := "menu"
var g: Node = null
var steering := false
var route: Array = []
var route_i := 0
var nav_goal := Vector3.ZERO
var use_nav := false
var nav_memo := {}
var wrong_answers := 0 ## answer this many questions wrong before answering right
var jump_at := {} ## waypoint index -> true: jump when reaching it
var _yaw_target := 0.0
var fast := false ## speedrun: no idling, quick answers and throws
var _frame0 := 0
const STATE_FILE := "C:/Users/user/Documents/tumbang-henyo/art/source/trailer/intro_clips/speed_state.json"


## Video time of this recording (Movie Maker renders one frame per process frame).
func vt() -> float:
	return (Engine.get_frames_drawn() - _frame0) / 30.0


func ev(name: String) -> void:
	var rn: int = g.round_number if is_instance_valid(g) else 0
	blog("EV %s round=%d vt=%.3f score=%d" % [name, rn, vt(), (g.score if is_instance_valid(g) else 0)])


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--demo="):
			scenario = a.substr(7)
	print("[demo] scenario ", scenario)
	_run.call_deferred()


func _process(_d: float) -> void:
	# never grab the real mouse while filming (the recording doesn't show the cursor)
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


var _log_t := 0.0

func blog(msg: String) -> void:
	var p := "C:/Users/user/Documents/tumbang-henyo/art/source/trailer/intro_clips/bot_%s.log" % scenario
	var f := FileAccess.open(p, FileAccess.READ_WRITE) if FileAccess.file_exists(p) else FileAccess.open(p, FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line("%8.2f %s" % [Time.get_ticks_msec() / 1000.0, msg])


func wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, false).timeout


func wait_until(cond: Callable, timeout := 30.0) -> bool:
	var t := 0.0
	while not cond.call():
		await get_tree().process_frame
		t += get_process_delta_time()
		if t > timeout:
			return false
	return true


func _prepare() -> void:
	var mi := AudioServer.get_bus_index("Music")
	if mi >= 0 and not scenario.begins_with("speed"):
		AudioServer.set_bus_mute(mi, true) # music is laid in the edit instead
	if "paused" in Achievements:
		Achievements.paused = true
	if not Accounts.has_any():
		Accounts.create("Henyo")
	Economy.tutorial_done = true
	for id in ["wind", "squad", "elite", "mama", "tanod"]:
		if not Economy.tips_seen.has(id):
			Economy.tips_seen.append(id)


func _run() -> void:
	_frame0 = Engine.get_frames_drawn()
	_prepare()
	await wait(0.3)
	if scenario.begins_with("speed"):
		var parts := scenario.split("_")
		fast = true
		await _speed_segment(int(parts[1]), int(parts[2]))
		blog("done")
		get_tree().quit()
		return
	match scenario:
		"menu":
			await _menu_tour()
		"round1":
			await _start_game("history", 0)
			await _play(1)
		"round3":
			wrong_answers = 1
			await _start_game("science", 3)
			await _play(1)
		"squad":
			await _start_game("mythology", 6)
			await _play(1)
		"mama":
			await _start_game("rrm", 15)
			await _play(1)
	await wait(2.5)
	print("[demo] done")
	get_tree().quit()


# ---------------------------------------------------------------- main menu ---

func _menu_tour() -> void:
	get_tree().change_scene_to_file(GameManager.MAIN_MENU)
	await wait_until(func(): return get_tree().current_scene != null and get_tree().current_scene.has_method("_show"))
	var m := get_tree().current_scene
	await wait(0.5)
	m._show("main", true)
	await wait(4.0)
	m._show("mode"); await wait(2.6)
	for th in ["mythology", "rrm", "science", "history"]:
		if m.has_method("_select_theme"):
			m._select_theme(th)
		await wait(1.5)
	m._show("character"); await wait(2.4)
	for i in 3:
		m._browse("character", 1); await wait(1.9)
	m._show("weapon"); await wait(2.4)
	for i in 6:
		m._browse("weapon", 1); await wait(1.7)
	m._show("collection"); await wait(3.2)
	m._show("achievements"); await wait(3.2)
	m._show("join"); await wait(3.2)
	m._show("main"); await wait(3.0)


# --------------------------------------------------------------- the game ---

func _start_game(theme: String, jump_round: int) -> void:
	GameManager.start_run(theme) # tips loading screen, then the game
	await wait_until(func(): return get_tree().current_scene != null and "state" in get_tree().current_scene, 40.0)
	g = get_tree().current_scene
	await wait(0.4)
	if jump_round > 1:
		if g._quiz.has_method("close"):
			g._quiz.close()
		g._jump_to_round(jump_round)
	await wait(0.2)


## One piece of the speedrun: rounds a..b in one recording. The next piece
## carries on from the score, Awra and caps saved here.
func _speed_segment(a: int, b: int) -> void:
	var st := {"score": 0, "awra": 100, "caps": Economy.caps}
	if a > 1 and FileAccess.file_exists(STATE_FILE):
		st = JSON.parse_string(FileAccess.get_file_as_string(STATE_FILE))
	if a == 1:
		await _start_game("history", 0)
	else:
		GameManager.selected_theme = "history"
		get_tree().change_scene_to_file(GameManager.GAME)
		await wait_until(func(): return get_tree().current_scene != null and "state" in get_tree().current_scene, 40.0)
		g = get_tree().current_scene
		await get_tree().process_frame
		Economy.caps = int(st.caps)
		g.score = int(st.score)
		g.awra = int(st.awra)
		g._hud.set_score(g.score)
		g._hud.set_awra(g.awra, 100)
		g._hud.set_caps(Economy.caps)
		if g._quiz.has_method("close"):
			g._quiz.close()
		g._jump_to_round(a)
	ev("segment_start")
	await _play(b - a + 1)
	var out := {"score": g.score, "awra": g.awra, "caps": Economy.caps}
	var f := FileAccess.open(STATE_FILE, FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	ev("segment_end")


func _play(rounds: int) -> void:
	var cleared := 0
	var last := -1
	while true:
		await get_tree().process_frame
		if not is_instance_valid(g):
			return
		var st: int = g.state
		if st != last:
			last = st
			match st:
				S.QUIZ:
					_do_quiz()
				S.THROW:
					_do_throw()
				S.RUN:
					_do_run()
				S.ROUND_CLEAR:
					_stop_steer()
					ev("round_clear")
					cleared += 1
					if cleared >= rounds:
						await wait(3.0 if fast else 2.6)
						return
				S.GAME_OVER:
					_stop_steer()
					ev("game_over")
					await wait(5.0)
					return
				S.TAGGED:
					_stop_steer()


func _do_quiz() -> void:
	while is_instance_valid(g) and g.state == S.QUIZ:
		var ok := await wait_until(func(): return not is_instance_valid(g) or g.state != S.QUIZ or g._quiz._active, 20.0)
		if not ok or not is_instance_valid(g) or g.state != S.QUIZ:
			return
		ev("quiz")
		await wait(1.0 if fast else 2.8) # read the question like a person
		if not is_instance_valid(g) or g.state != S.QUIZ or not g._quiz._active:
			continue
		var pick: int = g._correct_index
		if wrong_answers > 0:
			wrong_answers -= 1
			pick = (pick + 1) % 3
		g._quiz._choose(pick)
		await wait_until(func(): return not is_instance_valid(g) or g.state != S.QUIZ or not g._quiz._active, 10.0)
		await wait(0.2)


func _press(action: String, on: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = on
	Input.parse_input_event(ev)
	if on:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _do_throw() -> void:
	await wait(0.35 if fast else 0.9)
	if g.state != S.THROW:
		return
	var p: CharacterBody3D = g._player
	if not fast:
		# a little step to the side inside the throw zone, then line up the shot
		_press("move_left", true); await wait(0.45); _press("move_left", false)
		await wait(0.35)
	var lata: Vector3 = g._lata.global_position
	var d := lata - p.global_position
	var target := atan2(-d.x, -d.z)
	var tw := create_tween()
	tw.tween_property(p, "rotation:y", target, 0.6).set_trans(Tween.TRANS_SINE)
	var pivot := p.get_node_or_null("CameraPivot")
	if pivot:
		create_tween().tween_property(pivot, "rotation:x", deg_to_rad(-6.0), 0.6)
	await wait(0.35 if fast else 0.75)
	if g.state != S.THROW:
		return
	_press("throw", true) # the power gauge and aim arc show while charging
	await wait(0.45 if fast else 1.05)
	ev("throw")
	if g.state == S.THROW:
		g._throw.debug_throw_at(g._lata.global_position + Vector3(0, 0.1, 0), 0.8)
	_press("throw", false)


func _do_run() -> void:
	await get_tree().process_frame
	ev("run")
	for t in g._tayas:
		if is_instance_valid(t):
			t.chase_speed = 3.3 # slower than the player's walk: a chase, but a fair one
			t.lunge_range = 0.0
			t.tag_distance = 0.3
			t.aim_error = 2.4 # their tsinelas fly close but usually miss
	if g._mama_on:
		if is_instance_valid(g._mama) and "_stun" in g._mama:
			g._mama._stun = 2.6
		use_nav = true
		nav_goal = g._goal.centre
		nav_memo = {}
	else:
		use_nav = false
		var px: float = g._player.global_position.x
		var side := -1.0 if px <= 0.5 else 1.0
		route = [Vector3(side * 5.5, 0, -12), Vector3(side * 6.0, 0, -27), Vector3(side * 1.5, 0, -41)]
		jump_at = {1: true}
		route_i = 0
	steering = true
	_press("move_forward", true)
	_press("sprint", true)


func _stop_steer() -> void:
	if steering:
		steering = false
		_press("move_forward", false)
		_press("sprint", false)


func _physics_process(delta: float) -> void:
	if not steering or not is_instance_valid(g) or g.state != S.RUN:
		if steering and is_instance_valid(g) and g.state != S.RUN:
			_stop_steer()
		return
	var p: CharacterBody3D = g._player
	var pos := p.global_position
	var wp: Vector3
	_log_t -= delta
	if _log_t <= 0.0:
		_log_t = 0.5
		blog("st=%d pos=%s yaw=%.2f vel=%s nav=%s goal=%s fwd=%s" % [g.state, pos, p.rotation.y, p.velocity,
				use_nav, nav_goal, Input.is_action_pressed("move_forward")])
	if use_nav and g._mama_on and is_instance_valid(g._mama):
		# Mama keeps stumbling when she gets close: a tense chase that the hero wins
		if g._mama.global_position.distance_to(pos) < 3.0:
			g._mama._stun = maxf(g._mama._stun, 0.5)
	if use_nav:
		if g._nav.is_ready:
			wp = g._nav.route(p, nav_goal, nav_memo, delta)
		else:
			wp = nav_goal
	else:
		if route_i >= route.size():
			return
		wp = route[route_i]
		var flat := Vector2(wp.x - pos.x, wp.z - pos.z)
		if flat.length() < 1.6:
			if jump_at.has(route_i):
				_press("jump", true)
				_release_jump.call_deferred()
			route_i += 1
			if route_i >= route.size():
				return
			wp = route[route_i]
	var d := wp - pos
	if Vector2(d.x, d.z).length() < 0.05:
		return
	_yaw_target = atan2(-d.x, -d.z)
	p.rotation.y = lerp_angle(p.rotation.y, _yaw_target, clampf(delta * 7.0, 0.0, 1.0))
	var pivot := p.get_node_or_null("CameraPivot")
	if pivot:
		pivot.rotation.x = lerpf(pivot.rotation.x, deg_to_rad(-8.0), delta * 3.0)


func _release_jump() -> void:
	await wait(0.15)
	_press("jump", false)
