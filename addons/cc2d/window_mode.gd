extends Node
## Autoload: F11 (or Alt+Enter) toggles fullscreen. The window starts maximized
## (project setting display/window/size/mode).


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.keycode == KEY_F11 or (k.keycode == KEY_ENTER and k.alt_pressed):
		var w := get_window()
		w.mode = Window.MODE_MAXIMIZED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
		get_viewport().set_input_as_handled()
