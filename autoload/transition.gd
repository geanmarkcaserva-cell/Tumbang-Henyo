extends CanvasLayer
## Screen fades for every scene change: fade to black, swap the scene, fade
## the new one in. Sits above everything (layer 100) and keeps running while
## the game is paused. Clicks are blocked during a fade so a double-click
## can't start two transitions.
##
##   Transition.change_scene("res://...tscn")   or a PackedScene
##   Transition.reload()                        restart the current scene
##   Transition.quit()                          fade out, then quit
##   await Transition.fade_out() / fade_in()    for custom sequences

const FADE_TIME := 0.35

var _rect: ColorRect
var _tween: Tween
var _busy := false


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.color = Color(0, 0, 0, 1) # the game opens from black
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_rect)
	fade_in(0.6)


func is_busy() -> bool:
	return _busy


func fade_out(seconds: float = FADE_TIME) -> Signal:
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	return _fade_to(1.0, seconds)


func fade_in(seconds: float = FADE_TIME) -> Signal:
	var done := _fade_to(0.0, seconds)
	done.connect(func(): _rect.mouse_filter = Control.MOUSE_FILTER_IGNORE, CONNECT_ONE_SHOT)
	return done


## Fade out, change to `target` (a path or a PackedScene), fade the new scene in.
func change_scene(target: Variant) -> void:
	if _busy:
		return
	_busy = true
	await fade_out()
	get_tree().paused = false
	var err: Error
	if target is PackedScene:
		err = get_tree().change_scene_to_packed(target)
	else:
		err = get_tree().change_scene_to_file(str(target))
	if err != OK:
		push_error("Transition: could not change scene to %s (%s)" % [target, error_string(err)])
	# Let the new scene run _ready and draw a frame before revealing it.
	await get_tree().process_frame
	await get_tree().process_frame
	await fade_in()
	_busy = false


func reload() -> void:
	change_scene(get_tree().current_scene.scene_file_path)


func quit() -> void:
	if _busy:
		return
	_busy = true
	await fade_out()
	get_tree().quit()


func _fade_to(alpha: float, seconds: float) -> Signal:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_rect, "color:a", alpha, seconds).set_trans(Tween.TRANS_SINE)
	return _tween.finished
