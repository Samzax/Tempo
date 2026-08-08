extends GutTest

const PANEL_SCENE := preload("res://scenes/ui/ship_selection_panel.tscn")

func _panel() -> ShipSelectionPanel:
	var panel := PANEL_SCENE.instantiate() as ShipSelectionPanel
	add_child_autofree(panel)
	await get_tree().process_frame
	return panel

func test_catalog_populates_options_with_valid_ids_and_selects_first() -> void:
	var panel := await _panel()
	var option := panel.get_node("ShipOptionButton") as OptionButton
	var catalog := ShipCatalog.all()

	assert_eq(option.item_count, catalog.size())
	assert_gt(option.item_count, 0)
	assert_eq(option.selected, 0)
	for index in catalog.size():
		assert_eq(option.get_item_text(index), catalog[index].display_name)
		assert_eq(StringName(option.get_item_metadata(index)), catalog[index].id)
	assert_eq(panel.selected_id(), catalog[0].id)

func test_set_selected_id_accepts_valid_id_and_rejects_invalid_id() -> void:
	var panel := await _panel()
	var valid_id := ShipCatalog.all().back().id

	assert_true(panel.set_selected_id(valid_id))
	assert_eq(panel.selected_id(), valid_id)
	assert_false(panel.set_selected_id(&"nave_inexistente"))
	assert_eq(panel.selected_id(), valid_id)

func test_selection_changed_emits_selected_id() -> void:
	var panel := await _panel()
	var option := panel.get_node("ShipOptionButton") as OptionButton
	var catalog := ShipCatalog.all()
	assert_gt(catalog.size(), 1)
	watch_signals(panel)

	option.select(1)
	option.emit_signal("item_selected", 1)

	assert_eq(panel.selected_id(), catalog[1].id)
	assert_signal_emitted_with_parameters(panel, &"selection_changed", [catalog[1].id])

func test_continue_and_back_emit_expected_signals() -> void:
	var panel := await _panel()
	watch_signals(panel)
	var continue_button := panel.get_node("ButtonContainer/ContinueButton") as Button
	var back_button := panel.get_node("ButtonContainer/BackButton") as Button

	continue_button.emit_signal("pressed")
	back_button.emit_signal("pressed")

	assert_signal_emitted_with_parameters(panel, &"continue_requested", [ShipCatalog.all()[0].id])
	assert_signal_emitted(panel, &"back_requested")

func test_invalid_selection_cannot_continue() -> void:
	var panel := await _panel()
	watch_signals(panel)
	panel.get_node("ShipOptionButton").clear()
	panel.get_node("ButtonContainer/ContinueButton").emit_signal("pressed")

	assert_eq(panel.selected_id(), &"")
	assert_signal_not_emitted(panel, &"continue_requested")

func test_empty_catalog_state_disables_advance_and_focuses_back() -> void:
	var original_ships: Dictionary = ShipCatalog._ships
	var original_ordered_ids: Array[StringName] = ShipCatalog._ordered_ids
	ShipCatalog._ships = {&"__test_empty_catalog__": null}
	ShipCatalog._ordered_ids = []
	var panel := await _panel()
	var option := panel.get_node("ShipOptionButton") as OptionButton
	var continue_button := panel.get_node("ButtonContainer/ContinueButton") as Button
	var back_button := panel.get_node("ButtonContainer/BackButton") as Button
	ShipCatalog._ships = original_ships
	ShipCatalog._ordered_ids = original_ordered_ids

	panel.focus_default()
	assert_eq(option.item_count, 0)
	assert_true(option.disabled)
	assert_true(continue_button.disabled)
	assert_eq(panel.get_viewport().gui_get_focus_owner(), back_button)

func test_ui_cancel_emits_back_and_handles_input_when_visible() -> void:
	var panel := await _panel()
	watch_signals(panel)
	var cancel := InputEventAction.new()
	cancel.action = &"ui_cancel"
	cancel.pressed = true

	panel._unhandled_input(cancel)

	assert_signal_emitted(panel, &"back_requested")

func test_ui_cancel_is_ignored_when_ancestor_is_hidden() -> void:
	var container := Control.new()
	add_child_autofree(container)
	var panel := PANEL_SCENE.instantiate() as ShipSelectionPanel
	container.add_child(panel)
	await get_tree().process_frame
	container.hide()
	watch_signals(panel)
	var cancel := InputEventAction.new()
	cancel.action = &"ui_cancel"
	cancel.pressed = true

	panel._unhandled_input(cancel)

	assert_signal_not_emitted(panel, &"back_requested")
