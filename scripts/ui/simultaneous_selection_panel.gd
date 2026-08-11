class_name SimultaneousSelectionPanel
extends Control
## Selecao conjunta de piloto e casco. Os paineis legados continuam independentes
## para consumidores que ainda dependem de seus sinais e caminhos de nos.

signal selection_changed(ship_id: StringName, character_id: StringName)
signal continue_requested(ship_id: StringName, character_id: StringName)
signal back_requested()

const STAT_IDS: Array[StringName] = [&"max_health", &"max_speed", &"acceleration", &"fire_rate", &"damage", &"aim_tier"]
const STAT_LABELS := ["VIDA", "VELOCIDADE", "ACELERACAO", "CADENCIA", "DANO", "MIRA"]
const PLAYABLE_SHIP_IDS: Array[StringName] = [&"nave_interceptadora", &"nave_engenheira", &"nave_rastreadora", &"nave_bruta", &"nave_interestelar"]
const STAT_SEGMENT_COUNT := 4

@onready var _character_art: TextureRect = $CharacterCarousel/ArtClip/CharacterArt
@onready var _character_previous_art: TextureRect = $CharacterCarousel/ArtClip/PreviousArt
@onready var _character_next_art: TextureRect = $CharacterCarousel/ArtClip/NextArt
@onready var _character_name: Label = $CharacterCarousel/CharacterName
@onready var _character_previous: Label = $CharacterCarousel/Previous
@onready var _character_next: Label = $CharacterCarousel/Next
@onready var _ship_preview: TextureRect = $ShipCarousel/PreviewClip/ShipPreview
@onready var _ship_energy_fx: SelectionShipEnergyFx = $ShipCarousel/PreviewClip/ShipEnergyFx
@onready var _ship_ring: HBoxContainer = $ShipCarousel/ShipRing
@onready var _ship_name: Label = $ShipCarousel/ShipName
@onready var _combination: Label = $Header/Combination
@onready var _stats: VBoxContainer = $StatsPanel/Stats
@onready var _character_ability: Label = $AbilitySlots/CharacterAbility
@onready var _ship_ability: Label = $AbilitySlots/ShipAbility
@onready var _character_up: Button = $CharacterCarousel/Up
@onready var _character_down: Button = $CharacterCarousel/Down
@onready var _ship_left: Button = $ShipCarousel/Left
@onready var _ship_right: Button = $ShipCarousel/Right
@onready var _confirm: Button = $Actions/Confirm
@onready var _back: Button = $Actions/Back

var _roster: Array[CharacterDef] = []
var _ships: Array[ShipDef] = []
var _character_index := 0
var _ship_index := 0
var _ranges: Dictionary = {}
var _alpha_bounds_cache: Dictionary = {}
var _ship_ring_entries: Array[Dictionary] = []
var _emitted := false
var _mouse_navigation_target: Button

func _ready() -> void:
	_roster = CharacterDef.get_roster()
	_ships = _playable_ships()
	# As artes cobrem os botoes laterais no recorte do carrossel. Elas sao
	# estritamente decorativas e nao podem se tornar o alvo do mouse.
	($CharacterCarousel/ArtClip as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	_character_previous_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_character_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_character_next_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ship_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_character_up.pressed.connect(func() -> void: _step_character(-1))
	_character_down.pressed.connect(func() -> void: _step_character(1))
	_ship_left.pressed.connect(func() -> void: _step_ship(-1))
	_ship_right.pressed.connect(func() -> void: _step_ship(1))
	_confirm.pressed.connect(_confirm_selection)
	_back.pressed.connect(func() -> void: back_requested.emit())
	_rebuild_ranges()
	_refresh()

func selected_character_id() -> StringName:
	return _roster[_character_index].id if not _roster.is_empty() else &""

func selected_ship_id() -> StringName:
	return _ships[_ship_index].id if not _ships.is_empty() else &""

func set_selected_character_id(id: StringName) -> bool:
	var index := _character_index_for(id)
	if index < 0:
		return false
	_character_index = index
	_refresh()
	return true

func set_selected_ship_id(id: StringName) -> bool:
	var index := _ship_index_for(id)
	if index < 0:
		return false
	_ship_index = index
	_refresh()
	return true

func set_selected_ids(ship_id: StringName, character_id: StringName) -> bool:
	var ship_index := _ship_index_for(ship_id)
	var character_index := _character_index_for(character_id)
	if ship_index < 0 or character_index < 0:
		return false
	_ship_index = ship_index
	_character_index = character_index
	_refresh()
	return true

func grab_initial_focus() -> void:
	# O painel, e nao um Button, recebe o foco inicial: assim o D-pad chega ao
	# caminho de entrada da selecao em vez de ser consumido pela navegacao GUI.
	grab_focus()

func reset() -> void:
	_emitted = false
	_character_index = 0
	_ship_index = 0
	_refresh()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and _handle_navigation_mouse(event):
		return
	_handle_navigation_input(event)

func _unhandled_input(event: InputEvent) -> void:
	_handle_navigation_input(event)

func _handle_navigation_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event.is_pressed() or event.is_echo():
		return
	if event is InputEventJoypadButton:
		match event.button_index:
			JOY_BUTTON_DPAD_UP:
				_step_character(-1)
			JOY_BUTTON_DPAD_DOWN:
				_step_character(1)
			JOY_BUTTON_DPAD_LEFT:
				_step_ship(-1)
			JOY_BUTTON_DPAD_RIGHT:
				_step_ship(1)
			JOY_BUTTON_A:
				_confirm_selection()
			_:
				return
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_cancel"):
		back_requested.emit()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey:
		if event.keycode == KEY_E or event.keycode == KEY_S:
			_step_character(1)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_W:
			_step_character(-1)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_Q or event.keycode == KEY_A:
			_step_ship(-1)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_D:
			_step_ship(1)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_confirm_selection()
			get_viewport().set_input_as_handled()

func _handle_navigation_mouse(event: InputEventMouseButton) -> bool:
	if event.button_index != MOUSE_BUTTON_LEFT:
		return false
	if event.is_pressed():
		for button in [_character_up, _character_down, _ship_left, _ship_right]:
			if button.get_global_rect().has_point(event.position):
				_mouse_navigation_target = button
				get_viewport().set_input_as_handled()
				return true
		return false
	if _mouse_navigation_target == null:
		return false
	var target := _mouse_navigation_target
	_mouse_navigation_target = null
	if target.get_global_rect().has_point(event.position):
		if target == _character_up:
			_step_character(-1)
		elif target == _character_down:
			_step_character(1)
		elif target == _ship_left:
			_step_ship(-1)
		else:
			_step_ship(1)
	get_viewport().set_input_as_handled()
	return true

func _step_character(delta: int) -> void:
	if _roster.is_empty():
		return
	var next_index := posmod(_character_index + delta, _roster.size())
	if next_index == _character_index:
		return
	_character_index = next_index
	_refresh(true)

func _step_ship(delta: int) -> void:
	if _ships.is_empty():
		return
	var next_index := posmod(_ship_index + delta, _ships.size())
	if next_index == _ship_index:
		return
	_ship_index = next_index
	_refresh(true)

func _refresh(emit_selection_changed := false) -> void:
	if not is_node_ready():
		return
	var valid := not _roster.is_empty() and not _ships.is_empty()
	_confirm.disabled = not valid
	if not valid:
		return
	var character := _roster[_character_index]
	var ship := _ships[_ship_index]
	_refresh_character_carousel()
	_character_name.text = _display_name(character)
	_character_previous.text = "\u25B2  %s" % _display_name(_roster[posmod(_character_index - 1, _roster.size())])
	_character_next.text = "\u25BC  %s" % _display_name(_roster[posmod(_character_index + 1, _roster.size())])
	_ship_name.text = _display_name(ship)
	_combination.text = "%s  +  %s" % [_display_name(character).to_upper(), _display_name(ship).to_upper()]
	_apply_ship_frame(ship, character.thrust_color)
	_character_ability.text = "E  %s" % _ability_name(character.ability_e)
	_ship_ability.text = "Q  %s" % _ability_name(ship.ability_q)
	_refresh_ship_ring()
	_refresh_stats(ship, character)
	if emit_selection_changed:
		selection_changed.emit(ship.id, character.id)

func _refresh_character_carousel() -> void:
	# Os tres cartoes sao atualizados juntos para que o trilho nunca exiba
	# referencias defasadas. Com o elenco atual de tres pilotos, cada um ocupa
	# exatamente um slot; posmod tambem preserva o ciclo para elencos futuros.
	var previous := _roster[posmod(_character_index - 1, _roster.size())]
	var selected := _roster[_character_index]
	var next := _roster[posmod(_character_index + 1, _roster.size())]
	_character_previous_art.texture = _character_texture(previous)
	_character_art.texture = _character_texture(selected)
	_character_next_art.texture = _character_texture(next)

func _character_texture(character: CharacterDef) -> Texture2D:
	return character.splash_art if character.splash_art != null else character.portrait

func _character_index_for(id: StringName) -> int:
	for index in _roster.size():
		if _roster[index].id == id:
			return index
	return -1

func _ship_index_for(id: StringName) -> int:
	for index in _ships.size():
		if _ships[index].id == id:
			return index
	return -1

func _apply_ship_frame(ship: ShipDef, accent: Color) -> void:
	if ship.hull_texture == null:
		_ship_preview.texture = null
		return
	_apply_ship_preview(_ship_preview, ship, Rect2(Vector2.ZERO, _ship_preview.get_parent_control().size))
	_ship_preview.material = null
	_ship_energy_fx.set_frame(accent, ship.visual_rotation_offset)

func _playable_ships() -> Array[ShipDef]:
	var playable: Array[ShipDef] = []
	for ship_id in PLAYABLE_SHIP_IDS:
		var ship := ShipCatalog.get_ship(ship_id)
		if ship != null:
			playable.append(ship)
	return playable

func _preview_region(ship: ShipDef) -> Rect2:
	if ship.hull_texture == null:
		return Rect2()
	var bounds := Rect2(Vector2.ZERO, ship.hull_texture.get_size())
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return Rect2()
	if not ship.custom_frame_regions.is_empty():
		var custom_region := ship.custom_frame_regions[min(2, ship.custom_frame_regions.size() - 1)].intersection(bounds)
		if custom_region.size.x > 0.0 and custom_region.size.y > 0.0:
			return custom_region
	var cell := Vector2(ship.frame_size)
	if cell.x <= 0.0 or cell.y <= 0.0:
		return bounds
	var frame_count: int = max(1, ship.atlas_grid_size.x)
	var frame := Vector2i(min(2, frame_count - 1), 0)
	var region := Rect2(Vector2(frame) * cell, cell).intersection(bounds)
	if region.size.x > 0.0 and region.size.y > 0.0:
		return region
	# A configuracao do atlas pode declarar mais frames que a textura contem.
	# Neste caso, o primeiro frame valido e a melhor pre-visualizacao segura.
	return Rect2(Vector2.ZERO, cell).intersection(bounds)

func _apply_ship_preview(preview: TextureRect, ship: ShipDef, target: Rect2) -> void:
	var region := _preview_region(ship)
	if region.size.x <= 0.0 or region.size.y <= 0.0:
		preview.texture = null
		return
	var visible_region := _visible_region(ship.hull_texture, region)
	var atlas := AtlasTexture.new()
	atlas.atlas = ship.hull_texture
	# Mantem o frame/region do atlas intacto; os limites alpha so orientam o fit.
	atlas.region = region
	preview.texture = atlas
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var scale := _preview_fit_scale(visible_region.size, target.size, ship.visual_rotation_offset)
	preview.size = region.size * scale
	preview.pivot_offset = preview.size * 0.5
	var alpha_center := visible_region.get_center() - region.position
	var alpha_offset := (alpha_center - region.size * 0.5) * scale
	preview.position = target.get_center() - preview.pivot_offset - alpha_offset.rotated(ship.visual_rotation_offset)
	# Centralizar e redimensionar um Control atualiza seu transform. A rotacao
	# precisa ser o ultimo passo para nunca herdar um reset do fit/layout.
	preview.rotation = ship.visual_rotation_offset

func _visible_region(texture: Texture2D, region: Rect2) -> Rect2:
	var key := "%s:%s:%s:%s:%s" % [texture.get_instance_id(), region.position.x, region.position.y, region.size.x, region.size.y]
	if _alpha_bounds_cache.has(key):
		return _alpha_bounds_cache[key]
	var image := texture.get_image()
	if image == null:
		_alpha_bounds_cache[key] = region
		return region
	var min_x := ceili(region.end.x)
	var min_y := ceili(region.end.y)
	var max_x := floori(region.position.x) - 1
	var max_y := floori(region.position.y) - 1
	for y in range(floori(region.position.y), ceili(region.end.y)):
		for x in range(floori(region.position.x), ceili(region.end.x)):
			if image.get_pixel(x, y).a > 0.0:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	var visible := Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x + 1, max_y - min_y + 1)) if max_x >= min_x and max_y >= min_y else region
	_alpha_bounds_cache[key] = visible
	return visible

func _preview_fit_scale(content_size: Vector2, target_size: Vector2, rotation: float) -> float:
	if content_size.x <= 0.0 or content_size.y <= 0.0 or target_size.x <= 0.0 or target_size.y <= 0.0:
		return 1.0
	var cosine := absf(cos(rotation))
	var sine := absf(sin(rotation))
	var rotated_size := Vector2(cosine * content_size.x + sine * content_size.y, sine * content_size.x + cosine * content_size.y)
	return 0.8 * minf(target_size.x / rotated_size.x, target_size.y / rotated_size.y)

func _refresh_ship_ring() -> void:
	for child in _ship_ring.get_children():
		child.queue_free()
	_ship_ring_entries.clear()
	if _ships.is_empty():
		return
	# Cinco cascos do catalogo orbitam a nave selecionada; com seis entradas,
	# a sexta entra na proxima rotacao sem deixar de ser selecionavel.
	for offset in [-2, -1, 0, 1, 2]:
		var ship := _ships[posmod(_ship_index + offset, _ships.size())]
		var slot := Control.new()
		slot.custom_minimum_size = Vector2(19, 17) if offset != 0 else Vector2(27, 22)
		var icon := TextureRect.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.modulate = Color.WHITE if offset == 0 else Color(0.46, 0.57, 0.7, 0.72)
		slot.add_child(icon)
		_ship_ring.add_child(slot)
		_ship_ring_entries.append({"preview": icon, "slot": slot, "ship": ship})
	call_deferred("_layout_ship_ring_previews")

func _layout_ship_ring_previews() -> void:
	for entry in _ship_ring_entries:
		var preview: TextureRect = entry["preview"]
		var slot: Control = entry["slot"]
		var ship: ShipDef = entry["ship"]
		if is_instance_valid(preview) and is_instance_valid(slot) and ship.hull_texture != null:
			_apply_ship_preview(preview, ship, Rect2(Vector2.ZERO, slot.size))

func _refresh_stats(ship: ShipDef, character: CharacterDef) -> void:
	for child in _stats.get_children():
		child.queue_free()
	var stats := StatBlock.new(StatCatalog.get_all())
	Loadout.apply(stats, ship, character)
	var active_modifiers := stats.get_active_modifiers()
	for index in STAT_IDS.size():
		var stat_id := STAT_IDS[index]
		var row := VBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 18)
		row.add_theme_constant_override(&"separation", 1)
		var label := Label.new()
		label.text = STAT_LABELS[index]
		label.add_theme_font_size_override(&"font_size", 8)
		row.add_child(label)
		var segments := HBoxContainer.new()
		segments.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		segments.add_theme_constant_override(&"separation", 4)
		var value := stats.get_stat(stat_id)
		var fill := _stat_score(stat_id, value, _has_stat_presence(ship, active_modifiers, stat_id))
		for segment_index in STAT_SEGMENT_COUNT:
			var segment := ColorRect.new()
			segment.custom_minimum_size = Vector2(14, 8)
			segment.color = Color("69f6d9") if segment_index < fill else Color("203044")
			segments.add_child(segment)
		row.add_child(segments)
		_stats.add_child(row)

func _rebuild_ranges() -> void:
	_ranges.clear()
	for stat_id in STAT_IDS:
		var default_base := StatCatalog.get_stat(stat_id).default_base
		_ranges[stat_id] = {"min": default_base, "max": default_base}
	for ship in _ships:
		for character in _roster:
			var stats := StatBlock.new(StatCatalog.get_all())
			Loadout.apply(stats, ship, character)
			for stat_id in STAT_IDS:
				var range: Dictionary = _ranges[stat_id]
				var value := stats.get_stat(stat_id)
				range["min"] = minf(float(range["min"]), value)
				range["max"] = maxf(float(range["max"]), value)

func _normalized(stat_id: StringName, value: float) -> float:
	var range: Dictionary = _ranges.get(stat_id, {})
	if range.is_empty() or is_equal_approx(float(range["max"]), float(range["min"])):
		return 1.0
	return clampf((value - float(range["min"])) / (float(range["max"]) - float(range["min"])), 0.0, 1.0)

func _has_stat_presence(ship: ShipDef, active_modifiers: Array[StatModifierDef], stat_id: StringName) -> bool:
	if ship != null:
		for base_stat in ship.base_stats:
			if base_stat != null and base_stat.stat == stat_id:
				return true
	return _has_active_stat_modifier(active_modifiers, stat_id)

func _has_active_stat_modifier(active_modifiers: Array[StatModifierDef], stat_id: StringName) -> bool:
	for modifier in active_modifiers:
		if modifier != null and modifier.stat == stat_id:
			return true
	return false

func _stat_score(stat_id: StringName, value: float, is_present: bool) -> int:
	if not is_present:
		return 0
	var range: Dictionary = _ranges.get(stat_id, {})
	if range.is_empty() or is_equal_approx(float(range["max"]), float(range["min"])):
		return 1
	var normalized := clampf((value - float(range["min"])) / (float(range["max"]) - float(range["min"])), 0.0, 1.0)
	return clampi(1 + roundi(3.0 * normalized), 1, STAT_SEGMENT_COUNT)

func _confirm_selection() -> void:
	if _emitted or selected_ship_id().is_empty() or selected_character_id().is_empty():
		return
	_emitted = true
	continue_requested.emit(selected_ship_id(), selected_character_id())

func _display_name(definition: Resource) -> String:
	var value: String = definition.get("display_name")
	var id: StringName = definition.get("id")
	return value if not value.is_empty() else String(id)

func _ability_name(ability_id: StringName) -> String:
	if ability_id.is_empty():
		return "SEM HABILIDADE"
	var ability := AbilityCatalog.get_ability(ability_id)
	return ability.display_name if ability != null and not ability.display_name.is_empty() else String(ability_id)
