class_name PauseMenu
extends CanvasLayer

signal resume_requested
signal back_to_title_requested

@onready var _continue_button: Button = $Panel/ContinueButton
@onready var _controls_panel: ControlsPanel = $ControlsPanel
@onready var _controls_button: Button = $Panel/ControlsButton
@onready var _back_to_title_button: Button = $Panel/BackToTitleButton

var _tree_was_paused := false
var _request_pending := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_continue_button.pressed.connect(_request_resume)
	_back_to_title_button.pressed.connect(_request_back_to_title)
	_controls_button.pressed.connect(_open_controls)
	_controls_panel.close_requested.connect(_close_controls)
	hide()

func open() -> void:
	if visible:
		return
	_request_pending = false
	$Panel.show()
	set_status("")
	InputControls.set_modal(self, true)
	_continue_button.disabled = false
	_back_to_title_button.disabled = false
	_tree_was_paused = get_tree().paused
	get_tree().paused = true
	show()
	_continue_button.grab_focus()

func close() -> void:
	if _controls_panel.visible:
		_controls_panel.force_close()
	InputControls.set_modal(self, false)
	hide()
	get_tree().paused = _tree_was_paused

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.echo:
		return
	if not visible or _controls_panel.visible or not (InputControls.ui_pressed(event, &"ui_cancel") or InputControls.ui_pressed(event, &"pause")):
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

func set_status(message: String) -> void:
	var status := get_node_or_null("Panel/InputStatus") as Label
	if status == null:
		status = Label.new()
		status.name = "InputStatus"
		status.custom_minimum_size.x = 240
		status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		status.add_theme_font_size_override("font_size", 12)
		$Panel.add_child(status)
	status.text = message

func _exit_tree() -> void:
	InputControls.set_modal(self, false)

func _open_controls() -> void:
	$Panel.hide()
	_controls_panel.open()

func _close_controls() -> void:
	$Panel.show()
	_controls_button.grab_focus()
