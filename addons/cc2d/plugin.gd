@tool
extends EditorPlugin
## Editor side of the CC2D runtime. CC2DCharacter and CC2DExporter are global classes already
## (Create Node > CC2DCharacter); what this adds is an export plugin, because CC2D's data is
## JSON (rigs, animations, part catalogue, characters, export presets) and Godot leaves
## non-resource files out of exported games.

const DATA_DIRS := ["res://cc2d", "res://characters", "res://addons/cc2d", "res://custom"]

var _export: EditorExportPlugin


func _enter_tree() -> void:
	_export = CC2DExportData.new()
	add_export_plugin(_export)


func _exit_tree() -> void:
	remove_export_plugin(_export)
	_export = null


class CC2DExportData:
	extends EditorExportPlugin

	func _get_name() -> String:
		return "CC2D data"

	func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
		var n := 0
		for dir in DATA_DIRS:
			n += _add_json(dir)
		print("CC2D: added %d JSON files to the export" % n)

	func _add_json(dir: String) -> int:
		var n := 0
		if not DirAccess.dir_exists_absolute(dir):
			return 0
		for f in DirAccess.get_files_at(dir):
			if f.get_extension() == "json":
				var path := dir.path_join(f)
				add_file(path, FileAccess.get_file_as_bytes(path), false)
				n += 1
		for d in DirAccess.get_directories_at(dir):
			if not d.begins_with("."):
				n += _add_json(dir.path_join(d))
		return n
