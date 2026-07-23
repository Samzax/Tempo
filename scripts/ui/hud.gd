extends Control
## HUD: pontuação, vidas, vida (pips) e estado do blink, com tela de fim de jogo.
## Lê os valores por polling a cada quadro — simples e suficiente para esta UI.

var _score: Label
var _lives: Label
var _blink: Label
var _game_over: Label
var _pips: Array[ColorRect] = []
var _player: Node = null
var _gs: Node = null
var _over: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gs = get_node_or_null("/root/GameState")
	_player = get_tree().get_first_node_in_group("player")
	_build()

func _build() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(6, 5)
	box.add_theme_constant_override("separation", 3)
	add_child(box)

	_score = _make_label(14, Color(1, 1, 1))
	box.add_child(_score)
	_lives = _make_label(12, Color(0.85, 0.9, 1.0))
	box.add_child(_lives)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	box.add_child(row)
	var maxhp := 5
	if _player != null and _player.health != null:
		maxhp = _player.health.max_health
	for i in maxhp:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(7, 7)
		row.add_child(pip)
		_pips.append(pip)

	_blink = _make_label(11, Color(0.6, 0.9, 1.0))
	box.add_child(_blink)

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
	if _gs != null:
		_score.text = "PONTOS  %d" % _gs.score
		_lives.text = "VIDAS  %d" % _gs.player_lives
	if _player != null and is_instance_valid(_player) and _player.health != null:
		var hp: int = _player.health.health
		for i in _pips.size():
			_pips[i].color = Color(1.0, 0.3, 0.35) if i < hp else Color(0.25, 0.25, 0.3)
		if _player.blink_cooldown_ratio() <= 0.0:
			_blink.text = "BLINK  pronto"
			_blink.add_theme_color_override("font_color", Color(0.6, 0.95, 1.0))
		else:
			_blink.text = "BLINK  recarregando"
			_blink.add_theme_color_override("font_color", Color(0.5, 0.55, 0.65))
	if not _over and _gs != null and _gs.player_lives <= 0:
		_trigger_over()

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
