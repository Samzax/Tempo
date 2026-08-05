extends GutTest

const MAIN_MENU_SCENE := preload("res://scenes/ui/main_menu.tscn")
const MAIN_SCENE := preload("res://scenes/main/main.tscn")

class SelectionSpyPlayer extends Player:
	var call_log: Array[String] = []
	var selected_ship_id := &""
	var selected_character_id := &""
	var run_manager_character_id := &""

	func configure_selection(next_ship: ShipDef, character_id: StringName) -> bool:
		call_log.append("Player.configure_selection")
		selected_ship_id = next_ship.id if next_ship != null else &""
		selected_character_id = character_id
		run_manager_character_id = RunManager.selected_character_id
		return true

class SessionSpy extends Session:
	var call_log: Array[String] = []
	var received_seed := -1
	var received_character_id := &""

	func start_new_run(seed_value: int, character_id: StringName = RunManager.DEFAULT_CHARACTER_ID) -> void:
		call_log.append("Session.start_new_run")
		received_seed = seed_value
		received_character_id = character_id

var _previous_character_id := RunManager.DEFAULT_CHARACTER_ID

func before_each() -> void:
	_previous_character_id = RunManager.selected_character_id

func after_each() -> void:
	RunManager.select_character(_previous_character_id)

func _select_option_id(option: OptionButton, selected_id: StringName) -> bool:
	for index in option.item_count:
		if StringName(option.get_item_metadata(index)) == selected_id:
			option.select(index)
			return true
	return false

func _map_key() -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_M
	event.pressed = true
	event.echo = false
	return event

func _menu() -> MainMenu:
	var menu := MAIN_MENU_SCENE.instantiate() as MainMenu
	add_child_autofree(menu)
	await get_tree().process_frame
	await get_tree().process_frame
	return menu

func test_boot_shows_menu_and_focuses_new_game() -> void:
	var menu := await _menu()

	assert_true(menu.visible)
	assert_true(menu.get_node("MenuContainer").visible)
	assert_false(menu.get_node("ControlsPanel").visible)
	assert_eq(menu.get_viewport().gui_get_focus_owner(), menu.get_node("MenuContainer/StartButton"))
	assert_eq(menu.get_node("MenuContainer/StartButton").text, "Começar novo jogo")

func test_controls_panel_has_exact_requested_instructions() -> void:
	var menu := await _menu()
	var controls_button := menu.get_node("MenuContainer/ControlsButton") as Button
	controls_button.emit_signal("pressed")
	await get_tree().process_frame

	assert_true(menu.get_node("ControlsPanel").visible)
	assert_false(menu.get_node("MenuContainer").visible)
	assert_eq(menu.get_node("ControlsPanel/Panel/MarginContainer/Content/Instructions").text,
		"Mover: WASD\nAtirar: Espaço\nHabilidades: Q/E\nBlink: Shift")
	assert_eq(menu.get_viewport().gui_get_focus_owner(), menu.get_node("ControlsPanel/Panel/MarginContainer/Content/CloseButton"))

func test_back_closes_controls_and_returns_focus_to_controls_button() -> void:
	var menu := await _menu()
	var controls_button := menu.get_node("MenuContainer/ControlsButton") as Button
	controls_button.emit_signal("pressed")
	await get_tree().process_frame

	(menu.get_node("ControlsPanel/Panel/MarginContainer/Content/CloseButton") as Button).emit_signal("pressed")
	await get_tree().process_frame

	assert_false(menu.get_node("ControlsPanel").visible)
	assert_true(menu.get_node("MenuContainer").visible)
	assert_eq(menu.get_viewport().gui_get_focus_owner(), controls_button)

func test_ui_cancel_closes_controls_and_returns_focus_to_controls_button() -> void:
	var menu := await _menu()
	var controls_button := menu.get_node("MenuContainer/ControlsButton") as Button
	controls_button.emit_signal("pressed")
	await get_tree().process_frame

	var cancel := InputEventAction.new()
	cancel.action = &"ui_cancel"
	cancel.pressed = true
	menu._unhandled_input(cancel)
	await get_tree().process_frame

	assert_false(menu.get_node("ControlsPanel").visible)
	assert_eq(menu.get_viewport().gui_get_focus_owner(), controls_button)

func test_start_button_hides_menu_and_emits_start_request() -> void:
	var menu := await _menu()
	watch_signals(menu)

	(menu.get_node("MenuContainer/StartButton") as Button).emit_signal("pressed")
	await get_tree().process_frame

	assert_signal_emitted(menu, &"start_game_requested")
	assert_false(menu.visible)

func test_selected_ids_reach_player_before_session_starts() -> void:
	var main := MAIN_SCENE.instantiate()
	add_child_autofree(main)
	await get_tree().process_frame

	var call_log: Array[String] = []
	var player := SelectionSpyPlayer.new()
	player.call_log = call_log
	var world := Node2D.new()
	world.add_child(player)
	player.name = "Player"
	var session := SessionSpy.new()
	session.call_log = call_log
	main.set("_world", world)
	main.set("_session", session)

	var menu := main.get_node("MainMenu") as MainMenu
	assert_true(_select_option_id(menu.get_node("MenuContainer/ShipSelect") as OptionButton, &"nave_engenheira"))
	assert_true(_select_option_id(menu.get_node("MenuContainer/CharacterOption") as OptionButton, &"chronomancer"))
	(menu.get_node("MenuContainer/StartButton") as Button).emit_signal("pressed")

	assert_eq(RunManager.selected_character_id, &"chronomancer")
	assert_eq(player.selected_ship_id, &"nave_engenheira")
	assert_eq(player.selected_character_id, &"chronomancer")
	assert_eq(player.run_manager_character_id, &"chronomancer")
	assert_eq(session.received_seed, RunManager.DEFAULT_SEED)
	assert_eq(session.received_character_id, &"chronomancer")
	assert_eq(call_log, ["Player.configure_selection", "Session.start_new_run"])
	world.free()
	session.free()

func test_main_boot_disables_and_hides_world_and_hud_until_start() -> void:
	var main := MAIN_SCENE.instantiate()
	add_child_autofree(main)
	await get_tree().process_frame

	var world := main.get_node("World") as Node2D
	var hud := main.get_node("UI/HUD") as Control
	var menu := main.get_node("MainMenu") as MainMenu
	var sandbox := main.get_node("DevSandbox/Overlay") as SandboxUI
	assert_eq(world.process_mode, Node.PROCESS_MODE_DISABLED)
	assert_false(world.visible)
	assert_false(hud.visible)
	assert_false(sandbox.visible)

	watch_signals(menu)
	(menu.get_node("MenuContainer/StartButton") as Button).emit_signal("pressed")
	await get_tree().process_frame

	assert_signal_emitted(menu, &"start_game_requested")
	assert_true(world.visible)
	assert_eq(world.process_mode, Node.PROCESS_MODE_INHERIT)
	assert_true(hud.visible)

	var sandbox_toggle := InputEventAction.new()
	sandbox_toggle.action = &"dev_sandbox_toggle"
	sandbox_toggle.pressed = true
	sandbox._unhandled_input(sandbox_toggle)
	await get_tree().process_frame
	assert_true(sandbox.visible)

func test_map_key_before_session_start_does_not_open_map() -> void:
	var main := MAIN_SCENE.instantiate()
	add_child_autofree(main)
	await get_tree().process_frame

	var session := main.get_node("Session") as Session
	var map := main.get_node("Session/HyperspaceUI/Map") as HyperspaceUI
	session._unhandled_input(_map_key())
	map._unhandled_input(_map_key())
	await get_tree().process_frame

	assert_false(session._has_started)
	assert_false(map.visible)
	assert_false(map._sector != null)

func test_map_key_after_session_initialization_opens_map_outside_room() -> void:
	var main := MAIN_SCENE.instantiate()
	add_child_autofree(main)
	await get_tree().process_frame

	var session := main.get_node("Session") as Session
	var map := main.get_node("Session/HyperspaceUI/Map") as HyperspaceUI
	session._has_started = true
	session.run_state = RunState.new()
	session.run_state.run_seed = 4242
	session.sector = SectorGenerator.generate(session.run_state.run_seed, 0)
	session.run_state.current_node_id = session.sector.start_node_id
	session._room_active = false

	session._unhandled_input(_map_key())
	await get_tree().process_frame

	assert_true(map.visible)
	assert_eq(map._sector, session.sector)

func test_map_key_during_active_room_stays_blocked() -> void:
	var main := MAIN_SCENE.instantiate()
	add_child_autofree(main)
	await get_tree().process_frame

	var session := main.get_node("Session") as Session
	var map := main.get_node("Session/HyperspaceUI/Map") as HyperspaceUI
	session._has_started = true
	session.run_state = RunState.new()
	session.run_state.run_seed = 4242
	session.sector = SectorGenerator.generate(session.run_state.run_seed, 0)
	session.run_state.current_node_id = session.sector.start_node_id
	session._room_active = true
	map.hide()

	session._unhandled_input(_map_key())
	await get_tree().process_frame

	assert_false(map.visible)
