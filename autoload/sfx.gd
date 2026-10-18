extends Node
## One-shot sound effects. Add a sound by putting the file in art/Audio and
## listing it in SOUNDS, then call Sfx.play("name") from anywhere.

const SOUNDS := {
	"correct": preload("res://art/Audio/Correct answer.mp3"),
	"wrong": preload("res://art/Audio/Wrong answer.mp3"),
}
const VOICES := 6 ## how many sounds can overlap

var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX" # volume set in Settings
		add_child(p)
		_players.append(p)


## volume_db: 0 = as recorded. pitch adds a little variety when repeated.
func play(sound: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var stream: AudioStream = SOUNDS.get(sound)
	if stream == null:
		push_warning("Sfx: no sound named '%s'" % sound)
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()
