class_name CharacterSelectionPanel
extends PanelContainer
## Painel independente para escolher o personagem antes de iniciar a partida.

signal selection_changed(id: StringName)
signal continue_requested(id: StringName)
signal back_requested()

@onready var _portrait_rect: TextureRect = $MarginContainer/VBoxContainer/CharacterContent/PortraitRect
@onready var _character_option: OptionButton = $MarginContainer/VBoxContainer/CharacterContent/Details/CharacterOptionButton
@onready var _name_label: Label = $MarginContainer/VBoxContainer/CharacterContent/Details/NameLabel
@onready var _description_label: RichTextLabel = $MarginContainer/VBoxContainer/CharacterContent/Details/DescriptionLabel
@onready var _back_button: Button = $MarginContainer/VBoxContainer/Actions/BackButton
@onready var _continue_button: Button = $MarginContainer/VBoxContainer/Actions/ContinueButton

var _roster: Array[CharacterDef] = []
var _selected_id: StringName = &""

func _ready() -> void:
	_character_option.item_selected.connect(_on_character_selected)
	_back_button.pressed.connect(_on_back_pressed)
	_continue_button.pressed.connect(_on_continue_pressed)
	_populate_roster()

func selected_id() -> StringName:
	return _selected_id

func set_selected_id(id: StringName) -> bool:
	var index := _index_for_id(id)
	if index < 0:
		return false
	_selected_id = id
	_character_option.select(index)
	_refresh_character_details(_roster[index])
	return true

func grab_initial_focus() -> void:
	if not _character_option.disabled:
		_character_option.grab_focus()
	else:
		_back_button.grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event.is_action_pressed(&"ui_cancel"):
		return
	back_requested.emit()
	get_viewport().set_input_as_handled()

func _populate_roster() -> void:
	_roster = CharacterDef.get_roster()
	_character_option.clear()
	for definition in _roster:
		_character_option.add_item(_display_name(definition))
		_character_option.set_item_metadata(_character_option.item_count - 1, definition.id)

	var has_characters := not _roster.is_empty()
	_character_option.disabled = not has_characters
	_continue_button.disabled = not has_characters
	if has_characters:
		set_selected_id(_roster[0].id)
	else:
		_selected_id = &""
		_name_label.text = ""
		_description_label.text = ""
		_portrait_rect.texture = null

func _on_character_selected(index: int) -> void:
	if index < 0 or index >= _roster.size():
		return
	var id := _roster[index].id
	if id == _selected_id:
		return
	set_selected_id(id)
	selection_changed.emit(_selected_id)

func _on_continue_pressed() -> void:
	if not _selected_id.is_empty():
		continue_requested.emit(_selected_id)

func _on_back_pressed() -> void:
	back_requested.emit()

func _index_for_id(id: StringName) -> int:
	for index in _roster.size():
		if _roster[index].id == id:
			return index
	return -1

func _refresh_character_details(definition: CharacterDef) -> void:
	_name_label.text = _display_name(definition)
	_description_label.text = definition.description
	_portrait_rect.texture = definition.portrait

func _display_name(definition: CharacterDef) -> String:
	return definition.display_name if not definition.display_name.is_empty() else String(definition.id)
