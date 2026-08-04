class_name SandboxUI
extends Control
## Overlay minimo para comandos de desenvolvimento; a logica fica no SandboxController.

@export var player_path: NodePath
@export var session_path: NodePath

var _controller: SandboxController
var _status: Label
var _stat_id: OptionButton
var _stat_value: LineEdit
var _item_id: OptionButton
var _amount: SpinBox
var _god_mode: CheckButton
var _seed: LineEdit
var _sector: SpinBox
var _node: SpinBox
var _node_type: OptionButton
var _tree_was_paused := false

func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	_controller = SandboxController.new(get_node_or_null(player_path), get_node_or_null(session_path) as Session)
	_build_ui()
	hide()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"dev_sandbox_toggle"):
		if visible:
			_close()
		else:
			_open()
		get_viewport().set_input_as_handled()

func _open() -> void:
	_tree_was_paused = get_tree().paused
	get_tree().paused = true
	show()
	_stat_id.grab_focus()

func _close() -> void:
	hide()
	get_tree().paused = _tree_was_paused

func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-180, -125)
	panel.size = Vector2(360, 250)
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := Label.new()
	title.text = "Sandbox (F10)"
	box.add_child(title)
	var stats := HBoxContainer.new()
	_stat_id = OptionButton.new()
	_stat_id.custom_minimum_size.x = 70
	var stat_ids: Array[String] = []
	for stat: StatDef in StatCatalog.get_all():
		stat_ids.append(String(stat.id))
	stat_ids.sort()
	for stat_id: String in stat_ids:
		_stat_id.add_item(stat_id)
	if not stat_ids.is_empty():
		_stat_id.select(0)
	_stat_value = _line("valor", "10")
	stats.add_child(_stat_id)
	stats.add_child(_stat_value)
	stats.add_child(_button("Definir stat", _on_set_stat))
	box.add_child(stats)
	var items := HBoxContainer.new()
	_item_id = OptionButton.new()
	_item_id.custom_minimum_size.x = 70
	var item_ids: Array[String] = []
	for item: ItemDef in ItemCatalog.get_all():
		item_ids.append(String(item.id))
	item_ids.sort()
	for item_id: String in item_ids:
		_item_id.add_item(item_id)
	if not item_ids.is_empty():
		_item_id.select(0)
	_amount = SpinBox.new()
	_amount.min_value = 1
	_amount.max_value = 99
	_amount.value = 1
	_amount.custom_minimum_size.x = 55
	items.add_child(_item_id)
	items.add_child(_amount)
	items.add_child(_button("+ Item", _on_grant_item))
	items.add_child(_button("- Item", _on_remove_item))
	box.add_child(items)
	var actions := HBoxContainer.new()
	actions.add_child(_button("Curar", _on_heal))
	_god_mode = CheckButton.new()
	_god_mode.text = "God mode"
	_god_mode.toggled.connect(_on_god_mode)
	actions.add_child(_god_mode)
	actions.add_child(_button("Limpar sala", _on_clear_room))
	box.add_child(actions)
	var warp := HBoxContainer.new()
	_seed = _line("seed", "1")
	_seed.custom_minimum_size.x = 70
	_sector = SpinBox.new()
	_sector.min_value = 0
	_sector.max_value = 2
	_sector.tooltip_text = "Setor"
	_node = SpinBox.new()
	_node.min_value = 0
	_node.max_value = 26
	_node.tooltip_text = "No"
	_node_type = OptionButton.new()
	_node_type.add_item("Opening", SectorNode.NodeType.OPENING)
	_node_type.add_item("Combat", SectorNode.NodeType.COMBAT)
	_node_type.add_item("Boss", SectorNode.NodeType.BOSS)
	warp.add_child(_seed)
	warp.add_child(_sector)
	warp.add_child(_node)
	warp.add_child(_node_type)
	warp.add_child(_button("Warp", _on_warp))
	box.add_child(warp)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)

func _line(placeholder: String, value: String) -> LineEdit:
	var line := LineEdit.new()
	line.placeholder_text = placeholder
	line.text = value
	line.custom_minimum_size.x = 70
	return line

func _button(label: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.pressed.connect(callback)
	return button

func _on_set_stat() -> void:
	if _stat_id.item_count == 0 or _stat_id.selected < 0:
		_status.text = "Nenhuma stat disponivel."
		return
	if not _stat_value.text.is_valid_float():
		_status.text = "Valor invalido."
		return
	var stat_id := StringName(_stat_id.get_item_text(_stat_id.selected))
	_status.text = "Stat atualizado." if _controller.set_stat_override(stat_id, _stat_value.text.to_float()) else "Stat invalido."

func _on_grant_item() -> void:
	if _item_id.item_count == 0 or _item_id.selected < 0:
		_status.text = "Nenhum item disponivel."
		return
	var item_id := StringName(_item_id.get_item_text(_item_id.selected))
	_status.text = "%d item(ns) adicionados." % _controller.grant_item(item_id, int(_amount.value))

func _on_remove_item() -> void:
	if _item_id.item_count == 0 or _item_id.selected < 0:
		_status.text = "Nenhum item disponivel."
		return
	var item_id := StringName(_item_id.get_item_text(_item_id.selected))
	_status.text = "%d item(ns) removidos." % _controller.remove_item(item_id, int(_amount.value))

func _on_heal() -> void:
	_status.text = "Vida restaurada." if _controller.heal_player() else "Jogador indisponivel."

func _on_god_mode(enabled: bool) -> void:
	_status.text = "God mode ligado." if _controller.set_god_mode(enabled) else "Jogador indisponivel."

func _on_clear_room() -> void:
	_status.text = "Sala sendo limpa." if _controller.clear_room() else "Nenhuma sala ativa."

func _on_warp() -> void:
	if not _seed.text.is_valid_int():
		_status.text = "Seed invalida."
		return
	var type := _node_type.get_selected_id()
	_status.text = "Warp concluido." if _controller.warp(_seed.text.to_int(), int(_sector.value), int(_node.value), type) else "Destino invalido."
