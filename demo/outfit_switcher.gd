## Demo UI for runtime part swapping.
## Tab / Shift+Tab: choose slot   W/S or Up/Down: previous/next part
## C: random colours for the slot   R: random outfit   X: unequip slot   B: male/female
## 1-4: Blink / Attack / Hurt / Talk face (1.5 s)   0: reset face
## T: "Talk 1" animation   H: "Hit"   K: "Attack Main Hand 1"  (these drive the face too)
## Esc or the "Character Creator" button (top right): back to the creator, with this character.
extends CanvasLayer

## The creator hands its character over through this Engine meta key (see creator/creator.gd).
const SHARED_META := "cc2d_shared_character"
const CREATOR_SCENE := "res://creator/creator.tscn"

@export var character_path: NodePath = ^"../Player/Character"

const DEMO_SLOTS := ["Armor", "Pants", "Boots", "Gloves", "Helmet", "Hair", "FacialHair",
	"Eyebrow", "Eyes", "Mouth", "Nose", "Ear", "SkinDetails", "MainHand", "OffHand", "Cape", "Skirt"]

var slot_index := 0
var label: Label
@export var walker_path: NodePath = ^"../Player"
@onready var character = get_node(character_path)
@onready var walker = get_node(walker_path)
@export var camera_path: NodePath = ^"../Camera2D"
@onready var camera: Camera2D = get_node_or_null(camera_path)


func _ready() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	add_child(panel)
	label = Label.new()
	label.add_theme_font_size_override("font_size", 18)
	panel.add_child(label)
	var back := Button.new()
	back.text = "  Character Creator  "
	back.add_theme_font_size_override("font_size", 18)
	back.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	back.offset_left = -240
	back.offset_top = 16
	back.offset_right = -16
	back.offset_bottom = 58
	back.focus_mode = Control.FOCUS_NONE
	back.tooltip_text = "Back to the character creator with this character"
	back.pressed.connect(go_to_creator)
	add_child(back)
	# custom part packs, and the character from the creator if we came from there
	if DirAccess.dir_exists_absolute("res://custom"):
		for d in DirAccess.get_directories_at("res://custom"):
			if FileAccess.file_exists("res://custom/%s/parts.json" % d):
				CC2DCharacter.add_part_pack("res://custom/%s/parts.json" % d)
	if Engine.has_meta(SHARED_META):
		character.apply_character_data(Engine.get_meta(SHARED_META))
	character.part_equipped.connect(func(_slot, _part): _refresh())
	character.character_loaded.connect(_refresh)
	character.body_type_changed.connect(func(_b): _refresh())
	character.emote_changed.connect(func(_e): _refresh())
	_refresh.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var slot: String = DEMO_SLOTS[slot_index]
	match event.physical_keycode:
		KEY_TAB:
			slot_index = posmod(slot_index + (-1 if event.shift_pressed else 1), DEMO_SLOTS.size())
		KEY_W, KEY_UP:
			character.cycle_part(slot, 1)
		KEY_S, KEY_DOWN:
			character.cycle_part(slot, -1)
		KEY_X:
			character.equip_part(slot, "")
		KEY_C:
			character.set_part_color(slot, _rand_color(), _rand_color(), _rand_color())
		KEY_R:
			randomize_outfit()
		KEY_B:
			character.set_body_type("Female" if character.body_type == "Male" else "Male")
		KEY_1:
			character.emote("Blink", 1.5)
		KEY_2:
			character.emote("Attack", 1.5)
		KEY_3:
			character.emote("Hurt", 1.5)
		KEY_4:
			character.emote("Talk", 1.5)
		KEY_0:
			character.reset_emote()
		KEY_Z:
			if camera:
				var close := camera.zoom.x < 2.0
				camera.zoom = Vector2(5, 5) if close else Vector2.ONE
				camera.position.y = -335.0 if close else -250.0
		KEY_ESCAPE:
			go_to_creator()
			return
		KEY_T:
			walker.play_action("Talk 1")
		KEY_H:
			walker.play_action("Hit")
		KEY_K:
			walker.play_action("Attack Main Hand 1")
		_:
			return
	get_viewport().set_input_as_handled()
	_refresh()


## Back to the character creator, taking this character along.
func go_to_creator() -> void:
	Engine.set_meta(SHARED_META, character.get_character_data())
	get_tree().change_scene_to_file(CREATOR_SCENE)


func randomize_outfit() -> void:
	for slot in ["Armor", "Pants", "Boots", "Gloves", "Hair", "Eyebrow", "Eyes", "Mouth", "MainHand", "OffHand"]:
		var options: Array = character.get_parts(slot)
		if options.is_empty():
			continue
		var p = options.pick_random()
		character.equip_part(slot, p.name, p.package)
		character.set_part_color(slot, _rand_color(), _rand_color(), _rand_color())
	for slot in ["Cape", "Skirt"]:
		var options: Array = character.get_parts(slot)
		if randf() < 0.5 and not options.is_empty():
			var p = options.pick_random()
			character.equip_part(slot, p.name, p.package)
			character.set_part_color(slot, _rand_color(), _rand_color(), _rand_color())
		else:
			character.equip_part(slot, "")
	character.equip_part("Helmet", "")


func _rand_color() -> Color:
	return Color.from_hsv(randf(), randf_range(0.2, 0.8), randf_range(0.25, 0.85))


func _refresh() -> void:
	if label == null or character == null:
		return
	var slot: String = DEMO_SLOTS[slot_index]
	var equipped: String = character.get_equipped(slot)
	if equipped != "":
		equipped += " (%s)" % character.get_equipped_package(slot)
	label.text = "Body: %s   [B]\nSlot: %s   [Tab]\nPart: %s   [W/S]  (%d options)\n[C] colours   [X] remove   [R] random outfit\nFace: %s   [1] blink [2] attack [3] hurt [4] talk [0] reset\n[T] talk anim  [H] hit  [K] attack  [Z] zoom face   [A/D] walk  [Shift] run\n[Esc] back to the character creator" % [
		character.body_type, slot, equipped if equipped != "" else "(none)", character.get_parts(slot).size(),
		character.current_emote if character.current_emote != "" else "default"]
