## Godot runtime for characters exported from Character Creator 2D (Unity).
## Builds the part hierarchy, recolouring materials and an AnimationPlayer
## from the JSON written by Assets/Editor/CC2DGodotExporter.cs.
class_name CC2DCharacter
extends Node2D

const ARMOR_SHADER := preload("res://addons/cc2d/cc2d_armor.gdshader")
const SKIN_SHADER := preload("res://addons/cc2d/cc2d_skin.gdshader")

signal character_loaded

## character.json produced by the Unity exporter.
@export_file("*.json") var character_file: String
## Play the character's default animation (Idle) once loaded.
@export var autoplay := true
## Default cross-fade time when switching animations (seconds).
@export var default_blend := 0.1

var animation_player: AnimationPlayer
var current_animation := ""
var parts := {}      ## Unity path -> Node2D (bones / part anchors)
var sprites := {}    ## Unity path -> Sprite2D
var materials := {}  ## material key (e.g. "Exa Armor") -> ShaderMaterial
var data := {}


func _ready() -> void:
	if character_file != "":
		load_character(character_file)


## (Re)builds the character from an exported character.json.
func load_character(path: String) -> void:
	_clear()
	data = _read_json(path)
	if data.is_empty():
		return
	_build_materials(data.get("materials", {}))
	_build_nodes(data.get("nodes", []))
	_build_animations(data.get("animations", ""))
	if autoplay:
		play(data.get("default_animation", "Idle"), 0.0)
	character_loaded.emit()


## Plays a Character Creator 2D animation state by name ("Idle", "Walk", "Run", "Jump", ...).
func play(anim_name: String, blend := -1.0) -> void:
	if animation_player == null or not animation_player.has_animation(anim_name):
		push_warning("CC2DCharacter: no animation '%s'" % anim_name)
		return
	if anim_name == current_animation and animation_player.is_playing():
		return
	current_animation = anim_name
	animation_player.play(anim_name, default_blend if blend < 0.0 else blend)


func get_animation_names() -> PackedStringArray:
	return animation_player.get_animation_list() if animation_player else PackedStringArray()


## Recolours an armour-type material (e.g. "Exa Armor", "Exa Boots") using its 3-colour mask.
func set_part_colors(material_key: String, color1: Color, color2: Color, color3: Color) -> void:
	var m: ShaderMaterial = materials.get(material_key)
	if m == null or m.shader != ARMOR_SHADER:
		push_warning("CC2DCharacter: '%s' is not a recolourable material" % material_key)
		return
	m.set_shader_parameter("color1", color1)
	m.set_shader_parameter("color2", color2)
	m.set_shader_parameter("color3", color3)


## Sets the skin colour on every skin-shaded sprite that uses the given base colour.
func set_skin_color(color: Color) -> void:
	for n in data.get("nodes", []):
		var s = n.get("sprite")
		if s == null:
			continue
		var mat = data.materials.get(s.get("material", ""), {})
		if mat.get("shader") == "skin" and _col(s.color).is_equal_approx(_skin_reference()):
			sprites[n.path].self_modulate = color


# ------------------------------------------------------------------ building

func _clear() -> void:
	for c in get_children():
		if c.has_meta("cc2d_generated"):
			c.queue_free()
	parts.clear()
	sprites.clear()
	materials.clear()
	animation_player = null
	current_animation = ""


func _build_materials(mats: Dictionary) -> void:
	for key in mats:
		var m: Dictionary = mats[key]
		var sm := ShaderMaterial.new()
		match m.get("shader"):
			"armor":
				sm.shader = ARMOR_SHADER
				sm.set_shader_parameter("color1", _col(m.color1))
				sm.set_shader_parameter("color2", _col(m.color2))
				sm.set_shader_parameter("color3", _col(m.color3))
				if m.get("mask") != null:
					sm.set_shader_parameter("color_mask", load(m.mask))
					sm.set_shader_parameter("has_mask", true)
			"skin":
				sm.shader = SKIN_SHADER
				sm.set_shader_parameter("details_color", _col(m.details_color))
				if m.get("details") != null:
					sm.set_shader_parameter("details", load(m.details))
					sm.set_shader_parameter("has_details", true)
			_:
				continue  # plain sprite material -> default CanvasItem rendering
		sm.set_shader_parameter("tint", _col(m.tint))
		materials[key] = sm


func _build_nodes(nodes: Array) -> void:
	for n in nodes:
		var node := Node2D.new()
		node.name = n.name
		node.position = _v2(n.pos)
		node.rotation = n.rot
		node.scale = _v2(n.scale)
		node.visible = n.visible
		var parent: Node = self if n.parent == "" else parts[n.parent]
		parent.add_child(node)
		if n.parent == "":
			node.set_meta("cc2d_generated", true)
		parts[n.path] = node

		var s = n.get("sprite")
		if s == null:
			continue
		var spr := Sprite2D.new()
		spr.name = "_sprite"
		spr.centered = false
		spr.z_index = int(s.z)
		spr.self_modulate = _col(s.color)
		spr.visible = s.enabled
		if s.get("material") != null and materials.has(s.material):
			spr.material = materials[s.material]
		if s.get("texture") != null:
			spr.texture = load(s.texture)
			spr.region_enabled = true
			spr.region_rect = Rect2(s.region[0], s.region[1], s.region[2], s.region[3])
			spr.offset = _v2(s.offset)
			var k: float = s.px_scale
			spr.scale = Vector2(-k if s.flip_h else k, -k if s.flip_v else k)
		node.add_child(spr)
		node.move_child(spr, 0)
		sprites[n.path] = spr


func _build_animations(path: String) -> void:
	if path == "":
		return
	var d := _read_json(path)
	if d.is_empty():
		return
	animation_player = AnimationPlayer.new()
	animation_player.name = "AnimationPlayer"
	animation_player.set_meta("cc2d_generated", true)
	add_child(animation_player)  # root_node ".." -> this character

	var base_rot := {}
	for n in data.get("nodes", []):
		base_rot[n.path] = n.rot

	var lib := AnimationLibrary.new()
	var anims: Dictionary = d.get("animations", {})
	for anim_name in anims:
		var a: Dictionary = anims[anim_name]
		var anim := Animation.new()
		anim.length = a.length
		anim.loop_mode = Animation.LOOP_LINEAR if a.loop else Animation.LOOP_NONE
		for tr in a.tracks:
			var prop: String = tr.prop
			var idx := anim.add_track(Animation.TYPE_VALUE)
			anim.track_set_path(idx, NodePath("%s:%s" % [tr.path, prop]))
			if prop == "visible":
				anim.value_track_set_update_mode(idx, Animation.UPDATE_DISCRETE)
				anim.track_set_interpolation_type(idx, Animation.INTERPOLATION_NEAREST)
			else:
				anim.value_track_set_update_mode(idx, Animation.UPDATE_CONTINUOUS)
				anim.track_set_interpolation_type(idx, Animation.INTERPOLATION_LINEAR)
			var times: Array = tr.times
			var values: Array = tr.values
			# Keep rotation tracks in the same 2*PI "turn" as the rest pose, so
			# cross-fades between animations never spin a bone the long way round.
			var turn := 0.0
			if prop == "rotation" and values.size() > 0:
				turn = round((float(values[0]) - float(base_rot.get(tr.path, 0.0))) / TAU) * TAU
			for i in times.size():
				anim.track_insert_key(idx, times[i], _anim_value(prop, values[i], turn))
		lib.add_animation(anim_name, anim)
	animation_player.add_animation_library("", lib)


# ------------------------------------------------------------------ helpers

func _anim_value(prop: String, v, turn: float):
	match prop:
		"position", "scale":
			return Vector2(v[0], v[1])
		"rotation":
			return float(v) - turn
		"visible":
			return bool(v)
	return v


func _skin_reference() -> Color:
	# The colour the exporter found on the Hip sprite is used as "the skin colour".
	for n in data.get("nodes", []):
		if n.name == "Hip" and n.get("sprite") != null:
			return _col(n.sprite.color)
	return Color.WHITE


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("CC2DCharacter: file not found: %s" % path)
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("CC2DCharacter: could not parse %s" % path)
		return {}
	return parsed


static func _v2(a) -> Vector2:
	return Vector2(a[0], a[1])


static func _col(a) -> Color:
	return Color(a[0], a[1], a[2], a[3])
