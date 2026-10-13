extends Node
## The creator scene's Export PNG panel. Run:  godot --path . res://tests/creator_test.tscn

var failures: Array[String] = []


func check(cond: bool, what: String) -> void:
	print("  ", "ok   " if cond else "FAIL ", what)
	if not cond:
		failures.append(what)


func _ready() -> void:
	var creator: Node2D = load("res://creator/creator.tscn").instantiate()
	add_child(creator)
	for i in 5:
		await get_tree().process_frame
	var out := ProjectSettings.globalize_path("res://tests/shots/")
	DirAccess.make_dir_recursive_absolute(out + "creator")
	print("== the export panel")
	check(creator._export_preset.item_count == 1 + CC2DExporter.get_presets().size(), "preset list: Custom + %d" % CC2DExporter.get_presets().size())
	creator._export_preset.select(3)
	creator._export_preset.item_selected.emit(3)
	var pr: String = CC2DExporter.get_presets()[2]
	check(creator._export_fields.width.value == creator._exporter.width, "preset '%s' shown in the fields (%dx%d)" % [pr, creator._exporter.width, creator._exporter.height])
	creator._export_fields.width.value = 300
	check(creator._exporter.width == 300 and creator._export_preset.selected == 0, "editing a field: preset goes to Custom")
	creator._export_fields.height.value = 300
	creator.character.play("Run")
	creator._export_mode.select(2)
	await creator._export_to(out + "creator/run_sheet.png")
	check(FileAccess.file_exists(out + "creator/run_sheet.png") and FileAccess.file_exists(out + "creator/run_sheet.json"), "sprite sheet from the panel")
	creator._export_mode.select(1)
	await creator._export_to(out + "creator/run.png")
	check(FileAccess.file_exists(out + "creator/run_000.png"), "PNG sequence from the panel")
	creator._export_mode.select(0)
	await creator._export_to(out + "creator/single.png")
	check(FileAccess.file_exists(out + "creator/single.png"), "single image from the panel")
	print("   status: ", creator._status.text)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "creator_ui.png")
	print("== RESULT: %s" % ("PASS" if failures.is_empty() else "FAIL " + str(failures)))
	get_tree().quit(0 if failures.is_empty() else 1)
