class_name MainMenu
extends CanvasLayer

signal start_game_requested(ship_id: StringName, character_id: StringName)

@onready var _menu_container: Control = $MenuContainer
@onready var _background: ColorRect = $Background
@onready var _start_button: Button = $MenuContainer/StartButton
@onready var _controls_button: Button = $MenuContainer/ControlsButton
@onready var _video_button: Button = $MenuContainer/VideoButton
@onready var _character_panel: CharacterSelectionPanel = $CharacterSelectionPanel
@onready var _ship_panel: ShipSelectionPanel = $ShipSelectionPanel
@onready var _simultaneous_panel: SimultaneousSelectionPanel = $SimultaneousSelectionPanel
@onready var _controls_panel: ControlsPanel = $ControlsPanel
@onready var _video_panel: VideoPanel = $VideoPanel

enum MenuState { MAIN, CHARACTER, SHIP, CONTROLS, SIMULTANEOUS, VIDEO }

var _start_requested := false
var _state := MenuState.MAIN

func _ready() -> void:
	_start_button.pressed.connect(_on_start_button_pressed)
	_controls_button.pressed.connect(_open_controls)
	_video_button.pressed.connect(_open_video)
	_controls_panel.close_requested.connect(_close_controls)
	_video_panel.close_requested.connect(_close_video)
	_character_panel.continue_requested.connect(_on_character_continue_requested)
	_character_panel.back_requested.connect(_on_character_back_requested)
	_ship_panel.continue_requested.connect(_on_ship_continue_requested)
	_ship_panel.back_requested.connect(_on_ship_back_requested)
	_simultaneous_panel.continue_requested.connect(_on_simultaneous_continue_requested)
	_simultaneous_panel.back_requested.connect(_on_simultaneous_back_requested)
	_character_panel.hide()
	_ship_panel.hide()
	_simultaneous_panel.hide()
	_controls_panel.hide()
	_video_panel.hide()
	call_deferred(&"_focus_start_button")

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if _state == MenuState.CONTROLS:
		if InputControls.ui_pressed(event, &"ui_cancel"):
			_controls_panel.request_close()
			get_viewport().set_input_as_handled()
	elif _state == MenuState.VIDEO:
		if InputControls.ui_pressed(event, &"ui_cancel"):
			_video_panel.request_close()
			get_viewport().set_input_as_handled()

func _on_start_button_pressed() -> void:
	if _start_requested or _state != MenuState.MAIN:
		return
	_menu_container.hide()
	_simultaneous_panel.show()
	_state = MenuState.SIMULTANEOUS
	_simultaneous_panel.grab_initial_focus()

func _on_simultaneous_continue_requested(ship_id: StringName, character_id: StringName) -> void:
	if _state != MenuState.SIMULTANEOUS or _start_requested or not ShipCatalog.is_valid(ship_id):
		return
	_start_requested = true
	hide()
	start_game_requested.emit(ship_id, character_id)

func _on_simultaneous_back_requested() -> void:
	if _state != MenuState.SIMULTANEOUS:
		return
	_simultaneous_panel.hide()
	_menu_container.show()
	_state = MenuState.MAIN
	_start_button.grab_focus()

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
	if _controls_panel.visible:
		_controls_panel.force_close()
	if _video_panel.visible:
		_video_panel.force_close()
	_start_requested = false
	_state = MenuState.MAIN
	_controls_panel.hide()
	_video_panel.hide()
	_character_panel.hide()
	_ship_panel.hide()
	_simultaneous_panel.hide()
	_simultaneous_panel.reset()
	_menu_container.show()
	show()
	call_deferred(&"_focus_start_button")

func _open_controls() -> void:
	if _state != MenuState.MAIN:
		return
	_menu_container.hide()
	_state = MenuState.CONTROLS
	_controls_panel.open()

func _close_controls() -> void:
	if _state != MenuState.CONTROLS:
		return
	_controls_panel.hide()
	_menu_container.show()
	_state = MenuState.MAIN
	_controls_button.grab_focus()

func _open_video() -> void:
	if _state != MenuState.MAIN:
		return
	_menu_container.hide()
	_state = MenuState.VIDEO
	_video_panel.open()

func _close_video() -> void:
	if _state != MenuState.VIDEO:
		return
	_video_panel.hide()
	_menu_container.show()
	_state = MenuState.MAIN
	_video_button.grab_focus()

func _focus_start_button() -> void:
	_start_button.grab_focus()
