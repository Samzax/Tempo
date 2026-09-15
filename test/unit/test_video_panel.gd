extends GutTest

## Testes unitarios do painel de configuracoes de video (VideoPanel).

const VIDEO_PANEL_SCENE := preload("res://scenes/ui/video_panel.tscn")
const TEST_CONFIG_PATH := "user://test_video_panel_temp.cfg"

var _before_snapshot: Dictionary = {}

func before_each() -> void:
	_before_snapshot = VideoSettings.settings_snapshot()
	_remove_temp_config()

func after_each() -> void:
	VideoSettings.apply_snapshot(_before_snapshot)
	_remove_temp_config()

func _remove_temp_config() -> void:
	if FileAccess.file_exists(TEST_CONFIG_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_CONFIG_PATH))

func _panel() -> VideoPanel:
	var panel := VIDEO_PANEL_SCENE.instantiate() as VideoPanel
	add_child_autofree(panel)
	await get_tree().process_frame
	return panel

func _cancel_event() -> InputEventAction:
	var event := InputEventAction.new()
	event.action = &"ui_cancel"
	event.pressed = true
	return event

func test_video_panel_loads_hidden_with_portuguese_texts_and_populated_resolutions() -> void:
	var panel := await _panel()

	assert_false(panel.visible)
	assert_eq(panel.get_node("Panel/MarginContainer/Content/Title").text, "VÍDEO")
	assert_eq(panel.get_node("Panel/MarginContainer/Content/ResolutionRow/ResolutionLabel").text, "Resolução")
	assert_eq(panel.get_node("Panel/MarginContainer/Content/ModeRow/ModeLabel").text, "Modo")
	assert_eq(panel.get_node("Panel/MarginContainer/Content/Actions/Apply").text, "Aplicar")
	assert_eq(panel.get_node("Panel/MarginContainer/Content/Actions/CloseButton").text, "Voltar")
	assert_eq(panel.get_node("Panel/MarginContainer/Content/Actions/Reset").text, "Restaurar padrão")

	var resolution_opt := panel.get_node("Panel/MarginContainer/Content/ResolutionRow/Resolution") as OptionButton
	var candidates := VideoSettings.resolution_candidates()
	assert_eq(resolution_opt.item_count, candidates.size())
	for i in candidates.size():
		assert_eq(resolution_opt.get_item_metadata(i), candidates[i])

func test_open_shows_panel_sets_modal_and_focuses_close_button() -> void:
	var panel := await _panel()

	panel.open()
	await get_tree().process_frame

	assert_true(panel.visible)
	assert_true(InputControls._modals.has(panel.get_instance_id()))
	assert_eq(get_viewport().gui_get_focus_owner(), panel.get_node("Panel/MarginContainer/Content/Actions/CloseButton"))

func test_changing_selection_marks_dirty_and_apply_saves_clearing_dirty() -> void:
	var panel := await _panel()
	panel.open()
	await get_tree().process_frame

	var mode_opt := panel.get_node("Panel/MarginContainer/Content/ModeRow/Mode") as OptionButton
	var next_mode := 1 if mode_opt.selected == 0 else 0
	mode_opt.select(next_mode)
	mode_opt.item_selected.emit(next_mode)
	await get_tree().process_frame

	assert_true(panel._dirty)

	var apply_btn := panel.get_node("Panel/MarginContainer/Content/Actions/Apply") as Button
	apply_btn.pressed.emit()
	await get_tree().process_frame

	assert_false(panel._dirty)

func test_close_with_unsaved_changes_restores_previous_snapshot() -> void:
	var panel := await _panel()
	var original_snapshot := VideoSettings.settings_snapshot()

	panel.open()
	await get_tree().process_frame

	var mode_opt := panel.get_node("Panel/MarginContainer/Content/ModeRow/Mode") as OptionButton
	var new_mode := 1 if mode_opt.selected == 0 else 0
	mode_opt.select(new_mode)
	mode_opt.item_selected.emit(new_mode)
	await get_tree().process_frame

	assert_true(panel._dirty)

	var close_btn := panel.get_node("Panel/MarginContainer/Content/Actions/CloseButton") as Button
	close_btn.pressed.emit()
	await get_tree().process_frame

	assert_false(panel.visible)
	assert_eq(VideoSettings.settings_snapshot(), original_snapshot)

func test_cancel_event_closes_panel_and_emits_close_requested_once() -> void:
	var panel := await _panel()
	watch_signals(panel)

	panel.open()
	await get_tree().process_frame

	panel._unhandled_input(_cancel_event())
	await get_tree().process_frame

	assert_false(panel.visible)
	assert_signal_emit_count(panel, &"close_requested", 1)

func test_force_close_and_exit_tree_restore_draft_and_release_modal() -> void:
	var panel := await _panel()
	var original_snapshot := VideoSettings.settings_snapshot()

	panel.open()
	await get_tree().process_frame
	var mode_opt := panel.get_node("Panel/MarginContainer/Content/ModeRow/Mode") as OptionButton
	mode_opt.select(1 if mode_opt.selected == 0 else 0)
	mode_opt.item_selected.emit(mode_opt.selected)

	panel.force_close()
	assert_false(panel.visible)
	assert_false(InputControls._modals.has(panel.get_instance_id()))
	assert_eq(VideoSettings.settings_snapshot(), original_snapshot)

	var panel2 := VIDEO_PANEL_SCENE.instantiate() as VideoPanel
	add_child(panel2)
	await get_tree().process_frame
	panel2.open()
	mode_opt = panel2.get_node("Panel/MarginContainer/Content/ModeRow/Mode") as OptionButton
	mode_opt.select(1 if mode_opt.selected == 0 else 0)
	mode_opt.item_selected.emit(mode_opt.selected)

	remove_child(panel2)
	panel2._exit_tree()
	assert_false(InputControls._modals.has(panel2.get_instance_id()))
	assert_eq(VideoSettings.settings_snapshot(), original_snapshot)
	panel2.free()

func test_keyboard_navigation_keeps_focus_within_panel_controls() -> void:
	var panel := await _panel()
	panel.open()
	await get_tree().process_frame

	var focus_owner := get_viewport().gui_get_focus_owner()
	assert_not_null(focus_owner)
	assert_true(panel.is_ancestor_of(focus_owner))

	focus_owner.find_prev_valid_focus().grab_focus()
	var next_focus := get_viewport().gui_get_focus_owner()
	assert_not_null(next_focus)
	assert_true(panel.is_ancestor_of(next_focus))

func test_close_button_emits_close_requested_once_per_open_cycle() -> void:
	var panel := await _panel()
	watch_signals(panel)

	panel.open()
	await get_tree().process_frame

	var close_btn := panel.get_node("Panel/MarginContainer/Content/Actions/CloseButton") as Button
	close_btn.pressed.emit()
	await get_tree().process_frame

	assert_signal_emit_count(panel, &"close_requested", 1)

	panel.open()
	await get_tree().process_frame

	close_btn.pressed.emit()
	await get_tree().process_frame

	assert_signal_emit_count(panel, &"close_requested", 2)
