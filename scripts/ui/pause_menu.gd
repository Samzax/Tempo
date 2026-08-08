class_name PauseMenu
extends CanvasLayer

signal resume_requested
signal back_to_title_requested

@onready var _continue_button: Button = $Panel/ContinueButton
@onready var _back_to_title_button: Button = $Panel/BackToTitleButton

var _tree_was_paused := false
var _request_pending := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_continue_button.pressed.connect(_request_resume)
	_back_to_title_button.pressed.connect(_request_back_to_title)
	hide()

func open() -> void:
	if visible:
		return
	_request_pending = false
	_continue_button.disabled = false
	_back_to_title_button.disabled = false
	_tree_was_paused = get_tree().paused
	get_tree().paused = true
	show()
	_continue_button.grab_focus()

func close() -> void:
	hide()
	get_tree().paused = _tree_was_paused

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.echo:
		return
	if not visible or not event.is_action_pressed(&"ui_cancel"):
		return
	_request_resume()
	get_viewport().set_input_as_handled()

func _request_resume() -> void:
	if not visible or _request_pending:
		return
	_request_pending = true
	_continue_button.disabled = true
	_back_to_title_button.disabled = true
	resume_requested.emit()

func _request_back_to_title() -> void:
	if not visible or _request_pending:
		return
	_request_pending = true
	_continue_button.disabled = true
	_back_to_title_button.disabled = true
	back_to_title_requested.emit()
