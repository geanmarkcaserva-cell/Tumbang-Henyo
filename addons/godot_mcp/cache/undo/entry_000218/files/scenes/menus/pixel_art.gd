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


## Everything needed to draw a character from the catalog: hand-drawn sheets
## when the entry has a "sprite", otherwise the generated placeholder.
## Keys: front, back (Texture2D), front_frames, back_frames, front_fps,
## back_fps, frame_h and foot_pad (pixels), pixel_size (metres per pixel).
static func character_look(item: Dictionary) -> Dictionary:
	if item.has("sprite"):
		var s: Dictionary = item.sprite
		var front: Texture2D = load(s.front)
		var back: Texture2D = load(s.back) if s.has("back") else null
		if front:
			return {"front": front, "back": back,
				"front_frames": int(s.get("front_frames", 1)), "back_frames": int(s.get("back_frames", 1)),
				"front_fps": float(s.get("front_fps", 6.0)), "back_fps": float(s.get("back_fps", 8.0)),
				"frame_h": int(s.get("frame_h", front.get_height())), "foot_pad": int(s.get("foot_pad", 0)),
				"pixel_size": float(s.get("pixel_size", 0.08))}
		push_warning("Missing sprite sheet for %s, using placeholder" % item.id)
	return placeholder_look(item.palette)


static func placeholder_look(p: Dictionary) -> Dictionary:
	return {"front": character(p), "back": character_back(p), "front_frames": 1, "back_frames": 1,
		"front_fps": 0.0, "back_fps": 0.0, "frame_h": CHARACTER.size(), "foot_pad": 0, "pixel_size": 0.08}


static func character_back(p: Dictionary) -> ImageTexture:
	return _person(CHARACTER_BACK, p)


static func slipper(p: Dictionary) -> ImageTexture:
	return ImageTexture.create_from_image(_image(SLIPPER, {"S": p.sole, "D": p.sole.darkened(0.3), "T": p.strap}))


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
