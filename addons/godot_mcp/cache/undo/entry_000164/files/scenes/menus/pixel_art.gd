class_name PixelArt
extends RefCounted
## Placeholder pixel sprites generated from a palette, until the real
## character and tsinelas sprites are exported from the art files.

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

const SLIPPER := [
	"..SSSSSSS...",
	".SSSSSSSSSS.",
	"SSSSTTSSSSSS",
	"SSSTSSTSSSSS",
	".DDDDDDDDDD.",
	"..DDDDDDD...",
]


static func character(p: Dictionary) -> ImageTexture:
	return _make(CHARACTER, {
		"H": p.hair, "S": p.skin, "L": p.skin,
		"E": Color(0.12, 0.05, 0.05), "M": Color(0.6, 0.12, 0.12),
		"T": p.shirt, "A": p.accent, "P": p.pants, "F": p.feet,
	})


static func slipper(p: Dictionary) -> ImageTexture:
	return _make(SLIPPER, {"S": p.sole, "D": p.sole.darkened(0.3), "T": p.strap})


static func _make(rows: Array, colors: Dictionary) -> ImageTexture:
	var img := Image.create(rows[0].length(), rows.size(), false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			var key := row[x]
			if colors.has(key):
				img.set_pixel(x, y, colors[key])
	return ImageTexture.create_from_image(img)
