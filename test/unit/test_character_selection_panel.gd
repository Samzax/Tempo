extends GutTest

const PANEL_SCENE := preload("res://scenes/ui/character_selection_panel.tscn")

func _panel() -> CharacterSelectionPanel:
	var panel := PANEL_SCENE.instantiate() as CharacterSelectionPanel
	watch_signals(panel)
	add_child_autofree(panel)
	await get_tree().process_frame
	return panel

func _character(character_id: StringName) -> CharacterDef:
	return CharacterDef.resolve_id(character_id)

func _name_label(panel: CharacterSelectionPanel) -> Label:
	return panel.get_node("MarginContainer/VBoxContainer/CharacterContent/Details/NameLabel") as Label

func _description_label(panel: CharacterSelectionPanel) -> RichTextLabel:
	return panel.get_node("MarginContainer/VBoxContainer/CharacterContent/Details/DescriptionLabel") as RichTextLabel

func _portrait(panel: CharacterSelectionPanel) -> TextureRect:
	return panel.get_node("MarginContainer/VBoxContainer/CharacterContent/PortraitRect") as TextureRect

func _option(panel: CharacterSelectionPanel) -> OptionButton:
	return panel.get_node("MarginContainer/VBoxContainer/CharacterContent/Details/CharacterOptionButton") as OptionButton

func _back_button(panel: CharacterSelectionPanel) -> Button:
	return panel.get_node("MarginContainer/VBoxContainer/Actions/BackButton") as Button

func _continue_button(panel: CharacterSelectionPanel) -> Button:
	return panel.get_node("MarginContainer/VBoxContainer/Actions/ContinueButton") as Button

func test_initial_roster_and_selection_have_no_spurious_signals() -> void:
	var panel := await _panel()
	var option := _option(panel)
	var character := _character(&"hacker")

	assert_eq(option.item_count, 3)
	assert_eq(panel.selected_id(), &"hacker")
	assert_eq(_name_label(panel).text, character.display_name)
	assert_eq(_description_label(panel).text, character.description)
	assert_eq(_portrait(panel).texture, character.portrait)
	assert_eq(option.get_item_metadata(0), &"hacker")
	assert_eq(option.get_item_metadata(1), &"guardian")
	assert_eq(option.get_item_metadata(2), &"chronomancer")
	assert_signal_not_emitted(panel, &"selection_changed")
	assert_signal_not_emitted(panel, &"continue_requested")
	assert_signal_not_emitted(panel, &"back_requested")

func test_user_selection_emits_selected_id_once() -> void:
	var panel := await _panel()
	_option(panel).select(1)
	_option(panel).item_selected.emit(1)
	var character := _character(&"guardian")

	assert_eq(panel.selected_id(), &"guardian")
	assert_eq(_name_label(panel).text, character.display_name)
	assert_eq(_description_label(panel).text, character.description)
	assert_eq(_portrait(panel).texture, character.portrait)
	assert_signal_emitted_with_parameters(panel, &"selection_changed", [&"guardian"])
	assert_signal_emit_count(panel, &"selection_changed", 1)

func test_continue_and_back_buttons_emit_contract_signals() -> void:
	var panel := await _panel()
	_continue_button(panel).emit_signal("pressed")
	_back_button(panel).emit_signal("pressed")

	assert_signal_emitted_with_parameters(panel, &"continue_requested", [&"hacker"])
	assert_signal_emitted(panel, &"back_requested")

func test_programmatic_selection_accepts_valid_id_without_signal() -> void:
	var panel := await _panel()
	var character := _character(&"chronomancer")

	assert_true(panel.set_selected_id(&"chronomancer"))
	assert_eq(panel.selected_id(), &"chronomancer")
	assert_eq(_option(panel).selected, 2)
	assert_eq(_name_label(panel).text, character.display_name)
	assert_eq(_description_label(panel).text, character.description)
	assert_eq(_portrait(panel).texture, character.portrait)
	assert_signal_not_emitted(panel, &"selection_changed")

func test_invalid_ids_are_rejected_without_changing_selection_or_signals() -> void:
	var panel := await _panel()

	assert_false(panel.set_selected_id(&"missing"))
	assert_eq(panel.selected_id(), &"hacker")
	assert_signal_not_emitted(panel, &"selection_changed")
	assert_signal_not_emitted(panel, &"continue_requested")

func test_initial_focus_targets_character_option() -> void:
	var panel := await _panel()
	panel.grab_initial_focus()
	await get_tree().process_frame

	assert_eq(panel.get_viewport().gui_get_focus_owner(), _option(panel))

func test_ui_cancel_emits_back_and_handles_input() -> void:
	var panel := await _panel()
	var cancel := InputEventAction.new()
	cancel.action = &"ui_cancel"
	cancel.pressed = true

	panel._unhandled_input(cancel)

	assert_signal_emitted(panel, &"back_requested")
	assert_true(panel.get_viewport().is_input_handled())
