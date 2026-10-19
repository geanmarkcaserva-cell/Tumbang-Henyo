extends Node
## Background music that keeps playing across scene changes and loops.
## Music.play("menu") / Music.play("game"). If the new track is the same song
## that's already playing it just keeps going; otherwise it crossfades.
##
## To give gameplay its own song later: put the file in art/Audio and change
## the "game" entry below.

## Drop a file at a track's path and it's used; until then the track falls
## back to FALLBACK (see docs/AUDIO.md).
const TRACKS := {
	"menu": "res://art/Audio/Bg music default.mp3",
	"game": "res://art/Audio/music/game.ogg", # gameplay song (not made yet)
	"mama": "res://art/Audio/music/mama_chase.ogg", # Mama's chase (not made yet)
}
const FALLBACK := {
	"game": "menu",
	"mama": "game",
}
@export var volume_db := -8.0 ## a bit under the sound effects
const FADE := 1.2

var _a: AudioStreamPlayer
var _b: AudioStreamPlayer
var _current_path := ""
var _tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # keeps playing while paused
	_a = AudioStreamPlayer.new()
	_b = AudioStreamPlayer.new()
	_a.bus = &"Music" # volume set in Settings
	_b.bus = &"Music"
	add_child(_a)
	add_child(_b)


func play(track: String) -> void:
	var path: String = TRACKS.get(track, "")
	while path != "" and not ResourceLoader.exists(path) and FALLBACK.has(track):
		track = FALLBACK[track]
		path = TRACKS.get(track, "")
	if path == "" or path == _current_path:
		return
	var stream := load(path) as AudioStream
	if stream == null:
		push_warning("Music: can't load %s" % path)
		return
	_set_loop(stream)
	_current_path = path
	# Crossfade: the idle player takes the new song, the old one fades out.
	var incoming := _b if _a.playing else _a
	var outgoing := _a if incoming == _b else _b
	incoming.stream = stream
	incoming.volume_db = -40.0
	incoming.play()
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(incoming, "volume_db", volume_db, FADE)
	if outgoing.playing:
		_tween.tween_property(outgoing, "volume_db", -40.0, FADE)
		_tween.chain().tween_callback(outgoing.stop)


func stop(fade: float = FADE) -> void:
	_current_path = ""
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	for p in [_a, _b]:
		if p.playing:
			_tween.tween_property(p, "volume_db", -40.0, fade)
	_tween.chain().tween_callback(func(): _a.stop(); _b.stop())


func _set_loop(stream: AudioStream) -> void:
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
