extends Control
## First screen: black background, the tsinelas mascot wobbling in the middle,
## a small line explaining what is being prepared, and "Loading..." in the
## corner. Loads the main menu (with its 3D court) in the background.

@export var min_time := 2.2 ## keep the screen up at least this long

const MASCOT := preload("res://art/ui/loading_slipper.png")

const STEPS := [
	"Loading quiz questions...",
	"Building the barangay court...",
	"Waking up the taya...",
	"Preparing tsinelas physics...",
	"Almost there...",
]

var _time := 0.0
var _mascot: Node2D
var _explainer: Label
var _loading: Label


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Music.play("menu")
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_mascot = _build_mascot()
	_mascot.position = Vector2(960, 540)
	add_child(_mascot)

	_explainer = UiKit.label("", 24, Color(1, 1, 1, 0.85))
	_explainer.position = Vector2(40, 1000)
	add_child(_explainer)

	_loading = UiKit.label("Loading", 44)
	_loading.position = Vector2(1640, 990)
	add_child(_loading)

	ResourceLoader.load_threaded_request(GameManager.MAIN_MENU)


func _process(delta: float) -> void:
	_time += delta
	var progress := []
	var status := ResourceLoader.load_threaded_get_status(GameManager.MAIN_MENU, progress)
	var shown := minf(progress[0] if progress.size() > 0 else 0.0, _time / min_time)

	_explainer.text = STEPS[mini(int(shown * STEPS.size()), STEPS.size() - 1)]
	_loading.text = "Loading" + ".".repeat(int(_time * 3.0) % 4)
	# Little wobble, like a slipper about to be thrown.
	_mascot.rotation = deg_to_rad(sin(_time * 5.0) * 6.0) # the art is already tilted
	_mascot.scale = Vector2.ONE * (1.0 + sin(_time * 2.5) * 0.03)

	if status == ResourceLoader.THREAD_LOAD_LOADED and _time >= min_time:
		set_process(false)
		Transition.change_scene(ResourceLoader.load_threaded_get(GameManager.MAIN_MENU))
	elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		set_process(false)
		push_error("Boot loading: could not load the main menu")
		Transition.change_scene(GameManager.MAIN_MENU)


## The tsinelas mascot (art/ui/loading_slipper.png, from "Loading icon first").
func _build_mascot() -> Node2D:
	var root := Node2D.new()
	var sprite := Sprite2D.new()
	sprite.texture = MASCOT
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	root.add_child(sprite)
	return root
