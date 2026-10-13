extends Node
## Drives the character creator's UI with simulated clicks and saves screenshots of its main
## states to tests/shots/creator_ui/. Run (needs a display, not --headless):
##   godot --path . --fixed-fps 60 res://tests/creator_ui_test.tscn

const Creator := preload("res://creator/creator.gd")

var failures: Array[String] = []
var creator: Node2D
var out := ""


func check(cond: bool, what: String) -> void:
	print("  ", "ok   " if cond else "FAIL ", what)
	if not cond:
		failures.append(what)


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func settle() -> void:
	await frames(2)
	while creator.is_busy():
		await get_tree().process_frame
	await frames(3)


func shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + file_name)
	print("   shot ", file_name)


func tile_for(pred: Callable) -> Dictionary:
	for t in creator._tiles:
		if not t.part.is_empty() and pred.call(t.part):
			return t
	return {}


func _ready() -> void:
	creator = load("res://creator/creator.tscn").instantiate()
	add_child(creator)
	out = ProjectSettings.globalize_path("res://tests/shots/creator_ui/")
	DirAccess.make_dir_recursive_absolute(out)
	await settle()
	var ch: CC2DCharacter = creator.character

	print("== start: Equipment > Armor")
	check(creator.menu == "equipment" and creator.cat == "armor", "opens on Equipment > Armor")
	check(creator._tiles.size() > 20, "armor grid has %d tiles" % creator._tiles.size())
	var lit: Array = creator._tiles.filter(func(t): return t.button.button_pressed)
	check(lit.size() == 1 and not lit[0].part.is_empty() and lit[0].part.name == ch.get_equipped("Armor"), "the equipped armor is highlighted")
	var with_thumbs: Array = creator._tiles.filter(func(t): return t.rect.texture != null)
	check(with_thumbs.size() == creator._tiles.size(), "every tile has a thumbnail (%d/%d)" % [with_thumbs.size(), creator._tiles.size()])
	await shot("01_equipment_armor.png")

	print("== every part category")
	for m in Creator.MENUS:
		for c in m.cats:
			if Creator.CATS[c].kind != "parts":
				continue
			creator.open_category(c)
			await frames(1)
			var n: int = creator._tiles.size() - 1
			var want: int = creator._cat_parts(c, c != "body").size()   # other body type's parts are listed too (dimmed)
			check(n == want and n > 0, "%s > %s: %d parts" % [m.title, Creator.CATS[c].title, n])
			creator._thumb_queue.clear()

	creator._last_cat = {"equipment": "armor"}
	print("== picking parts")
	creator.open_menu("equipment")
	creator.open_category("armor")
	await settle()
	var before: Array = ch.get_part_colors("Armor")
	var t := tile_for(func(p): return p.package == "Fantasy" and p.name != ch.get_equipped("Armor"))
	t.button.pressed.emit()
	await frames(2)
	check(ch.get_equipped("Armor") == t.part.name and ch.get_equipped_package("Armor") == "Fantasy", "click a tile: %s equipped" % t.part.name)
	check(ch.get_part_colors("Armor") == before, "CC2D parts keep the slot's colours")
	check(t.button.button_pressed, "clicked tile is highlighted")

	# a custom pack part with designed colours (any category)
	var custom_cat := ""
	var custom_tile := {}
	for c in ["armor", "pants", "boots", "skirt", "helmet", "gloves", "cape", "hair", "main_hand"]:
		creator.open_category(c)
		await frames(1)
		custom_tile = tile_for(func(p): return p.has("colors") and p.package in creator.custom_packages)
		if not custom_tile.is_empty():
			custom_cat = c
			break
	check(not creator.custom_packages.is_empty(), "custom packs loaded: %s" % ", ".join(creator.custom_packages))
	if not custom_tile.is_empty():
		await settle()
		var cs: String = creator.slot
		custom_tile.button.pressed.emit()
		await frames(2)
		var want: Array = creator._designed_colors(custom_tile.part)
		var got: Array = ch.get_part_colors(cs)
		check(ch.get_equipped(cs) == custom_tile.part.name and ch.get_equipped_package(cs) == custom_tile.part.package,
			"custom part %s (%s) equipped" % [custom_tile.part.name, custom_tile.part.package])
		check(got[0].is_equal_approx(want[0]) and got[1].is_equal_approx(want[1]) and got[2].is_equal_approx(want[2]), "its designed colours applied")
		check(creator._btn_pack_colors.visible, "'Pack colours' button offered")
		creator._parts_scroll.ensure_control_visible(custom_tile.button)
		await settle()
		await shot("02_custom_part.png")

	print("== colour picker + palette")
	creator.open_category("armor")
	await settle()
	creator._swatches[1].pressed.emit()
	await frames(2)
	check(creator._color_index == 1 and creator._picker.visible, "second colour slot opens the picker")
	var pal_btn: Button = creator._palette_flow.get_child(3)
	pal_btn.pressed.emit()
	await frames(2)
	check(ch.get_part_colors("Armor")[1].is_equal_approx(Color(creator._palettes[0].colors[3], 1.0)), "palette swatch recolours colour 2")
	creator._palette_option.select(7)
	creator._palette_option.item_selected.emit(7)
	await frames(2)
	creator._palette_flow.get_child(5).pressed.emit()
	await settle()
	await shot("03_color_picker.png")
	creator._search_edit.text = "07"
	creator._search_edit.text_changed.emit("07")
	await frames(2)
	var shown: Array = creator._tiles.filter(func(tt): return not tt.part.is_empty() and tt.button.visible)
	check(shown.size() > 0 and shown.all(func(tt): return "07" in tt.part.name), "search '07' shows %d parts" % shown.size())
	creator._search_edit.text = ""
	creator._search_edit.text_changed.emit("")
	# a part made only for the other body type is listed dimmed; picking it switches the body
	var other: Array = creator._tiles.filter(func(tt): return not tt.part.is_empty() and not (ch.body_type in tt.part.body))
	check(other.size() > 0 and other[0].button.modulate.a < 1.0, "other body type's parts are listed dimmed (%d)" % other.size())
	if other.size() > 0:
		var op: Dictionary = other[0].part
		var was := ch.body_type
		other[0].button.pressed.emit()
		await settle()
		check(ch.body_type != was and ch.get_equipped(other[0].slot) == op.name, "picking %s switches to %s body and wears it" % [op.name, ch.body_type])
		creator._set_body_type(was)
		await settle()

	print("== body menu")
	creator._menu_buttons.body.button.pressed.emit()
	await settle()
	check(creator.cat == "body" and creator._cmode == "body", "Body menu opens Body with skin + tint colours")
	creator._body_buttons.Female.pressed.emit()
	await settle()
	check(ch.body_type == "Female", "Female button switches body")
	await shot("04_body.png")
	creator._body_buttons.Male.pressed.emit()
	await settle()
	creator._rail_rows.sliders.button.pressed.emit()
	await frames(2)
	creator._slider_rows.UpperLeg[1][0].value = 0.9
	creator._slider_rows.Body[0][0].value = 0.8
	await frames(2)
	check(ch.get_body_slider("UpperLeg").y > 0.89 and ch.get_body_slider("Body").x > 0.79, "body sliders drive the character")
	await shot("05_body_sliders.png")
	creator._slider_rows.UpperLeg[1][0].value = 0.5
	creator._slider_rows.Body[0][0].value = 0.5

	print("== face menu")
	creator._menu_buttons.face.button.pressed.emit()
	await settle()
	check(creator.cat == "hair" and creator._cmode == "part", "Face menu opens Hair")
	var hair := tile_for(func(p): return p.package == "Daily")
	if not hair.is_empty():
		hair.button.pressed.emit()
	await settle()
	await shot("06_face_hair.png")
	creator._rail_rows.emotion.button.pressed.emit()
	await frames(2)
	var grid: GridContainer = creator._emotion_box.get_child(0)
	for b in grid.get_children():
		if b.text == "Hurt":
			b.pressed.emit()
	await frames(3)
	check(ch.current_emote == "Hurt", "emotion button previews Hurt")
	creator._set_zoom(2.6)
	await frames(3)
	await shot("07_emotion.png")
	creator._set_zoom(1.0)
	creator._rail_rows.hair.button.pressed.emit()
	await frames(2)
	check(ch.current_emote == "", "leaving Emotion resets the face")

	print("== weapons and guns")
	creator._menu_buttons.gun.button.pressed.emit()
	await settle()
	var gun := tile_for(func(p): return p.get("weapon", "") == "Gun")
	gun.button.pressed.emit()
	await frames(2)
	check(ch.get_equipped("MainHand") == gun.part.name, "gun equipped in the main hand")
	creator._play_aim("Shot Main Hand")
	await frames(10)
	check(ch.aim_state == "Shot Main Hand" and creator._aim_slider.visible, "aim layer selector + angle slider")
	await shot("08_gun_aim.png")
	creator._play_aim("None")
	creator._menu_buttons.weapon.button.pressed.emit()
	await frames(2)
	creator._rail_rows.bow.button.pressed.emit()
	await frames(2)
	var bow := tile_for(func(p): return p.get("weapon", "") == "Bow")
	bow.button.pressed.emit()
	await frames(2)
	check(ch.get_equipped("OffHand") == bow.part.name and ch.get_equipped("MainHand") == "", "bow is two-handed: main hand emptied")

	print("== randomize")
	creator._menu_buttons.body.button.pressed.emit()
	await frames(2)
	creator._rail_rows.randomize.button.pressed.emit()
	await frames(2)
	seed(7)
	creator.randomize_character()
	await settle()
	await shot("09_randomize.png")

	print("== file > export")
	creator._menu_buttons.file.button.pressed.emit()
	await frames(2)
	check(creator.cat == "export" and creator._pages.export.visible, "File menu shows Export PNG")
	await creator._render_preview()
	await frames(2)
	check(creator._export_preview.texture != null, "export preview rendered")
	var esc: ScrollContainer = creator._pages.export.get_child(0)
	esc.scroll_vertical = 10000
	await frames(3)
	await shot("10_export.png")

	print("== wider window (1800x840)")
	get_window().size = Vector2i(1800, 840)
	creator.open_menu("equipment")
	await settle()
	await frames(5)
	await shot("11_window_1800x840.png")

	print("== RESULT: %s" % ("PASS" if failures.is_empty() else "FAIL " + str(failures)))
	get_tree().quit(0 if failures.is_empty() else 1)
