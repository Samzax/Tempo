extends GutTest

## Testes de contrato de exibicao de tela e integracao de menus.

const MAIN_SCENE := preload("res://scenes/main/main.tscn")
const MAIN_MENU_SCENE := preload("res://scenes/ui/main_menu.tscn")
const PAUSE_MENU_SCENE := preload("res://scenes/ui/pause_menu.tscn")

var _before_snapshot: Dictionary = {}

func before_each() -> void:
	_before_snapshot = VideoSettings.settings_snapshot()

func after_each() -> void:
	VideoSettings.apply_snapshot(_before_snapshot)

func test_entering_room_does_not_resize_window_geometry() -> void:
	var main := MAIN_SCENE.instantiate()
	add_child_autofree(main)
	await get_tree().process_frame

	var window := main.get_window()
	var original_window_size := window.size

	var session := main.get_node("Session") as Session
	session.start_new_run(4242)
	await get_tree().process_frame

	assert_eq(window.size, original_window_size)
	assert_eq(window.content_scale_size, Vector2i(1280, 720))

	assert_true(session.sandbox_warp(4242, 0, 3, SectorNode.NodeType.TREASURE))
	await get_tree().process_frame

	assert_eq(window.size, original_window_size)
	assert_eq(window.content_scale_size, Vector2i(720, 405))

	session.reset_run()
	await get_tree().process_frame

	assert_eq(window.size, original_window_size)

func test_video_panel_reachable_from_main_menu_and_returns_to_main_state() -> void:
	var menu := MAIN_MENU_SCENE.instantiate() as MainMenu
	add_child_autofree(menu)
	await get_tree().process_frame

	var video_button := menu.get_node("MenuContainer/VideoButton") as Button
	var video_panel := menu.get_node("VideoPanel") as VideoPanel

	assert_eq(menu._state, MainMenu.MenuState.MAIN)
	video_button.pressed.emit()
	await get_tree().process_frame

	assert_true(video_panel.visible)
	assert_eq(menu._state, MainMenu.MenuState.VIDEO)

	video_panel.close_requested.emit()
	await get_tree().process_frame

	assert_false(video_panel.visible)
	assert_eq(menu._state, MainMenu.MenuState.MAIN)
	assert_eq(menu.get_viewport().gui_get_focus_owner(), video_button)

func test_video_panel_reachable_from_pause_menu_and_returns_to_pause_panel() -> void:
	var menu := PAUSE_MENU_SCENE.instantiate() as PauseMenu
	add_child_autofree(menu)
	await get_tree().process_frame

	menu.open()
	await get_tree().process_frame

	var video_button := menu.get_node("Panel/VideoButton") as Button
	var video_panel := menu.get_node("VideoPanel") as VideoPanel

	video_button.pressed.emit()
	await get_tree().process_frame

	assert_true(video_panel.visible)
	assert_false(menu.get_node("Panel").visible)

	(video_panel.get_node("Panel/MarginContainer/Content/Actions/CloseButton") as Button).pressed.emit()
	await get_tree().process_frame

	assert_false(video_panel.visible)
	assert_true(menu.get_node("Panel").visible)
	assert_eq(menu.get_viewport().gui_get_focus_owner(), video_button)
	menu.close()
