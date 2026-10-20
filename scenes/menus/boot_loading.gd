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

	# Everything sits on a 1920x1080 stage kept in the middle of the screen,
	# so wide phones show it centred too.
	var stage := preload("res://scenes/menus/tips_loading.gd").make_stage()
	add_child(stage)

	_mascot = _build_mascot()
	_mascot.position = Vector2(960, 500)
	stage.add_child(_mascot)

	_loading = UiKit.title("Loading", 52, Color.WHITE, 0)
	_loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading.position = Vector2(660, 850)
	_loading.size = Vector2(600, 70)
	stage.add_child(_loading)

	_explainer = UiKit.label("", 28, Color(1, 1, 1, 0.75))
	_explainer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_explainer.position = Vector2(460, 930)
	_explainer.size = Vector2(1000, 50)
	stage.add_child(_explainer)

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
	# Springs in at the start (overshoot and settle), then breathes.
	var k := minf(_time / 0.7, 1.0) - 1.0
	var intro := 1.0 + 2.70158 * k * k * k + 1.70158 * k * k # ease-out-back
	_mascot.scale = Vector2.ONE * intro * (1.0 + sin(_time * 2.5) * 0.03)

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
