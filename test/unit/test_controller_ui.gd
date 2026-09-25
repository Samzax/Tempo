extends GutTest

const STATE := preload("res://test/support/control_test_state.gd")
const CONTROLS := preload("res://scenes/ui/controls_panel.tscn")
const PAUSE := preload("res://scenes/ui/pause_menu.tscn")
const TITLE := preload("res://scenes/ui/main_menu.tscn")
var _state: STATE
var _owned: Array[Node] = []

class OfferPlayer extends Node:
	var acquired: Array[StringName] = []
	var blocked: Array[StringName] = []

	func can_acquire_item(item: ItemDef) -> bool:
		return item.id not in blocked

	func acquire_item(item: ItemDef) -> bool:
		if not can_acquire_item(item):
			return false
		acquired.append(item.id)
		return true

func before_each() -> void:
	_state = STATE.new()
	_state.begin()

func after_each() -> void:
	for node in _owned:
		if is_instance_valid(node):
			node.free()
	_owned.clear()
	_state.finish()

func _keep(node: Node) -> Node:
	add_child(node)
	_owned.append(node)
	return node

func _button(code: int, pressed: bool = true) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = code
	event.pressed = pressed
	return event

func _key(code: int, pressed: bool = true) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	return event

func _controls() -> ControlsPanel:
	var panel := _keep(CONTROLS.instantiate()) as ControlsPanel
	await get_tree().process_frame
	panel.open()
	return panel

func _offer(player: OfferPlayer) -> ItemChoice:
	var choice := _keep(ItemChoice.new()) as ItemChoice
	var offer := RewardOffer.new()
	for index in 3:
		var item := ItemDef.new()
		item.id = StringName("controller_test_%d" % index)
		item.display_name = "Teste %d" % index
		offer.options.append(item)
	choice.open_offer(offer, player, true)
	return choice

func test_controls_panel_exposes_all_actions_and_leaves_gameplay_blocked() -> void:
	var panel := await _controls()
	assert_eq(panel._buttons.size(), ControlBindings.ACTIONS.size())
	assert_false(InputControls.gameplay_allowed())
	assert_eq(get_viewport().gui_get_focus_owner(), panel._close)
	panel.request_close()
	assert_false(panel.visible)
	assert_true(InputControls.gameplay_allowed())

func test_capture_waits_for_opener_and_captured_release() -> void:
	var panel := await _controls()
	var before := InputControls.settings_snapshot()
	panel._begin_capture(&"shoot")
	assert_false(panel._capture_armed)
	panel._input(_key(KEY_F))
	assert_eq(InputControls.settings_snapshot(), before)
	panel._input(_key(KEY_F, false))
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(panel._capture_armed)
	panel._input(_key(KEY_F))
	assert_eq(InputControls.settings_snapshot(), before)
	panel._input(_key(KEY_F, false))
	assert_eq(panel._capturing, &"")
	assert_eq(InputControls.bindings_for(&"shoot", ControlBindings.KEYBOARD), [ControlBindings.key(KEY_F)])
	assert_true(panel._dirty)
	panel.request_close()
	assert_eq(InputControls.settings_snapshot(), before)

func test_capture_escape_cancels_without_closing_or_changing_bindings() -> void:
	var panel := await _controls()
	var before := InputControls.settings_snapshot()
	panel._begin_capture(&"shoot")
	panel._input(_key(KEY_ESCAPE))
	assert_eq(panel._capturing, &"")
	assert_true(panel.visible)
	assert_eq(InputControls.settings_snapshot(), before)
	panel._input(_key(KEY_ESCAPE, false))

func test_controller_axis_capture_requires_neutral_before_commit() -> void:
	var panel := await _controls()
	panel._family.select(ControlBindings.CONTROLLER)
	panel._begin_capture(&"shoot")
	await get_tree().process_frame
	await get_tree().process_frame
	var event := InputEventJoypadMotion.new()
	event.device = 0
	event.axis = JOY_AXIS_TRIGGER_RIGHT
	event.axis_value = 0.9
	panel._input(event)
	assert_false(panel._pending_binding.is_empty())
	assert_ne(panel._capturing, &"")
	event.axis_value = 0.0
	panel._input(event)
	assert_eq(panel._capturing, &"")
	assert_eq(InputControls.bindings_for(&"shoot", ControlBindings.CONTROLLER), [ControlBindings.axis(JOY_AXIS_TRIGGER_RIGHT, 1)])

func test_conflict_is_shown_without_overwriting_other_action() -> void:
	var panel := await _controls()
	var before := InputControls.settings_snapshot()
	panel._begin_capture(&"shoot")
	panel._pending_binding = ControlBindings.key(KEY_Q)
	panel._finish_capture()
	assert_eq(InputControls.settings_snapshot(), before)
	assert_string_contains(panel._status.text, "Já usado")

func test_force_close_mid_capture_discards_draft_and_releases_context() -> void:
	var panel := await _controls()
	var before := InputControls.settings_snapshot()
	assert_eq(InputControls.rebind_action(&"shoot", ControlBindings.KEYBOARD, ControlBindings.key(KEY_F)), "")
	panel._changed()
	panel._begin_capture(&"blink")
	panel.force_close()
	assert_false(panel.visible)
	assert_eq(panel._capturing, &"")
	assert_eq(InputControls.settings_snapshot(), before)
	assert_true(InputControls.gameplay_allowed())

func test_f12_restores_defaults_while_capture_is_active() -> void:
	var panel := await _controls()
	assert_eq(InputControls.rebind_action(&"shoot", ControlBindings.KEYBOARD, ControlBindings.key(KEY_F)), "")
	panel._changed()
	panel._begin_capture(&"blink")
	panel._input(_key(KEY_F12))
	assert_eq(panel._capturing, &"")
	assert_eq(InputControls.bindings_for(&"shoot", ControlBindings.KEYBOARD), [ControlBindings.key(KEY_SPACE)])
	assert_true(panel._dirty)

func test_pause_controls_return_keeps_pause_and_restores_focus() -> void:
	var pause := _keep(PAUSE.instantiate()) as PauseMenu
	await get_tree().process_frame
	pause.open()
	pause._open_controls()
	assert_true(pause._controls_panel.visible)
	assert_true(get_tree().paused)
	pause._controls_panel.request_close()
	assert_false(pause._controls_panel.visible)
	assert_true(get_tree().paused)
	assert_eq(get_viewport().gui_get_focus_owner(), pause._controls_button)
	pause.close()
	assert_false(get_tree().paused)
	assert_true(InputControls.gameplay_allowed())

func test_title_reset_closes_active_controls_capture_and_restores_menu() -> void:
	var title := _keep(TITLE.instantiate()) as MainMenu
	await get_tree().process_frame
	title._open_controls()
	title._controls_panel._begin_capture(&"shoot")
	title.reset_for_new_run()
	assert_false(title._controls_panel.visible)
	assert_eq(title._state, MainMenu.MenuState.MAIN)
	assert_eq(title._controls_panel._capturing, &"")
	assert_false(InputControls._modals.has(title._controls_panel.get_instance_id()))

func test_controller_can_select_loadout_and_confirm_once() -> void:
	var title := _keep(TITLE.instantiate()) as MainMenu
	await get_tree().process_frame
	watch_signals(title)
	title._on_start_button_pressed()
	var panel := title._simultaneous_panel
	panel._handle_navigation_input(_button(JOY_BUTTON_DPAD_DOWN))
	assert_eq(panel._character_index, 1)
	panel._handle_navigation_input(_button(JOY_BUTTON_DPAD_RIGHT))
	assert_eq(panel._ship_index, 1)
	panel._handle_navigation_input(_button(JOY_BUTTON_A))
	panel._handle_navigation_input(_button(JOY_BUTTON_A))
	assert_signal_emit_count(title, &"start_game_requested", 1)

func test_reward_opener_cannot_choose_until_release_and_new_confirmation() -> void:
	var player := _keep(OfferPlayer.new()) as OfferPlayer
	Input.action_press(&"interact")
	Input.action_press(&"reward_confirm")
	var choice := _offer(player)
	choice._handle_choice_input(_button(JOY_BUTTON_A))
	assert_true(player.acquired.is_empty())
	assert_false(choice._confirm_armed)
	Input.action_release(&"interact")
	Input.action_release(&"reward_confirm")
	InputControls.observe_event(_button(JOY_BUTTON_A, false))
	InputControls._process(0.0)
	await get_tree().process_frame
	await get_tree().process_frame
	choice._handle_choice_input(_button(JOY_BUTTON_A))
	assert_eq(player.acquired.size(), 1)
	assert_true(choice._offer.claimed)
	assert_false(choice.visible)
	assert_false(get_tree().paused)

func test_reward_dpad_skips_disabled_options_without_stopping_combat() -> void:
	var player := _keep(OfferPlayer.new()) as OfferPlayer
	player.blocked.append(&"controller_test_1")
	var choice := _offer(player)
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_press(&"move_right")
	Input.action_press(&"shoot")
	choice._handle_choice_input(_button(JOY_BUTTON_DPAD_DOWN))
	assert_eq(choice._navigation_index, 2)
	assert_true(InputControls.pressed(&"shoot"))
	assert_gt(InputControls.movement_vector().x, 0.9)
	assert_false(get_tree().paused)
	choice._handle_choice_input(_button(JOY_BUTTON_A))
	assert_eq(player.acquired, [&"controller_test_2"])

func test_space_does_not_accept_focused_reward() -> void:
	var player := _keep(OfferPlayer.new()) as OfferPlayer
	var choice := _offer(player)
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_press(&"shoot")
	choice._handle_choice_input(_key(KEY_SPACE))
	assert_true(player.acquired.is_empty())
	assert_true(choice.visible)
	assert_true(InputControls.pressed(&"shoot"))

func test_controller_closes_map_and_releases_its_modal() -> void:
	var map := _keep(HyperspaceUI.new()) as HyperspaceUI
	map.show()
	assert_false(InputControls.gameplay_allowed())
	map._unhandled_input(_button(JOY_BUTTON_B))
	assert_false(map.visible)
	assert_true(InputControls.gameplay_allowed())
	map.show()
	map._unhandled_input(_button(JOY_BUTTON_BACK))
	assert_false(map.visible)
