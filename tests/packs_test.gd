extends Node2D
## Every part in the catalogue (all packs, both bodies), and the pack outfits compared with
## Unity. Run:  godot --path . --fixed-fps 60 res://tests/packs_test.tscn
## characters/packs/*.json are CharacterData files saved in Unity (one outfit per pack and body);
## tests/shots/packs/<id>_unity.png are Unity's renders of them (Idle, frame 0, 512 px, default
## export camera). This renders the same in Godot and writes <id>_compare.png side by side.

var failures: Array[String] = []


func check(cond: bool, what: String) -> void:
	print("  ", "ok   " if cond else "FAIL ", what)
	if not cond:
		failures.append(what)


## Every texture the character is drawing right now.
func _textures(ch: CC2DCharacter) -> Dictionary:
	var out := {}
	for spr in ch.sprites.values():
		if spr.texture != null and spr.visible:
			out[spr.texture.resource_path] = true
	for poly in ch.cloth.values():
		if poly.texture != null and poly.visible:
			out[poly.texture.resource_path] = true
	for m in ch.materials.values():
		var d = m.get_shader_parameter("details")
		if d != null:
			out[d.resource_path] = true
	return out


func _ready() -> void:
	var shots := ProjectSettings.globalize_path("res://tests/shots/")
	DirAccess.make_dir_recursive_absolute(shots + "packs")
	if not FileAccess.file_exists(shots + ".gdignore"):
		FileAccess.open(shots + ".gdignore", FileAccess.WRITE)

	var ch := CC2DCharacter.new()
	ch.character_file = "res://characters/exa/character.json"
	add_child(ch)
	await get_tree().process_frame

	print("== every part, both bodies")
	var packages := {}
	for body in CC2DCharacter.BODY_TYPES:
		ch.set_body_type(body)
		var tried := 0
		var bad: Array[String] = []
		for slot in CC2DCharacter.SLOTS:
			for p in ch.get_parts(slot):
				packages[p.package] = true
				tried += 1
				if not ch.equip_part(slot, p.name, p.package):
					bad.append("%s %s/%s (equip)" % [slot, p.package, p.name])
					continue
				if ch.slots[slot].part != p:
					bad.append("%s %s/%s (wrong part)" % [slot, p.package, p.name])
				elif p.texture != null and not _textures(ch).has(p.texture) and slot not in ["Ear", "Nose"]:
					bad.append("%s %s/%s (texture not drawn)" % [slot, p.package, p.name])
		check(bad.is_empty(), "%s: %d parts equip and draw%s" % [body, tried, "" if bad.is_empty() else ": " + ", ".join(bad.slice(0, 8))])
	check(packages.has("Daily") and packages.has("Post Apocalyptic") and packages.has("Undead"), "the new packs are in the catalogue (%s)" % ", ".join(packages.keys()))
	ch.queue_free()

	print("== pack outfits vs Unity")
	var ex := CC2DExporter.new()
	add_child(ex)
	ex.apply_preset("default")
	ex.background = CC2DExporter.Background.GRAY
	ex.super_sampling = 1
	var src := CC2DCharacter.new()
	src.character_file = "res://characters/exa/character.json"
	src.autoplay = false
	add_child(src)
	await get_tree().process_frame
	var files := DirAccess.get_files_at("res://characters/packs")
	var sheet := Image.create(1024 * 3, 512 * int(ceil(files.size() / 3.0)), false, Image.FORMAT_RGBA8)
	var n := 0
	for f in files:
		if f.get_extension() != "json":
			continue
		var id := f.get_basename()
		check(src.load_character_data("res://characters/packs/" + f) == OK, "%s loads" % id)
		var img := await ex.render_image(src, "Idle", 0.0)
		img.save_png(shots + "packs/%s_godot.png" % id)
		var ref := Image.load_from_file(shots + "packs/%s_unity.png" % id)
		if ref == null:
			print("  (no Unity render for %s)" % id)
			continue
		ref.convert(Image.FORMAT_RGBA8)
		# mean absolute difference over the character's area
		var diff := 0.0
		var count := 0
		for y in range(0, 512, 2):
			for x in range(0, 512, 2):
				var a := img.get_pixel(x, y)
				var b := ref.get_pixel(x, y)
				if absf(a.r - 0.5) + absf(a.g - 0.5) + absf(a.b - 0.5) > 0.03 or absf(b.r - 0.5) + absf(b.g - 0.5) + absf(b.b - 0.5) > 0.03:
					diff += (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) / 3.0
					count += 1
		var score := diff / maxf(count, 1.0)
		check(score < 0.06, "%s matches Unity (mean diff %.3f over %d px)" % [id, score, count])
		var pair := Image.create(1024, 512, false, Image.FORMAT_RGBA8)
		pair.blit_rect(ref, Rect2i(0, 0, 512, 512), Vector2i.ZERO)
		pair.blit_rect(img, Rect2i(0, 0, 512, 512), Vector2i(512, 0))
		pair.save_png(shots + "packs/%s_compare.png" % id)
		sheet.blit_rect(pair, Rect2i(0, 0, 1024, 512), Vector2i((n % 3) * 1024, (n / 3) * 512))
		n += 1
	sheet.save_png(shots + "packs/all_compare.png")

	print("== a pack outfit in motion (cape + skirt cloth)")
	src.load_character_data("res://characters/packs/post_apocalyptic_female_0.json")
	ex.width = 256
	ex.height = 256
	ex.target_fps = 8
	var walk := await ex.export_sheet(src, shots + "packs/pa_female_walk.png", "Walk")
	check(walk.get_width() > 0, "walk sheet rendered (%dx%d)" % [walk.get_width(), walk.get_height()])

	print("== RESULT: %s" % ("PASS" if failures.is_empty() else "FAIL " + str(failures)))
	get_tree().quit(0 if failures.is_empty() else 1)
