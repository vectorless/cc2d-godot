extends Node2D
## Renders every part of the custom packs (res://custom/*/parts.json) on a character, next to
## the template part it was drawn on, standing (Idle) and mid-stride (Walk), so generated parts
## can be checked for fit. Writes tests/shots/custom/<package>_<part>.png and custom_all.png.
## Run:  godot --path . --fixed-fps 60 res://tests/custom_preview.tscn

const SLOT_OF := {"Weapon": "MainHand"}


func _ready() -> void:
	var shots := ProjectSettings.globalize_path("res://tests/shots/")
	DirAccess.make_dir_recursive_absolute(shots + "custom")
	for d in DirAccess.get_directories_at("res://custom"):
		var n := CC2DCharacter.add_part_pack("res://custom/%s/parts.json" % d)
		print("pack %s: %d parts" % [d, n])
	var ch := CC2DCharacter.new()
	ch.character_file = "res://characters/exa/character.json"
	ch.autoplay = false
	add_child(ch)
	await get_tree().process_frame
	# plain base outfit so the new part stands out
	for s in ["Helmet", "Cape", "Skirt", "MainHand", "OffHand"]:
		ch.equip_part(s, "")
	var ex := CC2DExporter.new()
	add_child(ex)
	ex.apply_preset("default")
	ex.background = CC2DExporter.Background.GRAY
	ex.width = 384
	ex.height = 384
	ex.char_position = Vector2(0, -1.0)
	ex.char_scale = 1.25
	var rows: Array[Image] = []
	for d in DirAccess.get_directories_at("res://custom"):
		var pack: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://custom/%s/parts.json" % d))
		for category in pack.categories:
			for p in pack.categories[category]:
				var slot: String = SLOT_OF.get(category, category)
				ch.set_body_type(p.body[0])
				var row := Image.create(384 * 4, 384, false, Image.FORMAT_RGBA8)
				var col := 0
				for which in [p.get("template", ""), p.name]:
					if which == "":
						col += 2
						continue
					var pkg: String = p.package if which == p.name else ""
					ch.equip_part(slot, which, pkg)
					if which == p.name and p.has("colors"):
						var c: Array = p.colors
						ch.set_part_color(slot, Color(c[0][0], c[0][1], c[0][2]), Color(c[1][0], c[1][1], c[1][2]), Color(c[2][0], c[2][1], c[2][2]))
					for anim in [["Idle", 0.0], ["Walk", 0.27]]:
						var img := await ex.render_image(ch, anim[0], anim[1])
						row.blit_rect(img, Rect2i(0, 0, 384, 384), Vector2i(col * 384, 0))
						col += 1
				row.save_png(shots + "custom/%s_%s.png" % [d, String(p.name).to_snake_case()])
				rows.append(row)
				print("  %s / %s (template %s)" % [p.package, p.name, p.get("template", "-")])
	if not rows.is_empty():
		var all := Image.create(384 * 4, 384 * rows.size(), false, Image.FORMAT_RGBA8)
		for i in rows.size():
			all.blit_rect(rows[i], Rect2i(0, 0, 384 * 4, 384), Vector2i(0, i * 384))
		all.save_png(shots + "custom_all.png")
	get_tree().quit()
