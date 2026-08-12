extends Control

class AbilitySlotIcon:
	extends Control

	const SLOT_SIZE := 38.0
	const ICON_SIZE := 32.0
	const ICON_MARGIN := 3.0
	const SLOT_CENTER := Vector2(19, 20)
	const NEUTRAL_TINT := Color(0.933333, 0.945098, 0.964706, 1.0) # #EEF1F6
	const SLOT_BACKGROUND := Color(0.019608, 0.039216, 0.07451, 0.588235) # ARGB 150,5,10,19
	const INACTIVE_BORDER := Color(0.45098, 0.478431, 0.52549, 0.431373) # ARGB 110,115,122,134
	const KEY_TEXT := Color(0.894118, 0.917647, 0.94902, 0.933333) # ARGB 238,228,234,242
	const KEY_BADGE := Color(0.007843, 0.019608, 0.043137, 0.854902) # ARGB 218,2,5,11
	const COOLDOWN_WIPE := Color(0.007843, 0.019608, 0.043137, 0.72549) # ARGB 185,2,5,11
	const DISABLED_DIM := Color(0, 0, 0, 0.352941) # ARGB 90,0,0,0
	const DISABLED_ICON_TINT := Color(0.478431, 0.501961, 0.545098, 1.0)
	const KEY_FONT := preload("res://addons/gut/fonts/CourierPrime-Regular.ttf")
	const ICONS := {
		&"sobrecarga": preload("res://assets/ui/abilities/sobrecarga.png"),
		&"escudo": preload("res://assets/ui/abilities/escudo.png"),
		&"bruta_investida": preload("res://assets/ui/abilities/bruta_investida.png"),
		&"engenheira_deploy": preload("res://assets/ui/abilities/engenheira_deploy.png"),
		&"interceptadora_blink": preload("res://assets/ui/abilities/interceptadora_blink.png"),
		&"time_warp": preload("res://assets/ui/abilities/time_warp.png"),
		&"guardian_shield": preload("res://assets/ui/abilities/guardian_shield.png"),
		&"hacker_overdrive": preload("res://assets/ui/abilities/hacker_overdrive.png"),
	}

	var ability_id: StringName = &""
	var icon_id: StringName = &""
	var slot_state: StringName = &"disabled"
	var cooldown_ratio := 0.0
	var tint := NEUTRAL_TINT
	# Compatibilidade de leitura para o teste do HUD anterior; a Bruta usa a arte aprovada.
	var use_charge_indicator := false
	var _key_label: Label

	func _ready() -> void:
		custom_minimum_size = Vector2.ONE * SLOT_SIZE
		size = Vector2.ONE * SLOT_SIZE
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_key_label = Label.new()
		_key_label.position = Vector2(4, 1)
		_key_label.add_theme_font_override("font", KEY_FONT)
		_key_label.add_theme_font_size_override("font_size", 9)
		_key_label.add_theme_color_override("font_color", KEY_TEXT)
		_key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_key_label)

	func configure(slot: Dictionary) -> void:
		ability_id = slot.get("ability_id", &"")
		icon_id = slot.get("icon_id", ability_id)
		slot_state = slot.get("state", &"disabled")
		cooldown_ratio = clampf(float(slot.get("cooldown_ratio", 0.0)), 0.0, 1.0)
		tint = slot.get("tint", NEUTRAL_TINT)
		use_charge_indicator = ability_id == &"bruta_investida"
		if _key_label != null:
			_key_label.text = str(slot.get("key", ""))
		queue_redraw()

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, Vector2.ONE * SLOT_SIZE)
		var active := slot_state == &"ready" or slot_state == &"cooldown"
		var border_tint := Color(tint.r, tint.g, tint.b, 0.745098) if active else INACTIVE_BORDER
		draw_rect(rect, SLOT_BACKGROUND)
		draw_rect(rect, border_tint, false, 1.0)
		var icon_rect := Rect2(Vector2.ONE * ICON_MARGIN, Vector2.ONE * ICON_SIZE)
		if slot_state == &"passive":
			_draw_passive()
		else:
			var icon := ICONS.get(icon_id) as Texture2D
			if icon != null:
				var icon_tint := DISABLED_ICON_TINT if slot_state == &"disabled" else tint
				draw_texture_rect(icon, icon_rect, false, icon_tint)
			elif slot_state == &"disabled":
				_draw_disabled(icon_rect)
		if slot_state == &"cooldown":
			var covered := ceili(ICON_SIZE * cooldown_ratio)
			if covered > 0.0:
				# O wipe do preview V3 ocupa o final do glifo e cresce de baixo para cima.
				draw_rect(Rect2(Vector2(icon_rect.position.x, icon_rect.end.y - covered), Vector2(ICON_SIZE, covered)), COOLDOWN_WIPE)
		elif slot_state == &"disabled":
			draw_rect(icon_rect, DISABLED_DIM)
		_draw_key_badge()

	func _draw_key_badge() -> void:
		if _key_label == null or _key_label.text.is_empty():
			return
		var badge_width := clampf(ceilf(_key_label.get_minimum_size().x) + 5.0, 12.0, SLOT_SIZE - 4.0)
		# O badge fica dentro do slot/glifo; o Label e desenhado depois deste Control.
		draw_rect(Rect2(Vector2(2, 2), Vector2(badge_width, 11)), KEY_BADGE)

	func _draw_passive() -> void:
		_draw_diamond(SLOT_CENTER + Vector2(-13, 0), SLOT_CENTER + Vector2(-8, -4), SLOT_CENTER + Vector2(-3, 0), SLOT_CENTER + Vector2(-8, 4))
		_draw_diamond(SLOT_CENTER + Vector2(3, 0), SLOT_CENTER + Vector2(8, -4), SLOT_CENTER + Vector2(13, 0), SLOT_CENTER + Vector2(8, 4))

	func _draw_diamond(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> void:
		draw_line(a, b, INACTIVE_BORDER, 1.0)
		draw_line(b, c, INACTIVE_BORDER, 1.0)
		draw_line(c, d, INACTIVE_BORDER, 1.0)
		draw_line(d, a, INACTIVE_BORDER, 1.0)

	func _draw_disabled(icon_rect: Rect2) -> void:
		draw_line(icon_rect.position + Vector2(8, 8), icon_rect.end - Vector2(8, 8), INACTIVE_BORDER, 2.0)
		draw_line(Vector2(icon_rect.end.x - 8, icon_rect.position.y + 8), Vector2(icon_rect.position.x + 8, icon_rect.end.y - 8), INACTIVE_BORDER, 2.0)

## HUD: pontuacao, vidas, vida (pips), habilidades e tela de fim de jogo.
var _score: Label
var _lives: Label
var _blink_icon: AbilitySlotIcon
var _ability_slots: Array[AbilitySlotIcon] = []
var _game_over: Label
var _pips_row: HBoxContainer
var _pips: Array[ColorRect] = []
var _player: Node = null
var _gs: Node = null
var _over := false

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
	_score = _make_label(14, Color.WHITE)
	box.add_child(_score)
	_lives = _make_label(12, Color(0.85, 0.9, 1.0))
	box.add_child(_lives)
	_pips_row = HBoxContainer.new()
	_pips_row.add_theme_constant_override("separation", 2)
	box.add_child(_pips_row)

	var abilities := HBoxContainer.new()
	abilities.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	# Três slots de 38 px e dois vãos de 4 px: 122 x 38, a 8 px do canto.
	abilities.custom_minimum_size = Vector2(122, 38)
	abilities.offset_left = -130
	abilities.offset_top = -46
	abilities.offset_right = -8
	abilities.offset_bottom = -8
	abilities.add_theme_constant_override("separation", 4)
	abilities.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(abilities)
	for _index in 3:
		var slot := AbilitySlotIcon.new()
		abilities.add_child(slot)
		_ability_slots.append(slot)
	_blink_icon = _ability_slots[2]

	_game_over = _make_label(22, Color(1, 0.85, 0.4))
	_game_over.set_anchors_preset(Control.PRESET_FULL_RECT)
	_game_over.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_game_over.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_game_over.hide()
	add_child(_game_over)

func _make_label(size: int, col: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", col)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	label.add_theme_constant_override("outline_size", 4)
	return label

func _process(_dt: float) -> void:
	if not is_visible_in_tree():
		return
	if _player == null or not is_instance_valid(_player):
		_bind_player(get_tree().get_first_node_in_group("player"))
	if _gs != null:
		_score.text = "PONTOS  %d" % _gs.score
		_lives.text = "VIDAS  %d" % _gs.player_lives
	if _player != null and is_instance_valid(_player) and _player.health != null and is_instance_valid(_player.health):
		var hp := floori(_player.health.health)
		for i in _pips.size():
			_pips[i].color = Color(1.0, 0.3, 0.35) if i < hp else Color(0.25, 0.25, 0.3)
		_refresh_ability_slots()
	if not _over and _gs != null and _gs.player_lives <= 0:
		_trigger_over()

func _refresh_ability_slots() -> void:
	if _player == null or not _player.has_method(&"get_ability_hud_slots"):
		return
	var slots: Array = _player.call(&"get_ability_hud_slots")
	for index in mini(slots.size(), _ability_slots.size()):
		_ability_slots[index].configure(slots[index])

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
