extends Node
## Films the demo scenarios: for each job in jobs.json it starts a separate
## game process with Godot's Movie Maker (--write-movie) running demo_start.tscn,
## waits for it to finish, and then puts the player's save data back exactly as
## it was (the demo plays on the current account).

const JOBS := "res://tools/demo_bot/jobs.json"
const SKIP_DIRS := ["logs", "shader_cache", "vulkan", "godot_mcp"]

var _backup := ""
var _status := {}
var _status_path := ""


func _ready() -> void:
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(JOBS))
	var out_dir: String = cfg.out_dir
	DirAccess.make_dir_recursive_absolute(out_dir)
	_status_path = out_dir.path_join("status.json")
	_backup = OS.get_user_data_dir() + "_demo_backup"
	_remove_tree(_backup)
	_copy_tree(OS.get_user_data_dir(), _backup)
	_status = {"state": "running", "done": [], "current": "",
			"screen": str(DisplayServer.screen_get_size()), "scale": DisplayServer.screen_get_scale(),
			"usable": str(DisplayServer.screen_get_usable_rect()), "dpi": DisplayServer.screen_get_dpi(),
			"window": str(DisplayServer.window_get_size())}
	_save_status()
	_run_jobs(cfg, out_dir)


func _run_jobs(cfg: Dictionary, out_dir: String) -> void:
	# The project forces a 1280x720 window (window_*_override); for filming, an
	# override.cfg (read only at start-up) asks for full HD. Removed at the end.
	var ov := FileAccess.open(_override_path(), FileAccess.WRITE)
	ov.store_string("[display]\n\nwindow/size/window_width_override=%d\nwindow/size/window_height_override=%d\n\n[editor]\n\nmovie_writer/mjpeg_quality=%s\n"
			% [int(cfg.get("width", 1920)), int(cfg.get("height", 1080)), str(cfg.get("quality", 0.8))])
	ov.close()
	var exe := OS.get_executable_path()
	var proj := ProjectSettings.globalize_path("res://")
	for job in cfg.jobs:
		var movie: String = out_dir.path_join(job.name + ".avi")
		var args := ["--path", proj, "--write-movie", movie, "--fixed-fps", str(cfg.get("fps", 30)),
				"--resolution", cfg.get("resolution", "1920x1080"), "--disable-vsync",
				"res://tools/demo_bot/demo_start.tscn", "++", "--demo=" + job.name]
		_status.current = job.name
		_save_status()
		print("[launcher] filming ", job.name, " -> ", movie)
		var pid := OS.create_process(exe, args)
		var t0 := Time.get_ticks_msec()
		while pid > 0 and OS.is_process_running(pid):
			await get_tree().create_timer(1.0).timeout
			if Time.get_ticks_msec() - t0 > int(cfg.get("timeout_s", 900)) * 1000:
				OS.kill(pid)
				print("[launcher] timeout ", job.name)
				break
		_restore_user_data()
		_status.done.append({"name": job.name, "seconds": (Time.get_ticks_msec() - t0) / 1000.0, "pid": pid})
		_save_status()
	DirAccess.remove_absolute(_override_path())
	_status.state = "finished"
	_status.current = ""
	_save_status()
	print("[launcher] all done")
	get_tree().quit()


func _override_path() -> String:
	return ProjectSettings.globalize_path("res://override.cfg")


func _save_status() -> void:
	var f := FileAccess.open(_status_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_status, "  "))


# ---- save data snapshot -------------------------------------------------------

func _restore_user_data() -> void:
	var ud := OS.get_user_data_dir()
	_delete_new(ud, _backup)
	_copy_tree(_backup, ud)


func _copy_tree(src: String, dst: String) -> void:
	DirAccess.make_dir_recursive_absolute(dst)
	var d := DirAccess.open(src)
	if d == null:
		return
	for f in d.get_files():
		DirAccess.copy_absolute(src.path_join(f), dst.path_join(f))
	for sub in d.get_directories():
		if sub in SKIP_DIRS:
			continue
		_copy_tree(src.path_join(sub), dst.path_join(sub))


## Delete files in `live` that the snapshot `snap` doesn't have.
func _delete_new(live: String, snap: String) -> void:
	var d := DirAccess.open(live)
	if d == null:
		return
	for f in d.get_files():
		if not FileAccess.file_exists(snap.path_join(f)):
			DirAccess.remove_absolute(live.path_join(f))
	for sub in d.get_directories():
		if sub in SKIP_DIRS:
			continue
		if not DirAccess.dir_exists_absolute(snap.path_join(sub)):
			_remove_tree(live.path_join(sub))
		else:
			_delete_new(live.path_join(sub), snap.path_join(sub))


func _remove_tree(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	for sub in d.get_directories():
		_remove_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)
