class_name ItemChoice
extends Control
## Painel compacto de uma escolha; nao pausa a arvore para preservar o combate.

var _offer: RewardOffer
var _player: Node
var _buttons: Array[Button] = []
var _title: Label

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	hide()

func open_offer(offer: RewardOffer, player: Node) -> void:
	_offer = offer
	_player = player
	show()
	_build()

func _build() -> void:
	for child in get_children():
		child.queue_free()
	_buttons.clear()
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.02, 0.06, 0.86)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	var panel := VBoxContainer.new()
	panel.position = Vector2(42, 38)
	panel.size = Vector2(396, 194)
	panel.add_theme_constant_override("separation", 5)
	add_child(panel)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 16)
	_title.text = "ESCOLHA UMA MELHORIA"
	panel.add_child(_title)
	for index in _offer.options.size():
		var item := _offer.options[index]
		var button := Button.new()
		button.custom_minimum_size = Vector2(396, 42)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.add_theme_font_size_override("font_size", 11)
		button.pressed.connect(_choose.bind(index))
		panel.add_child(button)
		_buttons.append(button)
	var close := Button.new()
	close.text = "Fechar  [Esc]"
	close.pressed.connect(hide)
	panel.add_child(close)
	_refresh()

func _refresh() -> void:
	if _offer == null:
		return
	if _offer.claimed:
		_title.text = "RECOMPENSA COLETADA"
	for index in _buttons.size():
		var item := _offer.options[index]
		var available: bool = not _offer.claimed and _player != null and _player.can_acquire_item(item)
		_buttons[index].disabled = not available
		var suffix := "" if available else "  (LIMITE ATINGIDO)"
		_buttons[index].text = "%d. %s\n%s%s" % [index + 1, item.display_name, item.description, suffix]

func _choose(index: int) -> void:
	if _offer == null or _offer.claimed or index < 0 or index >= _offer.options.size():
		return
	var item := _offer.options[index]
	if _player == null or not _player.can_acquire_item(item):
		_refresh()
		return
	if _player.acquire_item(item):
		_offer.claimed = true
		_offer.claimed_item_id = item.id
		hide()
	else:
		_refresh()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel"):
		hide()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"loot_choice_1"):
		_choose(0)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"loot_choice_2"):
		_choose(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"loot_choice_3"):
		_choose(2)
		get_viewport().set_input_as_handled()
