extends Node
## Pitch-video filming bot (NOT part of the game). Started by pitch_start.tscn
## in a separate Movie Maker process. Scenarios (++ --pitch=<name>):
##   class   : custom quiz is filled in and saved, a class lobby is hosted,
##             simulated students join, answer two questions and climb the
##             live leaderboard, then the teacher ends the game.
##   credits : the credits screen tours the team.
## Save data is backed up and restored by whoever launches this process.

var scenario := "class"
var m: Node = null

const QUIZ_TITLE := "Grade 6 Science - Quarter 2"
const QUIZ_TEXT := """1. Which planet is the largest in our solar system?
a) Jupiter *
b) Saturn
c) Earth
Why: Jupiter is more than 11 times wider than Earth.

2. What do plants need to make their own food?
a) Sunlight *
b) Salt
c) Sand
Why: Plants use sunlight, water and air to make food through photosynthesis.

3. Which part of the body pumps blood?
a) Heart *
b) Lungs
c) Liver

4. What is the boiling point of water at sea level?
a) 100 degrees Celsius *
b) 50 degrees Celsius
c) 0 degrees Celsius

5. What layer of the Earth do we live on?
a) Crust *
b) Mantle
c) Core

6. Which gas do we breathe out?
a) Carbon dioxide *
b) Oxygen
c) Helium

7. What do you call animals that eat only plants?
a) Herbivores *
b) Carnivores
c) Omnivores

8. Which is the closest star to the Earth?
a) The Sun *
b) Polaris
c) Sirius
"""
const NAMES := ["Andrea", "Miguel", "Bea", "Paolo", "Jasmine", "Carlo", "Trisha", "Nico", "Kyla", "Renz", "Aira", "Jomar"]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pitch="):
			scenario = a.substr(8)
	_run.call_deferred()


func _process(_d: float) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


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
	if mi >= 0:
		AudioServer.set_bus_mute(mi, true)
	if "paused" in Achievements:
		Achievements.paused = true
	if not Accounts.has_any():
		Accounts.create("Henyo")
	Economy.tutorial_done = true


func _menu() -> void:
	get_tree().change_scene_to_file(GameManager.MAIN_MENU)
	await wait_until(func(): return get_tree().current_scene != null and get_tree().current_scene.has_method("_show"))
	m = get_tree().current_scene
	await wait(0.4)


func _run() -> void:
	_prepare()
	await wait(0.3)
	await _menu()
	match scenario:
		"class":
			await _class()
		"credits":
			m._show("main", true)
			await wait(1.5)
			m._show("credits")
			await wait(36.0)
	await wait(1.0)
	get_tree().quit()


func _type(edit: Object, text: String, per_char := 0.045) -> void:
	for c in text:
		edit.text += c
		if edit is LineEdit:
			edit.caret_column = edit.text.length()
		await wait(per_char)


func _class() -> void:
	m._show("main", true)
	await wait(1.2)
	m._show("mode")
	await wait(2.0)
	m._show("custom")
	await wait(1.0)
	m._new_custom()
	await wait(0.8)
	print("[pitch] MARK custom_typing")
	m._custom_title.grab_focus()
	await _type(m._custom_title, QUIZ_TITLE)
	await wait(0.8)
	print("[pitch] MARK paste")
	Sfx.play("ui_click")
	m._custom_text.text = QUIZ_TEXT # same as PASTE (the filming process can't use the clipboard)
	m._validate_custom()
	m._custom_text.grab_focus()
	m._custom_text.set_caret_line(0)
	await wait(2.6)
	m._save_custom()
	await wait(2.2)
	print("[pitch] MARK host")
	m._host_custom()
	var ok := await wait_until(func(): return Lobby.is_host(), 5.0)
	if not ok:
		print("[pitch] host failed")
		return
	await wait(3.5)
	# --- students join one by one
	print("[pitch] MARK joins")
	var ids := []
	for i in NAMES.size():
		var id := 1001 + i
		ids.append(id)
		Lobby.players[id] = {"name": NAMES[i], "score": 0, "round": 1, "awra": 100, "out": false, "perfect": 0, "left": false}
		Lobby.players_changed.emit()
		await wait(0.35 if i > 2 else 0.7)
	await wait(2.5)
	# --- start the game
	print("[pitch] MARK start")
	m._host_panel._on_start()
	await wait(1.5)
	for q in 2:
		for id in ids:
			Lobby.q_ready[id] = true
		print("[pitch] MARK question_%d" % (q + 1))
		Lobby.release_question()
		await wait(1.6)
		var qd := Lobby.class_question(Lobby.q_index)
		var right := int(qd.get("answer", 0))
		var order := ids.duplicate()
		order.shuffle()
		for k in order.size():
			var id: int = order[k]
			var correct := randf() < 0.75
			var choice := right if correct else (right + 1 + randi() % 2) % 3
			Lobby.q_answers[id] = {"choice": choice, "correct": correct}
			if correct:
				var p: Dictionary = Lobby.players[id]
				p.score = int(p.score) + 150 + randi() % 120
			Lobby.question_changed.emit()
			Lobby.players_changed.emit()
			await wait(0.45 + randf() * 0.35)
		await wait(1.2)
		Lobby.end_question()
		print("[pitch] MARK reveal_%d" % (q + 1))
		# students run their rounds: scores climb, a few bullseyes, one gets tagged out
		for t in 14:
			for id in ids:
				var p: Dictionary = Lobby.players[id]
				if p.out:
					continue
				if randf() < 0.55:
					p.score = int(p.score) + 40 + randi() % 260
				if randf() < 0.06:
					p.perfect = int(p.perfect) + 1
					p.score = int(p.score) + 150
			if q == 1 and t == 6:
				Lobby.players[ids[10]].out = true
			Lobby.players_changed.emit()
			await wait(0.45)
		for id in ids:
			Lobby.players[id].round = int(Lobby.players[id].round) + 1
		Lobby.players_changed.emit()
		await wait(0.8)
	print("[pitch] MARK end")
	m._host_panel._on_end()
	await wait(6.0)
