class_name ControlsPanel
extends Control
## Edicao transacional: Aplicar salva; Voltar descarta apenas o que nao foi salvo.

signal close_requested

const BINDINGS := preload("res://scripts/input/control_bindings.gd")
@onready var _family: OptionButton = $Panel/MarginContainer/Content/DeviceRow/Family
@onready var _style: OptionButton = $Panel/MarginContainer/Content/DeviceRow/Style
@onready var _rows: VBoxContainer = $Panel/MarginContainer/Content/BindingScroll/BindingRows
@onready var _move: HSlider = $Panel/MarginContainer/Content/DeadzoneRow/Move
@onready var _aim: HSlider = $Panel/MarginContainer/Content/DeadzoneRow/Aim
@onready var _move_value: Label = $Panel/MarginContainer/Content/DeadzoneRow/MoveValue
@onready var _aim_value: Label = $Panel/MarginContainer/Content/DeadzoneRow/AimValue
@onready var _status: Label = $Panel/MarginContainer/Content/Status
@onready var _apply: Button = $Panel/MarginContainer/Content/Actions/Apply
@onready var _reset: Button = $Panel/MarginContainer/Content/Actions/Reset
@onready var _close: Button = $Panel/MarginContainer/Content/Actions/CloseButton

var _before: Dictionary = {}
var _buttons: Dictionary = {}
var _resets: Dictionary = {}
var _dirty := false
var _refreshing := false
var _capturing := &""
var _capture_family := BINDINGS.KEYBOARD
var _capture_frame := -1
var _capture_armed := false
var _pending_binding: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_family.item_selected.connect(_on_family_changed)
	_style.item_selected.connect(_on_preferences_changed.unbind(1))
	_move.value_changed.connect(_on_preferences_changed.unbind(1))
	_aim.value_changed.connect(_on_preferences_changed.unbind(1))
	_apply.pressed.connect(_save)
	_reset.pressed.connect(_reset_all)
	_close.pressed.connect(request_close)
	InputControls.prompts_changed.connect(_refresh_rows)
	_build_rows()
	hide()

func open() -> void:
	_before = InputControls.settings_snapshot()
	_dirty = false
	_family.select(InputControls.prompt_family)
	InputControls.set_modal(self, true)
	show()
	_refresh_preferences()
	_refresh_rows()
	_status.text = InputControls.last_error
	_close.grab_focus()

func request_close() -> void:
	if not _capturing.is_empty():
		_cancel_capture()
		return
	if _dirty and not _before.is_empty():
		InputControls.apply_snapshot(_before)
	_dirty = false
	InputControls.set_modal(self, false)
	hide()
	close_requested.emit()

func force_close() -> void:
	_cancel_capture()
	request_close()

func _exit_tree() -> void:
	# Uma troca externa de cena tambem descarta o rascunho nao salvo.
	if _dirty and not _before.is_empty():
		InputControls.apply_snapshot(_before)
		_dirty = false
	InputControls.set_modal(self, false)

func _build_rows() -> void:
	for action in BINDINGS.ACTIONS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_rows.add_child(row)
		var label := Label.new()
		label.text = BINDINGS.LABELS[str(action)]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.custom_minimum_size.x = 210.0
		row.add_child(label)
		var bind_button := Button.new()
		bind_button.custom_minimum_size = Vector2(160, 25)
		bind_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		bind_button.pressed.connect(_begin_capture.bind(action))
		row.add_child(bind_button)
		_buttons[action] = bind_button
		var reset_button := Button.new()
		reset_button.text = "Padrão"
		reset_button.custom_minimum_size.x = 76.0
		reset_button.pressed.connect(_reset_one.bind(action))
		row.add_child(reset_button)
		_resets[action] = reset_button

func _on_family_changed(_index: int) -> void:
	_refresh_rows()

func _refresh_rows() -> void:
	if not is_node_ready():
		return
	for action in _buttons:
		var texts: PackedStringArray = []
		for binding in InputControls.bindings_for(action, _family.selected):
			texts.append(BINDINGS.label(binding, InputControls.selected_style()))
		var text := " / ".join(texts)
		if text.is_empty():
			text = "Mouse (ou atribuir tecla)" if str(action).begins_with("aim_") and _family.selected == BINDINGS.KEYBOARD else "Atribuir entrada"
		_buttons[action].text = text
		_buttons[action].tooltip_text = text
	_close.text = "Voltar / descartar" if _dirty else "Voltar"

func _refresh_preferences() -> void:
	_refreshing = true
	_move.value = InputControls.move_deadzone
	_aim.value = InputControls.aim_deadzone
	_style.select(BINDINGS.STYLES.find(InputControls.prompt_style))
	_move_value.text = "%d%%" % roundi(_move.value * 100.0)
	_aim_value.text = "%d%%" % roundi(_aim.value * 100.0)
	_refreshing = false

func _on_preferences_changed() -> void:
	if _refreshing or not visible:
		return
	var message := InputControls.set_preferences(_move.value, _aim.value, BINDINGS.STYLES[_style.selected])
	if not message.is_empty():
		_status.text = message
		return
	_changed()
	_refresh_preferences()

func _changed() -> void:
	_dirty = true
	_status.text = "Alterações em teste. Aplicar salva; Voltar descarta as alterações não salvas."
	_refresh_rows()

func _save() -> void:
	if not _capturing.is_empty():
		return
	if InputControls.save_settings() != OK:
		_status.text = InputControls.last_error
		return
	_before = InputControls.settings_snapshot()
	_dirty = false
	_status.text = "Controles salvos."
	_refresh_rows()

func _reset_all() -> void:
	_cancel_capture()
	InputControls.reset_defaults()
	_refresh_preferences()
	_changed()

func _reset_one(action: StringName) -> void:
	var message := InputControls.reset_action(action, _family.selected)
	if not message.is_empty():
		_status.text = message
		return
	_changed()

func _begin_capture(action: StringName) -> void:
	_capturing = action
	_capture_family = _family.selected
	_capture_frame = Engine.get_process_frames()
	_capture_armed = false
	_pending_binding.clear()
	_set_capture_enabled(true)
	_status.text = "Solte os controles antes de atribuir uma entrada. Esc / botão leste cancela."

func _set_capture_enabled(capturing: bool) -> void:
	_family.disabled = capturing
	_style.disabled = capturing
	_move.editable = not capturing
	_aim.editable = not capturing
	_apply.disabled = capturing
	_reset.disabled = capturing
	for action in _buttons:
		_buttons[action].disabled = capturing
		_resets[action].disabled = capturing
	_close.text = "Cancelar captura" if capturing else ("Voltar / descartar" if _dirty else "Voltar")
	_close.grab_focus()

func _process(_delta: float) -> void:
	if not visible or _capturing.is_empty() or _capture_armed:
		return
	if Engine.get_process_frames() <= _capture_frame or not _inputs_neutral():
		return
	_capture_armed = true
	_status.text = "Pressione a nova entrada para %s. Esc / botão leste cancela." % BINDINGS.LABELS[str(_capturing)]

func _inputs_neutral() -> bool:
	if Input.is_anything_pressed():
		return false
	if InputControls.active_device >= 0:
		for axis in range(JOY_AXIS_MAX):
			var value: float = InputControls._pad_axes.get(axis, Input.get_joy_axis(InputControls.active_device, axis))
			if absf(value) > maxf(0.25, maxf(InputControls.move_deadzone, InputControls.aim_deadzone)):
				return false
	return true

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not InputControls.observe_event(event):
		return
	if event is InputEventKey and event.pressed and not event.echo and (event.physical_keycode == KEY_F12 or event.keycode == KEY_F12):
		_reset_all()
		InputControls.consume_ui_event(event)
		return
	if _capturing.is_empty():
		return
	if InputControls.ui_pressed(event, &"ui_cancel"):
		_cancel_capture()
	elif event is InputEventMouseButton and event.pressed and _close.get_global_rect().has_point(event.position):
		_cancel_capture()
	elif _capture_armed:
		if not _pending_binding.is_empty():
			if _releases_binding(event, _pending_binding):
				_finish_capture()
		elif (event.is_pressed() and not event.is_echo()) or event is InputEventJoypadMotion:
			var binding: Dictionary = BINDINGS.from_event(event)
			if BINDINGS.valid(binding) and BINDINGS.family(binding) == _capture_family:
				_pending_binding = binding
				_status.text = "Solte %s para concluir a atribuição." % BINDINGS.label(binding, InputControls.selected_style())
	InputControls.consume_ui_event(event)

func _unhandled_input(event: InputEvent) -> void:
	if is_visible_in_tree() and _capturing.is_empty() and InputControls.ui_pressed(event, &"ui_cancel"):
		request_close()
		InputControls.consume_ui_event(event)

func _releases_binding(event: InputEvent, binding: Dictionary) -> bool:
	if binding.kind == "axis":
		return event is InputEventJoypadMotion and event.axis == binding.code and absf(event.axis_value) <= 0.2
	if event.is_pressed():
		return false
	var released: Dictionary = BINDINGS.from_event(event)
	return BINDINGS.valid(released) and BINDINGS.identity(released) == BINDINGS.identity(binding)

func _finish_capture() -> void:
	var action := _capturing
	var message := InputControls.rebind_action(action, _capture_family, _pending_binding)
	_cancel_capture()
	if message.is_empty():
		_changed()
	else:
		_status.text = message
	_buttons[action].grab_focus()

func _cancel_capture() -> void:
	if _capturing.is_empty():
		return
	var action := _capturing
	_capturing = &""
	_pending_binding.clear()
	_capture_armed = false
	_set_capture_enabled(false)
	_status.text = "Captura encerrada."
	_refresh_rows()
	_buttons[action].grab_focus()
	InputControls.suppress_held()
