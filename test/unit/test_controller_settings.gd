extends GutTest

const STATE := preload("res://test/support/control_test_state.gd")
var _state: STATE
var _directory := ""
var _path := ""

func before_each() -> void:
	_state = STATE.new()
	_state.begin()
	_directory = "user://controller-tests-%d" % Time.get_ticks_usec()
	_path = _directory + "/controls.cfg"
	assert_eq(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_directory)), OK)

func after_each() -> void:
	for suffix in ["", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_path + suffix))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_directory))
	_state.finish()

func test_default_document_is_valid_and_contains_no_device_id() -> void:
	var document := InputControls.settings_snapshot()
	assert_eq(InputControls.validate_snapshot(document), "")
	assert_eq(document.size(), 5)
	assert_false(document.has("active_device"))
	for action in document.bindings:
		for binding in document.bindings[action]:
			assert_false(binding.has("device"))

func test_keyboard_remap_preserves_controller_binding_and_updates_prompt() -> void:
	var controller := InputControls.bindings_for(&"shoot", ControlBindings.CONTROLLER)
	assert_eq(InputControls.rebind_action(&"shoot", ControlBindings.KEYBOARD, ControlBindings.key(KEY_F)), "")
	assert_eq(InputControls.bindings_for(&"shoot", ControlBindings.CONTROLLER), controller)
	assert_eq(InputControls.bindings_for(&"shoot", ControlBindings.KEYBOARD), [ControlBindings.key(KEY_F)])
	assert_eq(InputControls.prompt(&"shoot", ControlBindings.KEYBOARD), ControlBindings.label(ControlBindings.key(KEY_F)))
	var event := InputEventKey.new()
	event.physical_keycode = KEY_F
	assert_true(InputMap.event_is_action(event, &"shoot"))
	event.physical_keycode = KEY_SPACE
	assert_false(InputMap.event_is_action(event, &"shoot"))

func test_controller_remap_preserves_keyboard_and_uses_owned_device() -> void:
	var keyboard := InputControls.bindings_for(&"shoot", ControlBindings.KEYBOARD)
	assert_eq(InputControls.rebind_action(&"shoot", ControlBindings.CONTROLLER, ControlBindings.button(JOY_BUTTON_X)), "")
	assert_eq(InputControls.bindings_for(&"shoot", ControlBindings.KEYBOARD), keyboard)
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = JOY_BUTTON_X
	assert_true(InputMap.event_is_action(event, &"shoot"))
	event.device = 1
	assert_false(InputMap.event_is_action(event, &"shoot"))

func test_conflicts_and_reserved_recovery_buttons_are_atomic_rejections() -> void:
	var before := InputControls.settings_snapshot()
	assert_ne(InputControls.rebind_action(&"shoot", ControlBindings.KEYBOARD, ControlBindings.key(KEY_Q)), "")
	assert_eq(InputControls.settings_snapshot(), before)
	for code in [KEY_ENTER, KEY_ESCAPE, KEY_F12]:
		assert_ne(InputControls.rebind_action(&"shoot", ControlBindings.KEYBOARD, ControlBindings.key(code)), "")
	for code in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_START, JOY_BUTTON_DPAD_DOWN]:
		assert_ne(InputControls.rebind_action(&"shoot", ControlBindings.CONTROLLER, ControlBindings.button(code)), "")
	assert_eq(InputControls.settings_snapshot(), before)

func test_key_and_mouse_and_signed_axis_values_validate_without_objects() -> void:
	assert_true(ControlBindings.valid({"kind": "mouse", "code": MOUSE_BUTTON_RIGHT}))
	assert_false(ControlBindings.valid({"kind": "mouse", "code": MOUSE_BUTTON_WHEEL_UP}))
	assert_false(ControlBindings.valid({"kind": "axis", "code": JOY_AXIS_TRIGGER_LEFT, "sign": -1}))
	assert_false(ControlBindings.valid({"kind": "axis", "code": JOY_AXIS_LEFT_X, "sign": 0}))
	assert_false(ControlBindings.valid({"kind": "button", "code": 0, "device": 0}))
	assert_false(ControlBindings.valid({"kind": "key", "code": "F"}))
	assert_false(ControlBindings.valid({"kind": "button", "code": -1}))
	assert_true(ControlBindings.valid(ControlBindings.axis(JOY_AXIS_LEFT_X, -1)))
	assert_ne(ControlBindings.identity(ControlBindings.axis(JOY_AXIS_LEFT_X, -1)), ControlBindings.identity(ControlBindings.axis(JOY_AXIS_LEFT_X, 1)))

func test_malformed_snapshots_never_partially_replace_live_state() -> void:
	var before := InputControls.settings_snapshot()
	var invalid: Array[Dictionary] = []
	var document := before.duplicate(true)
	document.version = 999
	invalid.append(document)
	document = before.duplicate(true)
	document.bindings.erase(&"shoot")
	invalid.append(document)
	document = before.duplicate(true)
	document.bindings[&"shoot"] = []
	invalid.append(document)
	document = before.duplicate(true)
	document.bindings[&"shoot"] = [ControlBindings.key(KEY_Q)]
	invalid.append(document)
	document = before.duplicate(true)
	document.bindings[&"shoot"] = [ControlBindings.key(KEY_F), ControlBindings.key(KEY_F)]
	invalid.append(document)
	document = before.duplicate(true)
	document.move_deadzone = NAN
	invalid.append(document)
	document = before.duplicate(true)
	document.aim_deadzone = 1.0
	invalid.append(document)
	document = before.duplicate(true)
	document.prompt_style = "unknown"
	invalid.append(document)
	for malformed in invalid:
		assert_eq(InputControls.apply_snapshot(malformed), ERR_INVALID_DATA)
		assert_eq(InputControls.settings_snapshot(), before)

func test_preferences_keep_separate_deadzones_and_explicit_prompt_styles() -> void:
	assert_eq(InputControls.set_preferences(0.11, 0.34, "playstation"), "")
	assert_almost_eq(InputMap.action_get_deadzone(&"move_left"), 0.11, 0.001)
	assert_almost_eq(InputMap.action_get_deadzone(&"aim_left"), 0.34, 0.001)
	assert_eq(InputControls.prompt(&"shoot", ControlBindings.CONTROLLER), "R2")
	assert_eq(InputControls.set_preferences(0.11, 0.34, "nintendo"), "")
	assert_eq(InputControls.prompt(&"interact", ControlBindings.CONTROLLER), "B")
	assert_eq(InputControls.set_preferences(0.11, 0.34, "generic"), "")
	assert_eq(InputControls.prompt(&"interact", ControlBindings.CONTROLLER), "Sul")

func test_restore_one_family_does_not_remove_the_other() -> void:
	assert_eq(InputControls.rebind_action(&"shoot", ControlBindings.KEYBOARD, ControlBindings.key(KEY_F)), "")
	assert_eq(InputControls.rebind_action(&"shoot", ControlBindings.CONTROLLER, ControlBindings.button(JOY_BUTTON_X)), "")
	assert_eq(InputControls.reset_action(&"shoot", ControlBindings.KEYBOARD), "")
	assert_eq(InputControls.bindings_for(&"shoot", ControlBindings.CONTROLLER), [ControlBindings.button(JOY_BUTTON_X)])
	assert_eq(InputControls.bindings_for(&"shoot", ControlBindings.KEYBOARD), [ControlBindings.key(KEY_SPACE)])

func test_save_reload_round_trip_after_defaults_restored() -> void:
	assert_eq(InputControls.rebind_action(&"shoot", ControlBindings.KEYBOARD, {"kind": "mouse", "code": MOUSE_BUTTON_RIGHT}), "")
	assert_eq(InputControls.set_preferences(0.12, 0.31, "xbox"), "")
	var expected := InputControls.settings_snapshot()
	assert_eq(InputControls.save_settings(_path), OK)
	assert_true(FileAccess.file_exists(_path))
	assert_false(FileAccess.file_exists(_path + ".tmp"))
	InputControls.reset_defaults()
	assert_ne(InputControls.settings_snapshot(), expected)
	assert_eq(InputControls.load_settings(_path), OK)
	assert_eq(InputControls.settings_snapshot(), expected)

func test_existing_settings_file_can_be_replaced_without_leaving_a_temporary() -> void:
	assert_eq(InputControls.save_settings(_path), OK)
	assert_eq(InputControls.rebind_action(&"blink", ControlBindings.KEYBOARD, ControlBindings.key(KEY_F)), "")
	var expected := InputControls.settings_snapshot()
	assert_eq(InputControls.save_settings(_path), OK)
	InputControls.reset_defaults()
	assert_eq(InputControls.load_settings(_path), OK)
	assert_eq(InputControls.settings_snapshot(), expected)
	assert_false(FileAccess.file_exists(_path + ".tmp"))

func test_invalid_persisted_document_preserves_active_bindings() -> void:
	var before := InputControls.settings_snapshot()
	var file := ConfigFile.new()
	file.set_value("controls", "data", {"version": 500})
	assert_eq(file.save(_path), OK)
	assert_eq(InputControls.load_settings(_path), ERR_INVALID_DATA)
	assert_eq(InputControls.settings_snapshot(), before)

func test_missing_file_is_not_an_error_and_failed_save_is_reported() -> void:
	assert_eq(InputControls.load_settings(_path), OK)
	watch_signals(InputControls)
	var before := InputControls.settings_snapshot()
	assert_ne(InputControls.save_settings(_directory + "/missing/controls.cfg"), OK)
	assert_signal_emitted(InputControls, &"settings_error")
	assert_eq(InputControls.settings_snapshot(), before)
	assert_false(FileAccess.file_exists(_directory + "/missing/controls.cfg"))
