## Godot runtime for characters exported from Character Creator 2D (Unity).
## Port of CharacterViewer + HumanoidSetter/HumanoidAssigner:
## - builds the Male/Female rig from cc2d/rigs/*.json
## - equips any part from cc2d/parts.json (incl. capes and skirts)
## - recolours parts with the CC2D armour/skin shaders
## - plays CC2D animations (cape/skirt motion is pre-baked per frame by the exporter)
## - facial expressions (CharacterViewer.Expression): emote(), reset_emote(), animation-driven emotes
## - the Aim layer (aim blend trees for bows/guns/spells), weapon slash effects
## - body sliders (BodySegmentScaler) and CC2D CharacterData JSON save/load (Unity-compatible)
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
## Body slider segments, in CC2D SegmentType enum order.
const SEGMENTS := ["Head", "Ear", "Neck", "Body", "UpperArm", "LowerArm", "Hand", "UpperLeg", "LowerLeg", "Foot"]
## CC2D EmotionType values for the built-in emotes (custom ones are Emote_0..Emote_9 = 0..9).
const AIM_LAYER := "Aim Layer"
const MAIN_HAND_WEAPONS := ["OneHanded", "TwoHanded", "Gun", "Rifle"]
const OFF_HAND_WEAPONS := ["OneHanded", "Shield", "Bow", "Gun"]
const TWO_HANDED_WEAPONS := ["TwoHanded", "Bow", "Rifle"]
## SetupData.muzzleFXLinks: where each hand's muzzle flash lives (moved to Weapon.muzzlePosition).
const MUZZLE_LINKS := {
	"MainHand": "Root/Pos_Hip/Bone_Hip/Pos_Body/Bone_Body/Pos_Upper Arm R/Bone_Upper Arm R/Pos_Lower Arm R/Bone_Lower Arm R/Pos_Hand R/Bone_Hand R/Pos_Weapon R/Bone_Weapon R/Muzzle R",
	"OffHand": "Root/Pos_Hip/Bone_Hip/Pos_Body/Bone_Body/Pos_Upper Arm L/Bone_Upper Arm L/Pos_Lower Arm L/Bone_Lower Arm L/Pos_Hand L/Bone_Hand L/Pos_Weapon L/Bone_Weapon L/Muzzle L",
}

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

## Aim layer state (Unity "Aim Layer": override layer of 1D blend trees over the "Aim" parameter).
var aim_state := ""
var aim_value := 0.0
var _aim_phase := 0.0
var _aim_cache := {}

## Body sliders (0..1 per axis, 0.5 = default), keyed by SEGMENTS name.
var body_sliders := {}
var _segments := {}
var _pos_affections := {}  # node path -> [{segment, data}] in Unity's insertion order
var _rig_nodes := {}       # rig path -> node data from the rig json
var _particles := {}       # rig path -> {node, fx: CPUParticles2D, shown, cycle} (muzzle flashes)
var _posed := false        # frozen on one frame by pose() (for rendering) until the next play()
var loaded_file := ""      ## the character.json this character was built from
static var _flash_textures := {}   # padded particle textures, by source path

static var _sprite_tables := {}
static var _emote_keys := {}  # animations path -> {anim name: [times, values]}

static var _json_cache := {}
## Extra animation files added by part packs ({"animations": "res://custom/<pack>/animations.json"}):
## their clips are added to every character (see add_animation_pack).
static var _extra_anim_files: Array[String] = []
static var _anim_fx := {}     # clip name -> {"smoke": [[t0, t1], ...]} (exhale windows)
static var _library_cache := {}


func _ready() -> void:
	if character_file != "":
		load_character(character_file)


## (Re)builds the character from an exported character.json.
func load_character(path: String) -> void:
	data = _read_json(path)
	if data.is_empty():
		return
	loaded_file = path
	catalogue = _cached_json(data.get("parts", "res://cc2d/parts.json"))
	body_type = data.get("body_type", "Male")
	skin_color = _col(data.get("skin_color", [0.5, 0.5, 0.5, 1]))
	tint_color = _col(data.get("tint_color", [1, 1, 1, 1]))
	emotes = data.get("emotes", {})
	body_sliders.clear()
	for seg in SEGMENTS:
		body_sliders[seg] = Vector2(0.5, 0.5)
	aim_state = ""
	aim_value = 0.0
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
	_build_materials(catalogue.get("default_materials", {}))
	_build_materials(data.get("materials", {}))
	_build_nodes(rig.get("nodes", []))
	_build_cloth(rig.get("cloth", {}))
	_build_segments(rig.get("segments", {}))
	_build_animation_player()
	_aim_cache.clear()
	# CharacterViewer.Initialize: materials, skin, tint, then each slot's part -> sprites -> colours.
	_assign_slot_materials()
	set_skin_color(skin_color)
	set_tint_color(tint_color)
	for slot in SLOTS:
		_set_part_to_slot(slot, slots[slot].part)
	for slot in SLOTS:
		_assign_part_to_renderer(slot)
		_assign_color_to_renderer(slot)
	for seg in SEGMENTS:  # BodySegmentScaler.Initialize re-applies every slider
		_apply_segment(seg)
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
	if anim_name == current_animation and animation_player.is_playing() and not _posed:
		return
	_posed = false
	current_animation = anim_name
	animation_player.play(anim_name, default_blend if blend < 0.0 else blend)


## Freezes the character on one frame, for rendering: base animation at base_time seconds, plus
## an Aim-layer state at aim_time seconds ("" = none). Muzzle flashes are simulated up to that
## moment. play() / play_aim() unfreeze it.
func pose(base_anim: String, base_time: float, aim := "", aim_time := 0.0) -> void:
	if animation_player != null and animation_player.has_animation(base_anim):
		current_animation = base_anim
		animation_player.play(base_anim, 0.0)
		animation_player.seek(base_time, true)
		animation_player.pause()
	if aim == "" or aim == "None" or _aim_state_data(aim) == null:
		play_aim("")
	else:
		aim_state = aim
		var length := get_aim_length(aim)
		_aim_phase = aim_time / length if length > 0.0 else 0.0
		_apply_aim()
	_posed = true
	_update_emote_anim_index()
	for path in _particles:
		var e: Dictionary = _particles[path]
		e.shown = e.node.is_visible_in_tree()
		e.cycle = int(floor(_aim_phase)) if aim_state != "" else -1
		if e.shown:
			# CPUParticles2D pre-simulates in 1/30 s steps on its next update (plus that frame).
			var age := _flash_age(path, aim_time)
			e.fx.preprocess = age if age >= 1.0 / 30.0 else 0.0
			e.fx.restart()
	_pose_smoke(base_time)


## Length in seconds of an Aim-layer state (its longest blend-tree child), 0 if it has none.
func get_aim_length(state: String) -> float:
	var length := 0.0
	for c in _get_aim(state).children:
		length = maxf(length, c.anim.length)
	return length


## Length in seconds of a base animation, 0 if there isn't one.
func get_animation_length(anim_name: String) -> float:
	if animation_player == null or not animation_player.has_animation(anim_name):
		return 0.0
	return animation_player.get_animation(anim_name).length


## How long a muzzle flash has been on, at aim_time into the current aim state.
func _flash_age(path: String, aim_time: float) -> float:
	var e := _get_aim(aim_state)
	var key := path + "|visible"
	for c in e.children:
		if not c.idx.has(key):
			continue
		var anim: Animation = c.anim
		var t := fmod(aim_time, maxf(anim.length, 0.0001)) if c.loop else minf(aim_time, anim.length)
		var tr: int = c.idx[key]
		var onset := 0.0
		for k in anim.track_get_key_count(tr):
			var kt := anim.track_get_key_time(tr, k)
			if kt > t + 0.0001:
				break
			var on: bool = anim.track_get_key_value(tr, k)
			var prev: bool = anim.track_get_key_value(tr, k - 1) if k > 0 else false
			if on and not prev:
				onset = kt
		return maxf(t - onset, 0.0)
	return 0.0


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


## Adds a custom part pack (a JSON file shaped like cc2d/parts.json: {"categories": {...}})
## to the shared catalogue, so every character can equip its parts. Returns how many parts
## were added (0 if the pack was already added). Custom packs live in res://custom/<pack>/.
static func add_part_pack(path: String, catalogue_path := "res://cc2d/parts.json") -> int:
	var cat := _cached_json(catalogue_path)
	var pack := _read_json(path)
	if cat.is_empty() or pack.is_empty():
		return 0
	var added := 0
	for category in pack.get("categories", {}):
		if not cat.categories.has(category):
			cat.categories[category] = []
		var list: Array = cat.categories[category]
		for p in pack.categories[category]:
			if list.any(func(q): return q.name == p.name and q.package == p.package):
				continue
			list.append(p)
			added += 1
	if pack.get("animations") is String:
		add_animation_pack(pack.animations)
	return added


## Adds the clips of an extra animation file (same format as cc2d/animations/cc2d.json) to every
## character built from now on (existing ones get them on their next rebuild, e.g. set_body_type).
## A clip may give per-body tracks under "bodies": {"Male": {"tracks": [...]}, "Female": ...}, which
## replace the common ones for the same path and property, and smoke windows under "smoke".
## Returns false if the file was already added or can't be read.
static func add_animation_pack(path: String) -> bool:
	if path in _extra_anim_files or _read_json(path).is_empty():
		return false
	_extra_anim_files.append(path)
	_library_cache.clear()
	return true


## The animation data for a body: the exported file plus the clips of every animation pack.
static func _anim_data_for(anim_path: String, body: String) -> Dictionary:
	var base := _cached_json(anim_path)
	if _extra_anim_files.is_empty():
		return base
	var merged := base.duplicate()
	merged.animations = (base.get("animations", {}) as Dictionary).duplicate()
	for f in _extra_anim_files:
		var extra := _cached_json(f)
		for anim_name in extra.get("animations", {}):
			var a: Dictionary = extra.animations[anim_name]
			var tracks: Array = a.get("tracks", []).duplicate()
			var own: Array = a.get("bodies", {}).get(body, {}).get("tracks", [])
			if not own.is_empty():
				var keys := {}
				for tr in own:
					keys[tr.path + "|" + tr.prop] = true
				tracks = tracks.filter(func(tr): return not keys.has(tr.path + "|" + tr.prop)) + own
			merged.animations[anim_name] = {"length": a.length, "loop": a.get("loop", true), "tracks": tracks}
			_anim_fx[anim_name] = {"smoke": a.get("smoke", [])}
	return merged


## Name of the part currently in a slot ("" if empty). Names aren't unique across packs
## ("Gun 00" is in Fantasy, Daily and Post Apocalyptic): see get_equipped_package().
func get_equipped(slot: String) -> String:
	var p = slots.get(slot, {}).get("part")
	return p.name if p != null else ""


## Package (pack) of the part in a slot: "Base", "Fantasy", "Daily", ... ("" if empty).
func get_equipped_package(slot: String) -> String:
	var p = slots.get(slot, {}).get("part")
	return p.package if p != null else ""


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
	var current = slots[slot].part
	var idx := -1
	for i in list.size():
		if current != null and list[i].name == current.name and list[i].package == current.package:
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


# ================================================================== aim layer

## Starts an Aim-layer state ("Aim Bow", "Aim Rifle", "Shot Bow", "Rapid Shot Main Hand", ...)
## on top of the base animation, like animator.Play(state, 1). "" or "None" stops aiming.
func play_aim(state: String) -> void:
	_posed = false
	if state == "" or state == "None":
		aim_state = ""
		for path in _particles:
			_particles[path].node.visible = false   # the Aim layer's weight goes to 0: flashes off
		return
	if _aim_state_data(state) == null:
		push_warning("CC2DCharacter: no aim state '%s'" % state)
		return
	aim_state = state
	_aim_phase = 0.0


## The "Aim" parameter: -1 = down, 0 = forward, 1 = up.
func set_aim(value: float) -> void:
	aim_value = clampf(value, -1.0, 1.0)


func get_aim_states() -> PackedStringArray:
	var out := PackedStringArray()
	var states: Dictionary = _cached_json(data.get("animations", "")).get("layers", {}).get(AIM_LAYER, {}).get("states", {})
	for k in states:
		if states[k] != null:
			out.append(k)
	return out


func _aim_state_data(state: String):
	return _cached_json(data.get("animations", "")).get("layers", {}).get(AIM_LAYER, {}).get("states", {}).get(state)


func _get_aim(state: String) -> Dictionary:
	if _aim_cache.has(state):
		return _aim_cache[state]
	var sd = _aim_state_data(state)
	var entry := {"children": [], "tracks": {}}
	if sd != null:
		var base := {}
		for n in rig.get("nodes", []):
			base[n.path] = n
		var children: Array = sd.children.duplicate()
		children.sort_custom(func(a, b): return a.threshold < b.threshold)
		for c in children:
			var anim := Animation.new()
			anim.length = c.anim.length
			var idx_by_key := {}
			for tr in c.anim.tracks:
				if tr.prop == "sprite" or tr.prop == "emote_anim_index":
					continue
				var turn := 0.0
				if tr.prop == "rotation" and base.has(tr.path):
					turn = round((float(tr.values[0]) - float(base[tr.path].rot)) / TAU) * TAU
				_add_track(anim, tr.path, tr.prop, tr.times, tr.values, turn)
				var key: String = tr.path + "|" + tr.prop
				idx_by_key[key] = anim.get_track_count() - 1
				if not entry.tracks.has(key):
					var target = _track_target(tr.path, tr.prop)
					if target != null:
						entry.tracks[key] = target
			entry.children.append({"threshold": float(c.threshold), "anim": anim, "idx": idx_by_key, "loop": c.anim.loop})
	_aim_cache[state] = entry
	return entry


func _track_target(path: String, prop: String):
	var node: Node = self if path == "." else parts.get(path)
	if node == null:
		return null
	if prop == "alpha":
		node = sprites.get(path)
		return [node, NodePath("self_modulate:a")] if node != null else null
	return [node, NodePath(prop)]


func _apply_aim() -> void:
	if aim_state == "":
		return
	var e := _get_aim(aim_state)
	var ch: Array = e.children
	if ch.is_empty():
		return
	# 1D blend tree: the two children around aim_value, clamped at the ends
	var i0 := 0
	var i1 := 0
	var w := 0.0
	if aim_value <= ch[0].threshold:
		i0 = 0; i1 = 0
	elif aim_value >= ch[-1].threshold:
		i0 = ch.size() - 1; i1 = i0
	else:
		for i in ch.size() - 1:
			if aim_value >= ch[i].threshold and aim_value <= ch[i + 1].threshold:
				i0 = i; i1 = i + 1
				w = inverse_lerp(ch[i].threshold, ch[i + 1].threshold, aim_value)
				break
	for key in e.tracks:
		var v0 = _aim_sample(ch[i0], key)
		var v1 = _aim_sample(ch[i1], key)
		if v0 == null:
			v0 = v1
		if v1 == null:
			v1 = v0
		if v0 == null:
			continue
		var v = (v0 if w < 0.5 else v1) if typeof(v0) == TYPE_BOOL else lerpf(v0, v1, w)
		var target: Array = e.tracks[key]
		target[0].set_indexed(target[1], v)


func _aim_sample(child: Dictionary, key: String):
	if not child.idx.has(key):
		return null
	var anim: Animation = child.anim
	var t := fmod(_aim_phase * anim.length, maxf(anim.length, 0.0001)) if child.loop else minf(_aim_phase * anim.length, anim.length)
	return anim.value_track_interpolate(child.idx[key], t)


func _advance_aim(delta: float) -> void:
	if aim_state == "":
		return
	var e := _get_aim(aim_state)
	var length := 0.0
	for c in e.children:
		length = maxf(length, c.anim.length)
	if length > 0.0:
		_aim_phase += delta / length


## Weapon slash effects: sprite-swap keys from animations (method track -> here).
func _anim_sprite(path: String, index: int) -> void:
	var spr: Sprite2D = sprites.get(path)
	if spr == null:
		return
	if index == -2:  # back to the rig's own sprite (write defaults)
		var n = _rig_nodes.get(path, {})
		_set_sprite(spr, n.get("sprite", {}).get("data") if n.has("sprite") else null)
		return
	var table: Array = _sprite_tables.get(data.get("animations", ""), [])
	_set_sprite(spr, table[index] if index >= 0 and index < table.size() else null)


# ================================================================== body sliders

## Sets a body slider (CharacterViewer.SetBodySlider). Values are 0..1 per axis, 0.5 = default.
## For symmetrical segments (head, ears, hands, feet) both axes are kept equal, as in CC2D.
func set_body_slider(segment: String, value: Vector2) -> void:
	if not _segments.has(segment):
		return
	var prev: Vector2 = body_sliders.get(segment, Vector2(0.5, 0.5))
	if _segments[segment].get("symmetrical", false):
		if prev.x != value.x and prev.y == value.y:
			value.y = value.x
		elif prev.x == value.x and prev.y != value.y:
			value.x = value.y
		elif prev.x != value.x and prev.y != value.y:
			value.x = (value.x + value.y) * 0.5
			value.y = value.x
	body_sliders[segment] = value
	_apply_segment(segment)


func get_body_slider(segment: String) -> Vector2:
	return body_sliders.get(segment, Vector2(0.5, 0.5))


func _build_segments(seg_data: Dictionary) -> void:
	_segments = seg_data
	_pos_affections.clear()
	for seg in seg_data:
		for d in seg_data[seg].positioned:
			if not _pos_affections.has(d.path):
				_pos_affections[d.path] = []
			_pos_affections[d.path].append({"segment": seg, "data": d})


func _apply_segment(segment: String) -> void:
	if not _segments.has(segment):
		return
	var sv: Vector2 = body_sliders.get(segment, Vector2(0.5, 0.5))
	for o in _segments[segment].scaled:  # ScaledAffection.SetScale
		var node: Node2D = parts.get(o.path)
		if node == null:
			continue
		node.scale = Vector2(_slide(sv.x, o.min[0], o.def[0], o.max[0]), _slide(sv.y, o.min[1], o.def[1], o.max[1]))
	for o in _segments[segment].positioned:  # PositionedAffection.updateTransform
		_update_position(o.path)


func _update_position(path: String) -> void:
	var node: Node2D = parts.get(path)
	var entries: Array = _pos_affections.get(path, [])
	if node == null or entries.is_empty():
		return
	var pos := _v2(entries[0].data.default)
	for e in entries:
		var d: Dictionary = e.data
		var sv: Vector2 = body_sliders.get(e.segment, Vector2(0.5, 0.5))
		var def := _v2(d.default)
		if d.scale_x:
			pos += _slide_v(sv.x, _v2(d.min_x), def, _v2(d.max_x)) - def
		if d.scale_y:
			pos += _slide_v(sv.y, _v2(d.min_y), def, _v2(d.max_y)) - def
	node.position = pos


static func _slide(t: float, lo: float, def: float, hi: float) -> float:
	if t > 0.5:
		return lerpf(def, hi, (t - 0.5) * 2.0)
	if t < 0.5:
		return lerpf(lo, def, t * 2.0)
	return def


static func _slide_v(t: float, lo: Vector2, def: Vector2, hi: Vector2) -> Vector2:
	if t > 0.5:
		return def.lerp(hi, (t - 0.5) * 2.0)
	if t < 0.5:
		return lo.lerp(def, t * 2.0)
	return def


# ================================================================== character data (CC2D JSON)

## The character in CC2D's CharacterData layout (what CharacterViewer.SaveToJSON writes),
## so files round-trip between this runtime and Unity's CharacterViewer.LoadFromJSON.
func get_character_data() -> Dictionary:
	var slot_data := []
	for i in SLOTS.size():
		var s: Dictionary = slots[SLOTS[i]]
		var p = s.part
		slot_data.append({
			"category": i,
			"partName": p.name if p != null else "",
			"partPackage": p.package if p != null else "",
			"color1": _ucol(s.color1), "color2": _ucol(s.color2), "color3": _ucol(s.color3),
		})
	var emote_data := []
	for key in emotes:
		var e: Dictionary = emotes[key]
		if int(e.index) >= 10 or str(e.get("name", "")) == "" or str(e.get("name", "")) == key:
			continue  # CC2D only saves named custom emotes
		var row := {"emotionType": int(e.index), "emotionName": e.name}
		for slot in FACE_SLOTS:
			var f: String = str(slot).to_lower()
			var ref = e.get(slot)
			row[f + "PartName"] = ref.name if ref != null else ""
			row[f + "Package"] = ref.package if ref != null else ""
		emote_data.append(row)
	var segs := []
	for i in SEGMENTS.size():
		var v: Vector2 = body_sliders.get(SEGMENTS[i], Vector2(0.5, 0.5))
		segs.append({"segmentType": i, "scale": {"x": v.x, "y": v.y}})
	return {
		"dataVersion": 1,
		"bodyType": BODY_TYPES.find(body_type),
		"skinColor": _ucol(skin_color),
		"tintColor": _ucol(tint_color),
		"slotData": slot_data,
		"emoteData": emote_data,
		"bodySegmentData": segs,
	}


## Applies CC2D CharacterData (e.g. a file saved by Unity's CharacterViewer.SaveToJSON).
func apply_character_data(cd: Dictionary) -> void:
	reset_emote()
	var bt := int(cd.get("bodyType", BODY_TYPES.find(body_type)))
	if bt >= 0 and bt < BODY_TYPES.size():
		set_body_type(BODY_TYPES[bt])
	if cd.has("skinColor"):
		set_skin_color(_from_ucol(cd.skinColor))
	if cd.has("tintColor"):
		set_tint_color(_from_ucol(cd.tintColor))
	for row in cd.get("slotData", []):
		var cat := int(row.get("category", -1))
		if cat < 0 or cat >= SLOTS.size():
			continue
		var slot: String = SLOTS[cat]
		_ensure_slot_material(slot)
		equip_part(slot, str(row.get("partName", "")), str(row.get("partPackage", "")))
		var s: Dictionary = slots[slot]
		s.color1 = _from_ucol(row.get("color1", _ucol(s.color1)))
		s.color2 = _from_ucol(row.get("color2", _ucol(s.color2)))
		s.color3 = _from_ucol(row.get("color3", _ucol(s.color3)))
		_assign_color_to_renderer(slot)
	for row in cd.get("emoteData", []):
		var e := _find_emote(int(row.get("emotionType", -1)))
		if e.is_empty():
			continue
		e.name = row.get("emotionName", e.name)
		for slot in FACE_SLOTS:
			var f: String = str(slot).to_lower()
			var pn := str(row.get(f + "PartName", ""))
			e[slot] = null if pn == "" else {"name": pn, "package": str(row.get(f + "Package", ""))}
	for row in cd.get("bodySegmentData", []):
		var si := int(row.get("segmentType", -1))
		if si >= 0 and si < SEGMENTS.size():
			var sc: Dictionary = row.get("scale", {})
			body_sliders[SEGMENTS[si]] = Vector2(float(sc.get("x", 0.5)), float(sc.get("y", 0.5)))
			_apply_segment(SEGMENTS[si])
	_capture_default_emote()


## Saves CC2D CharacterData JSON (loadable by Unity's CharacterViewer.LoadFromJSON).
func save_character(path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(get_character_data(), "\t"))
	return OK


## Loads CC2D CharacterData JSON (from save_character or from Unity) onto this character.
func load_character_data(path: String) -> Error:
	var cd := _read_json(path)
	if cd.is_empty():
		return ERR_PARSE_ERROR
	apply_character_data(cd)
	return OK


func _ensure_slot_material(slot: String) -> void:
	if slots[slot].material != null:
		return
	var key = catalogue.get("default_slot_materials", {}).get(slot)
	if key != null and materials.has(key):
		slots[slot].material = key
		_assign_slot_materials()


static func _ucol(c: Color) -> Dictionary:
	return {"r": c.r, "g": c.g, "b": c.b, "a": c.a}


static func _from_ucol(d) -> Color:
	if typeof(d) == TYPE_ARRAY:
		return Color(d[0], d[1], d[2], d[3])
	return Color(float(d.get("r", 0.5)), float(d.get("g", 0.5)), float(d.get("b", 0.5)), float(d.get("a", 1.0)))


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


func _process(delta: float) -> void:
	if _posed:
		return
	_advance_aim(delta)
	_update_particles()
	_update_emote_anim_index()
	_update_smoke()


# ============================================================================ smoke
# A thin wisp rises from the ember of a held item whose part has "smoke_tip" (weapon-local px), and
# clips with "smoke" windows (see add_animation_pack) puff smoke from the mouth during them.

var _smoke := {}   # "wisp" / "puff" -> CPUParticles2D
static var _smoke_tex: Texture2D


func _update_smoke() -> void:
	var p = slots.get("MainHand", {}).get("part")
	var tip = p.get("smoke_tip") if p is Dictionary else null
	var wspr: Node2D = null
	if tip != null:
		for path in sprites:
			if String(path).ends_with("Bone_Weapon R/Weapon R"):
				wspr = sprites[path]
				break
	var lit := tip != null and wspr != null and wspr.is_visible_in_tree()
	if lit and not _smoke.has("wisp"):
		_smoke.wisp = _make_smoke(false)
	if _smoke.has("wisp"):
		_smoke.wisp.emitting = lit
		if lit:
			_smoke.wisp.global_position = wspr.global_transform * Vector2(tip[0], tip[1])
	var windows: Array = _anim_fx.get(current_animation, {}).get("smoke", [])
	var puffing := false
	if lit and not windows.is_empty() and animation_player != null:
		var t := animation_player.current_animation_position
		for w in windows:
			if t >= float(w[0]) and t <= float(w[1]):
				puffing = true
	if puffing and not _smoke.has("puff"):
		_smoke.puff = _make_smoke(true)
	if _smoke.has("puff"):
		_smoke.puff.emitting = puffing
		if puffing:
			for path in parts:
				if String(path).ends_with("/Mouth F"):
					var facing := signf(global_transform.x.x) if global_transform.x.x != 0.0 else 1.0
					_smoke.puff.global_position = parts[path].global_position + Vector2(14.0 * facing, 4.0)
					_smoke.puff.direction = Vector2(0.9 * facing, -0.5)
					break


## Smoke for a posed frame (exports): placed for this pose and pre-simulated with a fixed seed, so
## frames of one animation show the same smoke moving on (the wisp as if it had been rising for a while,
## the puff for as long as the exhale has been going).
func _pose_smoke(t: float) -> void:
	_update_smoke()
	var windows: Array = _anim_fx.get(current_animation, {}).get("smoke", [])
	for k in _smoke:
		var fx: CPUParticles2D = _smoke[k]
		if not fx.emitting:
			continue
		var age := fx.lifetime + t
		if k == "puff":
			for w in windows:
				if t >= float(w[0]) and t <= float(w[1]):
					age = t - float(w[0])
		fx.preprocess = age if age >= 1.0 / 30.0 else 0.0
		fx.restart()


func _make_smoke(puff: bool) -> CPUParticles2D:
	if _smoke_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(0.5, 0.0)
		gt.width = 64
		gt.height = 64
		_smoke_tex = gt
	var fx := CPUParticles2D.new()
	fx.name = "_smoke_puff" if puff else "_smoke_wisp"
	fx.texture = _smoke_tex
	fx.local_coords = false
	fx.z_index = 50
	fx.amount = 40 if puff else 20
	fx.lifetime = 2.2 if puff else 2.6
	fx.direction = Vector2(0.9, -0.5) if puff else Vector2(0, -1)
	fx.spread = 18.0 if puff else 6.0
	fx.initial_velocity_min = 45.0 if puff else 14.0
	fx.initial_velocity_max = 75.0 if puff else 24.0
	fx.gravity = Vector2(0, -18) if puff else Vector2(4, -10)
	fx.damping_min = 15.0 if puff else 2.0
	fx.damping_max = 25.0 if puff else 4.0
	fx.scale_amount_min = 0.55 if puff else 0.14
	fx.scale_amount_max = 0.9 if puff else 0.22
	var c := Curve.new()
	c.add_point(Vector2(0, 0.4))
	c.add_point(Vector2(1, 1.0 if not puff else 1.0))
	c.max_value = 1.0
	fx.scale_amount_curve = c
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.85, 0.85, 0.88, 0.0))
	ramp.add_point(0.1, Color(0.9, 0.9, 0.93, 0.75 if puff else 0.6))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.8, 0.8, 0.84, 0.0))
	fx.color_ramp = ramp
	fx.emitting = false
	if "use_fixed_seed" in fx:   # Godot 4.4+: the same smoke every time for the same pose (exports)
		fx.set("use_fixed_seed", true)
		fx.set("seed", 1234 if puff else 4321)
	add_child(fx)
	return fx


func _update_emote_anim_index() -> void:
	# emoteAnimIndex of the playing animation at its current time (-1 when it has none,
	# which is what Unity's write-defaults gives).
	if animation_player != null and animation_player.assigned_animation != "":
		var keys = _emote_keys.get(data.get("animations", ""), {}).get(animation_player.assigned_animation)
		var v := -1.0
		if keys != null:
			var t := animation_player.current_animation_position
			for i in keys[0].size():
				if float(keys[0][i]) <= t + 0.0001:
					v = float(keys[1][i])
		emote_anim_index = v
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
	# HumanoidAssigner.AssignMuzzlePosition
	var muzzle: Node2D = parts.get(MUZZLE_LINKS.get(slot, ""))
	if muzzle != null:
		muzzle.position = _v2(weapon.muzzle) if weapon != null and weapon.get("muzzle") != null else Vector2.ZERO


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
	_rig_nodes.clear()
	_particles.clear()
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
		_rig_nodes[n.path] = n
		if n.get("particles") != null:
			_build_particles(n.path, node, n.particles)

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


# ================================================================== muzzle flashes

## A Unity particle system (CC2D only uses them for gun muzzle flashes) as CPUParticles2D.
## It plays when its node is shown (playOnAwake: the Shot clips switch the Muzzle object on and
## off once per shot).
func _build_particles(path: String, node: Node2D, p: Dictionary) -> void:
	var holder := Node2D.new()
	holder.name = "_particles"
	holder.rotation = _v2(p.direction).angle()    # emit along +X of the holder
	node.add_child(holder)
	var fx := CPUParticles2D.new()
	fx.name = "_fx"
	fx.emitting = false
	var burst := int(p.burst)
	var life: Array = p.lifetime
	fx.one_shot = not p.loop
	fx.amount = maxi(1, burst if burst > 0 else int(ceil(float(p.rate) * float(life[1]))))
	fx.explosiveness = 1.0 if burst > 0 else 0.0
	fx.lifetime = maxf(float(life[1]), 0.01)
	fx.lifetime_randomness = clampf(1.0 - float(life[0]) / fx.lifetime, 0.0, 1.0)
	fx.local_coords = p.local
	fx.direction = Vector2.RIGHT
	fx.spread = float(p.spread)
	fx.gravity = Vector2.ZERO
	fx.initial_velocity_min = float(p.speed[0])
	fx.initial_velocity_max = float(p.speed[1])
	if float(p.radius) > 0.0:
		fx.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		fx.emission_sphere_radius = float(p.radius)
	fx.z_index = int(p.z)
	fx.color = _col(p.color)
	if p.get("color_over_life") != null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array()
		g.colors = PackedColorArray()
		for k in p.color_over_life:
			g.add_point(float(k[0]), Color(k[1], k[2], k[3], k[4]))
		fx.color_ramp = g
	if p.get("texture") != null:
		var stretch: bool = p.get("render_mode", "") == "Stretch"
		var length := absf(float(p.get("length_scale", 1.0))) if stretch else 1.0
		var forward = null
		if stretch:
			forward = float(p.get("length_scale", 1.0)) < 0.0
		var tex := _flash_texture(p.texture, length, forward)
		fx.texture = tex
		var art := float(tex.get_height())    # Unity's quad is size x size (x |lengthScale| along the motion)
		fx.scale_amount_min = float(p.size[0]) / art
		fx.scale_amount_max = float(p.size[1]) / art
	if p.get("additive", false):
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		fx.material = m
	holder.add_child(fx)
	_particles[path] = {"node": node, "fx": fx, "shown": false, "cycle": -1}


## Unity draws a stretched billboard from the particle's position along its velocity (forward,
## for a negative lengthScale) and CPUParticles2D draws textures centred, so: pad the texture
## with transparency on the other side, so its centre is the art's back (or front) edge.
## forward: true / false = stretched forward / backward, null = not stretched (as is).
static func _flash_texture(path: String, length: float, forward) -> Texture2D:
	var key := "%s|%s|%s" % [path, length, forward]
	if _flash_textures.has(key):
		return _flash_textures[key]
	var src: Texture2D = _tex(path)
	if forward == null or src == null:
		_flash_textures[key] = src
		return src
	var img := src.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var w := maxi(1, int(round(img.get_width() * length)))
	if w != img.get_width():
		img.resize(w, img.get_height(), Image.INTERPOLATE_BILINEAR)
	var out := Image.create(w * 2, img.get_height(), false, Image.FORMAT_RGBA8)
	out.blit_rect(img, Rect2i(0, 0, w, img.get_height()), Vector2i(w if forward else 0, 0))
	var tex := ImageTexture.create_from_image(out)
	_flash_textures[key] = tex
	return tex


## Restart a flash when its node is switched on, and again when a looping Shot clip comes round
## (Rapid Shot's "off" frame can be shorter than a frame).
func _update_particles() -> void:
	var cycle := int(floor(_aim_phase)) if aim_state != "" else -1
	for path in _particles:
		var e: Dictionary = _particles[path]
		var shown: bool = e.node.is_visible_in_tree()
		if shown and (not e.shown or cycle != e.cycle):
			e.fx.preprocess = 0.0
			e.fx.restart()
		e.shown = shown
		e.cycle = cycle


## Fire the muzzle flash of a hand by hand ("MainHand" / "OffHand"), outside of the Shot clips.
func muzzle_flash(slot := "MainHand") -> void:
	var e = _particles.get(MUZZLE_LINKS.get(slot, ""))
	if e == null:
		return
	e.node.visible = true
	e.fx.preprocess = 0.0
	e.fx.restart()
	e.shown = true


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
	var key := anim_path + "|" + rig_path + "|" + ",".join(_extra_anim_files)
	var anim_data := _anim_data_for(anim_path, body_type)
	_sprite_tables[anim_path] = anim_data.get("sprites", [])
	if not _emote_keys.has(anim_path):
		var keys := {}
		var anims: Dictionary = anim_data.get("animations", {})
		for anim_name in anims:
			for tr in anims[anim_name].tracks:
				if tr.prop == "emote_anim_index":
					keys[anim_name] = [tr.times, tr.values]
		_emote_keys[anim_path] = keys
	if not _library_cache.has(key):
		_library_cache[key] = _build_library(anim_data, rig)
	animation_player.add_animation_library("", _library_cache[key])
	# Aim layer overrides the base animation after it has been applied each frame.
	animation_player.mixer_applied.connect(_apply_aim)


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
			if tr.prop == "sprite":
				_add_sprite_track(anim, tr.path, tr.times, tr.values)
				continue
			if tr.prop == "emote_anim_index":
				continue  # read directly from the playing animation in _process
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
			if prop == "sprite":
				_add_sprite_track(anim, path, [0.0], [-2])  # restore the rig's sprite
			elif base.has(path):
				_add_track(anim, path, prop, [0.0], [_rest_value(base[path], prop)], 0.0)
			elif prop == "emote_anim_index":
				pass
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


static func _add_sprite_track(anim: Animation, path: String, times: Array, values: Array) -> void:
	var idx := anim.add_track(Animation.TYPE_METHOD)
	anim.track_set_path(idx, NodePath("."))
	for i in times.size():
		anim.track_insert_key(idx, times[i], {"method": "_anim_sprite", "args": [path, int(values[i])]})


static func _track_path(path: String, prop: String) -> NodePath:
	if prop == "alpha":
		return NodePath("%s/_sprite:self_modulate:a" % path)
	return NodePath("%s:%s" % [path, prop])


static func _add_track(anim: Animation, path: String, prop: String, times: Array, values: Array, turn: float) -> void:
	var idx := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(idx, _track_path(path, prop))
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
		"alpha":
			return n.sprite.color[3] if n.has("sprite") else 1.0
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
