extends Control
## Loading screen before a run: the barangay skyline in drifting parallax
## layers (ParallaxBackdrop), a tip in the middle, and a chalk-line loading bar.
## Loads the game scene in the background.
##
## The text sits on a 1920x1080 "stage" kept in the middle of the screen, so
## wide phones and tall tablets show it centred instead of pushed to one side.

@export var min_time := 3.5 ## long enough to read the tip

const GAMEPLAY_TIPS := [
	"Juke the taya: cut hard the other way and it keeps running where it thought you'd go.",
	"Tayas run faster than you walk but slower than you sprint. Save your Energy for the escape.",
	"A red ring means a tsinelas is coming fast. Get out of it right away.",
	"Jump while running for a burst of speed. Chain jumps to go even faster, if you have the Energy.",
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
	add_child(ParallaxBackdrop.new())
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
		Transition.change_scene(ResourceLoader.load_threaded_get(GameManager.GAME))
	elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		set_process(false)
		push_error("Tips loading: could not load the game scene")
		Transition.change_scene(GameManager.GAME)


## A 1920x1080 area pinned to the middle of the screen.
static func make_stage() -> Control:
	var stage := Control.new()
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.set_anchors_preset(Control.PRESET_CENTER)
	stage.offset_left = -960
	stage.offset_right = 960
	stage.offset_top = -540
	stage.offset_bottom = 540
	return stage


func _build_text() -> void:
	var stage := make_stage()
	add_child(stage)

	# The tip, centred in the sky above the rooftops.
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 14)
	col.position = Vector2(310, 170)
	col.size = Vector2(1300, 440)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(col)

	var tips := UiKit.title("Tips.", 100, Color.WHITE, 12)
	tips.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(tips)

	var fact := QuizDatabase.random_tip(GameManager.selected_theme)
	var use_fact := fact != "" and randf() < 0.6
	var header := UiKit.title("Did you know?" if use_fact else "Tip:", 48, UiKit.ACCENT, 8)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(header)

	var body := UiKit.label(fact if use_fact else GAMEPLAY_TIPS.pick_random(), 42, Color.WHITE, 8)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.custom_minimum_size = Vector2(1300, 0)
	col.add_child(body)

	# "Loading..." and the bar, centred near the bottom.
	_loading = UiKit.title("Loading", 56, Color.WHITE, 10)
	_loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading.position = Vector2(660, 890)
	_loading.size = Vector2(600, 80)
	stage.add_child(_loading)

	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.position = Vector2(635, 985)
	_bar.size = Vector2(650, 30)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.97, 0.95, 0.92)
	fill.set_corner_radius_all(14)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0, 0, 0, 0.28)
	back.set_corner_radius_all(14)
	_bar.add_theme_stylebox_override("fill", fill)
	_bar.add_theme_stylebox_override("background", back)
	stage.add_child(_bar)
	UiFx.pop_in(col, 0.35) # the tip springs in once the skyline has risen
