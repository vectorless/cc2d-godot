## Godot runtime for characters exported from Character Creator 2D (Unity).
## Port of CharacterViewer + HumanoidSetter/HumanoidAssigner:
## - builds the Male/Female rig from cc2d/rigs/*.json
## - equips any part from cc2d/parts.json (incl. capes and skirts)
## - recolours parts with the CC2D armour/skin shaders
## - plays CC2D animations (cape/skirt motion is pre-baked per frame by the exporter)
## - facial expressions (CharacterViewer.Expression): emote(), reset_emote(), animation-driven emotes
class_name CC2DCharacter
extends Node2D

const ARMOR_SHADER := preload("res://addons/cc2d/cc2d_armor.gdshader")
const SKIN_SHADER := preload("res://addons/cc2d/cc2d_skin.gdshader")

## Slot names, same as CC2D's SlotCategory enum.
const SLOTS := ["Armor", "Boots", "Ear", "Eyebrow", "Eyes", "FacialHair", "Gloves", "Hair",
	"Helmet", "Mouth", "Nose", "Pants", "SkinDetails", "MainHand", "OffHand", "Cape", "Skirt", "BodySkin"]
const BODY_TYPES := ["Male", "Female"]
const SKIN_SLOTS := ["BodySkin", "Ear", "Nose"]
const CLOTH_SLOTS := ["Cape", "Skirt"]
## Face slots swapped by emotes (HumanoidUtility.IsFace).
const FACE_SLOTS := ["Eyebrow", "Eyes", "Nose", "Mouth", "Ear"]
const MAIN_HAND_WEAPONS := ["OneHanded", "TwoHanded", "Gun", "Rifle"]
const OFF_HAND_WEAPONS := ["OneHanded", "Shield", "Bow", "Gun"]
const TWO_HANDED_WEAPONS := ["TwoHanded", "Bow", "Rifle"]

signal character_loaded
signal part_equipped(slot: String, part_name: String)
signal body_type_changed(body_type: String)
signal emote_changed(emotion: String)  ## "" when the face returns to default

## character.json produced by the Unity exporter.
@export_file("*.json") var character_file: String
## Play the character's default animation (Idle) once loaded.
@export var autoplay := true
## Default cross-fade time when switching animations (seconds).
@export var default_blend := 0.1

var animation_player: AnimationPlayer
var current_animation := ""
var parts := {}        ## rig path -> Node2D
var sprites := {}      ## rig path -> Sprite2D
var cloth := {}        ## "Cape"/"Skirt" -> Polygon2D
var materials := {}    ## material key -> ShaderMaterial
var slots := {}        ## slot -> {material, part (Dictionary or null), color1, color2, color3}
var body_type := "Male"
var skin_color := Color.GRAY
var tint_color := Color.WHITE
var catalogue := {}
var data := {}
var rig := {}
var emotes := {}  ## EmotionType name ("Blink", "Talk", "Emote_0", ...) -> {index, name, <face slot>: part ref or null}
## Driven by animations (CharacterViewer.emoteAnimIndex): EmotionType index, -1 = default face.
var emote_anim_index := -1.0
var current_emote := ""

var _current_emote_anim_index := -1.0
var _default_emote := {}
var _is_emoting := false
var _is_emoting_anim := false
var _emote_token := 0

static var _json_cache := {}
static var _library_cache := {}


func _ready() -> void:
	if character_file != "":
		load_character(character_file)


## (Re)builds the character from an exported character.json.
func load_character(path: String) -> void:
	data = _read_json(path)
	if data.is_empty():
		return
	catalogue = _cached_json(data.get("parts", "res://cc2d/parts.json"))
	body_type = data.get("body_type", "Male")
	skin_color = _col(data.get("skin_color", [0.5, 0.5, 0.5, 1]))
	tint_color = _col(data.get("tint_color", [1, 1, 1, 1]))
	emotes = data.get("emotes", {})
	_is_emoting = false
	_is_emoting_anim = false
	emote_anim_index = -1.0
	_current_emote_anim_index = -1.0
	slots.clear()
	var slot_data: Dictionary = data.get("slots", {})
	for slot in SLOTS:
		var sd: Dictionary = slot_data.get(slot, {})
		slots[slot] = {
			"material": sd.get("material"),
			"part": find_part(slot, sd.part, sd.get("package", "")) if sd.get("part") != null else null,
			"color1": _col(sd.get("color1", [0.5, 0.5, 0.5, 1])),
			"color2": _col(sd.get("color2", [0.5, 0.5, 0.5, 1])),
			"color3": _col(sd.get("color3", [0.5, 0.5, 0.5, 1])),
		}
	_rebuild("", 0.0)
	_capture_default_emote()
	character_loaded.emit()


# ================================================================== body type

## Switches between "Male" and "Female" (CharacterViewer.SetBodyType). Parts that
## don't support the new body are swapped for the nearest one that does.
func set_body_type(new_body_type: String) -> void:
	if not new_body_type in BODY_TYPES or new_body_type == body_type:
		return
	var anim := current_animation
	var t := animation_player.current_animation_position if animation_player and animation_player.is_playing() else 0.0
	if _is_emoting or _is_emoting_anim:
		reset_emote()
		_is_emoting_anim = false
	body_type = new_body_type
	_rebuild(anim, t)
	_capture_default_emote()
	_current_emote_anim_index = -1.0
	emote_anim_index = -1.0
	body_type_changed.emit(body_type)


func _rebuild(anim: String, anim_time: float) -> void:
	_clear()
	rig = _cached_json(data.get("rigs", {}).get(body_type, "res://cc2d/rigs/%s.json" % body_type.to_lower()))
	if rig.is_empty():
		return
	_build_materials(rig.get("materials", {}))
	_build_materials(data.get("materials", {}))
	_build_nodes(rig.get("nodes", []))
	_build_cloth(rig.get("cloth", {}))
	_build_animation_player()
	# CharacterViewer.Initialize: materials, skin, tint, then each slot's part -> sprites -> colours.
	_assign_slot_materials()
	set_skin_color(skin_color)
	set_tint_color(tint_color)
	for slot in SLOTS:
		_set_part_to_slot(slot, slots[slot].part)
	for slot in SLOTS:
		_assign_part_to_renderer(slot)
		_assign_color_to_renderer(slot)
	if anim != "":
		current_animation = ""
		play(anim, 0.0)
		animation_player.seek(anim_time, true)
	elif autoplay:
		play(data.get("default_animation", "Idle"), 0.0)


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
	return _equip(slot, part)


func _equip(slot: String, part) -> bool:
	if not _set_part_to_slot(slot, part):
		return false
	# CharacterViewer.EquipPart: changing a face part while not emoting changes the default face.
	if slot in FACE_SLOTS and not _is_emoting and not _is_emoting_anim:
		_default_emote[slot] = slots[slot].part
	_assign_part_to_renderer(slot)
	part_equipped.emit(slot, get_equipped(slot))
	return true


## Name of the part currently in a slot ("" if empty).
func get_equipped(slot: String) -> String:
	var p = slots.get(slot, {}).get("part")
	return p.name if p != null else ""


## All parts that can go in a slot (optionally only those supporting this body type).
func get_parts(slot: String, only_supported := true) -> Array:
	var source: Array
	match slot:
		"MainHand", "OffHand":
			var allowed := MAIN_HAND_WEAPONS if slot == "MainHand" else OFF_HAND_WEAPONS
			source = catalogue.get("categories", {}).get("Weapon", []).filter(func(w): return w.get("weapon", "") in allowed)
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

## Sets a slot's colours (CharacterViewer.SetPartColor). Hair, eyes, eyebrows,
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


# ================================================================== expressions

## Changes the facial expression (CharacterViewer.Emote). `emotion` is an EmotionType name
## ("Blink", "Attack", "Hurt", "Talk", "Emote_0".."Emote_9"), an emote's display name, or its index.
## With duration > 0 the face resets to default afterwards.
func emote(emotion, duration := 0.0) -> void:
	var e := _find_emote(emotion)
	if e.is_empty():
		push_error("CC2DCharacter: emotion not found: %s" % str(emotion))
		return
	if _is_emoting_anim:
		_update_anim_emote(-1.0)
	_emote(e, duration, false)


## Returns the face to its default parts (CharacterViewer.ResetEmote).
func reset_emote() -> void:
	for slot in FACE_SLOTS:
		_equip(slot, _default_emote.get(slot))
	_is_emoting = false
	current_emote = ""
	emote_changed.emit("")


## Sets which part an emotion uses for a face slot ("" = keep the default face part).
func set_emote_part(emotion: String, slot: String, part_name: String, package := "") -> void:
	var e := _find_emote(emotion)
	if e.is_empty() or not slot in FACE_SLOTS:
		return
	e[slot] = null if part_name == "" else {"name": part_name, "package": package}


func get_emotion_names() -> PackedStringArray:
	return PackedStringArray(emotes.keys())


func _process(_delta: float) -> void:
	# CharacterViewer.Update: follow emoteAnimIndex keys from the playing animation.
	if not _is_emoting and emote_anim_index != _current_emote_anim_index:
		_update_anim_emote(emote_anim_index)


func _emote(e: Dictionary, duration: float, is_animation: bool) -> void:
	_emote_token += 1  # cancels a pending timed reset (CancelInvoke)
	_is_emoting = not is_animation
	for slot in FACE_SLOTS:
		var ref = e.get(slot)
		var part = find_part(slot, ref.name, ref.get("package", "")) if ref != null else null
		_equip(slot, part if part != null else _default_emote.get(slot))
	current_emote = _emote_key(e)
	emote_changed.emit(current_emote)
	if duration > 0.0:
		var token := _emote_token
		get_tree().create_timer(duration).timeout.connect(func():
			if token == _emote_token:
				reset_emote())


func _update_anim_emote(value: float) -> void:
	var index := int(value)
	if index >= 0:
		reset_emote()
		_is_emoting_anim = true
		var e := _find_emote(index)
		if not e.is_empty():
			_emote(e, 0.0, true)
	else:
		reset_emote()
		_is_emoting_anim = false
	_current_emote_anim_index = emote_anim_index


func _capture_default_emote() -> void:
	for slot in FACE_SLOTS:
		_default_emote[slot] = slots[slot].part


func _find_emote(emotion) -> Dictionary:
	if typeof(emotion) == TYPE_INT or typeof(emotion) == TYPE_FLOAT:
		for key in emotes:
			if int(emotes[key].index) == int(emotion):
				return emotes[key]
		return {}
	if emotes.has(emotion):
		return emotes[emotion]
	for key in emotes:
		if emotes[key].get("name", "") == emotion:
			return emotes[key]
	return {}


func _emote_key(e: Dictionary) -> String:
	for key in emotes:
		if emotes[key] == e:
			return key
	return ""


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
	# HumanoidSetter.GetAlternatePart: walk forwards (Male) or backwards (Female)
	# from this part, then fall back to any part that supports the body.
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
			var part = slots[slot].part
			var poly: Polygon2D = cloth.get(slot)
			_set_mask(slot, part.mask if part != null else null)
			if poly == null:
				return
			if part == null or part.texture == null:
				poly.texture = null
				poly.visible = false
			else:
				var tex := _tex(part.texture)
				poly.texture = tex
				var uv_norm: PackedVector2Array = poly.get_meta("uv_norm")
				var size := tex.get_size()
				var uv := PackedVector2Array()
				uv.resize(uv_norm.size())
				for i in uv_norm.size():
					uv[i] = uv_norm[i] * size
				poly.uv = uv
				poly.visible = true
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


## CharacterViewer.RelinkMaterials: every renderer linked to a slot uses that slot's material.
func _assign_slot_materials() -> void:
	var wl: Dictionary = catalogue.get("weapon_links", {})
	for slot in SLOTS:
		var m := _slot_material(slot)
		if m == null:
			continue
		var paths: Array
		match slot:
			"MainHand":
				paths = wl.main.values()
			"OffHand":
				paths = wl.off.values() + wl.bow.values() + wl.shield.values()
			_:
				paths = catalogue.get("links", {}).get(slot, {}).values()
		for path in paths:
			if sprites.has(path):
				sprites[path].material = m
		if cloth.has(slot):
			cloth[slot].material = m


## RendererUtility.AssignSprites: clear every linked renderer, then fill those named by the part.
func _assign_sprites(links: Dictionary, part_sprites: Dictionary) -> void:
	for path in links.values():
		_set_sprite(sprites.get(path), null)
	for sprite_name in part_sprites:
		if links.has(sprite_name):
			_set_sprite(sprites.get(links[sprite_name]), part_sprites[sprite_name])


func _set_sprite(spr: Sprite2D, sd) -> void:
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
			remove_child(c)
			c.queue_free()
	parts.clear()
	sprites.clear()
	cloth.clear()
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
		if n.parent == "":
			node.set_meta("cc2d_generated", true)
			add_child(node)
		else:
			parts[n.parent].add_child(node)
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
		_set_sprite(spr, s.get("data"))
		node.add_child(spr)
		node.move_child(spr, 0)
		sprites[n.path] = spr


func _build_cloth(cloth_data: Dictionary) -> void:
	for slot in cloth_data:
		var c: Dictionary = cloth_data[slot]
		if not parts.has(c.parent):
			continue
		var poly := Polygon2D.new()
		poly.name = "_cloth_" + slot
		poly.polygon = _pv2(c.rest)
		var tris: Array = c.triangles
		var polys := []
		for i in range(0, tris.size(), 3):
			polys.append(PackedInt32Array([int(tris[i]), int(tris[i + 1]), int(tris[i + 2])]))
		poly.polygons = polys
		poly.set_meta("uv_norm", _pv2(c.uv))
		poly.z_index = int(c.z)
		poly.visible = false
		if c.get("material") != null and materials.has(c.material):
			poly.material = materials[c.material]
		parts[c.parent].add_child(poly)
		cloth[slot] = poly
		# The cloth's own bone nodes are only used by the bake; hide the subtree marker node.
		if parts.has(c.node):
			parts[c.node].visible = false


func _build_animation_player() -> void:
	animation_player = AnimationPlayer.new()
	animation_player.name = "AnimationPlayer"
	animation_player.set_meta("cc2d_generated", true)
	add_child(animation_player)  # root_node ".." -> this character
	var anim_path: String = data.get("animations", "res://cc2d/animations/cc2d.json")
	var rig_path: String = data.get("rigs", {}).get(body_type, "")
	var key := anim_path + "|" + rig_path
	if not _library_cache.has(key):
		_library_cache[key] = _build_library(_cached_json(anim_path), rig)
	animation_player.add_animation_library("", _library_cache[key])


## Builds an AnimationLibrary for one rig. Unity's "write defaults" is emulated by giving
## every animation a track for everything any animation touches, holding the rig's rest
## value where the clip doesn't animate it.
static func _build_library(anim_data: Dictionary, rig_data: Dictionary) -> AnimationLibrary:
	var base := {}
	for n in rig_data.get("nodes", []):
		base[n.path] = n
	var anims: Dictionary = anim_data.get("animations", {})
	var union := {}
	for anim_name in anims:
		for tr in anims[anim_name].tracks:
			union[tr.path + "|" + tr.prop] = true

	var lib := AnimationLibrary.new()
	for anim_name in anims:
		var a: Dictionary = anims[anim_name]
		var anim := Animation.new()
		anim.length = a.length
		anim.loop_mode = Animation.LOOP_LINEAR if a.loop else Animation.LOOP_NONE
		var present := {}
		for tr in a.tracks:
			present[tr.path + "|" + tr.prop] = true
			var turn := 0.0
			if tr.prop == "rotation" and base.has(tr.path):
				# keep rotations in the same 2*PI turn as the rest pose so cross-fades don't spin
				turn = round((float(tr.values[0]) - float(base[tr.path].rot)) / TAU) * TAU
			_add_track(anim, tr.path, tr.prop, tr.times, tr.values, turn)
		for key in union:
			if present.has(key):
				continue
			var path: String = key.get_slice("|", 0)
			var prop: String = key.get_slice("|", 1)
			if base.has(path):
				_add_track(anim, path, prop, [0.0], [_rest_value(base[path], prop)], 0.0)
			elif prop == "emote_anim_index":
				_add_track(anim, path, prop, [0.0], [-1.0], 0.0)  # prefab default: no emote
		for slot in rig_data.get("cloth", {}):
			var c: Dictionary = rig_data.cloth[slot]
			var idx := anim.add_track(Animation.TYPE_VALUE)
			anim.track_set_path(idx, NodePath("%s/_cloth_%s:polygon" % [c.parent, slot]))
			anim.value_track_set_update_mode(idx, Animation.UPDATE_CONTINUOUS)
			var ca = c.animations.get(anim_name)
			if ca == null:
				anim.track_insert_key(idx, 0.0, _pv2(c.rest))
			else:
				for i in ca.times.size():
					anim.track_insert_key(idx, ca.times[i], _pv2(ca.frames[i]))
		lib.add_animation(anim_name, anim)
	return lib


static func _add_track(anim: Animation, path: String, prop: String, times: Array, values: Array, turn: float) -> void:
	var idx := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(idx, NodePath("%s:%s" % [path, prop]))
	if prop == "visible" or prop == "emote_anim_index":
		anim.value_track_set_update_mode(idx, Animation.UPDATE_DISCRETE)
		anim.track_set_interpolation_type(idx, Animation.INTERPOLATION_NEAREST)
	else:
		anim.value_track_set_update_mode(idx, Animation.UPDATE_CONTINUOUS)
		anim.track_set_interpolation_type(idx, Animation.INTERPOLATION_LINEAR)
	for i in times.size():
		var v = values[i]
		if prop == "visible":
			v = bool(v)
		else:
			v = float(v) - turn
		anim.track_insert_key(idx, times[i], v)


static func _rest_value(n: Dictionary, prop: String):
	match prop:
		"position:x":
			return n.pos[0]
		"position:y":
			return n.pos[1]
		"scale:x":
			return n.scale[0]
		"scale:y":
			return n.scale[1]
		"rotation":
			return n.rot
		"visible":
			return n.visible
	return 0.0


# ================================================================== helpers

static func _cached_json(path: String) -> Dictionary:
	if not _json_cache.has(path):
		_json_cache[path] = _read_json(path)
	return _json_cache[path]


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


static func _pv2(a: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(a.size() / 2)
	for i in out.size():
		out[i] = Vector2(a[i * 2], a[i * 2 + 1])
	return out


static func _v2(a) -> Vector2:
	return Vector2(a[0], a[1])


static func _col(a) -> Color:
	return Color(a[0], a[1], a[2], a[3])
