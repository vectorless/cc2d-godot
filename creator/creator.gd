## Character creator for the CC2D Godot runtime: a port of CC2D's Creator UI (the Unity
## "Creator UI" scene), operable with the mouse alone.
##
## Layout, as in Unity: a top bar of menus (File | Body | Face | Equipment | Weapon | Gun), the
## menu's categories on the left, the chosen category's parts (thumbnails grouped by pack, with a
## search box and a pack filter), the character in the middle (zoom, background, Base Layer and
## Aim Layer animation selectors), and the COLOR panel on the right (the part's colour slots, a
## colour picker and CC2D's colour palettes). File > Export PNG is CC2D's Export PNG screen.
##
## Custom part packs (res://custom/<pack>/parts.json) are added at startup. Picking a custom part
## that carries "colors" applies its designed colours (CC2D's own parts keep the slot's colours).
extends Node2D

const ICON_DIR := "res://creator/icons/"
const BG_DIR := "res://creator/backgrounds/"
const PALETTE_FILE := "res://creator/palettes.json"
const CUSTOM_DIR := "res://custom"
const THUMB_DIR := "user://cc2d_thumbs/"
const DEMO_SCENE := "res://demo/walk_demo.tscn"
## The character is handed between the creator and the walk demo through this Engine meta key.
const SHARED_META := "cc2d_shared_character"
const PACKAGE_ORDER := ["Base", "Emote", "Fantasy", "Daily", "Post Apocalyptic", "Undead"]
## Creator UI/Animation List/Base Layer.asset: the order Unity's animation selector uses.
const BASE_LAYER_ORDER := ["Idle", "Walk", "Run", "Sprint", "Jump", "Fall", "Hit", "Die",
	"Attack Main Hand 1", "Attack Main Hand 2", "Attack Main Hand 3", "Attack Off Hand 1",
	"Attack Off Hand 2", "Attack Off Hand 3", "Attack Both Hand 1", "Attack Both Hand 2",
	"Attack Both Hand 3", "Attack Two Handed 1", "Attack Two Handed 2", "Attack Two Handed 3",
	"Cast 1", "Cast 2", "Shield Ready", "Shield Block", "Attack Punch 1", "Attack Punch 2",
	"Attack Punch 3", "Attack Kick 1", "Attack Kick 2", "Give", "Receive", "Push", "Pull",
	"Talk 1", "Talk 2", "Talk 3", "Crouch", "Walk Back", "Run Back", "Climb Up", "Climb Down",
	"Swim", "Idle Swim", "Idle Holding Rifle"]
const EXPORT_MODES := ["Single image", "PNG sequence", "Sprite sheet"]
## Background changer: CC2D's backgrounds, then plain colours.
const BACKGROUNDS := ["background1.png", "background2.png", "background3.png", "background4.png",
	"background5.png", "background6.png", "#23272e", "#8cc7f2", "#f2f2f2", "#00b140"]

const TOP_H := 80.0
const RAIL_W := 168.0
const CONTENT_W := 344.0
const COLOR_W := 290.0
const BOTTOM_H := 136.0          # animation controls under the character
const TILE_SIZE := Vector2(98, 114)
const THUMB_PX := 128

const C_TEXT := Color(0.88, 0.9, 0.93)
const C_DIM := Color(0.56, 0.6, 0.66)
const C_ACCENT := Color(0.98, 0.68, 0.26)
const C_PANEL := Color(0.065, 0.075, 0.09, 0.86)

## Menus of the top bar and the categories each one lists (as in Unity's Creator UI).
const MENUS := [
	{"id": "file", "title": "File", "icon": "menu", "cats": ["new", "clear", "open", "save", "export", "demo"]},
	{"id": "body", "title": "Body", "icon": "body", "cats": ["body", "skin_details", "sliders", "randomize"]},
	{"id": "face", "title": "Face", "icon": "face", "cats": ["hair", "eyebrow", "eyes", "nose", "mouth", "ear", "facial_hair", "emotion"]},
	{"id": "equipment", "title": "Equipment", "icon": "armor", "cats": ["helmet", "armor", "pants", "skirt", "gloves", "boots", "cape"]},
	{"id": "weapon", "title": "Weapon", "icon": "sword", "cats": ["main_hand", "off_hand", "two_handed", "shield", "bow"]},
	{"id": "gun", "title": "Gun", "icon": "gun", "cats": ["gun_main", "gun_off", "rifle"]},
]
## kind: action (runs something), parts (thumbnail grid for `slot`, optionally only `weapons`),
## sliders, randomize, emotion, export.
const CATS := {
	"new": {"title": "New", "icon": "plus", "kind": "action", "tip": "Start again from the default character"},
	"clear": {"title": "Clear All Items", "icon": "clear", "kind": "action", "tip": "Take off all clothing and weapons (body and face stay)"},
	"open": {"title": "Open JSON", "icon": "open_json", "kind": "action", "tip": "Load a CC2D CharacterData JSON (Unity's CharacterViewer files work too)"},
	"save": {"title": "Save As JSON", "icon": "save_json", "kind": "action", "tip": "Save as CC2D CharacterData JSON (Unity can load it)"},
	"export": {"title": "Export PNG", "icon": "png", "kind": "export", "tip": "Single image, PNG sequence or sprite sheet"},
	"demo": {"title": "Walk Demo", "icon": "play", "kind": "action", "tip": "Walk around with this character"},
	"body": {"title": "Body", "icon": "body", "kind": "parts", "slot": "BodySkin"},
	"skin_details": {"title": "Skin Details", "icon": "tattoo", "kind": "parts", "slot": "SkinDetails"},
	"sliders": {"title": "Body Sliders", "icon": "slider", "kind": "sliders"},
	"randomize": {"title": "Randomize", "icon": "dice", "kind": "randomize"},
	"hair": {"title": "Hair", "icon": "hair", "kind": "parts", "slot": "Hair"},
	"eyebrow": {"title": "Eyebrow", "icon": "eyebrow", "kind": "parts", "slot": "Eyebrow"},
	"eyes": {"title": "Eyes", "icon": "eyes", "kind": "parts", "slot": "Eyes"},
	"nose": {"title": "Nose", "icon": "nose", "kind": "parts", "slot": "Nose"},
	"mouth": {"title": "Mouth", "icon": "mouth", "kind": "parts", "slot": "Mouth"},
	"ear": {"title": "Ear", "icon": "ear", "kind": "parts", "slot": "Ear"},
	"facial_hair": {"title": "Facial Hair", "icon": "facial_hair", "kind": "parts", "slot": "FacialHair"},
	"emotion": {"title": "Emotion", "icon": "emote", "kind": "emotion"},
	"helmet": {"title": "Helmet", "icon": "helmet", "kind": "parts", "slot": "Helmet"},
	"armor": {"title": "Armor", "icon": "armor", "kind": "parts", "slot": "Armor"},
	"pants": {"title": "Pants", "icon": "pants", "kind": "parts", "slot": "Pants"},
	"skirt": {"title": "Skirt", "icon": "skirt", "kind": "parts", "slot": "Skirt"},
	"gloves": {"title": "Gloves", "icon": "gloves", "kind": "parts", "slot": "Gloves"},
	"boots": {"title": "Boots", "icon": "boots", "kind": "parts", "slot": "Boots"},
	"cape": {"title": "Cape", "icon": "cape", "kind": "parts", "slot": "Cape"},
	"main_hand": {"title": "Main Hand", "icon": "sword_r", "kind": "parts", "slot": "MainHand", "weapons": ["OneHanded"]},
	"off_hand": {"title": "Off Hand", "icon": "sword_l", "kind": "parts", "slot": "OffHand", "weapons": ["OneHanded"]},
	"two_handed": {"title": "Two Handed", "icon": "sword", "kind": "parts", "slot": "MainHand", "weapons": ["TwoHanded"]},
	"shield": {"title": "Shield", "icon": "shield", "kind": "parts", "slot": "OffHand", "weapons": ["Shield"]},
	"bow": {"title": "Bow", "icon": "bow", "kind": "parts", "slot": "OffHand", "weapons": ["Bow"]},
	"gun_main": {"title": "Main Hand", "icon": "gun_r", "kind": "parts", "slot": "MainHand", "weapons": ["Gun"]},
	"gun_off": {"title": "Off Hand", "icon": "gun_l", "kind": "parts", "slot": "OffHand", "weapons": ["Gun"]},
	"rifle": {"title": "Rifle", "icon": "rifle", "kind": "parts", "slot": "MainHand", "weapons": ["Rifle"]},
}
## UICreator._RANDSETTINGS: chance (%) that Randomize fills each slot.
const RAND_CHANCE := {"Armor": 100, "Boots": 100, "Cape": 40, "Ear": 40, "Eyebrow": 98, "Eyes": 100,
	"FacialHair": 50, "Gloves": 60, "Hair": 90, "Helmet": 70, "MainHand": 50, "Mouth": 100, "Nose": 100,
	"OffHand": 50, "Pants": 100, "SkinDetails": 40, "Skirt": 20, "BodySkin": 20}
## UIRandomizeCharacter's groups.
const FACE_SLOTS := ["Ear", "Eyebrow", "Eyes", "FacialHair", "Hair", "Mouth", "Nose"]
const OUTFIT_SLOTS := ["Armor", "Boots", "Cape", "Gloves", "Helmet", "Pants", "Skirt"]
const WEAPON_SLOTS := ["MainHand", "OffHand"]
const SLOT_TITLES := {"FacialHair": "Facial hair", "SkinDetails": "Skin details", "BodySkin": "Body skin",
	"MainHand": "Main hand", "OffHand": "Off hand"}

@onready var character: CC2DCharacter = $Character
@onready var camera: Camera2D = $Camera2D

var menu := ""
var cat := ""
var slot := ""                    ## the slot the parts grid and the COLOR panel edit ("" = none)
var custom_packages: Array[String] = []

var _last_cat := {"equipment": "armor"}   # menu id -> last category
var _palettes: Array = []         # [{name, colors: Array[Color]}]
var _recent: Array[Color] = []
var _clip_color := Color(0, 0, 0, 0)
var _updating := false
var _dirty := false               # equipment changed: refresh selection + colours next frame
var _rebuild := false             # body type changed: rebuild the page next frame
var _default_data := {}
var _zoom := 1.0
var _pan := Vector2.ZERO
var _bg_index := 0
var _color_index := 0
var _cmode := ""                  # COLOR panel: "" | "part" | "skin" | "body"
var _emotion := ""
var _recent_timer := 0.0

# thumbnails
var _thumbs := {}                 # key -> {tex, mask}
var _thumb_queue: Array = []      # [TextureRect, part, slot]
var _tiles: Array = []            # [{button, rect, part, slot}]
var _sections := {}               # package -> {header, flow, tiles, count}
var _collapsed := {}              # package -> true
var _search := ""
var _pack_filter := ""

# ui
var _theme: Theme
var _bold: FontVariation
var _bg_rect: TextureRect
var _bg_color: ColorRect
var _menu_buttons := {}
var _rail_box: VBoxContainer
var _rail_rows := {}              # cat -> {button, icon, label}
var _header_icon: TextureRect
var _header_title: Label
var _header_sub: Label
var _pages := {}
var _body_row: HBoxContainer
var _body_buttons := {}
var _parts_caption: Label
var _search_edit: LineEdit
var _pack_option: OptionButton
var _parts_scroll: ScrollContainer
var _parts_list: VBoxContainer
var _slider_rows := {}            # segment -> [HSlider, HSlider or null, Label]
var _rand_checks := {}
var _rand_pack_box: HFlowContainer
var _emotion_box: VBoxContainer
var _stage: Control
var _status: Label
var _zoom_slider: HSlider
var _anim_option: OptionButton
var _aim_option: OptionButton
var _aim_slider: HSlider
var _aim_row: HBoxContainer
var _anim_names: Array = []
var _aim_names: Array = []
# COLOR panel
var _color_info: Label
var _swatches: Array[Button] = []
var _swatch_labels: Array[Label] = []
var _swatch_box: HBoxContainer
var _picker: ColorPicker
var _opacity_row: HBoxContainer
var _opacity: HSlider
var _palette_box: VBoxContainer
var _palette_option: OptionButton
var _palette_flow: HFlowContainer
var _recent_flow: HFlowContainer
var _color_actions: HFlowContainer
var _btn_pack_colors: Button
var _btn_copy_hair: Button
var _btn_copy_skin: Button
# dialogs
var _file_dialog: FileDialog
var _file_cb := Callable()
var _confirm: ConfirmationDialog
# export
var _exporter: CC2DExporter
var _export_mode: OptionButton
var _export_preset: OptionButton
var _export_fields := {}          # name -> SpinBox / OptionButton / CheckBox
var _export_button: Button
var _export_info: Label
var _export_preview: TextureRect


func _ready() -> void:
	_load_custom_packs()
	_load_palettes()
	_default_data = character.get_character_data()
	if Engine.has_meta(SHARED_META):   # coming back from the walk demo
		character.apply_character_data(Engine.get_meta(SHARED_META))
	_build_ui()
	character.part_equipped.connect(func(_s, _p): _dirty = true)
	character.body_type_changed.connect(func(_b): _rebuild = true)
	_refresh_animation_lists()
	open_menu("equipment")
	_set_background(0)


func _process(delta: float) -> void:
	_layout_camera()
	if _rebuild:
		_rebuild = false
		_dirty = false
		_show_category(cat)
		_refresh_animation_lists()
	elif _dirty:
		_dirty = false
		_refresh_selection()
	_process_thumbs()
	if _recent_timer > 0.0:
		_recent_timer -= delta
		if _recent_timer <= 0.0:
			_push_recent(_picker.color)


## True while part thumbnails are still being made (tests wait for this).
func is_busy() -> bool:
	return not _thumb_queue.is_empty()


# ================================================================== data

## Adds every pack in res://custom to the catalogue. Returns how many parts were new.
func _load_custom_packs() -> int:
	custom_packages.clear()
	var added := 0
	if not DirAccess.dir_exists_absolute(CUSTOM_DIR):
		return 0
	for d in DirAccess.get_directories_at(CUSTOM_DIR):
		var path := "%s/%s/parts.json" % [CUSTOM_DIR, d]
		if not FileAccess.file_exists(path):
			continue
		added += CC2DCharacter.add_part_pack(path)
		var pack = JSON.parse_string(FileAccess.get_file_as_string(path))
		if pack is Dictionary:
			var pkg := str(pack.get("package", d.capitalize()))
			for category in pack.get("categories", {}):
				for p in pack.categories[category]:
					pkg = str(p.get("package", pkg))
					break
				break
			if not custom_packages.has(pkg):
				custom_packages.append(pkg)
	return added


## Packs generated while the creator is open show up when you come back to the window.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and is_node_ready():
		var n := _load_custom_packs()
		if n > 0:
			_rebuild = true
			_toast("%d new part%s found in custom packs" % [n, "" if n == 1 else "s"])


func _load_palettes() -> void:
	_palettes.clear()
	var d = JSON.parse_string(FileAccess.get_file_as_string(PALETTE_FILE)) if FileAccess.file_exists(PALETTE_FILE) else null
	if not (d is Dictionary):
		return
	for p in d.get("palettes", []):
		var cols: Array[Color] = []
		for c in p.colors:
			cols.append(Color(c[0], c[1], c[2], c[3] if c.size() > 3 else 1.0))
		_palettes.append({"name": p.name, "colors": cols})


func _pal(pal_name: String) -> Array:
	for p in _palettes:
		if p.name == pal_name:
			return p.colors.duplicate()
	return [Color.GRAY]


## Every package the catalogue has, CC2D's first, then the custom packs.
func _all_packages() -> Array:
	var seen := {}
	for list in character.catalogue.get("categories", {}).values():
		for p in list:
			seen[p.package] = true
	return _order_packages(seen.keys())


func _order_packages(pkgs: Array) -> Array:
	var out: Array = []
	for p in PACKAGE_ORDER:
		if pkgs.has(p):
			out.append(p)
	for p in custom_packages:
		if pkgs.has(p) and not out.has(p):
			out.append(p)
	var rest: Array = pkgs.filter(func(p): return not out.has(p))
	rest.sort()
	return out + rest


static func _designed_colors(p: Dictionary) -> Array:
	var c: Array = p.get("colors", [])
	var out: Array = []
	for i in 3:
		var a: Array = c[mini(i, c.size() - 1)]
		out.append(Color(a[0], a[1], a[2], a[3] if a.size() > 3 else 1.0))
	return out


func _is_single_color(s: String) -> bool:
	return character.catalogue.get("colorable_links", {}).has(s) or s == "SkinDetails"


func _slot_title(s: String) -> String:
	return SLOT_TITLES.get(s, s)


func _equipped_part(s: String):
	return character.slots.get(s, {}).get("part")


# ================================================================== theme

func _sb(bg: Color, radius := 6, border := Color(0, 0, 0, 0), bw := 0, margin := Vector4(10, 6, 10, 6)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.border_color = border
	s.set_border_width_all(bw)
	s.content_margin_left = margin.x
	s.content_margin_top = margin.y
	s.content_margin_right = margin.z
	s.content_margin_bottom = margin.w
	s.anti_aliasing = true
	return s


## Check box icons that read on the dark panels.
func _box_icon(on: bool) -> Texture2D:
	var n := 18
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var edge := C_ACCENT if on else Color(1, 1, 1, 0.5)
	for y in n:
		for x in n:
			var border := x < 2 or y < 2 or x >= n - 2 or y >= n - 2
			var corner := (x < 2 or x >= n - 2) and (y < 2 or y >= n - 2)
			if corner:
				continue
			if border:
				img.set_pixel(x, y, edge)
			elif on:
				img.set_pixel(x, y, C_ACCENT if (x > 4 and x < n - 5 and y > 4 and y < n - 5) else Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)


func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 15
	_bold = FontVariation.new()
	_bold.base_font = ThemeDB.fallback_font
	_bold.variation_embolden = 0.65
	var none := StyleBoxEmpty.new()
	th.set_color("font_color", "Label", C_TEXT)
	# buttons
	for t in ["Button", "OptionButton", "CheckBox", "CheckButton"]:
		th.set_color("font_color", t, C_TEXT)
		th.set_color("font_hover_color", t, Color.WHITE)
		th.set_color("font_pressed_color", t, Color.WHITE)
		th.set_color("font_hover_pressed_color", t, Color.WHITE)
		th.set_color("font_focus_color", t, C_TEXT)
		th.set_color("font_disabled_color", t, C_DIM * Color(1, 1, 1, 0.6))
		th.set_stylebox("focus", t, none)
	th.set_stylebox("normal", "Button", _sb(Color(1, 1, 1, 0.07)))
	th.set_stylebox("hover", "Button", _sb(Color(1, 1, 1, 0.13)))
	th.set_stylebox("pressed", "Button", _sb(Color(C_ACCENT, 0.3), 6, C_ACCENT, 1))
	th.set_stylebox("hover_pressed", "Button", _sb(Color(C_ACCENT, 0.38), 6, C_ACCENT, 1))
	th.set_stylebox("disabled", "Button", _sb(Color(1, 1, 1, 0.03)))
	for t in ["CheckBox", "CheckButton"]:
		for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			th.set_stylebox(st, t, _sb(Color(1, 1, 1, 0.05) if st.begins_with("hover") else Color(0, 0, 0, 0), 6, Color(0, 0, 0, 0), 0, Vector4(4, 3, 6, 3)))
	# flat (icons, headers)
	th.set_icon("unchecked", "CheckBox", _box_icon(false))
	th.set_icon("checked", "CheckBox", _box_icon(true))
	th.set_type_variation("FlatButton", "Button")
	th.set_stylebox("normal", "FlatButton", _sb(Color(0, 0, 0, 0)))
	th.set_stylebox("hover", "FlatButton", _sb(Color(1, 1, 1, 0.08)))
	th.set_stylebox("pressed", "FlatButton", _sb(Color(1, 1, 1, 0.12)))
	th.set_stylebox("hover_pressed", "FlatButton", _sb(Color(1, 1, 1, 0.14)))
	# top bar menus
	th.set_type_variation("TopButton", "Button")
	th.set_stylebox("normal", "TopButton", _sb(Color(0, 0, 0, 0), 8))
	th.set_stylebox("hover", "TopButton", _sb(Color(1, 1, 1, 0.08), 8))
	var top_on := _sb(Color(1, 1, 1, 0.1), 8, C_ACCENT, 0)
	top_on.border_width_bottom = 3
	th.set_stylebox("pressed", "TopButton", top_on)
	th.set_stylebox("hover_pressed", "TopButton", top_on)
	# category rail rows
	th.set_type_variation("RailButton", "Button")
	th.set_stylebox("normal", "RailButton", _sb(Color(0, 0, 0, 0), 0))
	th.set_stylebox("hover", "RailButton", _sb(Color(1, 1, 1, 0.06), 0))
	var rail_on := _sb(Color(1, 1, 1, 0.09), 0, C_ACCENT, 0)
	rail_on.border_width_left = 4
	th.set_stylebox("pressed", "RailButton", rail_on)
	th.set_stylebox("hover_pressed", "RailButton", rail_on)
	# part tiles
	th.set_type_variation("Tile", "Button")
	th.set_stylebox("normal", "Tile", _sb(Color(1, 1, 1, 0.045), 8, Color(1, 1, 1, 0.05), 1))
	th.set_stylebox("hover", "Tile", _sb(Color(1, 1, 1, 0.11), 8, Color(1, 1, 1, 0.3), 1))
	th.set_stylebox("pressed", "Tile", _sb(Color(C_ACCENT, 0.16), 8, C_ACCENT, 2))
	th.set_stylebox("hover_pressed", "Tile", _sb(Color(C_ACCENT, 0.24), 8, C_ACCENT, 2))
	# accent button
	th.set_type_variation("AccentButton", "Button")
	th.set_stylebox("normal", "AccentButton", _sb(C_ACCENT.darkened(0.08), 6, Color(0, 0, 0, 0), 0, Vector4(14, 9, 14, 9)))
	th.set_stylebox("hover", "AccentButton", _sb(C_ACCENT.lightened(0.12), 6, Color(0, 0, 0, 0), 0, Vector4(14, 9, 14, 9)))
	th.set_stylebox("pressed", "AccentButton", _sb(C_ACCENT.darkened(0.2), 6, Color(0, 0, 0, 0), 0, Vector4(14, 9, 14, 9)))
	th.set_stylebox("disabled", "AccentButton", _sb(Color(C_ACCENT, 0.3), 6, Color(0, 0, 0, 0), 0, Vector4(14, 9, 14, 9)))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		th.set_color(c, "AccentButton", Color(0.1, 0.08, 0.05))
	# panels
	th.set_type_variation("SidePanel", "PanelContainer")
	th.set_stylebox("panel", "SidePanel", _sb(C_PANEL, 0, Color(1, 1, 1, 0.06), 0, Vector4(0, 0, 0, 0)))
	th.set_type_variation("Card", "PanelContainer")
	th.set_stylebox("panel", "Card", _sb(Color(1, 1, 1, 0.04), 8, Color(1, 1, 1, 0.06), 1, Vector4(12, 10, 12, 12)))
	th.set_stylebox("panel", "PanelContainer", _sb(Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0, Vector4(0, 0, 0, 0)))
	# inputs
	th.set_stylebox("normal", "LineEdit", _sb(Color(0, 0, 0, 0.35), 6, Color(1, 1, 1, 0.12), 1, Vector4(10, 6, 10, 6)))
	th.set_stylebox("focus", "LineEdit", _sb(Color(0, 0, 0, 0), 6, C_ACCENT, 1, Vector4(10, 6, 10, 6)))
	th.set_stylebox("read_only", "LineEdit", _sb(Color(0, 0, 0, 0.2), 6, Color(1, 1, 1, 0.06), 1, Vector4(10, 6, 10, 6)))
	th.set_color("font_color", "LineEdit", C_TEXT)
	th.set_color("font_placeholder_color", "LineEdit", C_DIM * Color(1, 1, 1, 0.8))
	th.set_color("caret_color", "LineEdit", C_ACCENT)
	th.set_color("selection_color", "LineEdit", Color(C_ACCENT, 0.35))
	# popups / tooltips
	th.set_stylebox("panel", "PopupMenu", _sb(Color(0.1, 0.11, 0.13, 0.98), 6, Color(1, 1, 1, 0.12), 1, Vector4(4, 4, 4, 4)))
	th.set_stylebox("hover", "PopupMenu", _sb(Color(C_ACCENT, 0.3), 4))
	th.set_color("font_color", "PopupMenu", C_TEXT)
	th.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	th.set_stylebox("panel", "TooltipPanel", _sb(Color(0.08, 0.09, 0.11, 0.97), 6, Color(1, 1, 1, 0.15), 1, Vector4(10, 6, 10, 6)))
	th.set_color("font_color", "TooltipLabel", C_TEXT)
	# sliders
	th.set_stylebox("slider", "HSlider", _sb(Color(1, 1, 1, 0.14), 3, Color(0, 0, 0, 0), 0, Vector4(0, 2, 0, 2)))
	th.set_stylebox("grabber_area", "HSlider", _sb(Color(C_ACCENT, 0.85), 3, Color(0, 0, 0, 0), 0, Vector4(0, 2, 0, 2)))
	th.set_stylebox("grabber_area_highlight", "HSlider", _sb(C_ACCENT, 3, Color(0, 0, 0, 0), 0, Vector4(0, 2, 0, 2)))
	# scroll bars
	for t in ["VScrollBar", "HScrollBar"]:
		th.set_stylebox("scroll", t, _sb(Color(1, 1, 1, 0.03), 4, Color(0, 0, 0, 0), 0, Vector4(3, 3, 3, 3)))
		th.set_stylebox("grabber", t, _sb(Color(1, 1, 1, 0.18), 4))
		th.set_stylebox("grabber_highlight", t, _sb(Color(1, 1, 1, 0.3), 4))
		th.set_stylebox("grabber_pressed", t, _sb(C_ACCENT, 4))
	th.set_color("color", "HSeparator", Color(1, 1, 1, 0.08))
	th.set_stylebox("separator", "HSeparator", _sb(Color(1, 1, 1, 0.08), 0, Color(0, 0, 0, 0), 0, Vector4(0, 0, 0, 0)))
	th.set_constant("separation", "HSeparator", 14)
	return th


# ================================================================== ui helpers

func _icon(icon_name: String) -> Texture2D:
	var path := ICON_DIR + icon_name + ".png"
	return load(path) if ResourceLoader.exists(path) else null


func _label(text: String, size := 0, dim := false, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	if dim:
		l.add_theme_color_override("font_color", C_DIM)
	if bold:
		l.add_theme_font_override("font", _bold)
	return l


func _section_label(text: String) -> Label:
	var l := _label(text.to_upper(), 12, true, true)
	l.add_theme_constant_override("line_spacing", 0)
	return l


func _button(parent: Control, text: String, cb: Callable, icon_name := "", tip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	if icon_name != "":
		b.icon = _icon(icon_name)
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", 18)
	b.tooltip_text = tip
	b.pressed.connect(cb)
	if parent:
		parent.add_child(b)
	return b


func _icon_button(parent: Control, icon_name: String, cb: Callable, tip: String, px := 20) -> Button:
	var b := Button.new()
	b.theme_type_variation = "FlatButton"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(px + 16, px + 12)
	b.tooltip_text = tip
	var tr := TextureRect.new()
	tr.texture = _icon(icon_name)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tr.offset_left = 8
	tr.offset_right = -8
	tr.offset_top = 6
	tr.offset_bottom = -6
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.modulate = C_TEXT
	b.add_child(tr)
	b.pressed.connect(cb)
	if parent:
		parent.add_child(b)
	return b


func _hbox(parent: Control, sep := 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	parent.add_child(h)
	return h


func _vbox(parent: Control, sep := 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	parent.add_child(v)
	return v


func _margin(parent: Control, l: int, t: int, r: int, b: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", l)
	m.add_theme_constant_override("margin_top", t)
	m.add_theme_constant_override("margin_right", r)
	m.add_theme_constant_override("margin_bottom", b)
	parent.add_child(m)
	return m


func _scroll(parent: Control) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(s)
	return s


func _hslider(lo: float, hi: float, step: float, value: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_NONE
	return s


func _toast(text: String) -> void:
	_status.text = text
	_status.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(5.0)
	tw.tween_property(_status, "modulate:a", 0.0, 1.0)


# ================================================================== layout

func _build_ui() -> void:
	_theme = _make_theme()
	# background (behind the world)
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -100
	add_child(bg_layer)
	_bg_color = ColorRect.new()
	_bg_color.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg_color.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_layer.add_child(_bg_color)
	_bg_rect = TextureRect.new()
	_bg_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_layer.add_child(_bg_rect)
	_add_shadow()

	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	var root := Control.new()
	root.theme = _theme
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	_stage = Control.new()
	_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stage.offset_left = RAIL_W + CONTENT_W
	_stage.offset_right = -COLOR_W
	_stage.offset_top = TOP_H
	_stage.mouse_filter = Control.MOUSE_FILTER_STOP
	_stage.gui_input.connect(_on_stage_input)
	root.add_child(_stage)
	_build_stage()

	_build_top_bar(root)
	_build_left(root)
	_build_color_panel(root)

	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.use_native_dialog = true
	_file_dialog.file_selected.connect(func(p): _file_cb.call(p))
	add_child(_file_dialog)
	_confirm = ConfirmationDialog.new()
	_confirm.title = "New character"
	_confirm.dialog_text = "Start again from the default character?\nUnsaved changes are lost."
	_confirm.confirmed.connect(_new_character)
	root.add_child(_confirm)


func _add_shadow() -> void:
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.5))
	g.set_color(1, Color(0, 0, 0, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 256
	gt.height = 256
	var s := Sprite2D.new()
	s.texture = gt
	s.scale = Vector2(1.25, 0.2)
	s.z_index = -5
	add_child(s)
	move_child(s, 0)


func _build_top_bar(root: Control) -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = TOP_H
	var st := _sb(Color(0.04, 0.045, 0.055, 0.7), 0, Color(1, 1, 1, 0.07), 0, Vector4(16, 6, 16, 6))
	st.border_width_bottom = 1
	bar.add_theme_stylebox_override("panel", st)
	root.add_child(bar)
	var row := HBoxContainer.new()
	bar.add_child(row)
	var left := _hbox(row, 10)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title_box := VBoxContainer.new()
	title_box.add_theme_constant_override("separation", -2)
	title_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	left.add_child(title_box)
	title_box.add_child(_label("CHARACTER CREATOR 2D", 17, false, true))
	title_box.add_child(_label("Godot port · %d parts" % _count_parts(), 12, true))

	var mid := _hbox(row, 6)
	for m in MENUS:
		var b := Button.new()
		b.theme_type_variation = "TopButton"
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(78, TOP_H - 12)
		b.tooltip_text = "File menu" if m.id == "file" else "%s menu" % m.title
		var v := VBoxContainer.new()
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.offset_top = 6
		v.offset_bottom = -6
		v.add_theme_constant_override("separation", 3)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(v)
		var ic := TextureRect.new()
		ic.texture = _icon(m.icon)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.size_flags_vertical = Control.SIZE_EXPAND_FILL
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(ic)
		var l := _label(m.title.to_upper(), 11, false, true)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(l)
		var id: String = m.id
		b.pressed.connect(func(): open_menu(id))
		mid.add_child(b)
		_menu_buttons[id] = {"button": b, "icon": ic, "label": l}
		if id == "file":
			var sep := VSeparator.new()
			sep.add_theme_constant_override("separation", 14)
			sep.add_theme_stylebox_override("separator", _sb(Color(1, 1, 1, 0.35), 0, Color(0, 0, 0, 0), 0, Vector4(1, 10, 1, 10)))
			mid.add_child(sep)

	var right := _hbox(row, 8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.alignment = BoxContainer.ALIGNMENT_END
	var dice := _button(right, "Randomize", func(): randomize_character(), "dice", "Random parts and colours (Body > Randomize has the options)")
	dice.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var clear := _button(right, "Clear All", clear_items, "clear", "Take off all clothing and weapons (body and face stay)")
	clear.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var demo := _button(right, "Walk Demo", _go_demo, "play", "Walk around with this character")
	demo.size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _count_parts() -> int:
	var n := 0
	for list in character.catalogue.get("categories", {}).values():
		n += list.size()
	return n


func _build_left(root: Control) -> void:
	var left := HBoxContainer.new()
	left.add_theme_constant_override("separation", 0)
	left.anchor_bottom = 1.0
	left.offset_top = TOP_H
	left.offset_right = RAIL_W + CONTENT_W
	root.add_child(left)
	# rail: the menu's categories
	var rail := PanelContainer.new()
	rail.theme_type_variation = "SidePanel"
	rail.custom_minimum_size = Vector2(RAIL_W, 0)
	var rst := _sb(Color(0.045, 0.05, 0.06, 0.88), 0, Color(1, 1, 1, 0.06), 0, Vector4(0, 12, 0, 12))
	rst.border_width_right = 1
	rail.add_theme_stylebox_override("panel", rst)
	left.add_child(rail)
	var rs := _scroll(rail)
	_rail_box = VBoxContainer.new()
	_rail_box.add_theme_constant_override("separation", 2)
	_rail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rs.add_child(_rail_box)

	# content: the category's parts / settings
	var content := PanelContainer.new()
	content.theme_type_variation = "SidePanel"
	content.custom_minimum_size = Vector2(CONTENT_W, 0)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(content)
	var m := _margin(content, 14, 14, 8, 10)
	var box := _vbox(m, 10)
	var head := _hbox(box, 12)
	_header_icon = TextureRect.new()
	_header_icon.custom_minimum_size = Vector2(44, 44)
	_header_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_header_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(_header_icon)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 0)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(hv)
	_header_title = _label("", 24, false, true)
	hv.add_child(_header_title)
	_header_sub = _label("", 13, true)
	_header_sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_header_sub.custom_minimum_size = Vector2(CONTENT_W - 100, 0)
	hv.add_child(_header_sub)

	var pages := Control.new()
	pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(pages)
	for pname in ["parts", "sliders", "randomize", "emotion", "export"]:
		var p := VBoxContainer.new()
		p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		p.add_theme_constant_override("separation", 10)
		p.visible = false
		pages.add_child(p)
		_pages[pname] = p
	_build_parts_page(_pages.parts)
	_build_sliders_page(_pages.sliders)
	_build_randomize_page(_pages.randomize)
	_build_emotion_page(_pages.emotion)
	_build_export_page(_pages.export)


func _build_rail() -> void:
	for c in _rail_box.get_children():
		c.queue_free()
	_rail_rows.clear()
	var m := _menu(menu)
	var title := _section_label(m.title + (" menu" if m.id == "file" else ""))
	var tm := _margin(_rail_box, 16, 2, 8, 8)
	tm.add_child(title)
	for c in m.cats:
		var info: Dictionary = CATS[c]
		var b := Button.new()
		b.theme_type_variation = "RailButton"
		b.toggle_mode = info.kind != "action"
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 56)
		b.tooltip_text = info.get("tip", info.title)
		var hb := HBoxContainer.new()
		hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hb.offset_left = 14
		hb.add_theme_constant_override("separation", 12)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(hb)
		var ic := TextureRect.new()
		ic.texture = _icon(info.icon)
		ic.custom_minimum_size = Vector2(34, 34)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(ic)
		var l := _label(info.title.to_upper(), 13, false, true)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(l)
		var cid: String = c
		b.pressed.connect(func(): open_category(cid))
		_rail_box.add_child(b)
		_rail_rows[cid] = {"button": b, "icon": ic, "label": l}
	_refresh_rail()


func _refresh_rail() -> void:
	for c in _rail_rows:
		var r: Dictionary = _rail_rows[c]
		var on: bool = c == cat
		r.button.set_pressed_no_signal(on)
		r.icon.modulate = Color.WHITE if on else C_DIM
		r.label.add_theme_color_override("font_color", Color.WHITE if on else C_DIM)
	for id in _menu_buttons:
		var mb: Dictionary = _menu_buttons[id]
		mb.button.set_pressed_no_signal(id == menu)
		mb.icon.modulate = Color.WHITE if id == menu else Color(0.75, 0.78, 0.82)
		mb.label.add_theme_color_override("font_color", Color.WHITE if id == menu else C_DIM)


func _menu(id: String) -> Dictionary:
	for m in MENUS:
		if m.id == id:
			return m
	return MENUS[0]


## Opens a top-bar menu (file, body, face, equipment, weapon, gun) and its last category.
func open_menu(id: String) -> void:
	menu = id
	_build_rail()
	var m := _menu(id)
	var c: String = _last_cat.get(id, "")
	if c == "":
		for k in m.cats:
			if CATS[k].kind != "action":
				c = k
				break
	open_category(c)


## Opens a category (see CATS). Action categories (New, Open, Save, Walk Demo) run instead.
func open_category(c: String) -> void:
	if not CATS.has(c):
		return
	var info: Dictionary = CATS[c]
	if info.kind == "action":
		_refresh_rail()
		_run_action(c)
		return
	if cat == "emotion" and c != "emotion" and character.current_emote != "":
		character.reset_emote()
	for m in MENUS:
		if c in m.cats and m.id != menu:
			menu = m.id
			_build_rail()
	cat = c
	_last_cat[menu] = c
	_refresh_rail()
	_show_category(c)


func _show_category(c: String) -> void:
	var info: Dictionary = CATS[c]
	_header_icon.texture = _icon(info.icon)
	_header_title.text = info.title.to_upper()
	for p in _pages.values():
		p.visible = false
	slot = info.get("slot", "")
	match info.kind:
		"parts":
			_pages.parts.visible = true
			_body_row.visible = c == "body"
			_parts_caption.visible = c == "body"
			_build_parts()
		"sliders":
			_pages.sliders.visible = true
			_refresh_sliders()
		"randomize":
			_pages.randomize.visible = true
			_build_rand_packs()
		"emotion":
			_pages.emotion.visible = true
			_build_emotion_list()
		"export":
			_pages.export.visible = true
			_refresh_export()
	_refresh_header()
	_refresh_color_panel()


func _refresh_header() -> void:
	var info: Dictionary = CATS.get(cat, {})
	match info.get("kind", ""):
		"parts":
			var eq := character.get_equipped(slot)
			if cat == "body":
				_header_sub.text = "%s body · %s" % [character.body_type, ("skin " + eq) if eq != "" else "default skin"]
			elif eq == "":
				_header_sub.text = "Nothing equipped"
			else:
				_header_sub.text = "%s · %s" % [eq, character.get_equipped_package(slot)]
			_header_sub.tooltip_text = _header_sub.text
		"sliders":
			_header_sub.text = "Width and length of each body part"
		"randomize":
			_header_sub.text = "Roll a new character"
		"emotion":
			_header_sub.text = "Facial expressions"
		"export":
			_header_sub.text = "CC2D's Export PNG screen"
		_:
			_header_sub.text = ""


# ================================================================== parts page

func _build_parts_page(page: VBoxContainer) -> void:
	_body_row = _hbox(page, 8)
	for b in CC2DCharacter.BODY_TYPES:
		var bt: String = b
		var btn := Button.new()
		btn.toggle_mode = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(0, 58)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.text = bt.to_upper()
		btn.icon = _icon("body")
		btn.expand_icon = true
		btn.add_theme_constant_override("icon_max_width", 22)
		btn.add_theme_font_override("font", _bold)
		btn.tooltip_text = "%s body: parts switch to their %s versions" % [bt, bt.to_lower()]
		btn.pressed.connect(func(): _set_body_type(bt))
		_body_row.add_child(btn)
		_body_buttons[bt] = btn
	_parts_caption = _section_label("Body skin")
	page.add_child(_parts_caption)
	var tools := _hbox(page, 6)
	_search_edit = LineEdit.new()
	_search_edit.placeholder_text = "Search parts…"
	_search_edit.clear_button_enabled = true
	_search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_edit.text_changed.connect(func(t):
		_search = t
		_apply_filter())
	tools.add_child(_search_edit)
	_pack_option = OptionButton.new()
	_pack_option.focus_mode = Control.FOCUS_NONE
	_pack_option.custom_minimum_size = Vector2(118, 0)
	_pack_option.fit_to_longest_item = false
	_pack_option.clip_text = true
	_pack_option.tooltip_text = "Show one pack only"
	_pack_option.item_selected.connect(func(i):
		_pack_filter = "" if i == 0 else _pack_option.get_item_text(i)
		_apply_filter())
	tools.add_child(_pack_option)
	_icon_button(tools, "dice", _random_part, "Random part for this category", 18)
	_parts_scroll = _scroll(page)
	_parts_list = VBoxContainer.new()
	_parts_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_parts_list.add_theme_constant_override("separation", 6)
	_parts_scroll.add_child(_parts_list)


## Parts listed on a category page. all_bodies: also the other body type's parts (shown dimmed;
## picking one switches the body type).
func _cat_parts(c: String, all_bodies := false) -> Array:
	var info: Dictionary = CATS[c]
	var parts: Array = character.get_parts(info.slot, not all_bodies)
	if info.has("weapons"):
		var allowed: Array = info.weapons
		parts = parts.filter(func(p): return p.get("weapon", "") in allowed)
	return parts


func _build_parts() -> void:
	for ch in _parts_list.get_children():
		ch.queue_free()
	_tiles.clear()
	_sections.clear()
	_thumb_queue.clear()
	for b in _body_buttons:
		_body_buttons[b].set_pressed_no_signal(b == character.body_type)
	var parts := _cat_parts(cat, cat != "body")
	# this body type's parts first, then the other body's (dimmed)
	var fits := parts.filter(func(p): return character.body_type in p.body)
	parts = fits + parts.filter(func(p): return not (character.body_type in p.body))
	var by_pkg := {}
	for p in parts:
		if not by_pkg.has(p.package):
			by_pkg[p.package] = []
		by_pkg[p.package].append(p)
	var pkgs := _order_packages(by_pkg.keys())
	# pack filter
	_pack_option.clear()
	_pack_option.add_item("All packs")
	var sel := 0
	for pkg in pkgs:
		_pack_option.add_item(pkg)
		if pkg == _pack_filter:
			sel = _pack_option.item_count - 1
	if sel == 0:
		_pack_filter = ""
	_pack_option.select(sel)
	# "none" first
	var top := HFlowContainer.new()
	top.add_theme_constant_override("h_separation", 6)
	top.add_theme_constant_override("v_separation", 6)
	_parts_list.add_child(top)
	var none_text := "Default" if cat == "body" else "None"
	top.add_child(_make_tile({}, none_text))
	for pkg in pkgs:
		var header := Button.new()
		header.theme_type_variation = "FlatButton"
		header.focus_mode = Control.FOCUS_NONE
		header.alignment = HORIZONTAL_ALIGNMENT_LEFT
		header.add_theme_font_override("font", _bold)
		header.add_theme_font_size_override("font_size", 13)
		header.add_theme_color_override("font_color", C_DIM)
		header.expand_icon = false
		header.tooltip_text = "Click to fold or unfold the %s pack" % pkg
		_parts_list.add_child(header)
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 6)
		flow.add_theme_constant_override("v_separation", 6)
		_parts_list.add_child(flow)
		var sec := {"header": header, "flow": flow, "tiles": []}
		_sections[pkg] = sec
		var p_name: String = pkg
		header.pressed.connect(func():
			_collapsed[p_name] = not _collapsed.get(p_name, false)
			_apply_filter())
		for p in by_pkg[pkg]:
			var tile := _make_tile(p, _short_name(p.name))
			flow.add_child(tile)
			sec.tiles.append(_tiles[-1])
	_apply_filter()
	_refresh_selection()
	_parts_scroll.scroll_vertical = 0
	_scroll_to_selected.call_deferred()


func _short_name(n: String) -> String:
	for suffix in [" Male", " Female"]:
		if n.ends_with(suffix) and n.length() > suffix.length():
			return n.substr(0, n.length() - suffix.length())
	return n


func _make_tile(p: Dictionary, text: String) -> Button:
	var b := Button.new()
	b.theme_type_variation = "Tile"
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = TILE_SIZE
	if p.is_empty():
		b.tooltip_text = "Default body skin" if cat == "body" else "Remove the %s part" % _slot_title(slot).to_lower()
	else:
		b.tooltip_text = "%s\n%s pack · %s" % [p.name, p.package, " / ".join(p.body)]
		if p.has("colors"):
			b.tooltip_text += "\nComes with its own colours"
		if not (character.body_type in p.body):
			b.modulate = Color(1, 1, 1, 0.45)
			b.tooltip_text += "\n%s body only: click to switch to it and wear this" % " / ".join(p.body)
	var tr := TextureRect.new()
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tr.offset_left = 8
	tr.offset_top = 7
	tr.offset_right = -8
	tr.offset_bottom = -27
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(tr)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	l.offset_top = -25
	l.offset_bottom = -5
	l.offset_left = 4
	l.offset_right = -4
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(l)
	if p.is_empty():
		tr.texture = _icon("clear")
		tr.offset_left = 30
		tr.offset_right = -30
		tr.offset_top = 22
		tr.offset_bottom = -40
		tr.modulate = C_DIM
	else:
		_thumb_queue.append([tr, p, slot])
	var tile := {"button": b, "rect": tr, "part": p, "slot": slot, "label": l}
	_tiles.append(tile)
	b.pressed.connect(func(): _on_tile_pressed(p))
	return b


func _apply_filter() -> void:
	var q := _search.strip_edges().to_lower()
	for pkg in _sections:
		var sec: Dictionary = _sections[pkg]
		var n := 0
		for t in sec.tiles:
			var show: bool = q == "" or str(t.part.name).to_lower().contains(q) or str(pkg).to_lower().contains(q)
			t.button.visible = show
			if show:
				n += 1
		var pack_ok: bool = _pack_filter == "" or _pack_filter == pkg
		var folded: bool = _collapsed.get(pkg, false)
		sec.header.visible = n > 0 and pack_ok
		sec.flow.visible = n > 0 and pack_ok and not folded
		sec.header.text = "%s   %s   (%d)" % ["▸" if folded else "▾", str(pkg).to_upper(), n]


func _tile_selected(t: Dictionary) -> bool:
	var eq = _equipped_part(t.slot)
	var p: Dictionary = t.part
	if p.is_empty():
		if not (eq is Dictionary):
			return true
		var info: Dictionary = CATS.get(cat, {})
		# weapon categories: "None" is lit when the hand holds nothing of this kind
		return info.has("weapons") and not (eq.get("weapon", "") in info.weapons)
	return eq is Dictionary and eq.name == p.name and eq.package == p.package


func _refresh_selection() -> void:
	for t in _tiles:
		t.button.set_pressed_no_signal(_tile_selected(t))
	for b in _body_buttons:
		_body_buttons[b].set_pressed_no_signal(b == character.body_type)
	_paint_tiles()
	_refresh_header()
	_refresh_color_panel()


func _scroll_to_selected() -> void:
	for t in _tiles:
		if t.button.button_pressed and not t.part.is_empty() and t.button.is_visible_in_tree():
			_parts_scroll.ensure_control_visible(t.button)
			return


func _on_tile_pressed(p: Dictionary) -> void:
	if slot == "":
		return
	if not p.is_empty() and not (character.body_type in p.body) and not p.body.is_empty():
		character.set_body_type(p.body[0])   # rebuilds the page next frame
	if p.is_empty():
		character.equip_part(slot, "")
		_toast("%s removed" % _slot_title(slot))
	elif character.equip_part(slot, p.name, p.package):
		if p.has("colors"):
			var c := _designed_colors(p)
			character.set_part_color(slot, c[0], c[1], c[2])
		_toast("%s: %s (%s)" % [_slot_title(slot), p.name, p.package])
	else:
		_toast("Can't equip %s here" % p.name)
	_refresh_selection()


func _random_part() -> void:
	var parts := _cat_parts(cat)
	if parts.is_empty():
		return
	_on_tile_pressed(parts.pick_random())
	_scroll_to_selected()


func _set_body_type(bt: String) -> void:
	if bt != character.body_type:
		character.set_body_type(bt)
		_toast("%s body" % bt)
	_refresh_selection()


# ---------------------------------------------------------------- thumbnails

func _process_thumbs() -> void:
	var t0 := Time.get_ticks_usec()
	while not _thumb_queue.is_empty() and Time.get_ticks_usec() - t0 < 10000:
		var job: Array = _thumb_queue.pop_front()
		if is_instance_valid(job[0]):
			_apply_thumb(job[0], job[1], job[2])


func _apply_thumb(tr: TextureRect, p: Dictionary, s: String) -> void:
	var d := _thumb_data(p)
	if d.is_empty():
		tr.texture = _icon("info")
		tr.modulate = C_DIM
		return
	tr.texture = d.tex
	if d.get("mask") is Texture2D and not _modulated_slot(s):
		var m := ShaderMaterial.new()
		m.shader = CC2DCharacter.ARMOR_SHADER
		m.set_shader_parameter("color_mask", d.mask)
		m.set_shader_parameter("has_mask", true)
		m.set_shader_parameter("tint", Color.WHITE)
		tr.material = m
	_paint_tile_rect(tr, p, s)


## Slots drawn with the sprite colour (no colour mask): skin parts, hair, eyes, ...
func _modulated_slot(s: String) -> bool:
	return s in CC2DCharacter.SKIN_SLOTS or _is_single_color(s)


func _tile_colors(p: Dictionary, s: String) -> Array:
	var eq = _equipped_part(s)
	var is_eq: bool = eq is Dictionary and eq.name == p.name and eq.package == p.package
	if p.has("colors") and not is_eq:
		return _designed_colors(p)
	return character.get_part_colors(s)


func _paint_tile_rect(tr: TextureRect, p: Dictionary, s: String) -> void:
	if p.is_empty() or tr.texture == null:
		return
	if s in CC2DCharacter.SKIN_SLOTS:
		tr.self_modulate = character.skin_color
		return
	var cols := _tile_colors(p, s)
	if _is_single_color(s):
		var c: Color = cols[0]
		c.a = 1.0
		tr.self_modulate = c
	elif tr.material is ShaderMaterial:
		var m := tr.material as ShaderMaterial
		m.set_shader_parameter("color1", cols[0])
		m.set_shader_parameter("color2", cols[1])
		m.set_shader_parameter("color3", cols[2])


func _paint_tiles() -> void:
	for t in _tiles:
		_paint_tile_rect(t.rect, t.part, t.slot)


## A small picture of a part: its biggest sprite (or the whole texture for capes, skirts and
## skin details), cropped to what's drawn, plus the matching piece of its colour mask.
## Cached in memory and in user://cc2d_thumbs/.
func _thumb_data(p: Dictionary) -> Dictionary:
	var key := "%s|%s|%s" % [p.get("texture", ""), p.package, p.name]
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
	var tex_path := ""
	var region := Rect2i()
	if best is Dictionary:
		tex_path = best.texture
		region = Rect2i(int(best.region[0]), int(best.region[1]), int(best.region[2]), int(best.region[3]))
	elif p.get("texture") is String:
		tex_path = p.texture
	if tex_path == "" or not ResourceLoader.exists(tex_path):
		_thumbs[key] = {}
		return {}
	var mask_path := ""
	if p.get("mask") is String and p.get("texture") == tex_path and ResourceLoader.exists(p.mask):
		mask_path = p.mask
	var stamp := "%s|%s|%s|%d|%d|%d" % [tex_path, mask_path, region, FileAccess.get_modified_time(tex_path),
		FileAccess.get_modified_time(mask_path) if mask_path != "" else 0, THUMB_PX]
	var h := stamp.md5_text()
	var file := THUMB_DIR + h + ".png"
	var mfile := THUMB_DIR + h + "_m.png"
	var img: Image = null
	var mimg: Image = null
	if FileAccess.file_exists(file):
		img = Image.load_from_file(file)
		if mask_path != "" and FileAccess.file_exists(mfile):
			mimg = Image.load_from_file(mfile)
	if img == null:
		img = _load_image(tex_path)
		if img == null:
			_thumbs[key] = {}
			return {}
		var full := img.get_size()
		if region.size.x <= 0:
			region = Rect2i(Vector2i.ZERO, full)
		region = region.intersection(Rect2i(Vector2i.ZERO, full))
		img = img.get_region(region)
		var used := img.get_used_rect()
		if used.size.x <= 0 or used.size.y <= 0:
			_thumbs[key] = {}
			return {}
		img = img.get_region(used)
		if mask_path != "":
			var m := _load_image(mask_path)
			if m != null and m.get_size() == full:
				mimg = m.get_region(region).get_region(used)
		var k := float(THUMB_PX) / maxf(img.get_width(), img.get_height())
		if k < 1.0:
			var sz := Vector2i(maxi(1, int(img.get_width() * k)), maxi(1, int(img.get_height() * k)))
			img.resize(sz.x, sz.y, Image.INTERPOLATE_LANCZOS)
			if mimg != null:
				mimg.resize(sz.x, sz.y, Image.INTERPOLATE_BILINEAR)
		DirAccess.make_dir_recursive_absolute(THUMB_DIR)
		img.save_png(file)
		if mimg != null:
			mimg.save_png(mfile)
	var d := {"tex": ImageTexture.create_from_image(img)}
	if mimg != null:
		d.mask = ImageTexture.create_from_image(mimg)
	_thumbs[key] = d
	return d


static func _load_image(path: String) -> Image:
	if path == "" or not ResourceLoader.exists(path):
		return null
	var t = load(path)
	if not (t is Texture2D):
		return null
	var img: Image = t.get_image()
	if img == null:
		return null
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


# ================================================================== body sliders page

func _build_sliders_page(page: VBoxContainer) -> void:
	page.add_child(_label("Drag to change each body part. 0.5 is CC2D's default.", 13, true))
	var sc := _scroll(page)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	sc.add_child(box)
	for seg in CC2DCharacter.SEGMENTS:
		var segment: String = seg
		var card := PanelContainer.new()
		card.theme_type_variation = "Card"
		box.add_child(card)
		var v := _vbox(card, 2)
		var title := _hbox(v, 6)
		var tl := _label(segment.capitalize().to_upper(), 13, false, true)
		tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.add_child(tl)
		var reset := _icon_button(title, "zoom_reset", func():
			character.set_body_slider(segment, Vector2(0.5, 0.5))
			_refresh_sliders(), "Reset %s" % segment.capitalize().to_lower(), 14)
		reset.custom_minimum_size = Vector2(26, 22)
		var sym: bool = character._segments.get(segment, {}).get("symmetrical", false)
		var row_sliders: Array = []
		for axis in (1 if sym else 2):
			var ax: int = axis
			var r := _hbox(v, 8)
			var cap := _label("Size" if sym else ("Width" if axis == 0 else "Length"), 12, true)
			cap.custom_minimum_size = Vector2(52, 0)
			r.add_child(cap)
			var s := _hslider(0.0, 1.0, 0.01, 0.5)
			s.value_changed.connect(func(val): _on_slider_changed(segment, ax, val, sym))
			r.add_child(s)
			var vl := _label("0.50", 12, true)
			vl.custom_minimum_size = Vector2(34, 0)
			vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			r.add_child(vl)
			row_sliders.append([s, vl])
		_slider_rows[segment] = row_sliders
	var actions := _hbox(page, 8)
	var r1 := _button(actions, "Reset all", func():
		for seg in CC2DCharacter.SEGMENTS:
			character.set_body_slider(seg, Vector2(0.5, 0.5))
		_refresh_sliders(), "zoom_reset")
	r1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var r2 := _button(actions, "Randomize", func():
		_randomize_sliders()
		_refresh_sliders(), "dice")
	r2.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _on_slider_changed(segment: String, axis: int, val: float, sym: bool) -> void:
	if _updating:
		return
	var v := character.get_body_slider(segment)
	if sym:
		v = Vector2(val, val)
	elif axis == 0:
		v.x = val
	else:
		v.y = val
	character.set_body_slider(segment, v)
	_refresh_sliders()


func _refresh_sliders() -> void:
	_updating = true
	for seg in _slider_rows:
		var v := character.get_body_slider(seg)
		var rows: Array = _slider_rows[seg]
		for i in rows.size():
			var val: float = v.x if i == 0 else v.y
			rows[i][0].value = val
			rows[i][1].text = "%.2f" % val
	_updating = false


# ================================================================== randomize page

func _build_randomize_page(page: VBoxContainer) -> void:
	var sc := _scroll(page)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	sc.add_child(box)
	for group in [["Parts", [["body_parts", "Body"], ["face_parts", "Face"], ["outfit_parts", "Outfit"], ["weapon_parts", "Weapon"], ["sliders", "Body sliders"]]],
			["Colours", [["body_colors", "Skin"], ["face_colors", "Face"], ["outfit_colors", "Outfit"], ["weapon_colors", "Weapon"]]]]:
		var card := PanelContainer.new()
		card.theme_type_variation = "Card"
		box.add_child(card)
		var v := _vbox(card, 4)
		v.add_child(_section_label("Randomize " + str(group[0]).to_lower()))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 12)
		v.add_child(grid)
		for item in group[1]:
			var cb := CheckBox.new()
			cb.text = item[1]
			cb.focus_mode = Control.FOCUS_NONE
			cb.button_pressed = item[0] != "sliders"
			cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(cb)
			_rand_checks[item[0]] = cb
	var pcard := PanelContainer.new()
	pcard.theme_type_variation = "Card"
	box.add_child(pcard)
	var pv := _vbox(pcard, 4)
	pv.add_child(_section_label("Use parts from"))
	_rand_pack_box = HFlowContainer.new()
	_rand_pack_box.add_theme_constant_override("h_separation", 6)
	pv.add_child(_rand_pack_box)
	var go := _button(page, "RANDOMIZE", func():
		var opts := {}
		for k in _rand_checks:
			opts[k] = _rand_checks[k].button_pressed
		randomize_character(opts), "dice", "Roll parts and colours with the options above")
	go.theme_type_variation = "AccentButton"
	go.add_theme_font_override("font", _bold)
	go.add_theme_font_size_override("font_size", 17)
	go.custom_minimum_size = Vector2(0, 48)


func _build_rand_packs() -> void:
	var was := {}
	for c in _rand_pack_box.get_children():
		if c is CheckBox:
			was[c.text] = c.button_pressed
		c.queue_free()
	for pkg in _all_packages():
		var cb := CheckBox.new()
		cb.text = pkg
		cb.focus_mode = Control.FOCUS_NONE
		cb.button_pressed = was.get(pkg, true)
		_rand_pack_box.add_child(cb)


func _excluded_packs() -> Array:
	var out: Array = []
	if _rand_pack_box == null:
		return out
	for c in _rand_pack_box.get_children():
		if c is CheckBox and not c.button_pressed and not c.is_queued_for_deletion():
			out.append(c.text)
	return out


func _dice() -> int:
	return randi_range(0, 100)


## UIRandomizeCharacter.Randomize. Options (all default on, except sliders): body_parts,
## face_parts, outfit_parts, weapon_parts, sliders, body_colors, face_colors, outfit_colors,
## weapon_colors.
func randomize_character(opts := {}) -> void:
	var o := {"body_parts": true, "face_parts": true, "outfit_parts": true, "weapon_parts": true, "sliders": false,
		"body_colors": true, "face_colors": true, "outfit_colors": true, "weapon_colors": true}
	o.merge(opts, true)
	var ex_parts: Array = []
	var ex_colors: Array = []
	if o.body_parts:
		character.set_body_type("Male" if _dice() > 50 else "Female")   # UICreator.RandomizeBody
	else:
		ex_parts += ["SkinDetails", "BodySkin"]
	if not o.face_parts:
		ex_parts += FACE_SLOTS
	if not o.outfit_parts:
		ex_parts += OUTFIT_SLOTS
	if not o.weapon_parts:
		ex_parts += WEAPON_SLOTS
	if o.sliders:
		_randomize_sliders()
	if o.body_colors:
		var skins := _pal("Bleached") if _dice() > 80 else _pal("Skin")   # UICreator.RandomizeSkinColor
		character.set_skin_color(skins.pick_random())
	else:
		ex_colors.append("SkinDetails")
	if not o.face_colors:
		ex_colors += FACE_SLOTS
	if not o.outfit_colors:
		ex_colors += OUTFIT_SLOTS
	if not o.weapon_colors:
		ex_colors += WEAPON_SLOTS
	_randomize_parts(ex_parts, _excluded_packs())
	_randomize_colors(ex_colors)
	_rebuild = true
	_refresh_sliders()
	_toast("Randomized")


## UICreator.RandomizePart(excludedCategory, excludedPacks)
func _randomize_parts(excluded: Array, excluded_packs: Array) -> void:
	for s in CC2DCharacter.SLOTS:
		if s in excluded:
			continue
		var avail: Array = character.get_parts(s).filter(func(p): return not (p.package in excluded_packs))
		if avail.is_empty():
			continue
		var pick: Dictionary = avail.pick_random()
		match s:
			"OffHand":
				var main = _equipped_part("MainHand")
				if not (main is Dictionary):
					character.equip_part(s, "")
				elif not (main.get("weapon", "") in CC2DCharacter.TWO_HANDED_WEAPONS) and _dice() < RAND_CHANCE[s]:
					_equip_random(s, pick)
			"Ear", "BodySkin":
				_equip_random(s, pick)
			"Skirt":
				var chance := 40 if character.body_type == "Female" else 20
				if _dice() < chance:
					_equip_random(s, pick)
					if _dice() < chance:
						character.equip_part("Pants", "Base 00 Male", "Base")
				else:
					character.equip_part(s, "")
			_:
				if _dice() < RAND_CHANCE[s]:
					_equip_random(s, pick)
				else:
					character.equip_part(s, "")


func _equip_random(s: String, p: Dictionary) -> void:
	if character.equip_part(s, p.name, p.package) and p.has("colors"):
		var c := _designed_colors(p)
		character.set_part_color(s, c[0], c[1], c[2])


## UICreator.RandomizeColor(excludedCategory)
func _randomize_colors(excluded: Array) -> void:
	var flash := _dice()
	var variant := _dice()
	var pool := _pal("Bleak") + _pal("Dark") + _pal("Leather") + _pal("Grayscale")
	var hair := _pal("Hair")
	var lips := _pal("Lips") + _pal("Skin")
	var tatt := _pal("Grayscale") + _pal("Bleak") + _pal("Fabric") + _pal("Vibrant")
	var eyes := _pal("Eyes")
	if flash >= 20:
		pool += _pal("Metal") + _pal("Bleached")
		hair += _pal("Metal") + _pal("Eyes")
		lips += _pal("Bleached")
	if flash >= 50:
		pool += _pal("Fabric")
		hair += _pal("Fabric") + _pal("Vibrant")
		lips += _pal("Fabric") + _pal("Bleak") + _pal("Dark")
	if flash >= 80:
		pool += _pal("Vibrant")
		hair += _pal("Bleached")
		lips += _pal("Vibrant")
	var n := 6 if variant <= 30 else (9 if variant < 80 else 12)
	var theme_cols: Array = []
	for i in n:
		theme_cols.append(pool.pick_random())
	if _dice() > 60:
		eyes += _pal("Vibrant")
	for s in ["Armor", "Pants", "Helmet", "Gloves", "Boots", "Cape", "Skirt"]:
		if not (s in excluded):
			character.set_part_color(s, theme_cols.pick_random(), theme_cols.pick_random(), theme_cols.pick_random())
	for s in WEAPON_SLOTS:
		if not (s in excluded):
			character.set_part_color(s, pool.pick_random(), pool.pick_random(), pool.pick_random())
	var hc: Color = hair.pick_random()
	if not ("Hair" in excluded):
		character.set_part_color("Hair", hc)
	if not ("FacialHair" in excluded):
		character.set_part_color("FacialHair", hc)
	if not ("Eyebrow" in excluded):
		character.set_part_color("Eyebrow", hc if flash < 80 else hair.pick_random())
	if not ("Eyes" in excluded):
		character.set_part_color("Eyes", eyes.pick_random())
	if not ("Mouth" in excluded):
		character.set_part_color("Mouth", lips.pick_random() if character.body_type == "Female" else character.skin_color)
	if not ("SkinDetails" in excluded) and character.get_equipped("SkinDetails") != "":
		var tc: Color = tatt.pick_random()
		if _dice() > 50:
			tc.a = randf_range(0.2, 1.0)
		character.set_part_color("SkinDetails", tc)


## BodySegmentSlider.RandomizeScale for every slider.
func _randomize_sliders() -> void:
	for seg in CC2DCharacter.SEGMENTS:
		character.set_body_slider(seg, Vector2(_slider_roll(), _slider_roll()))


func _slider_roll() -> float:
	var extreme := randf()
	if extreme > 0.85:
		return randf()
	if extreme > 0.5:
		return randf_range(0.3, 0.7)
	if extreme > 0.15:
		return randf_range(0.4, 0.6)
	return 0.5


# ================================================================== emotion page

func _build_emotion_page(page: VBoxContainer) -> void:
	var hint := _label("Click an expression to preview it. Idle, Talk, Hit and attack animations switch faces by themselves.", 13, true)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(hint)
	var sc := _scroll(page)
	_emotion_box = VBoxContainer.new()
	_emotion_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_emotion_box.add_theme_constant_override("separation", 8)
	sc.add_child(_emotion_box)
	_button(page, "Reset face", func():
		character.reset_emote()
		_emotion = ""
		_build_emotion_list(), "zoom_reset", "Back to the default face")


func _emotion_keys() -> Array:
	var keys := Array(character.get_emotion_names())
	keys.sort_custom(func(a, b):
		var ia := int(character.emotes[a].index)
		var ib := int(character.emotes[b].index)
		# built-in emotions (10+) first, then the custom slots
		return (ia + 100 if ia < 10 else ia) < (ib + 100 if ib < 10 else ib))
	return keys


func _build_emotion_list() -> void:
	for c in _emotion_box.get_children():
		c.queue_free()
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	_emotion_box.add_child(grid)
	for k in _emotion_keys():
		var key: String = k
		var e: Dictionary = character.emotes[key]
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 38)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.text = str(e.name) if int(e.index) >= 10 or str(e.name) != key else "Custom %d" % int(e.index)
		b.clip_text = true
		b.tooltip_text = "Preview %s" % b.text
		b.button_pressed = key == _emotion
		b.pressed.connect(func():
			_emotion = key
			character.emote(key)
			_build_emotion_list())
		grid.add_child(b)
	if _emotion == "" or not character.emotes.has(_emotion):
		return
	var card := PanelContainer.new()
	card.theme_type_variation = "Card"
	_emotion_box.add_child(card)
	var v := _vbox(card, 6)
	v.add_child(_section_label("Edit emotion"))
	var e: Dictionary = character.emotes[_emotion]
	if int(e.index) < 10:
		var nr := _hbox(v, 6)
		nr.add_child(_label("Name", 13, true))
		var le := LineEdit.new()
		le.text = "" if str(e.name) == _emotion else str(e.name)
		le.placeholder_text = "Custom emote name"
		le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		le.text_submitted.connect(func(t):
			e.name = t if t != "" else _emotion
			_build_emotion_list())
		le.focus_exited.connect(func():
			e.name = le.text if le.text != "" else _emotion)
		nr.add_child(le)
	var grid2 := GridContainer.new()
	grid2.columns = 2
	grid2.add_theme_constant_override("h_separation", 8)
	v.add_child(grid2)
	for fs in CC2DCharacter.FACE_SLOTS:
		var face_slot: String = fs
		var l := _label(_slot_title(face_slot), 13, true)
		grid2.add_child(l)
		var ob := OptionButton.new()
		ob.focus_mode = Control.FOCUS_NONE
		ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ob.clip_text = true
		ob.fit_to_longest_item = false
		ob.add_item("(default face)")
		ob.set_item_metadata(0, {})
		var ref = e.get(face_slot)
		var sel := 0
		for p in character.get_parts(face_slot):
			ob.add_item("%s (%s)" % [p.name, p.package])
			ob.set_item_metadata(ob.item_count - 1, {"name": p.name, "package": p.package})
			if ref is Dictionary and ref.name == p.name and ref.get("package", "") == p.package:
				sel = ob.item_count - 1
		ob.select(sel)
		ob.item_selected.connect(func(i):
			var md: Dictionary = ob.get_item_metadata(i)
			character.set_emote_part(_emotion, face_slot, md.get("name", ""), md.get("package", ""))
			character.emote(_emotion))
		grid2.add_child(ob)


# ================================================================== export page (CC2D's Export PNG)

func _build_export_page(page: VBoxContainer) -> void:
	_exporter = CC2DExporter.new()
	add_child(_exporter)
	var sc := _scroll(page)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	sc.add_child(box)

	var card := PanelContainer.new()
	card.theme_type_variation = "Card"
	box.add_child(card)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	card.add_child(grid)
	_export_preset = OptionButton.new()
	_export_preset.focus_mode = Control.FOCUS_NONE
	_export_preset.add_item("Custom")
	for pr in CC2DExporter.get_presets():
		_export_preset.add_item(pr.capitalize())
	_export_preset.item_selected.connect(func(i):
		if i > 0:
			_exporter.apply_preset(CC2DExporter.get_presets()[i - 1])
			_export_mode.select(int(_exporter.mode))
			_refresh_export())
	_grid_row(grid, "Preset", _export_preset)
	_export_mode = OptionButton.new()
	_export_mode.focus_mode = Control.FOCUS_NONE
	for m in EXPORT_MODES:
		_export_mode.add_item(m)
	_export_mode.item_selected.connect(func(_i): _refresh_export_info())
	_grid_row(grid, "Export as", _export_mode)
	var size_row := HBoxContainer.new()
	_export_fields.width = _spin(size_row, 16, 4096, 1)
	size_row.add_child(_label("×", 14, true))
	_export_fields.height = _spin(size_row, 16, 4096, 1)
	_grid_row(grid, "Size (px)", size_row)
	var fps_row := HBoxContainer.new()
	_export_fields.fps = _spin(fps_row, 1, 60, 1)
	_grid_row(grid, "FPS", fps_row)
	var pos_row := HBoxContainer.new()
	_export_fields.x = _spin(pos_row, -50, 50, 0.05)
	_export_fields.y = _spin(pos_row, -50, 50, 0.05)
	_grid_row(grid, "Offset X / Y", pos_row)
	var sc_row := HBoxContainer.new()
	_export_fields.scale = _spin(sc_row, 0.05, 10, 0.05)
	_grid_row(grid, "Scale", sc_row)
	var bg := OptionButton.new()
	bg.focus_mode = Control.FOCUS_NONE
	for b in CC2DExporter.Background.keys():
		bg.add_item(String(b).capitalize())
	bg.item_selected.connect(func(_i): _read_export())
	_grid_row(grid, "Background", bg)
	_export_fields.bg = bg
	var sm := OptionButton.new()
	sm.focus_mode = Control.FOCUS_NONE
	sm.add_item("Automatic")
	sm.add_item("Actual pixel size")
	sm.item_selected.connect(func(_i): _read_export())
	_grid_row(grid, "Scale mode", sm)
	_export_fields.scale_mode = sm
	var flags := HBoxContainer.new()
	for flag in ["flip", "loop_aim"]:
		var cb := CheckBox.new()
		cb.text = "Flip X" if flag == "flip" else "Loop aim layer"
		cb.focus_mode = Control.FOCUS_NONE
		cb.toggled.connect(func(_on): _read_export())
		flags.add_child(cb)
		_export_fields[flag] = cb
	_grid_row(grid, "", flags)
	var cfg := _hbox(box, 6)
	var lc := _button(cfg, "Load preset…", func():
		_ask_file(false, PackedStringArray(["*.pngconfig, *.json ; Export settings"]), "", func(p):
			_toast(("Loaded " if _exporter.load_config(p) == OK else "Couldn't load ") + p)
			_export_preset.select(0)
			_refresh_export()), "open_json", "Load a CC2D .pngconfig (Unity's work too)")
	lc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var svc := _button(cfg, "Save preset…", func():
		_ask_file(true, PackedStringArray(["*.pngconfig ; Export settings"]), "my_preset.pngconfig", func(p):
			_toast(("Saved " if _exporter.save_config(p) == OK else "Couldn't save ") + p)), "save_json", "Save these settings as a .pngconfig")
	svc.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# preview
	var pcard := PanelContainer.new()
	pcard.theme_type_variation = "Card"
	box.add_child(pcard)
	var pv := _vbox(pcard, 6)
	var ph := _hbox(pv, 6)
	var pl := _section_label("Preview")
	pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ph.add_child(pl)
	_button(ph, "Render frame", _render_preview, "png", "Render the current frame with these settings")
	var frame := Control.new()
	frame.custom_minimum_size = Vector2(0, 170)
	frame.clip_contents = true
	pv.add_child(frame)
	var checker := TextureRect.new()
	checker.texture = load(BG_DIR + "transparent.png")
	checker.stretch_mode = TextureRect.STRETCH_TILE
	checker.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	checker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	checker.modulate = Color(1, 1, 1, 0.35)
	frame.add_child(checker)
	_export_preview = TextureRect.new()
	_export_preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_export_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_export_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	frame.add_child(_export_preview)
	_export_info = _label("", 12, true)
	_export_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_export_info)

	_export_button = _button(page, "EXPORT…", func():
		var base := character.current_animation.to_snake_case()
		_ask_file(true, PackedStringArray(["*.png ; PNG"]), "%s.png" % (base if base != "" else "character"), _export_to), "png", "Choose where to save")
	_export_button.theme_type_variation = "AccentButton"
	_export_button.add_theme_font_override("font", _bold)
	_export_button.add_theme_font_size_override("font_size", 17)
	_export_button.custom_minimum_size = Vector2(0, 46)
	_exporter.progress.connect(func(i, n): _status.text = "Exporting frame %d / %d…" % [i, n])
	_exporter.apply_preset("default")
	_refresh_export()


func _grid_row(grid: GridContainer, text: String, control: Control) -> void:
	var l := _label(text, 13, true)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grid.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(control)


func _spin(row: HBoxContainer, lo: float, hi: float, step: float) -> SpinBox:
	var sb := SpinBox.new()
	sb.min_value = lo
	sb.max_value = hi
	sb.step = step
	sb.custom_minimum_size = Vector2(86, 0)
	sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sb.select_all_on_focus = true
	sb.value_changed.connect(func(_v): _read_export())
	row.add_child(sb)
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
	_refresh_export_info()


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
	_refresh_export_info()


func _refresh_export_info() -> void:
	if _export_info == null or character.animation_player == null:
		return
	var anim := character.current_animation
	var aim := character.aim_state
	var what := anim + (" + " + aim if aim != "" else "")
	if _export_mode.selected == 0:
		_export_info.text = "Exports the frame showing now (%s) as one %d×%d PNG." % [what, _exporter.width, _exporter.height]
	else:
		var n := _exporter.frame_count(character, anim, aim)
		_export_info.text = "Exports %s: %d frames of %d×%d at %d fps%s. Change the animation under the character." % [
			what, n, _exporter.width, _exporter.height, _exporter.target_fps,
			", packed into one sheet with a .json" if _export_mode.selected == 2 else ""]


func _render_preview() -> void:
	var img := await _exporter.render_image(character)
	if img != null:
		_export_preview.texture = ImageTexture.create_from_image(img)


func _export_to(path: String) -> void:
	var anim := character.current_animation
	var aim := character.aim_state
	_export_button.disabled = true
	match _export_mode.selected:
		0:
			var err := await _exporter.export_image(character, path)
			_toast(("Saved " if err == OK else "Couldn't save ") + path)
		1:
			var files := await _exporter.export_sequence(character, path, anim, aim)
			_toast("Saved %d frames: %s … %s" % [files.size(), files[0].get_file() if files.size() > 0 else "", files[-1].get_file() if files.size() > 0 else ""])
		2:
			var sheet := await _exporter.export_sheet(character, path, anim, aim)
			_toast("Saved a %dx%d sprite sheet (%d frames of %dx%d) to %s, with a .json next to it" % [
				sheet.get_width(), sheet.get_height(), _exporter.frame_count(character, anim, aim), _exporter.width, _exporter.height, path])
	_export_button.disabled = false


# ================================================================== COLOR panel

func _build_color_panel(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = "SidePanel"
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -COLOR_W
	panel.offset_top = TOP_H
	root.add_child(panel)
	var sc := _scroll(panel)
	var m := _margin(sc, 14, 14, 14, 14)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := _vbox(m, 10)
	var head := _hbox(box, 10)
	var ic := TextureRect.new()
	ic.texture = _icon("brush")
	ic.custom_minimum_size = Vector2(30, 30)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(ic)
	var t := _label("COLOR", 22, false, true)
	head.add_child(t)
	_color_info = _label("", 13, true)
	_color_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_color_info.custom_minimum_size = Vector2(COLOR_W - 30, 0)
	box.add_child(_color_info)

	_swatch_box = _hbox(box, 8)
	for i in 3:
		var idx: int = i
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 3)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_swatch_box.add_child(v)
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 44)
		b.pressed.connect(func():
			_color_index = idx
			_refresh_color_panel())
		v.add_child(b)
		var l := _label("", 11, true)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		v.add_child(l)
		_swatches.append(b)
		_swatch_labels.append(l)

	_picker = ColorPicker.new()
	_picker.edit_alpha = false
	_picker.presets_visible = false
	_picker.can_add_swatches = false
	_picker.color_modes_visible = false
	_picker.sampler_visible = false
	_picker.sliders_visible = false
	_picker.hex_visible = true
	_picker.picker_shape = ColorPicker.SHAPE_HSV_RECTANGLE
	_picker.add_theme_constant_override("sv_width", int(COLOR_W - 80))
	_picker.add_theme_constant_override("sv_height", 150)
	_picker.add_theme_constant_override("h_width", 22)
	_picker.color_changed.connect(func(c):
		if not _updating:
			_set_target_color(_color_index, c)
			_recent_timer = 0.8)
	box.add_child(_picker)

	_opacity_row = _hbox(box, 8)
	_opacity_row.add_child(_label("Opacity", 13, true))
	_opacity = _hslider(0.0, 1.0, 0.01, 1.0)
	_opacity.value_changed.connect(func(v):
		if not _updating and slot == "SkinDetails":
			var c: Color = character.get_part_colors(slot)[0]
			c.a = v
			character.set_part_color(slot, c))
	_opacity_row.add_child(_opacity)

	_palette_box = _vbox(box, 6)
	var ph := _hbox(_palette_box, 8)
	var pl := _section_label("Palette")
	pl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ph.add_child(pl)
	_palette_option = OptionButton.new()
	_palette_option.focus_mode = Control.FOCUS_NONE
	_palette_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for p in _palettes:
		_palette_option.add_item(p.name)
	_palette_option.item_selected.connect(func(_i): _build_palette())
	ph.add_child(_palette_option)
	_palette_flow = HFlowContainer.new()
	_palette_flow.add_theme_constant_override("h_separation", 4)
	_palette_flow.add_theme_constant_override("v_separation", 4)
	_palette_box.add_child(_palette_flow)
	_palette_box.add_child(_section_label("Recent"))
	_recent_flow = HFlowContainer.new()
	_recent_flow.add_theme_constant_override("h_separation", 4)
	_recent_flow.add_theme_constant_override("v_separation", 4)
	_recent_flow.custom_minimum_size = Vector2(0, 24)
	_palette_box.add_child(_recent_flow)

	_color_actions = HFlowContainer.new()
	_color_actions.add_theme_constant_override("h_separation", 6)
	_color_actions.add_theme_constant_override("v_separation", 6)
	box.add_child(_color_actions)
	_button(_color_actions, "Random", _random_colors, "dice", "Random colours from CC2D's palettes")
	_btn_pack_colors = _button(_color_actions, "Pack colours", func():
		var p = _equipped_part(slot)
		if p is Dictionary and p.has("colors"):
			var c := _designed_colors(p)
			character.set_part_color(slot, c[0], c[1], c[2])
			_refresh_color_panel()
			_paint_tiles(), "color_palette", "Back to this part's designed colours")
	_btn_copy_hair = _button(_color_actions, "Hair colour", func():
		_set_target_color(0, character.get_part_colors("Hair")[0])
		_refresh_color_panel(), "hair", "Use the hair colour")
	_btn_copy_skin = _button(_color_actions, "Skin colour", func():
		_set_target_color(0, character.skin_color)
		_refresh_color_panel(), "body", "Use the skin colour")
	_button(_color_actions, "Copy", func():
		_clip_color = _picker.color
		DisplayServer.clipboard_set("#" + _picker.color.to_html(false))
		_toast("Copied #" + _picker.color.to_html(false)), "copy", "Copy this colour")
	_button(_color_actions, "Paste", func():
		var c := _clip_color
		var txt := DisplayServer.clipboard_get().strip_edges()
		if Color.html_is_valid(txt):
			c = Color.html(txt)
		if c.a > 0.0:
			_set_target_color(_color_index, c)
			_refresh_color_panel(), "paste", "Paste a copied colour (or a #hex from the clipboard)")
	_build_palette()


func _swatch_style(c: Color, active: bool) -> StyleBoxFlat:
	var s := _sb(Color(c, 1.0), 6, C_ACCENT if active else Color(1, 1, 1, 0.18), 3 if active else 1)
	return s


func _color_button(c: Color, px: int, cb: Callable) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(px, px)
	var st := _sb(Color(c, 1.0), 4, Color(1, 1, 1, 0.12), 1, Vector4(0, 0, 0, 0))
	b.add_theme_stylebox_override("normal", st)
	var hv := _sb(Color(c, 1.0), 4, Color.WHITE, 2, Vector4(0, 0, 0, 0))
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", hv)
	b.tooltip_text = "#" + c.to_html(false)
	b.pressed.connect(cb)
	return b


func _build_palette() -> void:
	for ch in _palette_flow.get_children():
		ch.queue_free()
	if _palettes.is_empty():
		return
	var p: Dictionary = _palettes[maxi(0, _palette_option.selected)]
	for c in p.colors:
		var col: Color = c
		_palette_flow.add_child(_color_button(col, 24, func(): _apply_swatch_color(col)))


func _build_recent() -> void:
	for ch in _recent_flow.get_children():
		ch.queue_free()
	for c in _recent:
		var col: Color = c
		_recent_flow.add_child(_color_button(col, 24, func(): _apply_swatch_color(col)))


func _push_recent(c: Color) -> void:
	c.a = 1.0
	for r in _recent:
		if r.is_equal_approx(c):
			return
	_recent.push_front(c)
	if _recent.size() > 9:
		_recent.resize(9)
	_build_recent()


func _apply_swatch_color(c: Color) -> void:
	if _cmode == "":
		return
	_set_target_color(_color_index, c)
	_push_recent(c)
	_refresh_color_panel()


## Picks which colours the COLOR panel shows for the open category.
func _refresh_color_panel() -> void:
	if _picker == null:
		return
	_updating = true
	var info: Dictionary = CATS.get(cat, {})
	var kind: String = info.get("kind", "")
	var labels: Array = []
	if cat == "body" or kind == "sliders" or kind == "randomize":
		_cmode = "body"
		labels = ["Skin", "Tint"]
		_color_info.text = "Skin colour (body, ears and nose) and a tint over the whole character."
	elif kind == "parts" and slot in CC2DCharacter.SKIN_SLOTS:
		_cmode = "skin"
		labels = ["Skin"]
		_color_info.text = "%s uses the skin colour." % _slot_title(slot)
	elif kind == "parts":
		var eq := character.get_equipped(slot)
		if eq == "":
			_cmode = ""
			_color_info.text = "No part selected. Please select a part to colour."
		else:
			_cmode = "part"
			labels = ["Colour"] if _is_single_color(slot) else ["Colour 1", "Colour 2", "Colour 3"]
			_color_info.text = "%s · %s (%s)" % [_slot_title(slot), eq, character.get_equipped_package(slot)]
	else:
		_cmode = ""
		_color_info.text = "Nothing to colour here. Choose a part in the Body, Face, Equipment, Weapon or Gun menu."
	_color_index = clampi(_color_index, 0, maxi(0, labels.size() - 1))
	_swatch_box.visible = not labels.is_empty()
	for i in 3:
		var show := i < labels.size()
		_swatches[i].get_parent().visible = show
		if show:
			var c := _get_target_color(i)
			var st := _swatch_style(c, i == _color_index and labels.size() > 1)
			for s in ["normal", "hover", "pressed", "hover_pressed"]:
				_swatches[i].add_theme_stylebox_override(s, st)
			_swatch_labels[i].text = labels[i]
			_swatches[i].tooltip_text = "%s  #%s\nClick to edit" % [labels[i], c.to_html(false)]
	_picker.visible = _cmode != ""
	_palette_box.visible = _cmode != ""
	_color_actions.visible = _cmode != ""
	if _cmode != "":
		var c := _get_target_color(_color_index)
		c.a = 1.0
		_picker.color = c
	var p = _equipped_part(slot) if slot != "" else null
	_btn_pack_colors.visible = _cmode == "part" and p is Dictionary and p.has("colors")
	_btn_copy_hair.visible = _cmode == "part" and slot in ["Eyebrow", "FacialHair"]
	_btn_copy_skin.visible = _cmode == "part" and slot == "Mouth"
	_opacity_row.visible = _cmode == "part" and slot == "SkinDetails"
	if _opacity_row.visible:
		_opacity.value = character.get_part_colors(slot)[0].a
	_updating = false


func _get_target_color(i: int) -> Color:
	match _cmode:
		"body":
			return character.skin_color if i == 0 else character.tint_color
		"skin":
			return character.skin_color
		"part":
			return character.get_part_colors(slot)[i]
	return Color.GRAY


func _set_target_color(i: int, c: Color) -> void:
	match _cmode:
		"body":
			if i == 0:
				character.set_skin_color(c)
			else:
				character.set_tint_color(c)
		"skin":
			character.set_skin_color(c)
		"part":
			var cols := character.get_part_colors(slot)
			if slot == "SkinDetails":
				c.a = cols[0].a
			cols[i] = c
			if _is_single_color(slot):
				character.set_part_color(slot, c)
			else:
				character.set_part_color(slot, cols[0], cols[1], cols[2])
		_:
			return
	# swatch + thumbnails follow
	if i < _swatches.size():
		var st := _swatch_style(c, i == _color_index and _swatches[1].get_parent().visible)
		for s in ["normal", "hover", "pressed", "hover_pressed"]:
			_swatches[i].add_theme_stylebox_override(s, st)
	_paint_tiles()


func _random_colors() -> void:
	match _cmode:
		"body", "skin":
			character.set_skin_color((_pal("Bleached") if _dice() > 80 else _pal("Skin")).pick_random())
		"part":
			var ex: Array = CC2DCharacter.SLOTS.filter(func(s): return s != slot)
			_randomize_colors(ex)
	_refresh_color_panel()
	_paint_tiles()


# ================================================================== stage (character view)

func _build_stage() -> void:
	var bp := PanelContainer.new()
	bp.anchor_left = 0.5
	bp.anchor_right = 0.5
	bp.anchor_top = 1.0
	bp.anchor_bottom = 1.0
	bp.offset_left = -226
	bp.offset_right = 226
	bp.offset_top = -BOTTOM_H + 2
	bp.offset_bottom = -8
	bp.add_theme_stylebox_override("panel", _sb(Color(0.04, 0.045, 0.055, 0.72), 12, Color(1, 1, 1, 0.07), 1, Vector4(10, 6, 10, 8)))
	_stage.add_child(bp)
	var bar := VBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	bp.add_child(bar)
	# zoom
	var zr := _hbox(bar, 6)
	zr.alignment = BoxContainer.ALIGNMENT_CENTER
	_icon_button(zr, "zoom_out", func(): _set_zoom(_zoom / 1.25), "Zoom out", 14)
	_zoom_slider = _hslider(0.6, 4.0, 0.01, 1.0)
	_zoom_slider.custom_minimum_size = Vector2(240, 0)
	_zoom_slider.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_zoom_slider.tooltip_text = "Zoom (mouse wheel over the character works too; drag to move)"
	_zoom_slider.value_changed.connect(func(v):
		if not _updating:
			_zoom = v)
	zr.add_child(_zoom_slider)
	_icon_button(zr, "zoom_in", func(): _set_zoom(_zoom * 1.25), "Zoom in", 14)
	_icon_button(zr, "zoom_reset", func():
		_pan = Vector2.ZERO
		_set_zoom(1.0), "Reset the view", 16)
	# base layer
	var ar := _layer_row(bar, "BASE LAYER", "body", "Base Layer animation")
	_anim_option = ar[1]
	_anim_option.item_selected.connect(func(i): _play_anim(_anim_names[i]))
	ar[0].pressed.connect(func(): _step_anim(-1))
	ar[2].pressed.connect(func(): _step_anim(1))
	_icon_button(ar[3], "play", func():
		character.current_animation = ""
		character.play(_anim_names[_anim_option.selected], 0.0), "Play it again from the start", 14)
	# aim layer
	var am := _layer_row(bar, "AIM LAYER", "aim", "Aim Layer: aiming and shooting on top of the base animation")
	_aim_row = am[3]
	_aim_option = am[1]
	_aim_option.item_selected.connect(func(i): _play_aim(_aim_names[i]))
	am[0].pressed.connect(func(): _step_aim(-1))
	am[2].pressed.connect(func(): _step_aim(1))
	_aim_slider = _hslider(-1.0, 1.0, 0.01, 0.0)
	_aim_slider.custom_minimum_size = Vector2(60, 0)
	_aim_slider.tooltip_text = "Aim angle: down … up"
	_aim_slider.value_changed.connect(func(v): character.set_aim(v))
	_aim_row.add_child(_aim_slider)

	# background changer (top right of the stage) + status (top left)
	var bl := HBoxContainer.new()
	bl.anchor_left = 1.0
	bl.anchor_right = 1.0
	bl.offset_left = -52
	bl.offset_right = -10
	bl.offset_top = 8
	bl.offset_bottom = 44
	_stage.add_child(bl)
	var bgb := _icon_button(bl, "background", func(): _set_background(_bg_index + 1), "Change the background (right-click: previous)", 22)
	bgb.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
			_set_background(_bg_index - 1))
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 13)
	_status.add_theme_color_override("font_color", C_TEXT)
	_status.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_status.add_theme_constant_override("shadow_offset_y", 1)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.anchor_right = 1.0
	_status.offset_left = 14
	_status.offset_top = 10
	_status.offset_right = -60
	_status.offset_bottom = 50
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_status)
	_toast("Click a menu at the top, a category on the left, then a part. Colours are on the right.")


## One selector row: [label] ◀ [name] ▶ [extra...]. Returns [left, option, right, row].
func _layer_row(parent: Control, text: String, icon_name: String, tip: String) -> Array:
	var r := _hbox(parent, 4)
	var ic := TextureRect.new()
	ic.texture = _icon(icon_name)
	ic.custom_minimum_size = Vector2(18, 18)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.modulate = C_DIM
	ic.tooltip_text = tip
	r.add_child(ic)
	var l := _label(text, 11, true, true)
	l.custom_minimum_size = Vector2(70, 0)
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	r.add_child(l)
	var left := _icon_button(r, "arrow_left", func(): pass, "Previous", 12)
	var ob := OptionButton.new()
	ob.focus_mode = Control.FOCUS_NONE
	ob.custom_minimum_size = Vector2(190, 32)
	ob.fit_to_longest_item = false
	ob.clip_text = true
	ob.alignment = HORIZONTAL_ALIGNMENT_CENTER
	ob.tooltip_text = tip
	r.add_child(ob)
	var right := _icon_button(r, "arrow_right", func(): pass, "Next", 12)
	return [left, ob, right, r]


func _refresh_animation_lists() -> void:
	var names := character.get_animation_names()
	_anim_names.clear()
	for n in BASE_LAYER_ORDER:
		if names.has(n):
			_anim_names.append(n)
	for n in names:
		if n != "RESET" and not _anim_names.has(n):
			_anim_names.append(n)
	_anim_option.clear()
	for n in _anim_names:
		_anim_option.add_item(n)
	var i := _anim_names.find(character.current_animation)
	_anim_option.select(maxi(i, 0))
	_aim_names = ["None"]
	for st in character.get_aim_states():
		if st != "None":
			_aim_names.append(st)
	_aim_option.clear()
	for n in _aim_names:
		_aim_option.add_item(n)
	var a := _aim_names.find(character.aim_state)
	_aim_option.select(maxi(a, 0))
	_aim_slider.visible = character.aim_state != ""
	_aim_slider.set_value_no_signal(character.aim_value)


func _play_anim(anim: String) -> void:
	character.play(anim)
	_anim_option.select(_anim_names.find(anim))
	_refresh_export_info()


func _step_anim(step: int) -> void:
	var i := posmod(_anim_names.find(character.current_animation) + step, _anim_names.size())
	_play_anim(_anim_names[i])


func _play_aim(state: String) -> void:
	character.play_aim("" if state == "None" else state)
	_aim_option.select(_aim_names.find(state))
	_aim_slider.visible = state != "None"
	_refresh_export_info()


func _step_aim(step: int) -> void:
	var cur := character.aim_state if character.aim_state != "" else "None"
	var i := posmod(_aim_names.find(cur) + step, _aim_names.size())
	_play_aim(_aim_names[i])


func _set_zoom(z: float) -> void:
	_zoom = clampf(z, 0.6, 4.0)
	_updating = true
	_zoom_slider.value = _zoom
	_updating = false


func _set_background(i: int) -> void:
	_bg_index = posmod(i, BACKGROUNDS.size())
	var b: String = BACKGROUNDS[_bg_index]
	if b.begins_with("#"):
		_bg_rect.texture = null
		_bg_color.color = Color.html(b)
	else:
		_bg_rect.texture = load(BG_DIR + b)
		_bg_color.color = Color.BLACK


func _on_stage_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed:
		match ev.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_set_zoom(_zoom * 1.1)
			MOUSE_BUTTON_WHEEL_DOWN:
				_set_zoom(_zoom / 1.1)
			MOUSE_BUTTON_LEFT:
				if ev.double_click:
					_pan = Vector2.ZERO
					_set_zoom(1.0)
	elif ev is InputEventMouseMotion and ev.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_MIDDLE | MOUSE_BUTTON_MASK_RIGHT):
		_pan -= ev.relative / camera.zoom.x


## Frames the character in the stage (between the side panels, above the animation controls).
## Zooming in moves the focus up towards the face.
func _layout_camera() -> void:
	if _stage == null:
		return
	var r := _stage.get_global_rect()
	var view := get_viewport().get_visible_rect().size
	var avail := r.size.y - BOTTOM_H - 20.0
	var fit := maxf(0.2, avail / 590.0)   # whole character (incl. tall hats) with some headroom
	var z := fit * _zoom
	var t := clampf((_zoom - 1.0) / 1.6, 0.0, 1.0)
	var focus := Vector2(0, lerpf(-250.0, -440.0, t)) + _pan
	var target := Vector2(r.get_center().x, r.position.y + 24.0 + avail * 0.5)
	camera.zoom = Vector2(z, z)
	camera.position = focus - (target - view * 0.5) / z


# ================================================================== file actions

func _run_action(c: String) -> void:
	match c:
		"new":
			_confirm.popup_centered()
		"open":
			_ask_file(false, PackedStringArray(["*.json ; CC2D character"]), "", func(p):
				var err := character.load_character_data(p)
				_toast(("Loaded " if err == OK else "Couldn't load ") + p)
				_after_load())
		"save":
			_ask_file(true, PackedStringArray(["*.json ; CC2D character"]), "my_character.json", func(p):
				var err := character.save_character(p)
				_toast(("Saved " if err == OK else "Couldn't save ") + p))
		"clear":
			clear_items()
		"demo":
			_go_demo()


func _ask_file(save: bool, filters: PackedStringArray, file_name: String, cb: Callable) -> void:
	_file_cb = cb
	_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE if save else FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.filters = filters
	_file_dialog.current_dir = ProjectSettings.globalize_path("res://characters")
	if file_name != "":
		_file_dialog.current_file = file_name
	_file_dialog.popup_centered(Vector2i(900, 600))


func _new_character() -> void:
	character.apply_character_data(_default_data)
	for seg in CC2DCharacter.SEGMENTS:
		character.set_body_slider(seg, Vector2(0.5, 0.5))
	_after_load()
	_toast("New character")


## Slots that "Clear All Items" empties: clothing and weapons. Body, skin and face stay.
const ITEM_SLOTS := ["Helmet", "Armor", "Pants", "Skirt", "Gloves", "Boots", "Cape", "MainHand", "OffHand"]


func clear_items() -> void:
	for s in ITEM_SLOTS:
		character.equip_part(s, "")
	_toast("All items removed")
	_show_category(cat if CATS.get(cat, {}).get("kind", "") != "action" else "armor")


func _after_load() -> void:
	_emotion = ""
	_refresh_animation_lists()
	_refresh_sliders()
	_show_category(cat)


func _go_demo() -> void:
	Engine.set_meta(SHARED_META, character.get_character_data())
	get_tree().change_scene_to_file(DEMO_SCENE)
