extends RefCounted
## Isola o singleton de entrada sem ler/escrever as preferencias pessoais.

var saved: Dictionary = {}
var _tree_was_paused := false
const FIELDS := ["active_device", "prompt_family", "prompt_style", "move_deadzone", "aim_deadzone", "application_focused", "_bindings", "_modals", "_rewards", "_suppressed", "_pad_axes", "_pad_buttons", "_axis_rearm", "_button_rearm", "_navigation_times", "_keys_down", "_mouse_down", "_key_rearm", "_mouse_rearm", "last_error"]

func begin() -> void:
	_tree_was_paused = InputControls.get_tree().paused
	InputControls.get_tree().paused = false
	for field in FIELDS:
		var value: Variant = InputControls.get(field)
		saved[field] = value.duplicate(true) if value is Dictionary else value
	for field in ["_modals", "_rewards", "_suppressed", "_pad_axes", "_pad_buttons", "_axis_rearm", "_button_rearm", "_navigation_times", "_keys_down", "_mouse_down", "_key_rearm", "_mouse_rearm"]:
		InputControls.set(field, {})
	InputControls.active_device = 0
	InputControls.application_focused = true
	InputControls.prompt_family = ControlBindings.KEYBOARD
	InputControls.prompt_style = "generic"
	InputControls.move_deadzone = 0.2
	InputControls.aim_deadzone = 0.2
	InputControls._bindings = InputControls._defaults.duplicate(true)
	InputControls._apply_bindings()
	release_all()

func finish() -> void:
	InputControls.get_tree().paused = _tree_was_paused
	release_all()
	for field in saved:
		InputControls.set(field, saved[field])
	InputControls._apply_bindings()

func release_all() -> void:
	for axis in range(JOY_AXIS_MAX):
		var event := InputEventJoypadMotion.new()
		event.device = 0
		event.axis = axis
		event.axis_value = 0.0
		Input.parse_input_event(event)
	for action in ControlBindings.ACTIONS + InputControls.UI_ACTIONS:
		Input.action_release(action)
	InputControls._suppressed.clear()
