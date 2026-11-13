extends Node2D
## Before/after demo. Loads the generated example PNGs and shows each one three times:
## original, RGB555 with Bayer dither, and 16-color palette with Bayer dither.

const _Prep := preload("res://addons/psx_texture_prep/psx_texture_prep.gd")
const EXAMPLES := ["gradient.png", "noise.png", "pattern.png"]
const SCALE := 2.0


func _ready() -> void:
	var headers := ["Original", "RGB555 + dither", "16 colors + dither"]
	for c in headers.size():
		_label(headers[c], Vector2(20 + c * 310, 8))
	for r in EXAMPLES.size():
		var img := Image.new()
		var path := ProjectSettings.globalize_path("res://demo/examples/" + EXAMPLES[r])
		if img.load(path) != OK:
			continue
		var fitted: Image = _Prep.fit_pow2(img, _Prep.MODE_NEAREST_POW2)
		var variants: Array[Image] = [
			fitted,
			_Prep.to_rgb555(fitted, true),
			_Prep.to_palette(fitted, 16, true)["image"],
		]
		for c in variants.size():
			var s := Sprite2D.new()
			s.texture = ImageTexture.create_from_image(variants[c])
			s.centered = false
			s.scale = Vector2(SCALE, SCALE)
			s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			s.position = Vector2(20 + c * 310, 32 + r * 170)
			add_child(s)


func _label(text: String, pos: Vector2) -> void:
	var l := Label.new()
	l.text = text
	l.position = pos
	add_child(l)
