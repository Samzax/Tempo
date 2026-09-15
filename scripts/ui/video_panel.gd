class_name VideoPanel
extends Control
## Painel transacional de video: Aplicar salva; Voltar descarta rascunhos nao salvos.

signal close_requested

@onready var _resolution: OptionButton = $Panel/MarginContainer/Content/ResolutionRow/Resolution
@onready var _mode: OptionButton = $Panel/MarginContainer/Content/ModeRow/Mode
@onready var _status: Label = $Panel/MarginContainer/Content/Status
@onready var _reset: Button = $Panel/MarginContainer/Content/Actions/Reset
@onready var _apply: Button = $Panel/MarginContainer/Content/Actions/Apply
@onready var _close: Button = $Panel/MarginContainer/Content/Actions/CloseButton

var _before: Dictionary = {}
var _dirty := false
var _refreshing := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_resolution.item_selected.connect(_on_selection_changed)
	_mode.item_selected.connect(_on_selection_changed)
	_apply.pressed.connect(_save)
	_reset.pressed.connect(_reset_default)
	_close.pressed.connect(request_close)
	_populate_options()
	hide()

func _populate_options() -> void:
	_resolution.clear()
	var candidates := VideoSettings.resolution_candidates()
	var native := VideoSettings.native_resolution()
	for i in candidates.size():
		var res := candidates[i]
		var text := "%dx%d" % [res.x, res.y]
		if res == native:
			text += " (nativa)"
		_resolution.add_item(text, i)
		_resolution.set_item_metadata(i, res)
	_mode.clear()
	_mode.add_item("Janela", 0)
	_mode.add_item("Tela cheia", 1)

func open() -> void:
	_before = VideoSettings.settings_snapshot()
	_dirty = false
	InputControls.set_modal(self, true)
	show()
	_refresh_controls()
	_status.text = VideoSettings.last_error
	_close.grab_focus()

func _refresh_controls() -> void:
	_refreshing = true
	var current_res := VideoSettings.resolution
	var best_index := -1
	var min_diff := 99999999
	for i in _resolution.item_count:
		var res: Vector2i = _resolution.get_item_metadata(i)
		if res == current_res:
			best_index = i
			break
		var area_diff := absi((res.x * res.y) - (current_res.x * current_res.y))
		if area_diff < min_diff:
			min_diff = area_diff
			best_index = i
	if best_index >= 0 and _resolution.item_count > 0:
		_resolution.select(best_index)
	_mode.select(1 if VideoSettings.fullscreen else 0)
	_refreshing = false

func _on_selection_changed(_index: int) -> void:
	if _refreshing or not visible:
		return
	var selected_res: Vector2i = _resolution.get_item_metadata(_resolution.selected) if _resolution.selected >= 0 else VideoSettings.resolution
	var selected_fs := _mode.selected == 1
	VideoSettings.apply_settings(selected_res, selected_fs)
	_dirty = true
	_status.text = "Aplicar salva; Voltar descarta mudanças não salvas."

func _save() -> void:
	var err := VideoSettings.save_settings()
	if err == OK:
		_before = VideoSettings.settings_snapshot()
		_dirty = false
		_status.text = "Configuração de vídeo salva."
	else:
		_status.text = VideoSettings.last_error

func _reset_default() -> void:
	VideoSettings.reset_to_default()
	_refresh_controls()
	_dirty = true
	_status.text = "Aplicar salva; Voltar descarta mudanças não salvas."

func request_close() -> void:
	if _dirty and not _before.is_empty():
		VideoSettings.apply_snapshot(_before)
	_dirty = false
	InputControls.set_modal(self, false)
	hide()
	close_requested.emit()

func force_close() -> void:
	request_close()

func _exit_tree() -> void:
	if _dirty and not _before.is_empty():
		VideoSettings.apply_snapshot(_before)
		_dirty = false
	InputControls.set_modal(self, false)

func _unhandled_input(event: InputEvent) -> void:
	if visible and InputControls.ui_pressed(event, &"ui_cancel"):
		request_close()
		InputControls.consume_ui_event(event)
