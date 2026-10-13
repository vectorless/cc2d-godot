## Character creator for the CC2D Godot runtime (port of CC2D's Creator UI essentials).
## Pick parts per slot, colours, skin, body type and body sliders, preview expressions,
## animations and aiming, save/load CC2D CharacterData JSON (compatible with Unity), and export
## PNGs: a single image, a PNG sequence or a sprite sheet (CC2D's Export PNG screen).
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
var _exporter: CC2DExporter
var _export_mode: OptionButton
var _export_preset: OptionButton
var _export_fields := {}   # name -> SpinBox / OptionButton / CheckBox
var _export_dialog: FileDialog
var _export_button: Button
const EXPORT_MODES := ["Single image", "PNG sequence", "Sprite sheet"]


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

	_build_export_ui(box)

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


func _build_export_ui(box: VBoxContainer) -> void:
	_exporter = CC2DExporter.new()
	add_child(_exporter)
	_heading(box, "Export PNG")
	var row1 := _row(box)
	_export_preset = OptionButton.new()
	_export_preset.add_item("Custom")
	for pr in CC2DExporter.get_presets():
		_export_preset.add_item(pr.capitalize())
	_export_preset.item_selected.connect(func(i):
		if i > 0:
			_exporter.apply_preset(CC2DExporter.get_presets()[i - 1])
			_export_mode.select(int(_exporter.mode))
			_refresh_export())
	_labelled(row1, "Preset", _export_preset)
	_export_mode = OptionButton.new()
	for m in EXPORT_MODES:
		_export_mode.add_item(m)
	_labelled(row1, "As", _export_mode)

	var row2 := _row(box)
	_export_fields.width = _spin(row2, "W", 16, 4096, 1)
	_export_fields.height = _spin(row2, "H", 16, 4096, 1)
	_export_fields.fps = _spin(row2, "FPS", 1, 60, 1)
	var row3 := _row(box)
	_export_fields.x = _spin(row3, "X", -50, 50, 0.05)
	_export_fields.y = _spin(row3, "Y", -50, 50, 0.05)
	_export_fields.scale = _spin(row3, "Scale", 0.05, 10, 0.05)
	var row4 := _row(box)
	var bg := OptionButton.new()
	for b in CC2DExporter.Background.keys():
		bg.add_item(String(b).capitalize())
	bg.item_selected.connect(func(_i): _read_export())
	_labelled(row4, "Background", bg)
	_export_fields.bg = bg
	var sm := OptionButton.new()
	sm.add_item("Automatic")
	sm.add_item("Actual pixel size")
	sm.item_selected.connect(func(_i): _read_export())
	_labelled(row4, "Scale mode", sm)
	_export_fields.scale_mode = sm
	var row5 := _row(box)
	for flag in ["flip", "loop_aim"]:
		var cb := CheckBox.new()
		cb.text = "Flip" if flag == "flip" else "Loop aim layer"
		cb.toggled.connect(func(_on): _read_export())
		row5.add_child(cb)
		_export_fields[flag] = cb
	_export_button = _button(row5, "Export…", func():
		_export_dialog.current_dir = ProjectSettings.globalize_path("res://")
		_export_dialog.current_file = "%s.png" % character.current_animation.to_snake_case()
		_export_dialog.popup_centered(Vector2i(900, 600)))

	_export_dialog = FileDialog.new()
	_export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_export_dialog.use_native_dialog = true
	_export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_export_dialog.filters = PackedStringArray(["*.png ; PNG"])
	_export_dialog.file_selected.connect(_export_to)
	add_child(_export_dialog)
	_exporter.progress.connect(func(i, n): _status.text = "Exporting frame %d / %d…" % [i, n])
	_exporter.apply_preset("default")
	_refresh_export()


func _spin(row: HBoxContainer, label: String, lo: float, hi: float, step: float) -> SpinBox:
	var sb := SpinBox.new()
	sb.min_value = lo
	sb.max_value = hi
	sb.step = step
	sb.custom_minimum_size = Vector2(90, 0)
	sb.value_changed.connect(func(_v): _read_export())
	_labelled(row, label, sb)
	return sb


## Exporter settings -> UI.
func _refresh_export() -> void:
	_updating = true
	_export_fields.width.value = _exporter.width
	_export_fields.height.value = _exporter.height
	_export_fields.fps.value = _exporter.target_fps
	_export_fields.x.value = _exporter.char_position.x
	_export_fields.y.value = _exporter.char_position.y
	_export_fields.scale.value = _exporter.char_scale
	_export_fields.bg.select(int(_exporter.background))
	_export_fields.scale_mode.select(int(_exporter.scale_mode))
	_export_fields.flip.button_pressed = _exporter.flip
	_export_fields.loop_aim.button_pressed = _exporter.loop_aim_layer
	_updating = false


## UI -> exporter settings (any edit makes the preset "Custom", as in CC2D).
func _read_export() -> void:
	if _updating:
		return
	_exporter.width = int(_export_fields.width.value)
	_exporter.height = int(_export_fields.height.value)
	_exporter.target_fps = int(_export_fields.fps.value)
	_exporter.char_position = Vector2(_export_fields.x.value, _export_fields.y.value)
	_exporter.char_scale = _export_fields.scale.value
	_exporter.background = _export_fields.bg.selected as CC2DExporter.Background
	_exporter.scale_mode = _export_fields.scale_mode.selected as CC2DExporter.ScaleMode
	_exporter.flip = _export_fields.flip.button_pressed
	_exporter.loop_aim_layer = _export_fields.loop_aim.button_pressed
	_export_preset.select(0)


func _export_to(path: String) -> void:
	var anim := character.current_animation
	var aim := character.aim_state
	_export_button.disabled = true
	match _export_mode.selected:
		0:
			var err := await _exporter.export_image(character, path)
			_status.text = ("Saved " if err == OK else "Couldn't save ") + path
		1:
			var files := await _exporter.export_sequence(character, path, anim, aim)
			_status.text = "Saved %d frames: %s … %s" % [files.size(), files[0].get_file() if files.size() > 0 else "", files[-1].get_file() if files.size() > 0 else ""]
		2:
			var sheet := await _exporter.export_sheet(character, path, anim, aim)
			_status.text = "Saved a %dx%d sprite sheet (%d frames of %dx%d) to %s, with a .json next to it" % [
				sheet.get_width(), sheet.get_height(), _exporter.frame_count(character, anim, aim), _exporter.width, _exporter.height, path]
	_export_button.disabled = false


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
	var package := character.get_equipped_package(slot)
	var sel := 0
	var parts := character.get_parts(slot)
	var seen := {}
	for p in parts:
		seen[p.name] = seen.get(p.name, 0) + 1
	for p in parts:
		# the same name in several packs ("Gun 00"): say which pack
		var label: String = p.name if seen[p.name] == 1 else "%s (%s)" % [p.name, p.package]
		var idx := _parts_list.add_item(label, _thumb(p))
		_parts_list.set_item_metadata(idx, p)
		_parts_list.set_item_tooltip(idx, "%s / %s" % [p.package, p.name])
		if p.name == equipped and p.package == package:
			sel = idx
	_parts_list.select(sel)
	_parts_list.ensure_current_is_visible()
	_part_label.text = "%s (%s)" % [equipped, package] if equipped != "" else "(none)"
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
