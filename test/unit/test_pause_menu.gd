extends GutTest

const PAUSE_MENU_SCENE := preload("res://scenes/ui/pause_menu.tscn")
const MAIN_SCENE := preload("res://scenes/main/main.tscn")

var _was_paused := false
var _score_before := 0
var _stage_before := 1
var _player_lives_before := 3

func before_each() -> void:
	_was_paused = get_tree().paused
	_score_before = GameState.score
	_stage_before = GameState.stage
	_player_lives_before = GameState.player_lives
	get_tree().paused = false

func after_each() -> void:
	GameState.score = _score_before
	GameState.stage = _stage_before
	GameState.player_lives = _player_lives_before
	get_tree().paused = _was_paused

func _pause_menu() -> PauseMenu:
	var menu := PAUSE_MENU_SCENE.instantiate() as PauseMenu
	add_child_autofree(menu)
	await get_tree().process_frame
	return menu

func _cancel_event() -> InputEventAction:
	var event := InputEventAction.new()
	event.action = &"ui_cancel"
	event.pressed = true
	return event

func _escape_key_event(echo := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	event.echo = echo
	return event

func test_pause_menu_loads_with_expected_defaults() -> void:
	var menu := await _pause_menu()

	assert_eq(menu.process_mode, Node.PROCESS_MODE_ALWAYS)
	assert_false(menu.visible)
	assert_eq(menu.get_node("Panel/ContinueButton").text, "Continuar")
	assert_eq(menu.get_node("Panel/BackToTitleButton").text, "Voltar à tela inicial")

func test_open_pauses_shows_and_focuses_continue() -> void:
	var menu := await _pause_menu()

	menu.open()

	assert_true(get_tree().paused)
	assert_true(menu.visible)
	assert_eq(menu.get_viewport().gui_get_focus_owner(), menu.get_node("Panel/ContinueButton"))

func test_continue_button_emits_signal_closes_and_unpauses() -> void:
	var main := MAIN_SCENE.instantiate()
	add_child_autofree(main)
	await get_tree().process_frame
	var menu := main.get_node("PauseMenu") as PauseMenu
	main.set("_gameplay_started", true)
	menu.open()
	watch_signals(menu)

	(menu.get_node("Panel/ContinueButton") as Button).emit_signal("pressed")
	await get_tree().process_frame

	assert_signal_emitted(menu, &"resume_requested")
	assert_false(menu.visible)
	assert_false(get_tree().paused)

func test_continue_button_duplicate_press_emits_once_per_opening() -> void:
	var menu := await _pause_menu()
	var continue_button := menu.get_node("Panel/ContinueButton") as Button
	watch_signals(menu)

	menu.open()
	continue_button.emit_signal("pressed")
	continue_button.emit_signal("pressed")
	assert_signal_emit_count(menu, &"resume_requested", 1)

	menu.close()
	menu.open()
	continue_button.emit_signal("pressed")
	continue_button.emit_signal("pressed")
	assert_signal_emit_count(menu, &"resume_requested", 2)

func test_back_to_title_returns_main_to_menu_and_resets_run() -> void:
	var main := MAIN_SCENE.instantiate()
	add_child_autofree(main)
	await get_tree().process_frame
	var pause_menu := main.get_node("PauseMenu") as PauseMenu
	var world := main.get_node("World") as Node2D
	var hud := main.get_node("UI/HUD") as Control
	var item_choice := main.get_node("UI/ItemChoice") as ItemChoice
	var session := main.get_node("Session") as Session
	var start_button := main.get_node("MainMenu/MenuContainer/StartButton") as Button

	main.set("_gameplay_started", true)
	world.show()
	hud.show()
	item_choice.show()
	GameState.score = 42
	GameState.stage = 4
	GameState.player_lives = 1
	session.run_state = RunState.new()
	pause_menu.open()
	(pause_menu.get_node("Panel/BackToTitleButton") as Button).emit_signal("pressed")
	await get_tree().process_frame

	assert_false(pause_menu.visible)
	assert_false(get_tree().paused)
	assert_false(world.visible)
	assert_false(hud.visible)
	assert_false(item_choice.visible)
	assert_null(session.run_state)
	assert_eq(GameState.score, 0)
	assert_eq(GameState.stage, 1)
	assert_eq(GameState.player_lives, 3)
	assert_false(main.get("_gameplay_started"))
	assert_false(start_button.disabled)
	assert_true(main.get_node("MainMenu").visible)

func test_back_to_title_duplicate_press_emits_once_per_opening() -> void:
	var menu := await _pause_menu()
	var back_button := menu.get_node("Panel/BackToTitleButton") as Button
	watch_signals(menu)

	menu.open()
	back_button.emit_signal("pressed")
	back_button.emit_signal("pressed")
	assert_signal_emit_count(menu, &"back_to_title_requested", 1)

	menu.close()
	menu.open()
	back_button.emit_signal("pressed")
	back_button.emit_signal("pressed")
	assert_signal_emit_count(menu, &"back_to_title_requested", 2)

func test_back_to_title_from_prepaused_tree_unpauses_and_main_menu_responds() -> void:
	var main := MAIN_SCENE.instantiate()
	add_child_autofree(main)
	await get_tree().process_frame
	var pause_menu := main.get_node("PauseMenu") as PauseMenu
	var start_button := main.get_node("MainMenu/MenuContainer/StartButton") as Button
	main.set("_gameplay_started", true)
	get_tree().paused = true

	watch_signals(pause_menu)
	pause_menu.open()
	(pause_menu.get_node("Panel/BackToTitleButton") as Button).emit_signal("pressed")
	await get_tree().process_frame

	assert_signal_emit_count(pause_menu, &"back_to_title_requested", 1)
	assert_false(get_tree().paused)
	assert_true(main.get_node("MainMenu").visible)
	assert_false(start_button.disabled)

func test_escape_during_gameplay_opens_pause() -> void:
	var main := MAIN_SCENE.instantiate()
	add_child_autofree(main)
	await get_tree().process_frame
	main.set("_gameplay_started", true)

	main._unhandled_input(_cancel_event())

	assert_true(main.get_node("PauseMenu").visible)
	assert_true(get_tree().paused)

func test_escape_echo_does_not_resume_or_reopen_pause() -> void:
	var main := MAIN_SCENE.instantiate()
	add_child_autofree(main)
	await get_tree().process_frame
	main.set("_gameplay_started", true)
	var pause_menu := main.get_node("PauseMenu") as PauseMenu

	main._unhandled_input(_escape_key_event())
	assert_true(pause_menu.visible)
	assert_true(get_tree().paused)

	main._unhandled_input(_escape_key_event(true))
	assert_true(pause_menu.visible)
	assert_true(get_tree().paused)

func test_escape_with_overlay_visible_does_not_open_pause() -> void:
	var main := MAIN_SCENE.instantiate()
	add_child_autofree(main)
	await get_tree().process_frame
	main.set("_gameplay_started", true)
	var pause_menu := main.get_node("PauseMenu") as PauseMenu
	var hyperspace := main.get_node("Session/HyperspaceUI/Map") as HyperspaceUI
	var item_choice := main.get_node("UI/ItemChoice") as ItemChoice

	hyperspace.show()
	main._unhandled_input(_cancel_event())
	assert_false(pause_menu.visible)
	hyperspace.hide()
	item_choice.show()
	main._unhandled_input(_cancel_event())
	assert_false(pause_menu.visible)

func test_escape_before_start_does_not_open_pause() -> void:
	var main := MAIN_SCENE.instantiate()
	add_child_autofree(main)
	await get_tree().process_frame

	main._unhandled_input(_cancel_event())

	assert_false(main.get_node("PauseMenu").visible)
	assert_false(get_tree().paused)
