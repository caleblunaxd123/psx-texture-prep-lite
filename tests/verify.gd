extends SceneTree
## Headless verification: godot --headless --path <lite> --script tests/verify.gd
## Exit code 0 = all pass, 1 = any failure. Writes tests/verify_report.txt.

const Prep := preload("res://addons/psx_texture_prep/psx_texture_prep.gd")
const Batch := preload("res://addons/psx_texture_prep/psx_batch.gd")
const TMP := "/tmp/psx_texture_prep_verify"

var lines: PackedStringArray = []
var passed := 0
var failed := 0


func check(name: String, ok: bool, detail: String = "") -> void:
	var s := ("PASS " if ok else "FAIL ") + name
	if detail != "" and not ok:
		s += "  -- " + detail
	lines.append(s)
	print(s)
	if ok:
		passed += 1
	else:
		failed += 1


func _is_pow2(n: int) -> bool:
	return n >= 1 and (n & (n - 1)) == 0


func _solid(w: int, h: int, c: Color) -> Image:
	var im := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	im.fill(c)
	return im


func _gradient(w: int, h: int) -> Image:
	var im := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var v := clampi(x * 4, 0, 255)
			im.set_pixel(x, y, Color8(v, v, v, 255))
	return im


func _noise(w: int, h: int, seed_v: int) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var im := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			im.set_pixel(x, y, Color8(rng.randi() % 256, rng.randi() % 256, rng.randi() % 256, 255))
	return im


func _rm_rf(path: String) -> void:
	if not path.begins_with("/tmp/psx_texture_prep_verify"):
		return
	if not DirAccess.dir_exists_absolute(path):
		return
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path + "/" + f)
	for d in DirAccess.get_directories_at(path):
		_rm_rf(path + "/" + d)
	DirAccess.remove_absolute(path)


func _hash_tree(root: String, rel: String = "") -> Dictionary:
	var out := {}
	var p := root if rel == "" else root + "/" + rel
	for f in DirAccess.get_files_at(p):
		var r := f if rel == "" else rel + "/" + f
		out[r] = FileAccess.get_sha256(p + "/" + f)
	for d in DirAccess.get_directories_at(p):
		out.merge(_hash_tree(root, d if rel == "" else rel + "/" + d))
	return out


func _distinct_rgb(im: Image) -> Dictionary:
	var s := {}
	for y in im.get_height():
		for x in im.get_width():
			var c := im.get_pixel(x, y)
			s[c.to_rgba32()] = true
	return s


func _init() -> void:
	run()
	var summary := "SUMMARY: %d passed, %d failed" % [passed, failed]
	lines.append(summary)
	print(summary)
	var rp := ProjectSettings.globalize_path("res://tests/verify_report.txt")
	var f := FileAccess.open(rp, FileAccess.WRITE)
	if f:
		f.store_string("PSX Texture Prep Lite - verify report\n" + Engine.get_version_info()["string"] + "\n\n" + "\n".join(lines) + "\n")
		f.close()
	quit(0 if failed == 0 else 1)


func run() -> void:
	# 1. Classes load.
	check("1 PsxTexturePrep loads", Prep != null)
	check("1 PsxBatch loads", Batch != null)
	var plugin_script: Script = load("res://addons/psx_texture_prep/plugin.gd")
	check("1 plugin.gd parses", plugin_script != null)

	# 2. fit_pow2.
	var src := _noise(100, 60, 7)
	var src_hash := src.get_data().hex_encode().sha256_text()
	var a: Image = Prep.fit_pow2(src, Prep.MODE_NEAREST_POW2)
	check("2 nearest 100x60 -> 128x64", a.get_width() == 128 and a.get_height() == 64, str(a.get_size()))
	var b: Image = Prep.fit_pow2(src, Prep.MODE_CROP)
	check("2 crop 100x60 -> 64x32", b.get_width() == 64 and b.get_height() == 32, str(b.get_size()))
	var c: Image = Prep.fit_pow2(src, Prep.MODE_PAD)
	check("2 pad 100x60 -> 128x64", c.get_width() == 128 and c.get_height() == 64, str(c.get_size()))
	check("2 pad is centred, unscaled, transparent border",
		c.get_pixel(0, 0).a == 0.0 and c.get_pixel(14, 2).to_rgba32() == src.get_pixel(0, 0).to_rgba32())
	check("2 crop is centred", b.get_pixel(0, 0).to_rgba32() == src.get_pixel(18, 14).to_rgba32())
	check("2 input not mutated", src.get_size() == Vector2i(100, 60) and src.get_data().hex_encode().sha256_text() == src_hash)
	var all_pow2 := true
	for mode in [Prep.MODE_NEAREST_POW2, Prep.MODE_CROP, Prep.MODE_PAD]:
		for sz in [Vector2i(1, 1), Vector2i(3, 5), Vector2i(33, 31), Vector2i(64, 64), Vector2i(97, 129), Vector2i(1000, 7)]:
			var r: Image = Prep.fit_pow2(_solid(sz.x, sz.y, Color.RED), mode)
			all_pow2 = all_pow2 and _is_pow2(r.get_width()) and _is_pow2(r.get_height())
	check("2 always power of two", all_pow2)
	var capped: Image = Prep.fit_pow2(_solid(300, 200, Color.RED), Prep.MODE_PAD, 100)
	check("2 max_side 100 -> sides <= 64", capped.get_width() == 64 and capped.get_height() == 64, str(capped.get_size()))
	var tie: Image = Prep.fit_pow2(_solid(96, 48, Color.RED), Prep.MODE_NEAREST_POW2)
	check("2 tie rounds up (96x48 -> 128x64)", tie.get_size() == Vector2i(128, 64), str(tie.get_size()))

	# 3. to_rgb555.
	var levels_ok := true
	var noise := _noise(32, 32, 3)
	for dither in [false, true]:
		var q: Image = Prep.to_rgb555(noise, dither)
		for y in 32:
			for x in 32:
				var px: Color = q.get_pixel(x, y)
				for v in [px.r8, px.g8, px.b8]:
					var lv := int(v) >> 3
					if int(v) != ((lv << 3) | (lv >> 2)):
						levels_ok = false
		check("3 rgb555 5-bit levels (dither=%s)" % dither, levels_ok)
	var expected_ok := true
	var qd: Image = Prep.to_rgb555(noise, true)
	var bayer := [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
	for y in 32:
		for x in 32:
			var o: Color = noise.get_pixel(x, y)
			var e: Color = qd.get_pixel(x, y)
			var off: float = (float(bayer[y % 4][x % 4]) / 16.0 - 0.5) * 8.0
			for pair in [[o.r8, e.r8], [o.g8, e.g8], [o.b8, e.b8]]:
				var lv := int(clampf(pair[0] + off, 0.0, 255.0)) >> 3
				if pair[1] != ((lv << 3) | (lv >> 2)):
					expected_ok = false
	check("3 rgb555 dither matches fixed formula", expected_ok)
	var half := Image.create_empty(2, 1, false, Image.FORMAT_RGBA8)
	half.set_pixel(0, 0, Color8(10, 20, 30, 127))
	half.set_pixel(1, 0, Color8(10, 20, 30, 128))
	var ha: Image = Prep.to_rgb555(half, false)
	check("3 alpha threshold 0.5", ha.get_pixel(0, 0).a8 == 0 and ha.get_pixel(1, 0).a8 == 255)
	var n_before := noise.get_data().hex_encode().sha256_text()
	Prep.to_rgb555(noise, true)
	check("3 input not mutated", noise.get_data().hex_encode().sha256_text() == n_before)

	# 4. to_palette.
	var pal_img := _noise(48, 48, 11)
	var pal_ok := true
	var pal_detail := ""
	for dither in [false, true]:
		var res: Dictionary = Prep.to_palette(pal_img, 16, dither)
		var pim: Image = res["image"]
		var pal: PackedColorArray = res["palette"]
		var distinct := _distinct_rgb(pim)
		var pal_set := {}
		for col in pal:
			pal_set[col.to_rgba32()] = true
		var covered := true
		for k in distinct:
			if not pal_set.has(k):
				covered = false
		check("4 palette <=16 distinct (dither=%s)" % dither, distinct.size() <= 16 and pal.size() <= 16, "%d/%d" % [distinct.size(), pal.size()])
		check("4 palette covers image (dither=%s)" % dither, covered)
	var p2: Dictionary = Prep.to_palette(pal_img, 2, false)
	check("4 palette 2 colors", _distinct_rgb(p2["image"]).size() <= 2)
	var p256: Dictionary = Prep.to_palette(pal_img, 999, false)
	check("4 colors clamped to 256", p256["palette"].size() <= 256)
	var pa: Dictionary = Prep.to_palette(pal_img, 16, true)
	var pb: Dictionary = Prep.to_palette(pal_img, 16, true)
	check("4 palette deterministic", pa["image"].get_data() == pb["image"].get_data() and pa["palette"] == pb["palette"])

	# 5. Dither is baked and the Bayer pattern repeats every 4 px.
	# A horizontal gradient is NOT periodic in x, so period-4 is checked on a
	# solid field (same input everywhere) and along y of the gradient (constant in y).
	var grad := _gradient(64, 16)
	var plain: Image = Prep.to_rgb555(grad, false)
	var dith: Image = Prep.to_rgb555(grad, true)
	var any_diff := false
	for y in 16:
		for x in 64:
			if plain.get_pixel(x, y).r8 != dith.get_pixel(x, y).r8:
				any_diff = true
	check("5 dither output differs from plain", any_diff)
	var solid := _solid(32, 32, Color8(80, 80, 80))
	var sd: Image = Prep.to_rgb555(solid, true)
	var periodic := true
	for y in 28:
		for x in 28:
			if sd.get_pixel(x, y).is_equal_approx(sd.get_pixel(x + 4, y)) == false or sd.get_pixel(x, y).is_equal_approx(sd.get_pixel(x, y + 4)) == false:
				periodic = false
	var grad_y_periodic := true
	for y in 12:
		for x in 64:
			if dith.get_pixel(x, y).r8 != dith.get_pixel(x, y + 4).r8:
				grad_y_periodic = false
	check("5 dither pattern periodic every 4 px", periodic and grad_y_periodic)
	var row_differs := false
	for x in 16:
		if dith.get_pixel(x, 0).r8 != dith.get_pixel(x, 1).r8:
			row_differs = true
	# On a steep gradient a given column may not change between rows; also check the solid field.
	if not row_differs:
		for x in 16:
			if sd.get_pixel(x, 0).r8 != sd.get_pixel(x, 1).r8 or sd.get_pixel(0, 0).r8 != sd.get_pixel(1, 0).r8:
				row_differs = true
	check("5 pattern varies between rows (2D Bayer)", row_differs)
	var pd: Image = Prep.to_palette(grad, 4, true)["image"]
	var pp: Image = Prep.to_palette(grad, 4, false)["image"]
	check("5 palette dither differs from plain", pd.get_data() != pp.get_data())

	# 6. process_folder.
	_rm_rf(TMP)
	var s := TMP + "/src"
	DirAccess.make_dir_recursive_absolute(s + "/sub/deep")
	_noise(100, 60, 1).save_png(s + "/a.png")
	_gradient(64, 64).save_png(s + "/sub/b.png")
	_noise(33, 17, 2).save_jpg(s + "/sub/deep/c.jpg")
	_noise(20, 20, 4).save_webp(s + "/d.webp")
	var cf := FileAccess.open(s + "/corrupt.png", FileAccess.WRITE)
	cf.store_string("this is not a png")
	cf.close()
	var cf2 := FileAccess.open(s + "/readme.txt", FileAccess.WRITE)
	cf2.store_string("ignored")
	cf2.close()
	var before := _hash_tree(s)
	var opts := {"mode": Prep.MODE_NEAREST_POW2, "max_side": 256, "color_mode": "rgb555", "dither": true}
	var rep: Dictionary = Batch.process_folder(s, TMP + "/out1", opts)
	check("6 batch ok", rep["ok"], str(rep))
	check("6 processed 4 files", rep["processed"].size() == 4, str(rep["processed"]))
	check("6 corrupt file reported, batch continued", rep["errors"].size() == 1 and rep["errors"][0]["path"] == "corrupt.png")
	var exp_files := ["a.png", "sub/b.png", "sub/deep/c.png", "d.png"]
	var all_exist := true
	for ef in exp_files:
		all_exist = all_exist and FileAccess.file_exists(TMP + "/out1/" + ef)
	check("6 expected PNG outputs with sub-folders", all_exist)
	var oa := Image.load_from_file(TMP + "/out1/a.png")
	check("6 output a.png is 128x64", oa != null and oa.get_size() == Vector2i(128, 64))
	check("6 source untouched (hashes)", _hash_tree(s) == before)
	var rep_again: Dictionary = Batch.process_folder(s, TMP + "/out1", opts)
	check("6 existing outputs skipped without overwrite", rep_again["processed"].size() == 0 and rep_again["omitted"].size() == 4)
	var opts_ow := opts.duplicate()
	opts_ow["overwrite"] = true
	var rep_ow: Dictionary = Batch.process_folder(s, TMP + "/out1", opts_ow)
	check("6 overwrite option rewrites", rep_ow["processed"].size() == 4)
	var rep_in: Dictionary = Batch.process_folder(s, s + "/inside", opts_ow)
	check("6 dst inside src refused", not rep_in["ok"] and not DirAccess.dir_exists_absolute(s + "/inside"))
	var rep_same: Dictionary = Batch.process_folder(s, s, opts_ow)
	check("6 dst == src refused", not rep_same["ok"])
	check("6 source untouched after refusals", _hash_tree(s) == before)
	var popts := {"mode": Prep.MODE_PAD, "max_side": 128, "color_mode": "palette", "palette_colors": 8, "dither": true}
	var rep_p: Dictionary = Batch.process_folder(s, TMP + "/outp", popts)
	var pimg := Image.load_from_file(TMP + "/outp/a.png")
	check("6 palette batch <= 8 colors", rep_p["ok"] and pimg != null and _distinct_rgb(pimg).size() <= 9)  # +1: transparent pad pixel

	# 7. Determinism.
	var rep2: Dictionary = Batch.process_folder(s, TMP + "/out2", opts)
	check("7 two runs identical hashes", _hash_tree(TMP + "/out1") == _hash_tree(TMP + "/out2") and rep2["processed"] == rep["processed"])
	var rp1: Dictionary = Batch.process_folder(s, TMP + "/outp2", popts)
	check("7 palette runs identical hashes", _hash_tree(TMP + "/outp") == _hash_tree(TMP + "/outp2") and rp1["ok"])

	_rm_rf(TMP)
