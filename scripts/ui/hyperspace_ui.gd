class_name HyperspaceUI
extends Control

signal node_selected(node_id: int)
signal sector_advance_requested

var _sector: SectorDef
var _completed: Dictionary = {}
var _selectable: Array[int] = []
var _node_positions: Dictionary = {}
var _cursor: int = 0
var _can_select := false
var _sector_advance_available := false
var _completes_run := false

func _ready() -> void:
	# CanvasLayer is not a Control parent, so full-rect anchors alone do not
	# establish a usable GUI rect. Keep this aligned to the fixed 480x270 map.
	position = Vector2.ZERO
	size = Vector2(480.0, 270.0)
	# O mapa precisa ser o alvo GUI do clique; eventos de teclado continuam no
	# _unhandled_input para preservar Esc, M e Enter.
	mouse_filter = Control.MOUSE_FILTER_STOP
	hide()

func present(sector: SectorDef, completed: Dictionary, selectable: Array[int], can_select: bool) -> void:
	_sector = sector
	_completed = completed
	_selectable = selectable
	_can_select = can_select
	_sector_advance_available = false
	_completes_run = false
	_cursor = 0
	_layout_nodes()
	show()
	queue_redraw()

func present_sector_advance(sector: SectorDef, completed: Dictionary, completes_run: bool) -> void:
	_sector = sector
	_completed = completed
	_selectable = []
	_can_select = false
	_sector_advance_available = true
	_completes_run = completes_run
	_cursor = 0
	_layout_nodes()
	show()
	queue_redraw()

func refresh(completed: Dictionary, selectable: Array[int], can_select: bool) -> void:
	_completed = completed
	_selectable = selectable
	_can_select = can_select
	_sector_advance_available = false
	_completes_run = false
	_cursor = clampi(_cursor, 0, maxi(0, _selectable.size() - 1))
	queue_redraw()

func _layout_nodes() -> void:
	_node_positions.clear()
	if _sector == null:
		return
	var rows := [1, 2, 2, 1, 1]
	for node in _sector.nodes.values():
		var row_count: int = rows[node.column]
		var row := _row_for_node(node, row_count)
		_node_positions[node.id] = Vector2(62.0 + node.column * 88.0, 135.0 + (row - (row_count - 1) * 0.5) * 66.0)

func _row_for_node(node: SectorNode, row_count: int) -> int:
	if row_count == 1:
		return 0
	return node.row

func _draw() -> void:
	if _sector == null:
		return
	draw_rect(Rect2(0, 0, 480, 270), Color(0.015, 0.025, 0.07, 0.94), true)
	draw_string(ThemeDB.fallback_font, Vector2(18, 22), "HIPERESPAÇO  —  SETOR %d" % (_sector.sector_index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.65, 0.9, 1.0))
	for node in _sector.nodes.values():
		for child_id in node.children:
			draw_line(_node_positions[node.id], _node_positions[child_id], Color(0.22, 0.36, 0.52), 2.0)
	for node in _sector.nodes.values():
		var pos: Vector2 = _node_positions[node.id]
		var completed := _completed.has("%d:%s" % [_sector.sector_index, node.id])
		var selectable := _selectable.has(node.id)
		var color := Color(0.24, 0.33, 0.45)
		if completed: color = Color(0.25, 0.82, 0.55)
		elif selectable: color = Color(0.45, 0.8, 1.0)
		if selectable and _cursor < _selectable.size() and _selectable[_cursor] == node.id:
			draw_circle(pos, 15.0, Color(0.75, 0.94, 1.0, 0.25))
		draw_circle(pos, 9.0, color)
		var label := "BOSS" if node.node_type == SectorNode.NodeType.BOSS else ("INICIO" if node.node_type == SectorNode.NodeType.OPENING else "COMBATE")
		draw_string(ThemeDB.fallback_font, pos + Vector2(-25, 25), label, HORIZONTAL_ALIGNMENT_CENTER, 50, 8, Color.WHITE)
	var footer := "Clique ou Enter para viajar · Esc fecha · M reabre"
	if _selectable.is_empty() and _sector.get_node(_sector.start_node_id) != null and _completed.has("%d:%s" % [_sector.sector_index, _sector.start_node_id + 6]):
		footer = "EXECUÇÃO CONCLUÍDA"
	if _sector_advance_available:
		footer = "Enter: %s | Esc fecha | M reabre" % ("CONCLUIR EXECUCAO" if _completes_run else "AVANCAR SETOR")
	draw_string(ThemeDB.fallback_font, Vector2(18, 252), footer, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.65, 0.72, 0.84))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			hide()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_M and not visible:
			show()
			queue_redraw()
			get_viewport().set_input_as_handled()
			return
	if not visible:
		return
	if event.is_action_pressed(&"ui_left") or event.is_action_pressed(&"ui_up"):
		_cursor = posmod(_cursor - 1, maxi(1, _selectable.size()))
		queue_redraw()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_right") or event.is_action_pressed(&"ui_down"):
		_cursor = posmod(_cursor + 1, maxi(1, _selectable.size()))
		queue_redraw()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_accept"):
		if _sector_advance_available:
			_sector_advance_available = false
			sector_advance_requested.emit()
		elif _cursor < _selectable.size():
			_try_select(_selectable[_cursor])
		get_viewport().set_input_as_handled()

func _gui_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventMouseButton) or event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return
	for node_id in _selectable:
		if _node_positions[node_id].distance_to(event.position) <= 16.0:
			_try_select(node_id)
			accept_event()
			return

func _try_select(node_id: int) -> void:
	if _can_select and _selectable.has(node_id):
		node_selected.emit(node_id)
