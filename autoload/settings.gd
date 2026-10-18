extends Node
## Player settings: volume (everything), music, sound effects, low detail
## mode and fullscreen. Saved to user://settings.cfg and applied at start.
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


func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus("Music")
	_ensure_bus("SFX")
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
