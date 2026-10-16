extends Control
## Loading screen before a run: blue sky, a barangay skyline with electric
## posts and wires, a tip, and a chalk-line loading bar. Loads the game scene
## in the background.

@export var min_time := 3.5 ## long enough to read the tip

const SKY_TOP := Color(0.35, 0.6, 1.0)
const SKY_BOTTOM := Color(0.55, 0.8, 1.0)
const SILHOUETTE := Color(0.3, 0.49, 0.78)
const WINDOW := Color(0.55, 0.78, 1.0)

const GAMEPLAY_TIPS := [
	"Juke the taya: cut hard the other way and it keeps running where it thought you'd go.",
	"Tayas run faster than you walk but slower than you sprint. Save your Energy for the escape.",
	"A red ring means a tsinelas is coming fast. Get out of it right away.",
	"Sidestep a lunge at the last moment and the taya stumbles. That's your chance.",
	"Answer fast: quicker answers score more points.",
	"A taya with no tsinelas left has to stop and pick one up.",
]

var _time := 0.0
var _bar: ProgressBar
var _loading: Label


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_sky()
	_build_skyline()
	_build_text()
	ResourceLoader.load_threaded_request(GameManager.GAME)


func _process(delta: float) -> void:
	_time += delta
	var progress := []
	var status := ResourceLoader.load_threaded_get_status(GameManager.GAME, progress)
	var loaded: float = progress[0] if progress.size() > 0 else 0.0
	_bar.value = minf(loaded, _time / min_time) * 100.0
	_loading.text = "Loading" + ".".repeat(int(_time * 3.0) % 4)

	if status == ResourceLoader.THREAD_LOAD_LOADED and _time >= min_time:
		set_process(false)
		get_tree().change_scene_to_packed(ResourceLoader.load_threaded_get(GameManager.GAME))
	elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		set_process(false)
		push_error("Tips loading: could not load the game scene")
		get_tree().change_scene_to_file(GameManager.GAME)


func _build_sky() -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, SKY_TOP)
	gradient.set_color(1, SKY_BOTTOM)
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	tex.width = 16
	tex.height = 256
	var sky := TextureRect.new()
	sky.texture = tex
	sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(sky)


func _build_skyline() -> void:
	var city := Node2D.new()
	add_child(city)
	# Houses: [x, width, height], standing on the bottom edge (y = 1080).
	for h in [[0, 330, 170], [380, 270, 235], [740, 330, 290], [1250, 450, 290], [1700, 220, 250]]:
		_rect(city, Rect2(h[0], 1080 - h[2], h[1], h[2]), SILHOUETTE)
	# Roof shapes and a gable.
	_poly(city, [Vector2(0, 920), Vector2(0, 860), Vector2(110, 900), Vector2(220, 800), Vector2(330, 910)], SILHOUETTE)
	_poly(city, [Vector2(650, 1080), Vector2(690, 880), Vector2(740, 1080)], SILHOUETTE)
	_poly(city, [Vector2(740, 790), Vector2(1070, 790), Vector2(1160, 1080), Vector2(740, 1080)], SILHOUETTE)
	_poly(city, [Vector2(1660, 790), Vector2(1725, 700), Vector2(1790, 790)], SILHOUETTE)
	_rect(city, Rect2(1245, 790, 600, 40), SILHOUETTE)
	# Windows.
	for w in [Rect2(415, 895, 100, 95), Rect2(1315, 845, 150, 160), Rect2(1500, 850, 70, 150), Rect2(1690, 920, 50, 160)]:
		_rect(city, w, WINDOW)
	# Electric posts and sagging wires.
	var posts := [Vector2(285, 545), Vector2(1375, 470), Vector2(1772, 595)]
	for p in posts:
		_rect(city, Rect2(p.x - 8, p.y, 16, 1080 - p.y), SILHOUETTE)
	_rect(city, Rect2(1655, 600, 265, 14), SILHOUETTE)
	for i in posts.size() - 1:
		for sag in [110.0, 160.0]:
			_wire(city, posts[i] + Vector2(0, 50), posts[i + 1] + Vector2(0, 50), sag)
	_wire(city, Vector2(-20, 760), posts[0] + Vector2(0, 50), 40.0)
	_wire(city, posts[2] + Vector2(0, 40), Vector2(1940, 560), 30.0)


func _build_text() -> void:
	var tips := UiKit.label("Tips.", 96, Color.WHITE, 10)
	tips.position = Vector2(240, 270)
	add_child(tips)

	var fact := QuizDatabase.random_tip(GameManager.selected_theme)
	var use_fact := fact != "" and randf() < 0.6
	var header := UiKit.label("Did you know?" if use_fact else "Tip:", 44, Color.WHITE, 6)
	header.position = Vector2(420, 400)
	add_child(header)

	var body := UiKit.label(fact if use_fact else GAMEPLAY_TIPS.pick_random(), 40, Color.WHITE, 6)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.position = Vector2(420, 465)
	body.size = Vector2(1150, 200)
	add_child(body)

	_loading = UiKit.label("Loading", 52, Color.WHITE, 8)
	_loading.position = Vector2(870, 905)
	add_child(_loading)

	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.position = Vector2(660, 1000)
	_bar.size = Vector2(650, 30)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.97, 0.95, 0.92)
	fill.set_corner_radius_all(14)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(1, 1, 1, 0.18)
	back.set_corner_radius_all(14)
	_bar.add_theme_stylebox_override("fill", fill)
	_bar.add_theme_stylebox_override("background", back)
	add_child(_bar)


func _rect(parent: Node, r: Rect2, color: Color) -> void:
	_poly(parent, [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)], color)


func _poly(parent: Node, points: Array, color: Color) -> void:
	var p := Polygon2D.new()
	p.color = color
	p.polygon = PackedVector2Array(points)
	parent.add_child(p)


func _wire(parent: Node, a: Vector2, b: Vector2, sag: float) -> void:
	var line := Line2D.new()
	line.width = 5
	line.default_color = SILHOUETTE
	var pts := PackedVector2Array()
	for i in 21:
		var t := i / 20.0
		pts.append(a.lerp(b, t) + Vector2(0, sin(t * PI) * sag))
	line.points = pts
	parent.add_child(line)
