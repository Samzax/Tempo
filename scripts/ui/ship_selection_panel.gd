class_name ShipSelectionPanel
extends VBoxContainer

signal selection_changed(id: StringName)
signal continue_requested(id: StringName)
signal back_requested()

@onready var _ship_option_button: OptionButton = $ShipOptionButton
@onready var _back_button: Button = $ButtonContainer/BackButton
@onready var _continue_button: Button = $ButtonContainer/ContinueButton


func _ready() -> void:
	_populate_ships()
	_ship_option_button.item_selected.connect(_on_ship_selected)
	_back_button.pressed.connect(_on_back_pressed)
	_continue_button.pressed.connect(_on_continue_pressed)


func selected_id() -> StringName:
	if _ship_option_button.item_count == 0 or _ship_option_button.selected < 0:
		return &""
	return StringName(_ship_option_button.get_item_metadata(_ship_option_button.selected))


func set_selected_id(id: StringName) -> bool:
	if not ShipCatalog.is_valid(id):
		return false
	for index in _ship_option_button.item_count:
		if StringName(_ship_option_button.get_item_metadata(index)) == id:
			_ship_option_button.select(index)
			return true
	return false


func focus_default() -> void:
	if _ship_option_button.disabled:
		_back_button.grab_focus()
	else:
		_ship_option_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event.is_action_pressed(&"ui_cancel"):
		return
	back_requested.emit()
	get_viewport().set_input_as_handled()


func _populate_ships() -> void:
	_ship_option_button.clear()
	for ship in ShipCatalog.all():
		var display_name := ship.display_name if not ship.display_name.is_empty() else String(ship.id)
		_ship_option_button.add_item(display_name)
		_ship_option_button.set_item_metadata(_ship_option_button.item_count - 1, ship.id)
	var has_ships := _ship_option_button.item_count > 0
	_ship_option_button.disabled = not has_ships
	_continue_button.disabled = not has_ships
	if has_ships:
		_ship_option_button.select(0)


func _on_ship_selected(_index: int) -> void:
	selection_changed.emit(selected_id())


func _on_back_pressed() -> void:
	back_requested.emit()


func _on_continue_pressed() -> void:
	var id := selected_id()
	if ShipCatalog.is_valid(id):
		continue_requested.emit(id)
