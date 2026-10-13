## Godot runtime for characters exported from Character Creator 2D (Unity).
## Port of CharacterViewer + HumanoidSetter/HumanoidAssigner: builds the rig,
## recolouring materials and AnimationPlayer from the exporter's JSON, and
## supports equipping any part from the exported catalogue at runtime.
class_name CC2DCharacter
extends Node2D

const ARMOR_SHADER := preload("res://addons/cc2d/cc2d_armor.gdshader")
const SKIN_SHADER := preload("res://addons/cc2d/cc2d_skin.gdshader")

## Slot names, same as CC2D's SlotCategory enum.
const SLOTS := ["Armor", "Boots", "Ear", "Eyebrow", "Eyes", "FacialHair", "Gloves", "Hair",
	"Helmet", "Mouth", "Nose", "Pants", "SkinDetails", "MainHand", "OffHand", "Cape", "Skirt", "BodySkin"]
const SKIN_SLOTS := ["BodySkin", "Ear", "Nose"]
const MAIN_HAND_WEAPONS := ["OneHanded", "TwoHanded", "Gun", "Rifle"]
const OFF_HAND_WEAPONS := ["OneHanded", "Shield", "Bow", "Gun"]
const TWO_HANDED_WEAPONS := ["TwoHanded", "Bow", "Rifle"]

signal character_loaded
signal part_equipped(slot: String, part_name: String)

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
var slots := {}      ## slot -> {material, part (Dictionary or null), color1, color2, color3}
var body_type := "Male"
var skin_color := Color.GRAY
var tint_color := Color.WHITE
var catalogue := {}  ## exported part catalogue (cc2d/parts.json)
var data := {}

static var _catalogue_cache := {}


func _ready() -> void:
	if character_file != "":
		load_character(character_file)


## (Re)builds the character from an exported character.json.
func load_character(path: String) -> void:
	_clear()
	data = _read_json(path)
	if data.is_empty():
		return
	catalogue = _load_catalogue(data.get("parts", "res://cc2d/parts.json"))
	body_type = data.get("body_type", "Male")
	skin_color = _col(data.get("skin_color", [0.5, 0.5, 0.5, 1]))
	tint_color = _col(data.get("tint_color", [1, 1, 1, 1]))
	_build_materials(data.get("materials", {}))
	_build_nodes(data.get("nodes", []))
	_build_animations(data.get("animations", ""))
	_init_slots(data.get("slots", {}))
	if autoplay:
		play(data.get("default_animation", "Idle"), 0.0)
	character_loaded.emit()


# ================================================================== animation

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


# ================================================================== equipment

## Equips a part by name (CharacterViewer.EquipPart). Empty name unequips the slot.
## If the part doesn't support this body type, the nearest one that does is used (as in CC2D).
func equip_part(slot: String, part_name: String, package := "") -> bool:
	if not slots.has(slot):
		push_warning("CC2DCharacter: unknown slot '%s'" % slot)
		return false
	var part = null
	if part_name != "":
		part = find_part(slot, part_name, package)
		if part == null:
			push_warning("CC2DCharacter: can't find part '%s' for slot %s" % [part_name, slot])
			return false
	if not _set_part_to_slot(slot, part):
		return false
	_assign_part_to_renderer(slot)
	part_equipped.emit(slot, get_equipped(slot))
	return true


## Name of the part currently in a slot ("" if empty).
func get_equipped(slot: String) -> String:
	var p = slots.get(slot, {}).get("part")
	return p.name if p != null else ""


## All parts that can go in a slot (optionally only those supporting this body type).
func get_parts(slot: String, only_supported := true) -> Array:
	var result := []
	var source: Array
	match slot:
		"MainHand", "OffHand":
			var allowed := MAIN_HAND_WEAPONS if slot == "MainHand" else OFF_HAND_WEAPONS
			for w in catalogue.get("categories", {}).get("Weapon", []):
				if w.get("weapon", "") in allowed:
					result.append(w)
			source = result
		_:
			source = catalogue.get("categories", {}).get(slot, [])
	if not only_supported:
		return source.duplicate()
	return source.filter(func(p): return body_type in p.body)


func find_part(slot: String, part_name: String, package := ""):
	for p in get_parts(slot, false):
		if p.name == part_name and (package == "" or p.package == package):
			return p
	return null


## Equips the next (step = 1) or previous (step = -1) part for a slot. Returns its name.
func cycle_part(slot: String, step := 1) -> String:
	var list := get_parts(slot)
	if list.is_empty():
		return get_equipped(slot)
	var current := get_equipped(slot)
	var idx := -1
	for i in list.size():
		if list[i].name == current:
			idx = i
			break
	var next = list[posmod(idx + step, list.size())]
	equip_part(slot, next.name, next.package)
	return next.name


# ================================================================== colours

## Sets a slot's three colours (CharacterViewer.SetPartColor). Hair, eyes, eyebrows,
## mouth and facial hair only use color1, applied as the sprite colour.
func set_part_color(slot: String, color1: Color, color2 = null, color3 = null) -> void:
	if not slots.has(slot):
		return
	var s: Dictionary = slots[slot]
	if catalogue.get("colorable_links", {}).has(slot):
		s.color1 = color1
		s.color2 = color1
		s.color3 = color1
	else:
		s.color1 = color1
		if color2 != null:
			s.color2 = color2
		if color3 != null:
			s.color3 = color3
	_assign_color_to_renderer(slot)


func get_part_colors(slot: String) -> Array:
	var s: Dictionary = slots.get(slot, {})
	return [s.get("color1", Color.GRAY), s.get("color2", Color.GRAY), s.get("color3", Color.GRAY)]


## Skin colour for body, ears and nose (CharacterViewer.SkinColor).
func set_skin_color(color: Color) -> void:
	skin_color = color
	for slot in SKIN_SLOTS:
		for path in catalogue.get("links", {}).get(slot, {}).values():
			if sprites.has(path):
				sprites[path].self_modulate = color


## Overall tint applied to every part (CharacterViewer.TintColor).
func set_tint_color(color: Color) -> void:
	tint_color = color
	for m in materials.values():
		m.set_shader_parameter("tint", color)


# ================================================================== setter (HumanoidSetter)

func _set_part_to_slot(slot: String, part) -> bool:
	part = _check_supported_body(slot, part)
	match slot:
		"MainHand":
			if part != null and not (part.get("weapon", "") in MAIN_HAND_WEAPONS):
				push_warning("CC2DCharacter: can't equip %s to main hand" % part.name)
				return false
			var off = slots.OffHand.part
			if part != null and (part.weapon in TWO_HANDED_WEAPONS or (off != null and off.weapon in TWO_HANDED_WEAPONS)):
				slots.OffHand.part = null
			slots.MainHand.part = part
		"OffHand":
			if part != null and not (part.get("weapon", "") in OFF_HAND_WEAPONS):
				push_warning("CC2DCharacter: can't equip %s to off hand" % part.name)
				return false
			var main = slots.MainHand.part
			if part != null and (part.weapon in TWO_HANDED_WEAPONS or (main != null and main.weapon in TWO_HANDED_WEAPONS)):
				slots.MainHand.part = null
			slots.OffHand.part = part
		_:
			slots[slot].part = part
	return true


func _check_supported_body(slot: String, part):
	if part == null or body_type in part.body:
		return part
	# Same search as HumanoidSetter.GetAlternatePart: walk forwards (Male) or
	# backwards (Female) from this part, then fall back to any supported part.
	var list := get_parts(slot, false)
	var sid := list.find(part)
	var inc := 1 if body_type == "Male" else -1
	var i := sid
	while i >= 0 and i < list.size():
		if body_type in list[i].body:
			return list[i]
		i += inc
	for p in list:
		if body_type in p.body:
			return p
	return null


# ================================================================== assigner (HumanoidAssigner)

func _assign_part_to_renderer(slot: String) -> void:
	match slot:
		"MainHand", "OffHand":
			_assign_weapon("MainHand")
			_assign_weapon("OffHand")
		"SkinDetails":
			var part = slots.SkinDetails.part
			var mat := _slot_material("SkinDetails")
			if mat:
				var tex = _tex(part.texture) if part != null and part.texture != null else null
				mat.set_shader_parameter("details", tex)
				mat.set_shader_parameter("has_details", tex != null)
		"Cape", "Skirt":
			# Cloth meshes aren't ported yet; keep them hidden.
			var link: String = catalogue.get("cape_link" if slot == "Cape" else "skirt_link", "")
			var cloth_root := link.get_base_dir()
			if parts.has(cloth_root):
				parts[cloth_root].visible = false
			if slots[slot].part != null:
				push_warning("CC2DCharacter: %s parts aren't supported in Godot yet" % slot)
		_:
			var part = slots[slot].part
			_set_mask(slot, part.mask if part != null else null)
			_assign_sprites(catalogue.get("links", {}).get(slot, {}), part.sprites if part != null else {})


func _assign_weapon(slot: String) -> void:
	var weapon = slots[slot].part
	var wl: Dictionary = catalogue.get("weapon_links", {})
	_set_mask(slot, weapon.mask if weapon != null else null)
	var category: String = weapon.weapon if weapon != null else "OneHanded"
	var spr: Dictionary = weapon.sprites if weapon != null else {}
	if slot == "MainHand":
		if category in MAIN_HAND_WEAPONS:
			_assign_sprites(wl.main, spr)
	else:
		match category:
			"OneHanded", "Gun":
				_assign_sprites(wl.bow, {})
				_assign_sprites(wl.shield, {})
				_assign_sprites(wl.off, spr)
			"Shield":
				_assign_sprites(wl.bow, {})
				_assign_sprites(wl.off, {})
				_assign_sprites(wl.shield, spr)
			"Bow":
				_assign_sprites(wl.shield, {})
				_assign_sprites(wl.off, {})
				_assign_sprites(wl.bow, spr)


func _assign_color_to_renderer(slot: String) -> void:
	if slot in SKIN_SLOTS:
		return
	var s: Dictionary = slots[slot]
	if slot == "SkinDetails":
		var mat := _slot_material(slot)
		if mat:
			mat.set_shader_parameter("details_color", s.color1)
		return
	if slot == "MainHand" or slot == "OffHand":
		var fx: String = catalogue.get("weapon_fx_links", {}).get(slot, "")
		if sprites.has(fx):
			sprites[fx].self_modulate = s.color1
	var colorable: Dictionary = catalogue.get("colorable_links", {})
	if colorable.has(slot):
		for path in colorable[slot]:
			if sprites.has(path):
				sprites[path].self_modulate = s.color1
		return
	var m := _slot_material(slot)
	if m:
		m.set_shader_parameter("color1", s.color1)
		m.set_shader_parameter("color2", s.color2)
		m.set_shader_parameter("color3", s.color3)


## RendererUtility.AssignSprites: clear every linked renderer, then fill those named by the part.
func _assign_sprites(links: Dictionary, part_sprites: Dictionary) -> void:
	for path in links.values():
		_set_sprite(path, null)
	for sprite_name in part_sprites:
		if links.has(sprite_name):
			_set_sprite(links[sprite_name], part_sprites[sprite_name])


func _set_sprite(path: String, sd) -> void:
	var spr: Sprite2D = sprites.get(path)
	if spr == null:
		return
	if sd == null:
		spr.texture = null
		return
	spr.texture = _tex(sd.texture)
	spr.region_enabled = true
	spr.region_rect = Rect2(sd.region[0], sd.region[1], sd.region[2], sd.region[3])
	spr.offset = _v2(sd.offset)
	var k: float = sd.px_scale
	spr.scale = Vector2(k * spr.get_meta("flip_x", 1.0), k * spr.get_meta("flip_y", 1.0))


func _set_mask(slot: String, mask_path) -> void:
	var m := _slot_material(slot)
	if m == null or m.shader != ARMOR_SHADER:
		return
	var tex = _tex(mask_path) if mask_path != null else null
	m.set_shader_parameter("color_mask", tex)
	m.set_shader_parameter("has_mask", tex != null)


func _slot_material(slot: String) -> ShaderMaterial:
	var key = slots.get(slot, {}).get("material")
	return materials.get(key) if key != null else null


# ================================================================== building

func _clear() -> void:
	for c in get_children():
		if c.has_meta("cc2d_generated"):
			c.queue_free()
	parts.clear()
	sprites.clear()
	materials.clear()
	slots.clear()
	animation_player = null
	current_animation = ""


func _init_slots(slot_data: Dictionary) -> void:
	# Same order as CharacterViewer.Initialize: skin colour, tint, then every slot's
	# part (setter) -> sprites (assigner) -> colours.
	for slot in SLOTS:
		var sd: Dictionary = slot_data.get(slot, {})
		slots[slot] = {
			"material": sd.get("material"),
			"part": null,
			"color1": _col(sd.get("color1", [0.5, 0.5, 0.5, 1])),
			"color2": _col(sd.get("color2", [0.5, 0.5, 0.5, 1])),
			"color3": _col(sd.get("color3", [0.5, 0.5, 0.5, 1])),
		}
	set_skin_color(skin_color)
	set_tint_color(tint_color)
	for slot in SLOTS:
		var sd: Dictionary = slot_data.get(slot, {})
		var part = null
		if sd.get("part") != null:
			part = find_part(slot, sd.part, sd.get("package", ""))
		_set_part_to_slot(slot, part)
	for slot in SLOTS:
		_assign_part_to_renderer(slot)
		_assign_color_to_renderer(slot)


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
					sm.set_shader_parameter("color_mask", _tex(m.mask))
					sm.set_shader_parameter("has_mask", true)
			"skin":
				sm.shader = SKIN_SHADER
				sm.set_shader_parameter("details_color", _col(m.details_color))
				if m.get("details") != null:
					sm.set_shader_parameter("details", _tex(m.details))
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
		spr.set_meta("flip_x", -1.0 if s.get("flip_h", false) else 1.0)
		spr.set_meta("flip_y", -1.0 if s.get("flip_v", false) else 1.0)
		if s.get("material") != null and materials.has(s.material):
			spr.material = materials[s.material]
		if s.get("texture") != null:
			_set_sprite_from_node_data(spr, s)
		node.add_child(spr)
		node.move_child(spr, 0)
		sprites[n.path] = spr


func _set_sprite_from_node_data(spr: Sprite2D, s: Dictionary) -> void:
	spr.texture = _tex(s.texture)
	spr.region_enabled = true
	spr.region_rect = Rect2(s.region[0], s.region[1], s.region[2], s.region[3])
	spr.offset = _v2(s.offset)
	var k: float = s.px_scale
	spr.scale = Vector2(k * spr.get_meta("flip_x"), k * spr.get_meta("flip_y"))


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


# ================================================================== helpers

func _anim_value(prop: String, v, turn: float):
	match prop:
		"position", "scale":
			return Vector2(v[0], v[1])
		"rotation":
			return float(v) - turn
		"visible":
			return bool(v)
	return v


static func _load_catalogue(path: String) -> Dictionary:
	if not _catalogue_cache.has(path):
		_catalogue_cache[path] = _read_json(path)
	return _catalogue_cache[path]


static func _tex(path) -> Texture2D:
	return load(path) if path != null else null


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
