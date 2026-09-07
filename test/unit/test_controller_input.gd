extends GutTest

const STATE := preload("res://test/support/control_test_state.gd")
var _state: STATE

func before_each() -> void:
	_state = STATE.new()
	_state.begin()

func after_each() -> void:
	_state.finish()

func _axis(axis: int, value: float, device: int = 0) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.device = device
	event.axis = axis
	event.axis_value = value
	return event

func _button(code: int, pressed: bool = true, device: int = 0) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = code
	event.pressed = pressed
	return event

func test_defaults_cover_combat_and_preserve_keyboard() -> void:
	for action in [&"move_up", &"move_down", &"move_left", &"move_right", &"shoot", &"ability_q", &"ability_e", &"blink", &"interact", &"pause", &"map_toggle"]:
		assert_gt(InputControls.bindings_for(action, ControlBindings.CONTROLLER).size(), 0, str(action))
		assert_gt(InputControls.bindings_for(action, ControlBindings.KEYBOARD).size(), 0, str(action))
	assert_true(InputMap.event_is_action(_button(JOY_BUTTON_LEFT_SHOULDER), &"blink"))
	assert_true(InputMap.event_is_action(_button(JOY_BUTTON_RIGHT_SHOULDER), &"ability_e"))
	assert_true(InputMap.event_is_action(_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0), &"shoot"))
	assert_true(InputMap.event_is_action(_axis(JOY_AXIS_TRIGGER_LEFT, 1.0), &"ability_q"))

func test_real_axis_events_preserve_analog_magnitude_and_limit_diagonals() -> void:
	Input.parse_input_event(_axis(JOY_AXIS_LEFT_X, 0.6))
	await get_tree().process_frame
	assert_almost_eq(InputControls.movement_vector().x, 0.5, 0.001)
	assert_almost_eq(InputControls.controller_move_vector().x, 0.5, 0.001)
	Input.parse_input_event(_axis(JOY_AXIS_LEFT_X, 1.0))
	Input.parse_input_event(_axis(JOY_AXIS_LEFT_Y, 1.0))
	await get_tree().process_frame
	assert_almost_eq(InputControls.movement_vector().length(), 1.0, 0.001)

func test_other_controller_cannot_inject_actions_or_prompts() -> void:
	assert_false(InputControls.observe_event(_button(JOY_BUTTON_A, true, 3)))
	Input.parse_input_event(_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0, 3))
	await get_tree().process_frame
	assert_false(InputControls.pressed(&"shoot"))
	assert_eq(InputControls.active_device, 0)
	assert_eq(InputControls.prompt_family, ControlBindings.KEYBOARD)

func test_small_axis_drift_mouse_jitter_and_release_do_not_switch_prompts() -> void:
	InputControls.observe_event(_axis(JOY_AXIS_RIGHT_X, 0.15))
	assert_eq(InputControls.prompt_family, ControlBindings.KEYBOARD)
	InputControls.observe_event(_button(JOY_BUTTON_A))
	assert_eq(InputControls.prompt_family, ControlBindings.CONTROLLER)
	InputControls.observe_event(_button(JOY_BUTTON_A, false))
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(0.1, 0.0)
	InputControls.observe_event(motion)
	assert_eq(InputControls.prompt_family, ControlBindings.CONTROLLER)
	motion.relative = Vector2(4, 0)
	InputControls.observe_event(motion)
	assert_eq(InputControls.prompt_family, ControlBindings.KEYBOARD)

func test_modal_blocks_polled_combat_and_requires_release_after_close() -> void:
	var owner := Node.new()
	add_child_autofree(owner)
	Input.action_press(&"shoot")
	InputControls.set_modal(owner, true)
	assert_false(InputControls.pressed(&"shoot"))
	InputControls.set_modal(owner, false)
	assert_false(InputControls.pressed(&"shoot"))
	Input.action_release(&"shoot")
	InputControls._process(0.0)
	Input.action_press(&"shoot")
	assert_true(InputControls.pressed(&"shoot"))

func test_non_pausing_offer_preserves_held_combat_but_blocks_interaction() -> void:
	var owner := Node.new()
	add_child_autofree(owner)
	Input.action_press(&"move_right")
	Input.action_press(&"shoot")
	Input.action_press(&"interact")
	InputControls.set_reward_context(owner, true)
	assert_false(get_tree().paused)
	assert_true(InputControls.pressed(&"shoot"))
	assert_gt(InputControls.movement_vector().x, 0.9)
	assert_false(InputControls.pressed(&"interact"))
	InputControls.set_reward_context(owner, false)
	assert_false(InputControls.pressed(&"interact"))

func test_disconnect_requests_pause_without_automatically_reconnecting_gameplay() -> void:
	watch_signals(InputControls)
	InputControls.observe_event(_button(JOY_BUTTON_A))
	Input.action_press(&"shoot")
	InputControls._on_joy_connection_changed(0, false)
	assert_signal_emitted(InputControls, &"safety_pause_requested")
	assert_eq(InputControls.active_device, -1)
	assert_false(InputControls.pressed(&"shoot"))
	assert_eq(InputControls.prompt_family, ControlBindings.KEYBOARD)
	InputControls._on_joy_connection_changed(2, true)
	assert_eq(InputControls.active_device, 2)
	assert_false(InputControls.pressed(&"shoot"))

func test_focus_loss_blocks_controller_until_return_and_neutral() -> void:
	watch_signals(InputControls)
	InputControls.observe_event(_axis(JOY_AXIS_RIGHT_X, 0.8))
	InputControls.set_application_focus(false)
	assert_signal_emitted(InputControls, &"safety_pause_requested")
	assert_false(InputControls.observe_event(_button(JOY_BUTTON_A)))
	assert_eq(InputControls.aim_vector(), Vector2.ZERO)
	InputControls.set_application_focus(true)
	assert_false(InputControls.observe_event(_axis(JOY_AXIS_RIGHT_X, 0.8)))
	assert_true(InputControls.observe_event(_axis(JOY_AXIS_RIGHT_X, 0.0)))

func test_radial_helper_rejects_non_finite_input() -> void:
	assert_eq(ControlBindings.radial(Vector2(NAN, 0), 0.2), Vector2.ZERO)
	assert_eq(ControlBindings.radial(Vector2.ONE, NAN), Vector2.ZERO)
	assert_eq(ControlBindings.radial(Vector2(0.2, 0), 0.2), Vector2.ZERO)
	assert_almost_eq(ControlBindings.radial(Vector2(0.6, 0), 0.2).x, 0.5, 0.001)
