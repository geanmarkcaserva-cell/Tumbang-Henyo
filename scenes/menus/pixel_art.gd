class_name PixelArt
extends RefCounted
## Placeholder pixel sprites generated from a palette, until the real
## character and tsinelas sprites are exported from the art files.
## A palette may include "band" to paint a headband across the hair.

const CHARACTER := [
	"...HHHHHHH....",
	"..HHHHHHHHH...",
	".HHHHHHHHHHH..",
	".HHSSSSSSSHH..",
	".HSSSSSSSSSH..",
	".HSEESSSEESH..",
	".HSSSSSSSSSH..",
	"..SSSSMMSSS...",
	"..SSSSSSSSS...",
	"...TTTTTTT....",
	"..TTTTTTTTT...",
	".STTTAATTTTS..",
	".STTTAATTTTS..",
	".STTTTTTTTTS..",
	"..TTTTTTTTT...",
	"..PPPPPPPPP...",
	"..PPPP.PPPP...",
	"..PPP...PPP...",
	"...LL...LL....",
	"...LL...LL....",
	"..FFF...FFF...",
	"..............",
]

## Seen from behind: hair instead of a face, no shirt print.
const CHARACTER_BACK := [
	"...HHHHHHH....",
	"..HHHHHHHHH...",
	".HHHHHHHHHHH..",
	".HHHHHHHHHHH..",
	".HHHHHHHHHHH..",
	".HHHHHHHHHHH..",
	".SHHHHHHHHHS..",
	"..SSSSSSSSS...",
	"...SSSSSSS....",
	"...TTTTTTT....",
	"..TTTTTTTTT...",
	".STTTTTTTTTS..",
	".STTTTTTTTTS..",
	".STTTTTTTTTS..",
	"..TTTTTTTTT...",
	"..PPPPPPPPP...",
	"..PPPP.PPPP...",
	"..PPP...PPP...",
	"...LL...LL....",
	"...LL...LL....",
	"..FFF...FFF...",
	"..............",
]

const BAND_ROW := 2

const SLIPPER := [
	"..SSSSSSS...",
	".SSSSSSSSSS.",
	"SSSSTTSSSSSS",
	"SSSTSSTSSSSS",
	".DDDDDDDDDD.",
	"..DDDDDDD...",
]


static func character(p: Dictionary) -> ImageTexture:
	return _person(CHARACTER, p)


## --- Character sprite standard --------------------------------------------
## Every character has three sheets in its folder (art/characters/<id>/):
##   <id>_idle.png   front, standing (character select, facing the camera)
##   <id>_run.png    back view while running (the usual in-game view)
##   <id>_happy.png  front, celebrating (correct answer, round clear, equip)
## Each is a horizontal strip of SQUARE frames, so the frame count is just
## width / height. Feet should sit on the same row in every frame; the empty
## rows under them are measured from the idle sheet automatically.
## Export the .aseprite files to .png next to them (Godot can't read .aseprite).
const STATES := ["idle", "run", "happy"]
const DEFAULT_FPS := {"idle": 6.0, "run": 8.0, "happy": 8.0}

static var _looks := {}


## Everything needed to draw a character from the catalog: its three sheets
## when the entry has a "sprite" folder, otherwise generated placeholders.
## Returns {idle, run, happy: {texture, frames, fps}, frame_h, foot_pad,
## pixel_size}. Missing run/happy sheets fall back to idle.
static func character_look(item: Dictionary) -> Dictionary:
	if _looks.has(item.id):
		return _looks[item.id]
	var look := {}
	if item.has("sprite"):
		look = _load_sheets(item.id, item.sprite)
	if look.is_empty():
		look = placeholder_look(item.palette)
	_looks[item.id] = look
	return look


static func _load_sheets(id: String, s: Dictionary) -> Dictionary:
	var look := {}
	for state in STATES:
		# The artist's own file names can be given per state ("idle": "Kei idle.png");
		# otherwise <id>_<state>.png.
		var file: String = s.get(state, "%s_%s.png" % [id, state])
		var path := "%s/%s" % [s.dir, file]
		if not ResourceLoader.exists(path):
			continue
		var tex: Texture2D = load(path)
		# Square frames: count = width / height ("<state>_frames" overrides it).
		var frames: int = s.get(state + "_frames", maxi(floori(float(tex.get_width()) / tex.get_height()), 1))
		var fps: float = s.get(state + "_fps", DEFAULT_FPS[state])
		look[state] = {"texture": tex, "frames": frames, "fps": fps}
	if not look.has("idle"):
		push_warning("%s: no idle sheet in %s, using a placeholder" % [id, s.dir])
		return {}
	for state in ["run", "happy"]:
		if not look.has(state):
			push_warning("%s: no %s sheet, using idle for it" % [id, state])
			look[state] = look.idle
	var idle_tex: Texture2D = look.idle.texture
	look.frame_h = idle_tex.get_height()
	look.foot_pad = _empty_rows_below(idle_tex)
	# Sheets drawn on the 24 px grid but saved bigger (e.g. 240 px frames, 10x)
	# get a pixel size scaled down to match, so everyone stays the same size.
	var px := float(s.get("pixel_size", GRID_PIXEL))
	if look.frame_h > GRID_FRAME * 2:
		px *= GRID_FRAME / float(look.frame_h)
	# Big hair or antennae can't make anyone taller than MAX_HEIGHT (they'd
	# outgrow the character select stand and tower over the others).
	# ("cap_height": false for grown-ups like Mama and the tanods.)
	var drawn: int = look.frame_h - look.foot_pad - _empty_rows_above(idle_tex)
	if drawn > 0 and s.get("cap_height", true):
		px = minf(px, MAX_HEIGHT / drawn)
	look.pixel_size = px
	return look


## Metres per art pixel for characters on the 24 px grid (same as GM).
const GRID_PIXEL := 0.095
const GRID_FRAME := 24
const MAX_HEIGHT := 1.75 ## metres, top of the head (or hair) to the feet


## How many fully transparent rows are above the head (in any frame).
static func _empty_rows_above(tex: Texture2D) -> int:
	var img := tex.get_image()
	if img == null:
		return 0
	if img.is_compressed():
		img.decompress()
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.5:
				return y
	return 0


## One sheet for every state: the barangay folk (art/characters/Npc*) are
## drawn facing front only. Cached by path.
static func single_sheet_look(path: String, fps: float = 5.0) -> Dictionary:
	if _looks.has(path):
		return _looks[path]
	var tex: Texture2D = load(path)
	var h := tex.get_height()
	var sheet := {"texture": tex, "frames": maxi(floori(float(tex.get_width()) / h), 1), "fps": fps}
	var foot := _empty_rows_below(tex)
	var px := GRID_PIXEL * GRID_FRAME / float(h) if h > GRID_FRAME * 2 else GRID_PIXEL
	var drawn := h - foot - _empty_rows_above(tex)
	if drawn > 0:
		px = minf(px, MAX_HEIGHT / drawn)
	var look := {"idle": sheet, "run": sheet, "happy": sheet, "frame_h": h, "foot_pad": foot, "pixel_size": px}
	_looks[path] = look
	return look


## How many fully transparent rows are under the feet (lowest drawn row).
static func _empty_rows_below(tex: Texture2D) -> int:
	var img := tex.get_image()
	if img == null:
		return 0
	if img.is_compressed():
		img.decompress()
	for y in range(img.get_height() - 1, -1, -1):
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.5:
				return img.get_height() - 1 - y
	return 0


static func placeholder_look(p: Dictionary) -> Dictionary:
	var front := {"texture": character(p), "frames": 1, "fps": 0.0}
	return {"idle": front, "run": {"texture": character_back(p), "frames": 1, "fps": 0.0}, "happy": front,
		"frame_h": CHARACTER.size(), "foot_pad": 0, "pixel_size": 0.08}


static func character_back(p: Dictionary) -> ImageTexture:
	return _person(CHARACTER_BACK, p)


static func slipper(p: Dictionary) -> ImageTexture:
	return ImageTexture.create_from_image(_image(SLIPPER, {"S": p.sole, "D": p.sole.darkened(0.3), "T": p.strap}))


## A catalog slipper's picture: its hand-drawn icon from art/Slippers when
## it has one, otherwise the generated placeholder from its palette.
static func slipper_texture(item: Dictionary) -> Texture2D:
	var icon: String = item.get("icon", "")
	if icon != "" and ResourceLoader.exists(icon):
		return load(icon)
	return slipper(item.palette)


static func _person(rows: Array, p: Dictionary) -> ImageTexture:
	var img := _image(rows, {
		"H": p.hair, "S": p.skin, "L": p.skin,
		"E": Color(0.12, 0.05, 0.05), "M": Color(0.6, 0.12, 0.12),
		"T": p.shirt, "A": p.accent, "P": p.pants, "F": p.feet,
	})
	if p.has("band"):
		var row: String = rows[BAND_ROW]
		for x in row.length():
			if row[x] == "H":
				img.set_pixel(x, BAND_ROW, p.band)
	return ImageTexture.create_from_image(img)


static func _image(rows: Array, colors: Dictionary) -> Image:
	var img := Image.create(rows[0].length(), rows.size(), false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			var key := row[x]
			if colors.has(key):
				img.set_pixel(x, y, colors[key])
	return img
