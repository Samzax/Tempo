extends Control

class ShiftCooldownIcon:
	extends Control

	const CORE_TEXTURE := preload("res://assets/ui/blink_core.png")
	const ICON_SIZE := 32
	var cooldown_ratio: float = 0.0
	var use_charge_indicator := false
	var _pulse_step: int = -1

	func _ready() -> void:
		set_process(cooldown_ratio <= 0.0)
		if cooldown_ratio <= 0.0:
			_update_pulse_step()

	func set_cooldown_ratio(value: float) -> void:
		var next_ratio := clampf(value, 0.0, 1.0)
		var was_ready := cooldown_ratio <= 0.0
		var is_ready := next_ratio <= 0.0
		var ratio_changed := not is_equal_approx(next_ratio, cooldown_ratio)
		cooldown_ratio = next_ratio
		if is_ready:
			set_process(true)
			if not was_ready:
				_pulse_step = -1
			_update_pulse_step()
		else:
			set_process(false)
			if was_ready:
				_pulse_step = -1
			if was_ready or ratio_changed:
				queue_redraw()

	func set_charge_indicator(value: bool) -> void:
		if use_charge_indicator == value:
			return
		use_charge_indicator = value
		queue_redraw()

	func _process(_delta: float) -> void:
		if cooldown_ratio <= 0.0:
			_update_pulse_step()

	func _update_pulse_step() -> void:
		var next_step := int(Time.get_ticks_msec() / 180) % 4
		if next_step != _pulse_step:
			_pulse_step = next_step
			queue_redraw()

	func _draw() -> void:
		if use_charge_indicator:
			_draw_charge_indicator()
			return
		var full_rect := Rect2(Vector2.ZERO, Vector2.ONE * ICON_SIZE)
		if cooldown_ratio <= 0.0:
			# Alterna apenas a cor: o pulso mantém pixels inteiros e sem blur.
			var ready_tint := Color(0.76, 1.0, 1.0) if _pulse_step < 2 else Color(0.96, 1.0, 1.0)
			draw_texture_rect(CORE_TEXTURE, full_rect, false, ready_tint)
			return

		var covered_height := ceili(ICON_SIZE * cooldown_ratio)
		var covered_rect := Rect2(0, 0, ICON_SIZE, covered_height)
		# A própria alpha da textura recorta a máscara e conserva o fundo transparente.
		draw_texture_rect_region(CORE_TEXTURE, covered_rect, covered_rect, Color(0.04, 0.18, 0.22, 0.92))
		if covered_height < ICON_SIZE:
			var revealed_rect := Rect2(0, covered_height, ICON_SIZE, ICON_SIZE - covered_height)
			draw_texture_rect_region(CORE_TEXTURE, revealed_rect, revealed_rect, Color.WHITE)

	## Três células de energia: um sinal neutro de carga, sem sugerir teleporte.
	func _draw_charge_indicator() -> void:
		var ready_ratio := 1.0 - cooldown_ratio
		var ready_tint := Color(1.0, 0.78, 0.35) if _pulse_step < 2 else Color(1.0, 0.9, 0.52)
		var frame_tint := Color(0.46, 0.29, 0.12, 0.95)
		for index in 3:
			var cell := Rect2(5.0, 5.0 + index * 8.0, 22.0, 5.0)
			draw_rect(cell, frame_tint, false, 1.0)
			var fill_width := clampf(ready_ratio * 22.0 - index * 3.0, 0.0, 22.0)
			if fill_width > 0.0:
				draw_rect(Rect2(cell.position, Vector2(fill_width, cell.size.y)), ready_tint)
## HUD: pontuação, vidas, vida (pips) e estado do blink, com tela de fim de jogo.
## Lê os valores por polling a cada quadro — simples e suficiente para esta UI.

var _score: Label
var _lives: Label
var _blink_icon: ShiftCooldownIcon
var _game_over: Label
var _pips_row: HBoxContainer
var _pips: Array[ColorRect] = []
var _player: Node = null
var _gs: Node = null
var _over: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gs = get_node_or_null("/root/GameState")
	_build()
	_bind_player(get_tree().get_first_node_in_group("player"))

func _build() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(6, 5)
	box.add_theme_constant_override("separation", 3)
	add_child(box)

	_score = _make_label(14, Color(1, 1, 1))
	box.add_child(_score)
	_lives = _make_label(12, Color(0.85, 0.9, 1.0))
	box.add_child(_lives)

	_pips_row = HBoxContainer.new()
	_pips_row.add_theme_constant_override("separation", 2)
	box.add_child(_pips_row)

	_blink_icon = ShiftCooldownIcon.new()
	_blink_icon.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_blink_icon.offset_left = -44
	_blink_icon.offset_top = -44
	_blink_icon.offset_right = -12
	_blink_icon.offset_bottom = -12
	_blink_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_blink_icon)

	_game_over = _make_label(22, Color(1, 0.85, 0.4))
	_game_over.set_anchors_preset(Control.PRESET_FULL_RECT)
	_game_over.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_game_over.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_game_over.hide()
	add_child(_game_over)

func _make_label(size: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("outline_size", 4)
	return l

func _process(_dt: float) -> void:
	if not is_visible_in_tree():
		return
	if _player == null or not is_instance_valid(_player):
		_bind_player(get_tree().get_first_node_in_group("player"))
	if _gs != null:
		_score.text = "PONTOS  %d" % _gs.score
		_lives.text = "VIDAS  %d" % _gs.player_lives
	var blink_ratio := 0.0
	var use_charge_indicator := false
	if _player != null and is_instance_valid(_player) and _player.health != null and is_instance_valid(_player.health):
		var hp: int = floori(_player.health.health)
		for i in _pips.size():
			_pips[i].color = Color(1.0, 0.3, 0.35) if i < hp else Color(0.25, 0.25, 0.3)
		blink_ratio = clampf(_player.shift_cooldown_ratio(), 0.0, 1.0)
		use_charge_indicator = _player.has_method(&"uses_bruta_charge_shift") and bool(_player.call(&"uses_bruta_charge_shift"))
	_blink_icon.set_charge_indicator(use_charge_indicator)
	_blink_icon.set_cooldown_ratio(blink_ratio)
	if not _over and _gs != null and _gs.player_lives <= 0:
		_trigger_over()

func _bind_player(next_player: Node) -> void:
	if next_player == _player and is_instance_valid(_player):
		if not _player.health_capacity_changed.is_connected(_on_player_health_capacity_changed):
			_player.health_capacity_changed.connect(_on_player_health_capacity_changed)
		return
	if is_instance_valid(_player) and _player.health_capacity_changed.is_connected(_on_player_health_capacity_changed):
		_player.health_capacity_changed.disconnect(_on_player_health_capacity_changed)
	_player = next_player
	if not is_instance_valid(_player):
		_player = null
		return
	if not _player.health_capacity_changed.is_connected(_on_player_health_capacity_changed):
		_player.health_capacity_changed.connect(_on_player_health_capacity_changed)
	if _player.health != null and is_instance_valid(_player.health):
		_rebuild_pips(_player.health.max_health)

func _on_player_health_capacity_changed(max_health: float) -> void:
	_rebuild_pips(max_health)

func _rebuild_pips(max_health: float) -> void:
	var pip_count := maxi(floori(max_health), 0)
	for child in _pips_row.get_children():
		_pips_row.remove_child(child)
		child.queue_free()
	_pips.clear()
	var health := floori(_player.health.health) if is_instance_valid(_player) and _player.health != null else 0
	for i in pip_count:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(7, 7)
		pip.color = Color(1.0, 0.3, 0.35) if i < health else Color(0.25, 0.25, 0.3)
		_pips_row.add_child(pip)
		_pips.append(pip)

func _trigger_over() -> void:
	_over = true
	_game_over.text = "FIM DE JOGO\nEnter para reiniciar"
	_game_over.show()
	get_tree().paused = true

func _unhandled_input(event: InputEvent) -> void:
	if _over and event.is_action_pressed("ui_accept"):
		_restart()

func _restart() -> void:
	_over = false
	get_tree().paused = false
	if _gs != null:
		_gs.score = 0
		_gs.player_lives = 3
	get_tree().reload_current_scene()
