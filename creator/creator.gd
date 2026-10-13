## Character creator for the CC2D Godot runtime (port of CC2D's Creator UI essentials).
## Pick parts per slot, colours, skin, body type and body sliders, preview expressions,
## animations and aiming, and save/load CC2D CharacterData JSON (compatible with Unity).
extends Node2D

const PANEL_WIDTH := 470
const EDIT_SLOTS := ["Hair", "Eyebrow", "Eyes", "Nose", "Mouth", "Ear", "FacialHair", "SkinDetails", "BodySkin",
	"Helmet", "Armor", "Gloves", "Pants", "Boots", "Cape", "Skirt", "MainHand", "OffHand"]
const RANDOM_SLOTS := ["Hair", "Eyebrow", "Eyes", "Mouth", "Armor", "Gloves", "Pants", "Boots", "MainHand", "OffHand"]

@onready var character: CC2DCharacter = $Character
@onready var camera: Camera2D = $Camera2D

var slot := "Armor"
var _slot_option: OptionButton
var _parts_list: ItemList
var _part_label: Label
var _color_buttons: Array[ColorPickerButton] = []
var _body_option: OptionButton
var _skin_button: ColorPickerButton
var _tint_button: ColorPickerButton
var _anim_option: OptionButton
var _aim_option: OptionButton
var _aim_slider: HSlider
var _sliders := {}  # segment -> [HSlider x, HSlider y]
var _file_dialog: FileDialog
var _status: Label
var _thumbs := {}
var _updating := false


func _ready() -> void:
	_build_ui()
	character.part_equipped.connect(func(s, _p):
		if s == slot:
			_refresh_slot())
	character.body_type_changed.connect(func(_b): _refresh_all())
	_refresh_all()


# ------------------------------------------------------------------ UI construction

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2.ZERO
	panel.size = Vector2(PANEL_WIDTH, get_viewport_rect().size.y)
	layer.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)

	_heading(box, "Character Creator")

	# body
	var body_row := _row(box)
	_body_option = OptionButton.new()
	for b in CC2DCharacter.BODY_TYPES:
		_body_option.add_item(b)
	_body_option.item_selected.connect(func(i):
		if not _updating:
			character.set_body_type(CC2DCharacter.BODY_TYPES[i]))
	_labelled(body_row, "Body", _body_option)
	_skin_button = _color_button(func(c): character.set_skin_color(c))
	_labelled(body_row, "Skin", _skin_button)
	_tint_button = _color_button(func(c): character.set_tint_color(c))
	_labelled(body_row, "Tint", _tint_button)

	# parts
	_heading(box, "Parts")
	_slot_option = OptionButton.new()
	for s in EDIT_SLOTS:
		_slot_option.add_item(s)
	_slot_option.select(EDIT_SLOTS.find(slot))
	_slot_option.item_selected.connect(func(i):
		slot = EDIT_SLOTS[i]
		_refresh_slot())
	var slot_row := _row(box)
	_labelled(slot_row, "Slot", _slot_option)
	_part_label = Label.new()
	slot_row.add_child(_part_label)

	_parts_list = ItemList.new()
	_parts_list.custom_minimum_size = Vector2(0, 250)
	_parts_list.max_columns = 0
	_parts_list.same_column_width = true
	_parts_list.icon_mode = ItemList.ICON_MODE_TOP
	_parts_list.fixed_icon_size = Vector2i(64, 64)
	_parts_list.fixed_column_width = 78
	_parts_list.item_selected.connect(_on_part_selected)
	box.add_child(_parts_list)

	var color_row := _row(box)
	color_row.add_child(_small_label("Colours"))
	for i in 3:
		var idx: int = i
		var b := _color_button(func(_c): _on_part_color_changed(idx))
		_color_buttons.append(b)
		color_row.add_child(b)
	var rand_colors := Button.new()
	rand_colors.text = "Random"
	rand_colors.pressed.connect(func():
		character.set_part_color(slot, _rand_color(), _rand_color(), _rand_color())
		_refresh_slot())
	color_row.add_child(rand_colors)

	# expressions
	_heading(box, "Expression")
	var emo_row := _row(box)
	for e in ["Blink", "Attack", "Hurt", "Talk"]:
		var emo_name: String = e
		_button(emo_row, e, func(): character.emote(emo_name, 1.5))
	_button(emo_row, "Reset", func(): character.reset_emote())

	# animation + aim
	_heading(box, "Animation")
	var anim_row := _row(box)
	_anim_option = OptionButton.new()
	_anim_option.item_selected.connect(func(i): character.play(_anim_option.get_item_text(i)))
	anim_row.add_child(_anim_option)
	_button(anim_row, "Replay", func():
		character.current_animation = ""
		character.play(_anim_option.get_item_text(_anim_option.selected), 0.0))
	var aim_row := _row(box)
	_aim_option = OptionButton.new()
	_aim_option.item_selected.connect(func(i):
		var st := _aim_option.get_item_text(i)
		character.play_aim("" if st == "None" else st))
	_labelled(aim_row, "Aim", _aim_option)
	_aim_slider = HSlider.new()
	_aim_slider.min_value = -1.0
	_aim_slider.max_value = 1.0
	_aim_slider.step = 0.01
	_aim_slider.custom_minimum_size = Vector2(150, 0)
	_aim_slider.value_changed.connect(func(v): character.set_aim(v))
	aim_row.add_child(_aim_slider)

	# body sliders
	_heading(box, "Body sliders")
	var grid := GridContainer.new()
	grid.columns = 3
	box.add_child(grid)
	for seg in CC2DCharacter.SEGMENTS:
		var segment: String = seg
		grid.add_child(_small_label(seg))
		var pair := []
		for axis in 2:
			var ax: int = axis
			var sl := HSlider.new()
			sl.min_value = 0.0
			sl.max_value = 1.0
			sl.step = 0.01
			sl.value = 0.5
			sl.custom_minimum_size = Vector2(170, 0)
			sl.tooltip_text = "width" if axis == 0 else "length"
			sl.value_changed.connect(func(_v): _on_slider_changed(segment, ax))
			grid.add_child(sl)
			pair.append(sl)
		_sliders[segment] = pair

	# actions
	_heading(box, "Character")
	var act_row := _row(box)
	_button(act_row, "Randomise", _randomise)
	_button(act_row, "Reset sliders", func():
		for seg in CC2DCharacter.SEGMENTS:
			character.set_body_slider(seg, Vector2(0.5, 0.5))
		_refresh_sliders())
	var file_row := _row(box)
	_button(file_row, "Save JSON…", func(): _open_dialog(FileDialog.FILE_MODE_SAVE_FILE))
	_button(file_row, "Load JSON…", func(): _open_dialog(FileDialog.FILE_MODE_OPEN_FILE))
	_status = _small_label("Files use CC2D's CharacterData format (Unity: CharacterViewer.LoadFromJSON).")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(PANEL_WIDTH - 30, 0)
	box.add_child(_status)

	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.use_native_dialog = true
	_file_dialog.filters = PackedStringArray(["*.json ; CC2D character"])
	_file_dialog.file_selected.connect(_on_file_selected)
	add_child(_file_dialog)


func _heading(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 18)
	parent.add_child(l)


func _row(parent: Control) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 6)
	parent.add_child(r)
	return r


func _small_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _labelled(row: HBoxContainer, text: String, control: Control) -> void:
	row.add_child(_small_label(text))
	row.add_child(control)


func _button(row: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	row.add_child(b)
	return b


func _color_button(cb: Callable) -> ColorPickerButton:
	var b := ColorPickerButton.new()
	b.custom_minimum_size = Vector2(44, 28)
	b.color_changed.connect(func(c):
		if not _updating:
			cb.call(c))
	return b


# ------------------------------------------------------------------ refresh

func _refresh_all() -> void:
	_updating = true
	_body_option.select(CC2DCharacter.BODY_TYPES.find(character.body_type))
	_skin_button.color = character.skin_color
	_tint_button.color = character.tint_color
	var current := _anim_option.get_item_text(_anim_option.selected) if _anim_option.item_count > 0 else ""
	_anim_option.clear()
	var names := character.get_animation_names()
	for n in names:
		_anim_option.add_item(n)
	var want := current if current != "" else character.current_animation
	for i in _anim_option.item_count:
		if _anim_option.get_item_text(i) == want:
			_anim_option.select(i)
	_aim_option.clear()
	_aim_option.add_item("None")
	for st in character.get_aim_states():
		if st != "None":
			_aim_option.add_item(st)
	_updating = false
	_refresh_slot()
	_refresh_sliders()


func _refresh_slot() -> void:
	_updating = true
	_parts_list.clear()
	_parts_list.add_item("(none)")
	var equipped := character.get_equipped(slot)
	var sel := 0
	for p in character.get_parts(slot):
		var idx := _parts_list.add_item(p.name, _thumb(p))
		_parts_list.set_item_metadata(idx, p)
		_parts_list.set_item_tooltip(idx, "%s / %s" % [p.package, p.name])
		if p.name == equipped:
			sel = idx
	_parts_list.select(sel)
	_parts_list.ensure_current_is_visible()
	_part_label.text = equipped if equipped != "" else "(none)"
	var cols := character.get_part_colors(slot)
	var single: bool = character.catalogue.get("colorable_links", {}).has(slot) or slot == "SkinDetails"
	for i in 3:
		_color_buttons[i].color = cols[i]
		_color_buttons[i].visible = not (slot in CC2DCharacter.SKIN_SLOTS) and (i == 0 or not single)
	_updating = false


func _refresh_sliders() -> void:
	_updating = true
	for seg in _sliders:
		var v := character.get_body_slider(seg)
		_sliders[seg][0].value = v.x
		_sliders[seg][1].value = v.y
	_updating = false


func _thumb(p: Dictionary) -> Texture2D:
	var key: String = p.package + "/" + p.name + "/" + slot
	if _thumbs.has(key):
		return _thumbs[key]
	var best = null
	var best_area := 0.0
	for sname in p.get("sprites", {}):
		var sd: Dictionary = p.sprites[sname]
		var area: float = sd.region[2] * sd.region[3]
		if area > best_area:
			best_area = area
			best = sd
	var tex: Texture2D = null
	if best != null:
		var at := AtlasTexture.new()
		at.atlas = load(best.texture)
		at.region = Rect2(best.region[0], best.region[1], best.region[2], best.region[3])
		tex = at
	elif p.get("texture") != null:
		tex = load(p.texture)  # capes / skirts / skin details: whole texture
	_thumbs[key] = tex
	return tex


# ------------------------------------------------------------------ actions

func _on_part_selected(index: int) -> void:
	if _updating:
		return
	var p = _parts_list.get_item_metadata(index)
	if p == null:
		character.equip_part(slot, "")
	else:
		character.equip_part(slot, p.name, p.package)
	_refresh_slot()


func _on_part_color_changed(_index: int) -> void:
	var c := [_color_buttons[0].color, _color_buttons[1].color, _color_buttons[2].color]
	character.set_part_color(slot, c[0], c[1], c[2])


func _on_slider_changed(segment: String, _axis: int) -> void:
	if _updating:
		return
	var pair: Array = _sliders[segment]
	character.set_body_slider(segment, Vector2(pair[0].value, pair[1].value))
	_refresh_sliders()  # symmetrical segments keep both axes equal


func _randomise() -> void:
	for s in RANDOM_SLOTS:
		var options: Array = character.get_parts(s)
		if options.is_empty():
			continue
		var p = options.pick_random()
		character.equip_part(s, p.name, p.package)
		character.set_part_color(s, _rand_color(), _rand_color(), _rand_color())
	for s in ["Cape", "Skirt", "Helmet", "FacialHair"]:
		var options: Array = character.get_parts(s)
		if randf() < 0.35 and not options.is_empty():
			var p = options.pick_random()
			character.equip_part(s, p.name, p.package)
			character.set_part_color(s, _rand_color(), _rand_color(), _rand_color())
		else:
			character.equip_part(s, "")
	character.set_skin_color(Color.from_hsv(randf_range(0.03, 0.09), randf_range(0.2, 0.6), randf_range(0.35, 1.0)))
	_refresh_all()


func _open_dialog(mode: FileDialog.FileMode) -> void:
	_file_dialog.file_mode = mode
	_file_dialog.current_dir = ProjectSettings.globalize_path("res://characters")
	if mode == FileDialog.FILE_MODE_SAVE_FILE:
		_file_dialog.current_file = "my_character.json"
	_file_dialog.popup_centered(Vector2i(900, 600))


func _on_file_selected(path: String) -> void:
	var err: Error
	if _file_dialog.file_mode == FileDialog.FILE_MODE_SAVE_FILE:
		err = character.save_character(path)
		_status.text = ("Saved " if err == OK else "Couldn't save ") + path
	else:
		err = character.load_character_data(path)
		_status.text = ("Loaded " if err == OK else "Couldn't load ") + path
		_refresh_all()


func _rand_color() -> Color:
	return Color.from_hsv(randf(), randf_range(0.2, 0.8), randf_range(0.25, 0.85))
