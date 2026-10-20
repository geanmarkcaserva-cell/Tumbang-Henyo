extends Node
## Player settings: volume (everything), music, sound effects, low detail
## mode, fullscreen and key bindings. Saved to user://settings.cfg and
## applied at start.
##
## Key bindings: REMAPPABLE lists the actions players can rebind. Each keeps
## one keyboard key or mouse button (gamepad bindings are left alone);
## rebind() swaps keys when the new one was already used elsewhere.
## Every keyboard/mouse binding is set to answer any device: some bindings in
## the project were tied to one device number (Space and Shift ended up on
## device 16), and a key press from the keyboard never matched them.
##
## Touch layout: where the on-screen joystick and buttons sit, and how big
## they are (Settings > Touch buttons). Positions are fractions of the screen.
##
## Audio goes through two buses made here, "Music" and "SFX" (both feed
## "Master"); the Music and Sfx autoloads play on them.
## Low detail mode: no sun shadows, 3D drawn at 75% resolution, and nodes in
## the "detail_heavy" group (grass, small plants, far-off houses) hidden.
## Nodes in the "blob_shadow" group (round shadows under characters) show only
## in low detail mode, since the sun draws real shadows otherwise.

signal changed

const PATH := "user://settings.cfg"
const LOW_DETAIL_3D_SCALE := 0.75

var volume := 1.0 ## 0..1, everything
var music := 0.8 ## 0..1
var sfx := 1.0 ## 0..1
var low_detail := false
var fullscreen := false
## On-screen joystick and buttons in the game. On by default on phones/tablets.
var touch_controls := OS.has_feature("mobile")

## Actions players can rebind in Settings > Controls: [action, label].
const REMAPPABLE := [
	["move_forward", "Move forward"], ["move_back", "Move back"],
	["move_left", "Move left"], ["move_right", "Move right"],
	["sprint", "Sprint"], ["jump", "Jump"], ["look_back", "Look back"],
	["throw", "Throw (hold)"],
	["answer_a", "Answer a"], ["answer_b", "Answer b"], ["answer_c", "Answer c"],
	["pause", "Pause"],
]
var _default_keys := {} ## action -> the project's own key/mouse event (for Reset)
## Touch layout: control id ("stick", "jump", "sprint", "back", "throw") ->
## Vector2 position as a fraction of the screen. Missing = the default spot.
var touch_layout := {}
var touch_scale := 1.0 ## size of the on-screen controls (0.7 - 1.4)


func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus("Music")
	_ensure_bus("SFX")
	_any_device_keys()
	for a in REMAPPABLE:
		_default_keys[a[0]] = _first_key(a[0])
	_load()
	_apply_audio()
	_apply_window()
	get_tree().node_added.connect(_on_node_added)


func _ready() -> void:
	_apply_detail.call_deferred()


## Fullscreen only makes sense on PC.
func can_fullscreen() -> bool:
	return not OS.has_feature("mobile") and not OS.has_feature("web")


func set_volume(v: float) -> void:
	volume = clampf(v, 0.0, 1.0)
	_apply_audio()
	_save()


func set_music(v: float) -> void:
	music = clampf(v, 0.0, 1.0)
	_apply_audio()
	_save()


func set_sfx(v: float) -> void:
	sfx = clampf(v, 0.0, 1.0)
	_apply_audio()
	_save()


func set_low_detail(on: bool) -> void:
	low_detail = on
	_apply_detail()
	_save()


func set_touch_controls(on: bool) -> void:
	touch_controls = on
	_save()
	changed.emit()


## Save the on-screen controls' layout (see touch_layout / touch_scale).
func set_touch_layout(layout: Dictionary, scale: float) -> void:
	touch_layout = layout.duplicate()
	touch_scale = clampf(scale, 0.7, 1.4)
	_save()
	changed.emit()


func reset_touch_layout() -> void:
	set_touch_layout({}, 1.0)


func set_fullscreen(on: bool) -> void:
	fullscreen = on
	_apply_window()
	_save()


# --- Applying -----------------------------------------------------------------

func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var i := AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, bus_name)
	AudioServer.set_bus_send(i, "Master")


func _apply_audio() -> void:
	_set_bus("Master", volume)
	_set_bus("Music", music)
	_set_bus("SFX", sfx)
	changed.emit()


func _set_bus(bus_name: String, v: float) -> void:
	var i := AudioServer.get_bus_index(bus_name)
	if i == -1:
		return
	AudioServer.set_bus_mute(i, v <= 0.001)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.001)))


func _apply_window() -> void:
	if not can_fullscreen():
		return
	var mode := DisplayServer.window_get_mode()
	var is_full := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if fullscreen and not is_full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif not fullscreen and is_full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	changed.emit()


func _apply_detail() -> void:
	if not is_inside_tree():
		return
	get_tree().root.scaling_3d_scale = LOW_DETAIL_3D_SCALE if low_detail else 1.0
	for n in get_tree().get_nodes_in_group("detail_heavy"):
		if n is Node3D:
			n.visible = not low_detail
	for n in get_tree().get_nodes_in_group("blob_shadow"):
		if n is Node3D:
			n.visible = low_detail
	for light in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
		_apply_light(light)
	changed.emit()


func _apply_light(light: DirectionalLight3D) -> void:
	if not light.has_meta("shadow_default"):
		light.set_meta("shadow_default", light.shadow_enabled)
	light.shadow_enabled = bool(light.get_meta("shadow_default")) and not low_detail


## New scenes come in with full detail; trim them as they load.
func _on_node_added(n: Node) -> void:
	# Round blob shadows under characters stand in for the sun's shadows,
	# so they only show in low detail mode.
	if n is Node3D and n.is_in_group("blob_shadow"):
		n.visible = low_detail
		return
	if not low_detail:
		return
	if n is DirectionalLight3D:
		_apply_light(n)
	elif n is Node3D and n.is_in_group("detail_heavy"):
		n.visible = false


# --- Saving -------------------------------------------------------------------

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "volume", volume)
	cfg.set_value("audio", "music", music)
	cfg.set_value("audio", "sfx", sfx)
	cfg.set_value("video", "low_detail", low_detail)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("controls", "touch", touch_controls)
	cfg.set_value("controls", "touch_layout", touch_layout)
	cfg.set_value("controls", "touch_scale", touch_scale)
	var keys := {}
	for a in REMAPPABLE:
		var e := _first_key(a[0])
		if e and not _same(e, _default_keys.get(a[0])):
			keys[a[0]] = _to_dict(e)
	cfg.set_value("controls", "keys", keys)
	cfg.save(PATH)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	volume = cfg.get_value("audio", "volume", volume)
	music = cfg.get_value("audio", "music", music)
	sfx = cfg.get_value("audio", "sfx", sfx)
	low_detail = cfg.get_value("video", "low_detail", low_detail)
	fullscreen = cfg.get_value("video", "fullscreen", fullscreen)
	touch_controls = cfg.get_value("controls", "touch", touch_controls)
	touch_layout = cfg.get_value("controls", "touch_layout", {})
	touch_scale = cfg.get_value("controls", "touch_scale", 1.0)
	var keys: Dictionary = cfg.get_value("controls", "keys", {})
	for action in keys:
		var e := _from_dict(keys[action])
		if e and InputMap.has_action(action):
			_set_key(action, e)


# --- Key bindings ---------------------------------------------------------------

## Make every keyboard and mouse binding answer any device (-1). A binding
## saved with a specific device number only fires for that device.
func _any_device_keys() -> void:
	for action in InputMap.get_actions():
		if String(action).begins_with("ui_"):
			continue
		for e in InputMap.action_get_events(action):
			if (e is InputEventKey or e is InputEventMouseButton) and e.device != -1:
				InputMap.action_erase_event(action, e)
				var copy: InputEvent = e.duplicate()
				copy.device = -1
				InputMap.action_add_event(action, copy)

## The keyboard key / mouse button bound to an action (null if none).
func _first_key(action: String) -> InputEvent:
	if not InputMap.has_action(action):
		return null
	for e in InputMap.action_get_events(action):
		if e is InputEventKey or e is InputEventMouseButton:
			return e
	return null


## Short name of an action's key for hints and the Controls page ("W", "Space", "LMB").
func key_name(action: String) -> String:
	return event_name(_first_key(action))


static func event_name(e: InputEvent) -> String:
	if e is InputEventMouseButton:
		match e.button_index:
			MOUSE_BUTTON_LEFT: return "LMB"
			MOUSE_BUTTON_RIGHT: return "RMB"
			MOUSE_BUTTON_MIDDLE: return "MMB"
			_: return "Mouse %d" % e.button_index
	if e is InputEventKey:
		var code: int = e.physical_keycode if e.physical_keycode != 0 else e.keycode
		if e.physical_keycode != 0:
			code = DisplayServer.keyboard_get_keycode_from_physical(e.physical_keycode)
		var t := OS.get_keycode_string(code)
		return t if t != "" else "?"
	return "-"


## Bind `event` to `action`. If another remappable action used that key, the
## two swap keys so nothing is left unbound. Returns the action that swapped ("" if none).
func rebind(action: String, event: InputEvent) -> String:
	var old := _first_key(action)
	var swapped := ""
	for a in REMAPPABLE:
		if a[0] != action and _same(_first_key(a[0]), event):
			swapped = a[0]
			if old:
				_set_key(a[0], old)
			break
	_set_key(action, event)
	_save()
	changed.emit()
	return swapped


func reset_keys() -> void:
	for a in REMAPPABLE:
		var e: InputEvent = _default_keys.get(a[0])
		if e:
			_set_key(a[0], e)
	_save()
	changed.emit()


## Replace the action's keyboard/mouse binding, keeping gamepad ones.
func _set_key(action: String, event: InputEvent) -> void:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey or e is InputEventMouseButton:
			InputMap.action_erase_event(action, e)
	var copy: InputEvent = event.duplicate()
	copy.device = -1 # any keyboard / mouse
	InputMap.action_add_event(action, copy)


static func _same(a: InputEvent, b: InputEvent) -> bool:
	if a == null or b == null:
		return false
	if a is InputEventMouseButton and b is InputEventMouseButton:
		return a.button_index == b.button_index
	if a is InputEventKey and b is InputEventKey:
		var ka: int = a.physical_keycode if a.physical_keycode != 0 else a.keycode
		var kb: int = b.physical_keycode if b.physical_keycode != 0 else b.keycode
		return ka == kb
	return false


static func _to_dict(e: InputEvent) -> Dictionary:
	if e is InputEventMouseButton:
		return {"mouse": e.button_index}
	return {"key": e.keycode, "physical": e.physical_keycode}


static func _from_dict(d: Dictionary) -> InputEvent:
	if d.has("mouse"):
		var m := InputEventMouseButton.new()
		m.button_index = int(d.mouse)
		m.device = -1 # any device
		return m
	if d.has("key") or d.has("physical"):
		var k := InputEventKey.new()
		k.keycode = int(d.get("key", 0))
		k.physical_keycode = int(d.get("physical", 0))
		k.device = -1 # any keyboard
		return k
	return null
