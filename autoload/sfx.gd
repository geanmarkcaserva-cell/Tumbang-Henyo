extends Node
## Sound effects. Every sound is a file in art/Audio/sfx named after it:
## Sfx.play("lata_hit") plays art/Audio/sfx/lata_hit.wav (or .ogg / .mp3).
##
## - Variants: step_1, step_2, ... are picked at random by Sfx.play("step").
## - A name with no file yet stays silent. Voice lines and new sounds can be
##   dropped into the folder later (see docs/AUDIO.md) with no code change.
## - Loops (wind, crickets, the throw charge): start_loop / set_loop / stop_loop.
##   They pause with the game; one-shots keep playing (the pause menu clicks).
## - Every button gets a hover tick and a click by itself (Back buttons a lower
##   click, disabled ones a "nope" buzz). Set the "sfx_skip" meta to opt out.
## - Every slider ticks as it moves.

const DIR := "res://art/Audio/sfx/"
const EXTS := ["wav", "ogg", "mp3"]
## Sounds that live outside the sfx folder.
const LEGACY := {
	"correct": "res://art/Audio/Correct answer.mp3",
	"wrong": "res://art/Audio/Wrong answer.mp3",
}
## Loaded up front so nothing hitches the first time it plays.
const PRELOAD := [
	"ui_hover", "ui_click", "ui_back", "ui_tick", "ui_error", "ui_pop", "ui_whoosh",
	"ui_pause", "ui_buy", "ui_equip", "join", "whistle", "correct", "wrong",
	"quiz_open", "tick", "tick_urgent", "timeout", "hint", "coin",
	"charge", "throw", "throw_heavy", "slap_ground", "lata_hit", "lata_set", "bonk",
	"miss", "bullseye", "wind", "step", "jump", "land", "exhausted", "alert", "slap",
	"tagged", "round_clear", "bell", "mama_sting", "clatter", "palo", "victory",
	"game_over", "banner", "crickets",
]
const BACK_WORDS := ["back", "<", "cancel", "close", "no"]
const VOICES := 12 ## how many one-shots can overlap
const REPEAT_GAP_MS := 35 ## the same sound twice within this is dropped (no stacking)
const HOVER_GAP_MS := 60

var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _cache := {} ## name -> Array of AudioStream (empty: no file yet)
var _loops := {} ## name -> AudioStreamPlayer
var _loop_tweens := {}
var _last_ms := {} ## name -> Time.get_ticks_msec() of the last play


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX" # volume set in Settings
		add_child(p)
		_players.append(p)
	for sound in PRELOAD:
		_streams(sound)
	get_tree().node_added.connect(_on_node_added)


# --- One-shots -------------------------------------------------------------------

## volume_db: 0 = as made. pitch: 1 = as made. jitter: random pitch spread
## (0.05 = +-5%) so repeated sounds (steps, clinks) don't sound copy-pasted.
func play(sound: String, volume_db: float = 0.0, pitch: float = 1.0, jitter: float = 0.0) -> void:
	var stream := _pick(sound)
	if stream == null:
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_ms.get(sound, -100000)) < REPEAT_GAP_MS:
		return
	_last_ms[sound] = now
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = maxf(pitch * (1.0 + randf_range(-jitter, jitter)), 0.05)
	p.play()


## A sound from somewhere in the world: quieter the farther it is from the
## camera (silent past ~60 m).
func play_at(sound: String, at: Vector3, volume_db: float = 0.0, pitch: float = 1.0, jitter: float = 0.06) -> void:
	var cam := get_viewport().get_camera_3d()
	var dist := cam.global_position.distance_to(at) if cam else 0.0
	var drop := clampf((dist - 5.0) * 0.45, 0.0, 26.0)
	if drop >= 26.0:
		return
	play(sound, volume_db - drop, pitch, jitter)


## True when a file exists for this sound (voice lines may not be recorded yet).
func has(sound: String) -> bool:
	return not _streams(sound).is_empty()


# --- Loops -------------------------------------------------------------------------

func start_loop(sound: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var p := _loop_player(sound)
	if p == null:
		return
	_kill_loop_tween(sound)
	p.volume_db = volume_db
	p.pitch_scale = pitch
	if not p.playing:
		p.play()


func set_loop(sound: String, volume_db: float, pitch: float = 1.0) -> void:
	var p: AudioStreamPlayer = _loops.get(sound)
	if p:
		p.volume_db = volume_db
		p.pitch_scale = maxf(pitch, 0.05)


## Fade a loop to volume_db over `seconds`; fading to -60 dB or lower stops it.
func fade_loop(sound: String, volume_db: float, seconds: float = 0.6) -> void:
	var p: AudioStreamPlayer = _loops.get(sound)
	if p == null:
		if volume_db > -60.0:
			start_loop(sound, -60.0)
			p = _loops.get(sound)
		if p == null:
			return
	if not p.playing and volume_db <= -60.0:
		return
	if not p.playing:
		p.volume_db = -60.0
		p.play()
	_kill_loop_tween(sound)
	var t := create_tween()
	t.tween_property(p, "volume_db", volume_db, seconds)
	if volume_db <= -60.0:
		t.tween_callback(p.stop)
	_loop_tweens[sound] = t


func stop_loop(sound: String) -> void:
	_kill_loop_tween(sound)
	var p: AudioStreamPlayer = _loops.get(sound)
	if p:
		p.stop()


func stop_all_loops() -> void:
	for sound in _loops:
		stop_loop(sound)


func _loop_player(sound: String) -> AudioStreamPlayer:
	if _loops.has(sound):
		return _loops[sound]
	var list := _streams(sound)
	if list.is_empty():
		return null
	var stream: AudioStream = list[0]
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(wav.get_length() * wav.mix_rate)
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	var p := AudioStreamPlayer.new()
	p.bus = &"SFX"
	p.stream = stream
	p.process_mode = Node.PROCESS_MODE_PAUSABLE # wind and crickets hold still on the pause menu
	add_child(p)
	_loops[sound] = p
	return p


func _kill_loop_tween(sound: String) -> void:
	var t: Tween = _loop_tweens.get(sound)
	if t and t.is_valid():
		t.kill()
	_loop_tweens.erase(sound)


# --- Files -------------------------------------------------------------------------

func _pick(sound: String) -> AudioStream:
	var list := _streams(sound)
	if list.is_empty():
		return null
	return list[randi() % list.size()]


## The file for `sound`, or its numbered variants (sound_1, sound_2, ...).
func _streams(sound: String) -> Array:
	if _cache.has(sound):
		return _cache[sound]
	var list := []
	if LEGACY.has(sound):
		list.append(load(LEGACY[sound]))
	else:
		var one := _load(sound)
		if one:
			list.append(one)
		else:
			for i in range(1, 10):
				var v := _load("%s_%d" % [sound, i])
				if v == null:
					break
				list.append(v)
	_cache[sound] = list
	return list


func _load(file_name: String) -> AudioStream:
	for ext in EXTS:
		var path: String = DIR + file_name + "." + ext
		if ResourceLoader.exists(path):
			return load(path) as AudioStream
	return null


# --- UI: buttons and sliders sound by themselves -------------------------------------

func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		_hook_button(node)
	elif node is Slider:
		_hook_slider(node)


func _hook_button(b: BaseButton) -> void:
	if b.has_meta("sfx_hooked"):
		return
	b.set_meta("sfx_hooked", true)
	b.mouse_entered.connect(func():
		if not b.disabled and not b.has_meta("sfx_skip"):
			_hover())
	b.pressed.connect(func():
		if not b.has_meta("sfx_skip"):
			play(_click_for(b)))
	b.gui_input.connect(func(e: InputEvent):
		if b.disabled and not b.has_meta("sfx_skip") and e is InputEventMouseButton \
				and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			play("ui_error"))


func _hook_slider(s: Slider) -> void:
	if s.has_meta("sfx_hooked"):
		return
	s.set_meta("sfx_hooked", true)
	s.value_changed.connect(func(_v: float):
		if not s.has_meta("sfx_skip") and s.is_visible_in_tree():
			play("ui_tick", 0.0, 1.0, 0.04))


func _hover() -> void:
	play("ui_hover", 0.0, 1.0, 0.03)


func _click_for(b: BaseButton) -> String:
	if b is CheckBox or b is CheckButton:
		return "ui_tick"
	var text := ""
	if b is Button:
		text = (b as Button).text.strip_edges().to_lower()
	for word in BACK_WORDS:
		if text == word or text.begins_with(word + " "):
			return "ui_back"
	return "ui_click"
