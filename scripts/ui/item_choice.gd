class_name ItemChoice
extends Control
## Painel compacto de uma escolha; nao pausa a arvore para preservar o combate.

signal offer_resolved(offer: RewardOffer, refused: bool)

var _offer: RewardOffer
var _player: Node
var _buttons: Array[Button] = []
var _title: Label
var _choosing := false
var _refreshing := false
var _refresh_pending := false
var _refresh_deferred_queued := false
var _ui_generation := 0
var _rebuild_deferred_queued := false
var _rebuild_offer: RewardOffer
var _rebuild_generation := -1
var _terminal_invalidated_generation := -1
var _can_refuse := false

func _enter_tree() -> void:
	_ensure_echoes_connection()

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	hide()

func _exit_tree() -> void:
	if GameState.temporal_echoes_changed.is_connected(_on_temporal_echoes_changed):
		GameState.temporal_echoes_changed.disconnect(_on_temporal_echoes_changed)

func open_offer(offer: RewardOffer, player: Node, allow_refuse: bool = false) -> void:
	if _choosing or _refreshing:
		return
	_offer = offer
	_player = player
	_can_refuse = allow_refuse
	_terminal_invalidated_generation = -1
	_ensure_echoes_connection()
	show()
	_build()

func _build(allow_rebuild: bool = true, fail_closed: bool = false) -> void:
	_ui_generation += 1
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
	if _can_refuse:
		var refuse := Button.new()
		refuse.text = "RECUSAR"
		refuse.pressed.connect(_refuse)
		panel.add_child(refuse)
	if fail_closed:
		_terminal_invalidated_generation = _ui_generation
		for button in _buttons:
			button.disabled = true
		return
	_refresh(true, allow_rebuild)

func _is_live_object(value: Variant) -> bool:
	if typeof(value) != TYPE_OBJECT:
		return false
	if not is_instance_valid(value):
		return false
	if value is Node and value.is_queued_for_deletion():
		return false
	return true

func _is_valid_ui_node(node: Variant) -> bool:
	if not _is_live_object(node) or not node is Node:
		return false
	var ui_node: Node = node
	return ui_node.is_inside_tree() and is_ancestor_of(ui_node)

func _is_valid_button(candidate_button: Variant, index: int, generation: int) -> bool:
	if generation != _ui_generation or index < 0 or index >= _buttons.size():
		return false
	if not _is_live_object(candidate_button) or not candidate_button is Button:
		return false
	var current_button: Variant = _buttons[index]
	if not _is_live_object(current_button) or not current_button is Button:
		return false
	if current_button != candidate_button:
		return false
	return _is_valid_ui_node(candidate_button)

func _is_valid_title(candidate_title: Variant, generation: int) -> bool:
	if generation != _ui_generation or not _is_live_object(candidate_title) or not candidate_title is Label:
		return false
	var current_title: Variant = _title
	if not _is_live_object(current_title) or not current_title is Label:
		return false
	if current_title != candidate_title:
		return false
	return _is_valid_ui_node(candidate_title)

func _refresh(allow_followup: bool = true, allow_rebuild: bool = true) -> void:
	if _refreshing:
		_refresh_pending = true
		return
	if not _is_live_object(_offer) or not _is_live_object(_title):
		return
	_refreshing = true
	_refresh_pending = false
	var snap_offer: Variant = _offer
	var snap_player: Variant = _player
	var snap_generation := _ui_generation
	var snap_claimed: bool = snap_offer.claimed
	var snap_paid: bool = snap_offer.paid_with_temporal_echoes
	var snap_echoes := GameState.temporal_echoes
	var snap_options: Variant = snap_offer.options.duplicate()
	var snap_costs: Variant = snap_offer.option_costs.duplicate()
	var snap_buttons: Variant = _buttons.duplicate()
	var snap_title: Variant = _title
	var paid_metadata_valid: bool = snap_paid and snap_costs.size() == snap_options.size()
	if paid_metadata_valid:
		for cost in snap_costs:
			if cost <= 0:
				paid_metadata_valid = false
				break
	var rows: Array[Dictionary] = []
	for index in snap_buttons.size():
		var item: Variant = snap_options[index] if index < snap_options.size() else null
		var display_name := "ITEM INVÁLIDO"
		var description := ""
		if _is_live_object(item):
			display_name = item.display_name
			description = item.description
		rows.append({"index": index, "item": item, "display_name": display_name, "description": description, "cost": snap_costs[index] if index < snap_costs.size() else 0})
	var needs_rebuild := false
	var ui_invalidated := false
	var player_invalidated := not _is_live_object(snap_player)
	if not _is_valid_title(snap_title, snap_generation):
		needs_rebuild = true
		ui_invalidated = true
	elif snap_claimed:
		snap_title.text = "RECOMPENSA COLETADA"
	elif snap_paid:
		snap_title.text = "ESCOLHA UMA MELHORIA  —  ECOS: %d" % snap_echoes
	else:
		snap_title.text = "ESCOLHA UMA MELHORIA"
	if not needs_rebuild and not player_invalidated:
		for row in rows:
			var index: int = row.index
			var button: Variant = snap_buttons[index]
			var item: Variant = row.item
			if not _is_live_object(snap_offer) or _offer != snap_offer:
				needs_rebuild = true
				break
			if not _is_valid_title(snap_title, snap_generation) or not _is_valid_button(button, index, snap_generation):
				needs_rebuild = true
				ui_invalidated = true
				break
			if not _is_live_object(snap_player):
				player_invalidated = true
				break
			if _player != snap_player:
				needs_rebuild = true
				break
			if index >= snap_options.size():
				(button as Button).disabled = true
				(button as Button).text = "%d. ITEM INVÁLIDO  (INDISPONÍVEL)" % [index + 1]
				continue
			if item == null:
				(button as Button).disabled = true
				(button as Button).text = "%d. ITEM INVÁLIDO  (INDISPONÍVEL)" % [index + 1]
				continue
			if not _is_live_object(item):
				needs_rebuild = true
				break
			var available := false
			var suffix := ""
			if snap_paid and not paid_metadata_valid:
				suffix = "  (INDISPONÍVEL)"
			elif not snap_claimed:
				available = snap_player.can_acquire_item(item)
				if not _is_live_object(snap_player):
					player_invalidated = true
					break
				var title_valid_after := _is_valid_title(snap_title, snap_generation)
				var button_valid_after := _is_valid_button(button, index, snap_generation)
				if not title_valid_after or not button_valid_after:
					ui_invalidated = true
					_terminal_invalidated_generation = snap_generation
				if not _is_live_object(snap_offer) or _offer != snap_offer or not _is_live_object(item) or not title_valid_after or not button_valid_after or _player != snap_player:
					needs_rebuild = true
					break
				if snap_paid:
					if not available:
						suffix = "  (%d ECOS — LIMITE ATINGIDO)" % row.cost
					elif snap_echoes < row.cost:
						available = false
						suffix = "  (%d ECOS — ECOS INSUFICIENTES)" % row.cost
					else:
						suffix = "  (%d ECOS)" % row.cost
			elif snap_paid:
				suffix = "  (%d ECOS — LIMITE ATINGIDO)" % row.cost
			elif not available:
				suffix = "  (LIMITE ATINGIDO)"
			(button as Button).disabled = not available
			(button as Button).text = "%d. %s\n%s%s" % [index + 1, row.display_name, row.description, suffix]
	if player_invalidated:
		if not _is_live_object(_player):
			_player = null
		for row in rows:
			var button: Variant = snap_buttons[row.index]
			if _is_valid_button(button, row.index, snap_generation):
				(button as Button).disabled = true
				(button as Button).text = "%d. %s\n%s  (INDISPONÍVEL)" % [row.index + 1, row.display_name, row.description]
	var state_mutated := false
	if _is_live_object(snap_offer):
		state_mutated = _offer != snap_offer or _player != snap_player or (snap_offer.claimed != snap_claimed or snap_offer.paid_with_temporal_echoes != snap_paid or snap_offer.options != snap_options or snap_offer.option_costs != snap_costs) or GameState.temporal_echoes != snap_echoes
	else:
		needs_rebuild = true
	_refreshing = false
	if needs_rebuild and allow_rebuild and not player_invalidated:
		_refresh_pending = false
		if ui_invalidated:
			_terminal_invalidated_generation = snap_generation
		_queue_deferred_rebuild(snap_offer, snap_generation)
	elif allow_followup and (_refresh_pending or state_mutated):
		_refresh_pending = false
		_queue_deferred_refresh()
	elif not allow_followup:
		_refresh_pending = false

func _queue_deferred_refresh() -> void:
	if _refresh_deferred_queued or not is_inside_tree() or not _is_live_object(_offer) or not visible:
		return
	_refresh_deferred_queued = true
	call_deferred(&"_run_deferred_refresh")

func _run_deferred_refresh() -> void:
	_refresh_deferred_queued = false
	if not is_inside_tree() or not _is_live_object(_offer) or not visible or _offer.claimed or _choosing or _refreshing:
		_refresh_pending = false
		return
	_refresh(false, true)

func _queue_deferred_rebuild(offer: Variant, generation: int) -> void:
	if _rebuild_deferred_queued or not is_inside_tree() or not _is_live_object(offer) or not visible:
		return
	_rebuild_deferred_queued = true
	_rebuild_offer = offer
	_rebuild_generation = generation
	call_deferred(&"_run_deferred_rebuild")

func _run_deferred_rebuild() -> void:
	var target_offer: Variant = _rebuild_offer
	var target_generation := _rebuild_generation
	_rebuild_deferred_queued = false
	_rebuild_offer = null
	_rebuild_generation = -1
	if not is_inside_tree() or not visible or _choosing or _refreshing or not _is_live_object(target_offer) or _offer != target_offer or _ui_generation != target_generation or target_offer.claimed:
		return
	if not _is_live_object(_player):
		_player = null
		return
	_build(false, _terminal_invalidated_generation == target_generation)

func _choose(index: int) -> void:
	if _choosing or _refreshing or _terminal_invalidated_generation == _ui_generation or not _is_live_object(_offer) or _offer.claimed or index < 0 or index >= _offer.options.size() or index >= _buttons.size():
		return
	var choice_generation: Variant = _ui_generation
	var choice_button: Variant = _buttons[index]
	var choice_title: Variant = _title
	var offer: Variant = _offer
	if not _is_valid_button(choice_button, index, choice_generation) or not _is_valid_title(choice_title, choice_generation):
		_terminalize_choice_generation(offer, choice_generation)
		return
	_choosing = true
	var item: Variant = offer.options[index]
	if not _is_live_object(item):
		_refresh()
		_choosing = false
		return
	var captured_item_id: String = item.id
	var player: Variant = _player
	var is_paid: bool = offer.paid_with_temporal_echoes
	var cost := 0
	var plan_valid := true
	if is_paid:
		plan_valid = _has_valid_paid_metadata(offer)
		if plan_valid:
			cost = offer.option_costs[index]
	var acquired := _try_choose(offer, item, player, is_paid, cost, plan_valid, index, choice_generation, choice_button, choice_title)
	if acquired:
		offer.claimed = true
		offer.claimed_item_id = captured_item_id
		hide()
		offer_resolved.emit(offer, false)
	elif _terminal_invalidated_generation != choice_generation:
		_refresh()
	_choosing = false

func _try_choose(offer: Variant, item: Variant, player: Variant, is_paid: bool, cost: int, plan_valid: bool, index: int, generation: Variant, button: Variant, title: Variant) -> bool:
	if not plan_valid or not _is_live_object(offer) or not _is_live_object(item) or not _is_live_object(player) or _offer != offer or _player != player or offer.claimed:
		return false
	var available: bool = bool(player.can_acquire_item(item))
	if not _is_valid_button(button, index, generation) or not _is_valid_title(title, generation):
		_terminalize_choice_generation(offer, generation)
		return false
	if not _is_live_object(offer) or not _is_live_object(item) or not _is_live_object(player) or _offer != offer or _player != player or offer.claimed or index < 0 or index >= offer.options.size() or offer.options[index] != item:
		if not _is_live_object(player) and not _is_live_object(_player):
			_player = null
		return false
	if not available:
		return false
	if is_paid:
		if not player.has_method(&"buy_item"):
			return false
		if not GameState.has_temporal_echoes(cost):
			return false
		return player.buy_item(item, cost)
	return player.acquire_item(item)

func _terminalize_choice_generation(offer: Variant, generation: Variant) -> void:
	_terminal_invalidated_generation = generation
	_queue_deferred_rebuild(offer, generation)

func _has_valid_paid_metadata(offer: Variant) -> bool:
	if not _is_live_object(offer) or offer.option_costs.size() != offer.options.size():
		return false
	for cost in offer.option_costs:
		if cost <= 0:
			return false
	return true

func _refuse() -> void:
	if not _can_refuse or _choosing or _refreshing or not _is_live_object(_offer) or _offer.claimed:
		return
	_choosing = true
	var offer := _offer
	offer.claimed = true
	offer.claimed_item_id = &""
	hide()
	_choosing = false
	offer_resolved.emit(offer, true)

func _ensure_echoes_connection() -> void:
	if not GameState.temporal_echoes_changed.is_connected(_on_temporal_echoes_changed):
		GameState.temporal_echoes_changed.connect(_on_temporal_echoes_changed)

func _on_temporal_echoes_changed(_amount: int, _total: int) -> void:
	if not visible:
		return
	if _refreshing:
		_refresh_pending = true
	elif not _choosing:
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
