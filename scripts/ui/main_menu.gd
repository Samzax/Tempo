class_name MainMenu
extends CanvasLayer

signal start_game_requested(ship_id: StringName, character_id: StringName)

@onready var _menu_container: Control = $MenuContainer
@onready var _background: ColorRect = $Background
@onready var _start_button: Button = $MenuContainer/StartButton
@onready var _controls_button: Button = $MenuContainer/ControlsButton
@onready var _character_panel: CharacterSelectionPanel = $CharacterSelectionPanel
@onready var _ship_panel: ShipSelectionPanel = $ShipSelectionPanel
@onready var _controls_panel: Control = $ControlsPanel
@onready var _close_button: Button = $ControlsPanel/Panel/MarginContainer/Content/CloseButton

enum MenuState { MAIN, CHARACTER, SHIP, CONTROLS }

var _start_requested := false
var _state := MenuState.MAIN

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
	_close_button.pressed.connect(_close_controls)
	_character_panel.continue_requested.connect(_on_character_continue_requested)
	_character_panel.back_requested.connect(_on_character_back_requested)
	_ship_panel.continue_requested.connect(_on_ship_continue_requested)
	_ship_panel.back_requested.connect(_on_ship_back_requested)
	_character_panel.hide()
	_ship_panel.hide()
	_controls_panel.hide()
	call_deferred(&"_focus_start_button")

func _unhandled_input(event: InputEvent) -> void:
	if not visible or _state != MenuState.CONTROLS:
		return
	if event.is_action_pressed(&"ui_cancel"):
		_close_controls()
		get_viewport().set_input_as_handled()

func _on_start_button_pressed() -> void:
	if _start_requested or _state != MenuState.MAIN:
		return
	_menu_container.hide()
	_character_panel.show()
	_state = MenuState.CHARACTER
	_character_panel.grab_initial_focus()

func _on_character_continue_requested(_character_id: StringName) -> void:
	if _state != MenuState.CHARACTER:
		return
	_character_panel.hide()
	_ship_panel.show()
	_state = MenuState.SHIP
	_ship_panel.focus_default()

func _on_character_back_requested() -> void:
	if _state != MenuState.CHARACTER:
		return
	_character_panel.hide()
	_menu_container.show()
	_state = MenuState.MAIN
	_start_button.grab_focus()

func _on_ship_continue_requested(_ship_id: StringName) -> void:
	if _state != MenuState.SHIP or _start_requested:
		return
	if not ShipCatalog.is_valid(_ship_panel.selected_id()):
		return
	_start_requested = true
	hide()
	start_game_requested.emit(_ship_panel.selected_id(), _character_panel.selected_id())

func _on_ship_back_requested() -> void:
	if _state != MenuState.SHIP:
		return
	_ship_panel.hide()
	_character_panel.show()
	_state = MenuState.CHARACTER
	_character_panel.grab_initial_focus()

func reset_for_new_run() -> void:
	_start_requested = false
	_state = MenuState.MAIN
	_controls_panel.hide()
	_character_panel.hide()
	_ship_panel.hide()
	_menu_container.show()
	show()
	call_deferred(&"_focus_start_button")

func _open_controls() -> void:
	if _state != MenuState.MAIN:
		return
	_menu_container.hide()
	_controls_panel.show()
	_state = MenuState.CONTROLS
	_close_button.grab_focus()

func _close_controls() -> void:
	if _state != MenuState.CONTROLS:
		return
	_controls_panel.hide()
	_menu_container.show()
	_state = MenuState.MAIN
	_controls_button.grab_focus()

func _focus_start_button() -> void:
	_start_button.grab_focus()
