class_name MainMenu
extends CanvasLayer

signal start_game_requested(ship_id: StringName, character_id: StringName)

@onready var _menu_container: Control = $MenuContainer
@onready var _background: ColorRect = $Background
@onready var _start_button: Button = $MenuContainer/StartButton
@onready var _controls_button: Button = $MenuContainer/ControlsButton
@onready var _ship_select: OptionButton = $MenuContainer/ShipSelect
@onready var _character_option: OptionButton = $MenuContainer/CharacterOption
@onready var _character_description: Label = $MenuContainer/CharacterDescription
@onready var _controls_panel: Control = $ControlsPanel
@onready var _close_button: Button = $ControlsPanel/Panel/MarginContainer/Content/CloseButton

var _start_requested := false

func _ready() -> void:
	var viewport_size := Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 480)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 270))
	)
	_background.position = Vector2.ZERO
	_background.size = viewport_size
	_controls_panel.position = Vector2.ZERO
	_controls_panel.size = viewport_size
	_start_button.pressed.connect(_on_start_button_pressed)
	_controls_button.pressed.connect(_open_controls)
	_populate_ship_select()
	_close_button.pressed.connect(_close_controls)
	_character_option.item_selected.connect(_on_character_selected)
	_populate_characters()
	_controls_panel.hide()
	call_deferred(&"_focus_start_button")

func _unhandled_input(event: InputEvent) -> void:
	if not visible or not _controls_panel.visible:
		return
	if event.is_action_pressed(&"ui_cancel"):
		_close_controls()
		get_viewport().set_input_as_handled()

func _on_start_button_pressed() -> void:
	if _start_requested:
		return
	var ship_id := _selected_ship_id()
	if not ShipCatalog.is_valid(ship_id):
		return
	_start_requested = true
	hide()
	start_game_requested.emit(ship_id, _selected_character_id())

func reset_for_new_run() -> void:
	_start_requested = false
	_controls_panel.hide()
	_menu_container.show()
	show()
	call_deferred(&"_focus_start_button")

func _populate_ship_select() -> void:
	_ship_select.clear()
	for ship in ShipCatalog.all():
		_ship_select.add_item(ship.display_name if not ship.display_name.is_empty() else String(ship.id))
		_ship_select.set_item_metadata(_ship_select.item_count - 1, ship.id)
	var has_ships := _ship_select.item_count > 0
	_ship_select.disabled = not has_ships
	_start_button.disabled = not has_ships

func _selected_ship_id() -> StringName:
	if _ship_select.item_count == 0:
		return &""
	var selected := clampi(_ship_select.selected, 0, _ship_select.item_count - 1)
	return StringName(_ship_select.get_item_metadata(selected))

func _populate_characters() -> void:
	_character_option.clear()
	for definition in CharacterDef.get_roster():
		_character_option.add_item(definition.display_name)
		_character_option.set_item_metadata(_character_option.item_count - 1, definition.id)
	_character_option.select(0)
	_refresh_character_description()

func _on_character_selected(_index: int) -> void:
	_refresh_character_description()

func _selected_character_id() -> StringName:
	var metadata: Variant = _character_option.get_item_metadata(_character_option.selected)
	return StringName(metadata) if metadata is StringName else CharacterDef.ROSTER_IDS[0]

func _refresh_character_description() -> void:
	var definition := CharacterDef.resolve_id(_selected_character_id())
	_character_description.text = definition.description

func _open_controls() -> void:
	_menu_container.hide()
	_controls_panel.show()
	_close_button.grab_focus()

func _close_controls() -> void:
	_controls_panel.hide()
	_menu_container.show()
	_controls_button.grab_focus()

func _focus_start_button() -> void:
	_start_button.grab_focus()
