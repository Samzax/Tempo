class_name StatBlock
extends RefCounted
## Mantém os valores base, modificadores ativos e cache de um ator.

class ActiveModifier extends RefCounted:
	var def: StatModifierDef
	var time_left: float

	func _init(definition: StatModifierDef) -> void:
		def = definition
		time_left = definition.duration

var _definitions: Dictionary = {}
var _base_values: Dictionary = {}
var _modifiers: Array[ActiveModifier] = []
var _cache: Dictionary = {}
var _dirty: Dictionary = {}

func _init(definitions: Array[StatDef]) -> void:
	for definition in definitions:
		_definitions[definition.id] = definition
		_base_values[definition.id] = definition.default_base
		_cache[definition.id] = definition.default_base
		_dirty[definition.id] = true

## Devolve os ids de todas as estatísticas do catálogo.
func get_stat_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for id in _definitions:
		ids.append(id)
	return ids

## Devolve os modificadores ativos, para inspeção e UI.
func get_active_modifiers() -> Array[StatModifierDef]:
	var modifiers: Array[StatModifierDef] = []
	for active in _modifiers:
		modifiers.append(active.def)
	return modifiers

## Devolve o valor atual da estatística, resolvendo-o apenas se estiver sujo.
func get_stat(id: StringName) -> float:
	if not _definitions.has(id):
		push_error("Estatística desconhecida: %s" % id)
		return 0.0
	if _dirty[id]:
		_cache[id] = _resolve_stat(id)
		_dirty[id] = false
	return _cache[id]

## Devolve uma estatística inteira como inteiro.
func get_stat_int(id: StringName) -> int:
	return roundi(get_stat(id))

## Define o valor base de uma estatística deste ator.
func set_base(id: StringName, value: float) -> void:
	if not _definitions.has(id):
		push_error("Estatística desconhecida: %s" % id)
		return
	_base_values[id] = value
	_dirty[id] = true

## Adiciona um modificador permitido e marca apenas sua estatística como suja.
func add_modifier(def: StatModifierDef) -> void:
	if def == null:
		push_error("Não é possível adicionar um modificador nulo.")
		return
	if not _definitions.has(def.stat):
		push_error("Estatística desconhecida no modificador: %s" % def.stat)
		return
	if def.source_id.is_empty():
		push_error("Não é possível adicionar um modificador sem origem.")
		return
	var definition: StatDef = _definitions[def.stat]
	if not definition.allowed_ops.has(def.op):
		push_error("Operação não permitida para a estatística: %s" % def.stat)
		return
	_modifiers.append(ActiveModifier.new(def))
	_dirty[def.stat] = true

## Remove todos os modificadores pertencentes a uma origem.
func remove_modifiers_by_source(source_id: StringName) -> void:
	var affected_stats: Dictionary = {}
	for index in range(_modifiers.size() - 1, -1, -1):
		var active := _modifiers[index]
		if active.def.source_id == source_id:
			affected_stats[active.def.stat] = true
			_modifiers.remove_at(index)
	for id in affected_stats:
		_dirty[id] = true

## Avança modificadores temporários e remove somente os que expiraram.
func tick(delta: float) -> void:
	var affected_stats: Dictionary = {}
	for index in range(_modifiers.size() - 1, -1, -1):
		var active := _modifiers[index]
		if active.def.duration < 0.0:
			continue
		active.time_left -= delta
		if active.time_left <= 0.0:
			affected_stats[active.def.stat] = true
			_modifiers.remove_at(index)
	for id in affected_stats:
		_dirty[id] = true

func _resolve_stat(id: StringName) -> float:
	var definition: StatDef = _definitions[id]
	var override_modifier: ActiveModifier = null
	var flat_sum := 0.0
	var add_pct_sum := 0.0
	var mult_product := 1.0

	for active in _modifiers:
		if active.def.stat != id:
			continue
		match active.def.op:
			StatDef.Op.FLAT:
				flat_sum += active.def.value
			StatDef.Op.ADD_PCT:
				add_pct_sum += active.def.value
			StatDef.Op.MULT:
				mult_product *= maxf(0.0, 1.0 + active.def.value)
			StatDef.Op.OVERRIDE:
				if override_modifier == null or active.def.priority >= override_modifier.def.priority:
					override_modifier = active

	var final_value: float = override_modifier.def.value if override_modifier != null else (_base_values[id] + flat_sum) * maxf(0.0, 1.0 + add_pct_sum) * mult_product
	final_value = clampf(final_value, definition.default_min, definition.default_max)
	if definition.is_integer:
		final_value = float(roundi(final_value))
	return final_value
