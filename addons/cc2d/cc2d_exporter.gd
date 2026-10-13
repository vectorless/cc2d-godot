class_name CC2DExporter
extends Node
## Renders a CC2DCharacter to PNG: a single image, a PNG sequence of an animation (+ Aim layer),
## or the same frames packed into one sprite sheet. Port of CC2D's Export PNG screen
## (UIExportPNG): same settings, same framing and the same .pngconfig / preset JSON.
##
##   var ex := CC2DExporter.new()
##   add_child(ex)
##   ex.apply_preset("fullbody")                       # or load_config("user://my.pngconfig")
##   await ex.export_image(character, "user://hero.png")
##   var files := await ex.export_sequence(character, "user://hero_walk.png", "Walk")
##   await ex.export_sheet(character, "user://hero_shot.png", "Idle", "Shot Main Hand")
##
## The character itself is left alone: the exporter renders a copy of it (same parts, colours,
## body sliders, expression) in its own SubViewport.

enum Background { TRANSPARENT, BLACK, WHITE, GRAY, MAGENTA, GREEN }
enum ScaleMode { AUTOMATIC, ACTUAL_PIXEL_SIZE }
enum Mode { SINGLE_IMAGE, PNG_SEQUENCE }

const PRESETS_DIR := "res://addons/cc2d/export_presets/"
const PPU := 100.0                       # Unity pixels per unit (1 unit = 100 px in this port)
const CAMERA_Y := 6.0                    # the export camera in CC2D's Creator UI scene, in units
const AUTO_ORTHO := 10.0                 # its orthographic size in Automatic mode
const BG_COLORS := [Color(0, 0, 0, 0), Color.BLACK, Color.WHITE, Color(0.5, 0.5, 0.5), Color.MAGENTA, Color.GREEN]

@export var target_fps := 12
@export var width := 512
@export var height := 512
@export var background := Background.TRANSPARENT
@export var mode := Mode.SINGLE_IMAGE
@export var char_position := Vector2.ZERO   ## Unity units, +y up (as in CC2D)
@export var char_scale := 1.0
@export var scale_mode := ScaleMode.AUTOMATIC
@export var flip := false
@export var loop_aim_layer := false
@export var super_sampling := 2           ## render at N x and scale down, as CC2D does

signal progress(frame: int, total: int)

const UNPREMULTIPLY := """shader_type canvas_item;
render_mode blend_premul_alpha;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	COLOR = vec4(c.a > 0.0 ? c.rgb / c.a : vec3(0.0), c.a);
}
"""

var _vp: SubViewport
var _out: SubViewport      # second pass: straight (not premultiplied) alpha, for PNG
var _cam: Camera2D
var _bg: ColorRect
var _copy: CC2DCharacter


# ------------------------------------------------------------------ config

## Unity's ExportConfig JSON (a .pngconfig file, or one of CC2D's default presets).
func load_config(path: String) -> Error:
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary:
		return ERR_PARSE_ERROR
	apply_config(d)
	return OK


## Built-in presets from CC2D: "default", "portrait", "fullbody", "animation".
func apply_preset(preset_name: String) -> Error:
	return load_config(PRESETS_DIR + preset_name.to_lower() + ".json")


static func get_presets() -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(PRESETS_DIR):
		if f.ends_with(".json"):
			out.append(f.get_basename())
	return out


func apply_config(d: Dictionary) -> void:
	target_fps = int(d.get("targetFPS", target_fps))
	width = int(d.get("width", width))
	height = int(d.get("height", height))
	background = int(d.get("bgColor", background)) as Background
	mode = int(d.get("exportMode", mode)) as Mode
	var p: Dictionary = d.get("charPosition", {})
	char_position = Vector2(float(p.get("x", char_position.x)), float(p.get("y", char_position.y)))
	char_scale = float(d.get("charScale", {}).get("x", char_scale))
	scale_mode = int(d.get("scaleMode", scale_mode)) as ScaleMode


func get_config() -> Dictionary:
	return {
		"targetFPS": target_fps, "width": width, "height": height, "bgColor": int(background),
		"exportMode": int(mode),
		"charPosition": {"x": char_position.x, "y": char_position.y, "z": 0.0},
		"charScale": {"x": char_scale, "y": char_scale, "z": 1.0},
		"scaleMode": int(scale_mode),
	}


func save_config(path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(get_config(), "\t"))
	return OK


# ------------------------------------------------------------------ timing (UIExportPNG.GetAnimationLength)

## Seconds the sequence lasts: the base animation, repeated until the aim state has played
## through (unless loop_aim_layer), or the aim state alone if there's no base animation.
func sequence_length(character: CC2DCharacter, base_anim: String, aim := "") -> float:
	var base_len := character.get_animation_length(base_anim)
	var aim_len := character.get_aim_length(aim) if aim != "" and aim != "None" else 0.0
	var target := base_len
	if target <= 0.0 and aim_len > target:
		target = aim_len
	elif not loop_aim_layer and base_len > 0.0:
		while aim_len > target:
			target += base_len
	return target


func frame_count(character: CC2DCharacter, base_anim: String, aim := "") -> int:
	return maxi(1, int(sequence_length(character, base_anim, aim) * target_fps))


# ------------------------------------------------------------------ export

## The character as it is now (or posed on base_anim / aim at the given times) to one PNG.
func export_image(character: CC2DCharacter, path: String, base_anim := "", base_time := 0.0,
		aim := "", aim_time := 0.0, emotion := "") -> Error:
	var img := await render_image(character, base_anim, base_time, aim, aim_time, emotion)
	return img.save_png(path) if img != null else ERR_CANT_CREATE


## A PNG sequence: <path without .png>_000.png, _001.png, ... Returns the files written.
func export_sequence(character: CC2DCharacter, path: String, base_anim: String, aim := "",
		emotion := "") -> PackedStringArray:
	var base := path.trim_suffix(".png") + "_"
	var out := PackedStringArray()
	var frames := await render_frames(character, base_anim, aim, emotion)
	for i in frames.size():
		var file := base + ("%03d" % i) + ".png"
		if frames[i].save_png(file) == OK:
			out.append(file)
	return out


## The same frames as export_sequence, packed left-to-right, top-to-bottom into one PNG
## (columns 0 = as square as possible). Writes <path>.json next to it with the frame size,
## count and fps. Returns the sheet image.
func export_sheet(character: CC2DCharacter, path: String, base_anim: String, aim := "",
		emotion := "", columns := 0) -> Image:
	var frames := await render_frames(character, base_anim, aim, emotion)
	var n := frames.size()
	var cols := columns if columns > 0 else int(ceil(sqrt(float(n))))
	var rows := int(ceil(float(n) / cols))
	var sheet := Image.create(width * cols, height * rows, false, Image.FORMAT_RGBA8)
	for i in n:
		sheet.blit_rect(frames[i], Rect2i(0, 0, width, height), Vector2i((i % cols) * width, (i / cols) * height))
	sheet.save_png(path)
	var meta := {"image": path.get_file(), "frame_width": width, "frame_height": height,
		"columns": cols, "rows": rows, "frames": n, "fps": target_fps,
		"animation": base_anim, "aim": aim}
	var f := FileAccess.open(path.get_basename() + ".json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(meta, "\t"))
	return sheet


## Every frame of base_anim (+ aim) at target_fps, as UIExportPNG.SaveSequence samples them.
func render_frames(character: CC2DCharacter, base_anim: String, aim := "", emotion := "") -> Array[Image]:
	var out: Array[Image] = []
	await _setup(character, emotion)
	var base_len := _copy.get_animation_length(base_anim)
	var aim_len := _copy.get_aim_length(aim) if aim != "" and aim != "None" else 0.0
	var n := frame_count(_copy, base_anim, aim)
	var dt := 1.0 / float(target_fps)
	var aim_t := 0.0
	for i in n:
		var t := i * dt
		var bt := fmod(t, base_len) if base_len > 0.0 and _copy.animation_player.get_animation(base_anim).loop_mode != Animation.LOOP_NONE else minf(t, base_len)
		# The aim layer plays once and holds its last frame, unless loop_aim_layer.
		if t <= aim_len or loop_aim_layer:
			aim_t = t
		_copy.pose(base_anim, bt, aim, aim_t)
		out.append(await _grab())
		progress.emit(i + 1, n)
	_teardown()
	return out


## One frame. With base_anim "" the copy keeps whatever the character is playing, at its
## current position (aim state and time included).
func render_image(character: CC2DCharacter, base_anim := "", base_time := 0.0, aim := "",
		aim_time := 0.0, emotion := "") -> Image:
	await _setup(character, emotion)
	if base_anim == "":
		base_anim = character.current_animation
		if character.animation_player != null:
			base_time = character.animation_player.current_animation_position
		aim = character.aim_state
		aim_time = character._aim_phase * character.get_aim_length(aim) if aim != "" else 0.0
	_copy.aim_value = character.aim_value
	_copy.pose(base_anim, base_time, aim, aim_time)
	var img := await _grab()
	_teardown()
	return img


# ------------------------------------------------------------------ internals

func _setup(character: CC2DCharacter, emotion: String) -> void:
	_teardown()
	var ss := maxi(1, super_sampling)
	_vp = SubViewport.new()
	_vp.size = Vector2i(width * ss, height * ss)
	_vp.transparent_bg = true
	_vp.disable_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	add_child(_vp)
	# Camera: CC2D's preview camera sits at (0, 6) units; Automatic mode shows 20 units of
	# height, Actual Pixel Size shows height / 100 * 2 units.
	var ortho := AUTO_ORTHO if scale_mode == ScaleMode.AUTOMATIC else float(height) / PPU
	_cam = Camera2D.new()
	_cam.position = Vector2(0, -CAMERA_Y * PPU)
	_cam.zoom = Vector2.ONE * float(_vp.size.y) / (2.0 * ortho * PPU)
	_vp.add_child(_cam)
	_cam.make_current()
	var bgc: Color = BG_COLORS[clampi(int(background), 0, BG_COLORS.size() - 1)]
	if bgc.a > 0.0:
		_bg = ColorRect.new()
		_bg.color = bgc
		_bg.z_index = RenderingServer.CANVAS_ITEM_Z_MIN
		var view := Vector2(_vp.size) / _cam.zoom
		_bg.position = _cam.position - view
		_bg.size = view * 2.0
		_vp.add_child(_bg)
	# Drawing over a transparent background leaves colours premultiplied by alpha; PNG wants
	# them straight, so the frame goes through one more pass.
	_out = SubViewport.new()
	_out.size = _vp.size
	_out.transparent_bg = true
	_out.disable_3d = true
	_out.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_out)
	var rect := TextureRect.new()
	rect.texture = _vp.get_texture()
	rect.size = Vector2(_vp.size)
	var sh := Shader.new()
	sh.code = UNPREMULTIPLY
	var mat := ShaderMaterial.new()
	mat.shader = sh
	rect.material = mat
	_out.add_child(rect)
	_copy = CC2DCharacter.new()
	_copy.autoplay = false
	_vp.add_child(_copy)
	_copy.load_character(character.loaded_file if character.loaded_file != "" else character.character_file)
	_copy.apply_character_data(character.get_character_data())
	_copy.position = Vector2(char_position.x, -char_position.y) * PPU
	_copy.scale = Vector2(-char_scale if flip else char_scale, char_scale)
	if emotion != "" and emotion != "None":
		_copy.emote(emotion)
	elif character._is_emoting and character.current_emote != "":
		_copy.emote(character.current_emote)
	await RenderingServer.frame_post_draw


func _grab() -> Image:
	# One frame for the pose (and any muzzle flash pre-simulation) to land, one to draw it, and
	# one for the un-premultiply pass to pick it up.
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := _out.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	if super_sampling > 1:
		img.resize(width, height, Image.INTERPOLATE_BILINEAR)
	return img


func _teardown() -> void:
	if _vp != null:
		_vp.queue_free()
	if _out != null:
		_out.queue_free()
	_vp = null
	_out = null
	_cam = null
	_bg = null
	_copy = null
