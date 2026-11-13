extends SceneTree
## Writes processed copies of the demo examples for preview composition.
const Prep := preload("res://addons/psx_texture_prep/psx_texture_prep.gd")
const OUT := "res://tests/_preview_raw"

func _init() -> void:
	var dir := ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(dir)
	for name in ["gradient.png", "noise.png", "pattern.png"]:
		var src := Image.load_from_file("res://demo/examples/" + name)
		if src == null or src.is_empty():
			push_error("missing " + name)
			quit(1)
			return
		var fitted: Image = Prep.fit_pow2(src, Prep.MODE_NEAREST_POW2)
		var rgb: Image = Prep.to_rgb555(fitted, true)
		var pal: Image = Prep.to_palette(fitted, 16, true)["image"]
		src.save_png(OUT + "/" + name.get_basename() + "_src.png")
		fitted.save_png(OUT + "/" + name.get_basename() + "_fit.png")
		rgb.save_png(OUT + "/" + name.get_basename() + "_rgb555.png")
		pal.save_png(OUT + "/" + name.get_basename() + "_pal16.png")
	# Solid + gradient strips for the dither close-up.
	var grad := Image.create_empty(128, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 128:
			var v := clampi(x * 2, 0, 255)
			grad.set_pixel(x, y, Color8(v, v, v, 255))
	Prep.to_rgb555(grad, false).save_png(OUT + "/strip_plain.png")
	Prep.to_rgb555(grad, true).save_png(OUT + "/strip_dither.png")
	quit(0)
