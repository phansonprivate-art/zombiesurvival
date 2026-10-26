class_name InputSetup
extends RefCounted
## Tastenbelegung an einer Stelle. Wird beim Start registriert (statt im project.godot),
## damit sie lesbar und testbar bleibt.

const KEYS := {
	"move_forward": [KEY_W],
	"move_back": [KEY_S],
	"move_left": [KEY_A],
	"move_right": [KEY_D],
	"sprint": [KEY_SHIFT],
	"interact": [KEY_F],
	"cam_rotate_left": [KEY_Q],
	"cam_rotate_right": [KEY_E],
	"cam_pan_up": [KEY_UP],
	"cam_pan_down": [KEY_DOWN],
	"cam_pan_left": [KEY_LEFT],
	"cam_pan_right": [KEY_RIGHT],
	"cam_center": [KEY_SPACE],
	"build_menu": [KEY_B],
	"build_rotate": [KEY_R],
	"inventory": [KEY_I, KEY_TAB],
	"map": [KEY_M],
	"pause": [KEY_ESCAPE],
}


static func register() -> void:
	for action in KEYS:
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
		else:
			InputMap.add_action(action)
		for key in KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
