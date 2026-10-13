## Demo UI for runtime part swapping.
## Tab / Shift+Tab: choose slot   W/S or Up/Down: previous/next part
## C: random colours for the slot   R: random outfit   X: unequip slot   B: male/female
extends CanvasLayer

@export var character_path: NodePath = ^"../Player/Character"

const DEMO_SLOTS := ["Armor", "Pants", "Boots", "Gloves", "Helmet", "Hair", "FacialHair",
	"Eyebrow", "Eyes", "Mouth", "Nose", "Ear", "SkinDetails", "MainHand", "OffHand", "Cape", "Skirt"]

var slot_index := 0
var label: Label
@onready var character = get_node(character_path)


func _ready() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	add_child(panel)
	label = Label.new()
	label.add_theme_font_size_override("font_size", 18)
	panel.add_child(label)
	character.part_equipped.connect(func(_slot, _part): _refresh())
	character.character_loaded.connect(_refresh)
	character.body_type_changed.connect(func(_b): _refresh())
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
		_:
			return
	get_viewport().set_input_as_handled()
	_refresh()


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
	label.text = "Body: %s   [B]\nSlot: %s   [Tab]\nPart: %s   [W/S]  (%d options)\n[C] colours   [X] remove   [R] random outfit\n[A/D] walk   [Shift] run" % [
		character.body_type, slot, equipped if equipped != "" else "(none)", character.get_parts(slot).size()]
