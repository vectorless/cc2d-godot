## Port of CharacterWalker.cs: A/D or Left/Right to walk, hold Shift to run.
## Gamepad: left stick to walk, X / Square to run.
extends Node2D

@export var walk_speed := 190.0
@export var run_speed := 410.0
@export var idle_state := "Idle"
@export var walk_state := "Walk"
@export var run_state := "Run"
## Tick if the character's art faces left at positive X scale.
@export var art_faces_left := false
@export var character_path: NodePath = ^"Character"
@export var camera_path: NodePath = ^"../Camera2D"
@export var camera_smooth := 5.0

@onready var character = get_node(character_path)
@onready var camera: Camera2D = get_node_or_null(camera_path)
var _base_scale_x := 1.0


func _ready() -> void:
	_base_scale_x = absf(character.scale.x)


func _process(delta: float) -> void:
	var input := 0.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		input -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input += 1.0
	var stick := Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
	if absf(stick) > 0.2:
		input = stick
	var running := Input.is_key_pressed(KEY_SHIFT) or Input.is_joy_button_pressed(0, JOY_BUTTON_X)

	if absf(input) > 0.01:
		position.x += input * (run_speed if running else walk_speed) * delta
		var face_right := input > 0.0
		if art_faces_left:
			face_right = not face_right
		character.scale.x = _base_scale_x if face_right else -_base_scale_x
		character.play(run_state if running else walk_state)
	else:
		character.play(idle_state)

	if camera:
		camera.position.x = lerpf(camera.position.x, position.x, 1.0 - exp(-camera_smooth * delta))
