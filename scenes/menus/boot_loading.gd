extends Control
## First screen: black background, the tsinelas mascot wobbling in the middle,
## a small line explaining what is being prepared, and "Loading..." in the
## corner. Loads the main menu (with its 3D court) in the background.

@export var min_time := 2.2 ## keep the screen up at least this long

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
	_mascot.rotation = deg_to_rad(-22.0 + sin(_time * 5.0) * 6.0)
	_mascot.scale = Vector2.ONE * (1.0 + sin(_time * 2.5) * 0.03)

	if status == ResourceLoader.THREAD_LOAD_LOADED and _time >= min_time:
		set_process(false)
		Transition.change_scene(ResourceLoader.load_threaded_get(GameManager.MAIN_MENU))
	elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		set_process(false)
		push_error("Boot loading: could not load the main menu")
		Transition.change_scene(GameManager.MAIN_MENU)


## Placeholder mascot: a white tsinelas with a black strap and grey toes.
func _build_mascot() -> Node2D:
	var root := Node2D.new()
	var sole := Polygon2D.new()
	sole.color = Color.WHITE
	sole.polygon = _ellipse(Vector2.ZERO, Vector2(230, 105), 40)
	root.add_child(sole)
	var heel := Polygon2D.new()
	heel.color = Color(0.8, 0.8, 0.8)
	heel.polygon = _ellipse(Vector2(130, -5), Vector2(70, 55), 24)
	root.add_child(heel)
	for toe in [Vector2(-185, -25), Vector2(-175, 20), Vector2(-160, 55)]:
		var t := Polygon2D.new()
		t.color = Color(0.82, 0.82, 0.82)
		t.polygon = _ellipse(toe, Vector2(22, 16), 16)
		root.add_child(t)
	var strap := Line2D.new()
	strap.width = 12
	strap.default_color = Color.BLACK
	strap.joint_mode = Line2D.LINE_JOINT_ROUND
	strap.begin_cap_mode = Line2D.LINE_CAP_ROUND
	strap.end_cap_mode = Line2D.LINE_CAP_ROUND
	strap.points = PackedVector2Array([Vector2(-140, 20), Vector2(-40, -20), Vector2(60, 15), Vector2(150, 10)])
	root.add_child(strap)
	var post := Line2D.new()
	post.width = 12
	post.default_color = Color.BLACK
	post.begin_cap_mode = Line2D.LINE_CAP_ROUND
	post.end_cap_mode = Line2D.LINE_CAP_ROUND
	post.points = PackedVector2Array([Vector2(-40, -20), Vector2(-5, -65)])
	root.add_child(post)
	return root


func _ellipse(center: Vector2, radii: Vector2, points: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in points:
		var a := TAU * i / points
		out.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	return out
