class_name Avatars
extends RefCounted
## Profile pictures for local accounts: a round badge in the account's colour
## with a picture on it. The picture ("avatar" in the account entry) is one of
##   {"kind": "letter"}                      just the colour (the card adds the initial)
##   {"kind": "character", "id": "gm"}       the character's face (owned ones)
##   {"kind": "slipper", "id": "kroks"}      a tsinelas (owned ones)
##   {"kind": "item", "id": "holen"}         a Collection item (found ones)
## plus an optional "crop" the player framed themselves (AvatarCropper).
## Pictures are pixel art scaled up with no smoothing, clipped to the circle.

static var _cache := {}


static func texture(account: Dictionary, px: int) -> Texture2D:
	var av: Dictionary = account.get("avatar", {"kind": "letter"})
	var col: Color = account.get("color", UiKit.ACCENT)
	var key := "%s|%s|%s|%s|%d" % [av.get("kind", "letter"), av.get("id", ""), str(av.get("crop", [])), col.to_html(), px]
	if _cache.has(key):
		return _cache[key]
	var art := picture(av)
	var img := _badge(col, px, art, av.has("crop"))
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## The bare picture (no circle) for an avatar choice, or null for "letter".
## "crop": [x, y, side] - the player's own framing (Change picture > Crop),
## as fractions of the source picture's width/height/width. Without it a
## character shows its face, anything else the whole picture.
static func picture(av: Dictionary) -> Image:
	var src := source(av)
	if src == null:
		return null
	var crop: Array = av.get("crop", [])
	if crop.size() == 3:
		return crop_square(src, crop_rect(src, crop))
	if String(av.get("kind", "")) == "character":
		return crop_square(src, face_rect(src))
	return src


## The whole picture a choice is cut from: a character's first front frame,
## a slipper's sprite, a Collection item's icon.
static func source(av: Dictionary) -> Image:
	match String(av.get("kind", "letter")):
		"character":
			var look := PixelArt.character_look(Economy.find_item("character", av.get("id", "proktoy")))
			var sheet: Dictionary = look.idle
			var img := _image_of(sheet.texture)
			if img == null:
				return null
			var fw := img.get_width() / maxi(int(sheet.frames), 1)
			return img.get_region(Rect2i(0, 0, fw, img.get_height()))
		"slipper":
			return _image_of(PixelArt.slipper_texture(Economy.find_item("slipper", av.get("id", "goma"))))
		"item":
			return _image_of(EasterEggs.icon(av.get("id", "trumpo")))
	return null


## A saved crop ([x, y, side] fractions) as a pixel square on `src`.
static func crop_rect(src: Image, crop: Array) -> Rect2i:
	var w := src.get_width()
	var h := src.get_height()
	var side := maxi(int(round(float(crop[2]) * w)), 1)
	return Rect2i(int(round(float(crop[0]) * w)), int(round(float(crop[1]) * h)), side, side)


## The other way round: a pixel square on `src` as saved fractions.
static func crop_of(src: Image, r: Rect2i) -> Array:
	return [float(r.position.x) / src.get_width(), float(r.position.y) / src.get_height(), float(r.size.x) / src.get_width()]


## `r` cut out of `img`; parts outside the picture come out transparent.
static func crop_square(img: Image, r: Rect2i) -> Image:
	var out := Image.create(maxi(r.size.x, 1), maxi(r.size.y, 1), false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	var clipped := r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if clipped.size.x > 0 and clipped.size.y > 0:
		out.blit_rect(img, clipped, clipped.position - r.position)
	return out


## Share of a character's drawn height that is head (chibi proportions).
const HEAD_SHARE := 0.8


## Where a character's face is on its front frame: the top of the drawing
## (skipping a thin ahoge, a sparkle...) down a HEAD_SHARE of the way to the
## feet, centred on where most of the drawing in those rows is (so long hair
## on one side doesn't push the face off). Square, so the whole face - eyes,
## mouth, chin - sits inside the circle.
static func face_rect(frame: Image) -> Rect2i:
	var used := frame.get_used_rect()
	if used.size.x <= 0:
		return Rect2i(Vector2i.ZERO, frame.get_size())
	var g := maxf(frame.get_height() / 24.0, 1.0) # sheets saved at 10x
	var rows := PackedInt32Array()
	rows.resize(frame.get_height())
	for y in range(used.position.y, used.end.y):
		var n := 0
		for x in range(used.position.x, used.end.x):
			if frame.get_pixel(x, y).a > 0.5:
				n += 1
		rows[y] = n
	var top := used.position.y
	while top < used.end.y - 1 and rows[top] < int(3.0 * g):
		top += 1
	var side := maxi(int(round((used.end.y - top) * HEAD_SHARE)), 1)
	var sum_x := 0.0
	var count := 0
	for y in range(top, mini(top + side, used.end.y)):
		for x in range(used.position.x, used.end.x):
			if frame.get_pixel(x, y).a > 0.5:
				sum_x += x
				count += 1
	var cx := sum_x / maxi(count, 1) + 0.5
	return Rect2i(int(round(cx - side * 0.5)), top - int(side * 0.06), side, side)


static func _image_of(tex: Texture2D) -> Image:
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return null
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


## Circle in `col` (thin darker rim), with `art` scaled up crisply in the middle.
## `fill`: the art is the player's own crop - it fills the circle exactly, as
## they framed it (otherwise it sits in the middle 80%).
static func _badge(col: Color, px: int, art: Image, fill: bool = false) -> Image:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var r := px * 0.5
	var rim := px * 0.06
	for y in px:
		for x in px:
			var d := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			var alpha := clampf(r - d, 0.0, 1.0)
			if alpha > 0.0:
				var c := col.darkened(0.25) if d > r - rim else col
				img.set_pixel(x, y, Color(c, alpha))
	if art == null:
		return img
	# Fit the art in the middle 80% of the badge, whole-pixel scale if it's tiny.
	var box := int(px * (1.0 - 0.12) if fill else px * 0.8)
	var scale := minf(float(box) / art.get_width(), float(box) / art.get_height())
	if scale >= 1.0:
		scale = maxf(floorf(scale), 1.0)
	var w := maxi(int(art.get_width() * scale), 1)
	var h := maxi(int(art.get_height() * scale), 1)
	var a := art.duplicate() as Image
	a.resize(w, h, Image.INTERPOLATE_NEAREST if scale >= 1.0 else Image.INTERPOLATE_BILINEAR)
	var ox := (px - w) / 2
	var oy := (px - h) / 2
	for y in h:
		for x in w:
			var c := a.get_pixel(x, y)
			if c.a <= 0.02:
				continue
			var tx := ox + x
			var ty := oy + y
			var d := Vector2(tx + 0.5 - r, ty + 0.5 - r).length()
			if d > r - rim:
				continue # keep the rim clean
			img.set_pixel(tx, ty, img.get_pixel(tx, ty).blend(c))
	return img
