extends Node2D
## Smoke clip test: both bodies x cigarette / cigar / pipe, frames at rest, raising, at the lips, exhaling.
## Run:  godot --path . --fixed-fps 60 res://tests/smoke_test.tscn   (writes tests/shots/smoke_test.png)
const TIMES := [0.2, 0.95, 2.0, 3.8]
var fails := []
func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok: fails.append(msg)
func _ready() -> void:
	CC2DCharacter.add_part_pack("res://custom/smoking/parts.json")
	var vp := SubViewport.new()
	vp.size = Vector2i(360, 360)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var ch := CC2DCharacter.new()
	ch.character_file = "res://characters/exa/character.json"
	ch.autoplay = false
	vp.add_child(ch)
	var cam := Camera2D.new()
	cam.zoom = Vector2(0.75, 0.75)
	vp.add_child(cam)
	await get_tree().process_frame
	var items := ["Cigarette", "Cigar", "Tobacco Pipe"]
	var sheet := Image.create(360 * TIMES.size(), 360 * 6, false, Image.FORMAT_RGBA8)
	var row := 0
	for bt in ["Male", "Female"]:
		ch.set_body_type(bt)
		check("Smoke" in ch.get_animation_names(), "%s: Smoke clip listed" % bt)
		for w in items:
			ch.equip_part("MainHand", w, "Smoking")
			cam.position = Vector2(30, -930) if bt == "Male" else Vector2(25, -880)
			ch.play("Smoke", 0.0)
			ch.animation_player.seek(0.0, true)
			var col := 0
			for t in TIMES:
				while ch.animation_player.current_animation_position < t:
					await get_tree().process_frame
				await RenderingServer.frame_post_draw
				sheet.blit_rect(vp.get_texture().get_image(), Rect2i(0, 0, 360, 360), Vector2i(col * 360, row * 360))
				if is_equal_approx(t, 3.8):
					check(ch._smoke.has("puff") and ch._smoke.puff.emitting, "%s %s: puffing during the exhale" % [bt, w])
				col += 1
			check(ch._smoke.has("wisp") and ch._smoke.wisp.emitting, "%s %s: wisp from the ember" % [bt, w])
			row += 1
	# an exported frame (CC2DExporter poses a copy of the character) shows the exhale puff
	var ex := CC2DExporter.new()
	add_child(ex)
	ex.apply_preset("default")
	ex.width = 512
	ex.height = 640
	ex.char_position = Vector2(0, -1.0)
	ex.char_scale = 1.15
	ch.equip_part("MainHand", "Cigarette", "Smoking")
	var with_smoke := await ex.render_image(ch, "Smoke", 3.8)
	ch.equip_part("MainHand", "")
	var without := await ex.render_image(ch, "Smoke", 3.8)
	var diff := 0
	for y in range(0, 280):
		for x in range(200, 512):
			var a := with_smoke.get_pixel(x, y)
			var b := without.get_pixel(x, y)
			if absf(a.a - b.a) + absf(a.r - b.r) > 0.15:
				diff += 1
	check(diff > 40, "exported frame shows smoke (%d pixels differ near the head)" % diff)
	ch.equip_part("MainHand", "")
	await get_tree().process_frame
	await get_tree().process_frame
	check(not ch._smoke.wisp.emitting, "no wisp without a smoking item")
	sheet.save_png(ProjectSettings.globalize_path("res://tests/shots/smoke_test.png"))
	print("== RESULT: ", "PASS" if fails.is_empty() else "FAIL " + str(fails))
	get_tree().quit()
