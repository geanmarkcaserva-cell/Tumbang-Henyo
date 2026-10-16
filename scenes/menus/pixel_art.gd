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
