extends Node2D
## Muzzle flash / export checks. Run:  godot --path . res://tests/fx_test.tscn
## Screenshots go to tests/shots/ (not committed).

var ch: CC2DCharacter
var cam: Camera2D
var failures: Array[String] = []


func check(cond: bool, what: String) -> void:
	print("  ", "ok   " if cond else "FAIL ", what)
	if not cond:
		failures.append(what)


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img:
		_shots_dir()
		img.save_png(ProjectSettings.globalize_path("res://tests/shots/%s.png" % file))


## tests/shots/, kept out of the import (.gdignore).
static func _shots_dir() -> String:
	var dir := ProjectSettings.globalize_path("res://tests/shots/")
	DirAccess.make_dir_recursive_absolute(dir)
	if not FileAccess.file_exists(dir + ".gdignore"):
		FileAccess.open(dir + ".gdignore", FileAccess.WRITE)
	return dir


func muzzle(slot: String) -> Node2D:
	return ch.parts[CC2DCharacter.MUZZLE_LINKS[slot]]


func fx(slot: String) -> CPUParticles2D:
	return muzzle(slot).get_node("_particles/_fx")


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.2, 0.2, 0.25))
	ch = CC2DCharacter.new()
	ch.character_file = "res://characters/exa/character.json"
	add_child(ch)
	cam = Camera2D.new()
	add_child(cam)
	cam.make_current()
	await frames(3)

	print("== muzzle flash nodes")
	check(fx("MainHand") != null and fx("OffHand") != null, "both hands have a muzzle flash emitter")
	check(not muzzle("MainHand").visible, "hidden until a Shot clip turns it on")

	print("== Gun 00 in the main hand")
	ch.equip_part("OffHand", "")
	check(ch.equip_part("MainHand", "Gun 00"), "equipped Gun 00")
	check(muzzle("MainHand").position.is_equal_approx(Vector2(76, 218)), "muzzle moved to the gun's muzzlePosition (%s)" % muzzle("MainHand").position)
	ch.equip_part("MainHand", "Rifle 01")
	check(muzzle("MainHand").position.is_equal_approx(Vector2(63, 540)), "...and to the rifle's")
	ch.equip_part("MainHand", "")
	check(muzzle("MainHand").position == Vector2.ZERO, "no weapon: back to zero, as in HumanoidAssigner")
	ch.equip_part("MainHand", "Gun 00")

	print("== Shot Main Hand fires it")
	ch.play("Idle")
	ch.play_aim("Shot Main Hand")
	ch.set_aim(0.0)
	var fired := false
	for i in 30:
		await get_tree().process_frame
		if muzzle("MainHand").is_visible_in_tree() and fx("MainHand").emitting:
			fired = true
			break
	check(fired, "Shot Main Hand shows the muzzle and starts the burst")
	cam.global_position = muzzle("MainHand").global_position + Vector2(-150, 0)
	cam.zoom = Vector2(0.75, 0.75)
	await frames(1)
	await shot("muzzle_gun00")
	# A second shot as the clip loops
	var restarts := 0
	var was := true
	for i in 90:
		await get_tree().process_frame
		var on := muzzle("MainHand").is_visible_in_tree()
		if on and not was:
			restarts += 1
		was = on
	check(restarts >= 3, "the looping clip fires again every cycle (%d shots in 1.5 s)" % restarts)
	ch.play_aim("")
	await frames(2)
	check(not muzzle("MainHand").visible, "stopping the aim layer puts the flash out")

	print("== Rapid Shot Both Hand, two guns")
	ch.equip_part("OffHand", "Gun 01")
	ch.play_aim("Rapid Shot Both Hand")
	var both := false
	for i in 30:
		await get_tree().process_frame
		if muzzle("MainHand").is_visible_in_tree() and muzzle("OffHand").is_visible_in_tree():
			both = true
			break
	check(both, "both muzzles flash")
	cam.global_position = (muzzle("MainHand").global_position + muzzle("OffHand").global_position) * 0.5
	cam.zoom = Vector2(0.5, 0.5)
	await frames(1)
	await shot("muzzle_both")
	ch.play_aim("")

	print("== PNG export")
	var ex := CC2DExporter.new()
	add_child(ex)
	var out := _shots_dir()
	check(CC2DExporter.get_presets().has("fullbody"), "CC2D's presets are there (%s)" % ", ".join(CC2DExporter.get_presets()))
	check(ex.apply_preset("default") == OK and ex.width == 512 and ex.scale_mode == CC2DExporter.ScaleMode.AUTOMATIC, "Default preset: 512x512, automatic")
	ch.play("Idle")
	check(await ex.export_image(ch, out + "export_default.png") == OK, "single image written")
	var img := Image.load_from_file(out + "export_default.png")
	check(img != null and img.get_size() == Vector2i(512, 512), "512x512")
	check(img.get_pixel(5, 5).a == 0.0, "transparent background")
	var opaque := 0
	for y in range(0, 512, 8):
		for x in range(0, 512, 8):
			if img.get_pixel(x, y).a > 0.9:
				opaque += 1
	check(opaque > 150, "the character is in the picture (%d opaque samples)" % opaque)
	check(ex.apply_preset("portrait") == OK and ex.height == 400, "Portrait preset")
	await ex.export_image(ch, out + "export_portrait.png")
	ex.apply_preset("animation")
	ex.background = CC2DExporter.Background.GRAY
	check(ex.frame_count(ch, "Walk") == int(ch.get_animation_length("Walk") * 10), "Walk at 10 fps: %d frames" % ex.frame_count(ch, "Walk"))
	var files := await ex.export_sequence(ch, out + "seq/walk.png", "Walk") if DirAccess.make_dir_recursive_absolute(out + "seq") == OK else PackedStringArray()
	check(files.size() == ex.frame_count(ch, "Walk") and files[0].ends_with("walk_000.png"), "PNG sequence: %d files" % files.size())
	var f0 := Image.load_from_file(files[0])
	var f5 := Image.load_from_file(files[5])
	check(f0.get_data() != f5.get_data(), "frames differ (he's walking)")
	check(absf(f0.get_pixel(3, 3).r - 0.5) < 0.01 and f0.get_pixel(3, 3).a == 1.0, "gray background (%s)" % f0.get_pixel(3, 3))
	ex.apply_preset("default")
	ex.width = 256
	ex.height = 256
	ex.target_fps = 12
	ex.char_position = Vector2(-2, 0)
	var n := ex.frame_count(ch, "Idle", "Shot Main Hand")
	var sheet := await ex.export_sheet(ch, out + "sheet_shot.png", "Idle", "Shot Main Hand")
	var cols := int(ceil(sqrt(float(n))))
	check(sheet.get_width() == 256 * cols and FileAccess.file_exists(out + "sheet_shot.json"), "sprite sheet %dx%d, %d frames + json" % [sheet.get_width(), sheet.get_height(), n])
	check(ch.current_animation == "Idle" and not ch._posed, "the character on screen wasn't touched")

	print("== RESULT: %s" % ("PASS" if failures.is_empty() else "FAIL " + str(failures)))
	get_tree().quit(0 if failures.is_empty() else 1)
