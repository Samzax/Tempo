class_name Inventory
extends RefCounted
## Mantem os itens adquiridos e suas instancias de execucao.

var _stats: StatBlock
var _dispatcher: EffectDispatcher
var _stacks: Dictionary = {}
var _instances: Array = []
var _next_instance: int = 0

func _init(stats: StatBlock, dispatcher: EffectDispatcher) -> void:
	_stats = stats
	_dispatcher = dispatcher

## Adquire uma instancia do item, respeitando seu limite de acumulacao.
func acquire(item: ItemDef) -> bool:
	if item == null or item.id.is_empty():
		push_error("Nao e possivel adquirir um item nulo ou sem id.")
		return false

	var current: int = _stacks.get(item.id, 0)
	if current >= item.max_stacks:
		return false

	var source_id: StringName = "%s#%d" % [item.id, _next_instance]
	_next_instance += 1
	for modifier in item.get_runtime_modifiers():
		modifier.source_id = source_id
		_stats.add_modifier(modifier)

	var clones: Array[EffectDef] = []
	for effect in item.effects:
		if effect != null:
			clones.append(effect.duplicate() as EffectDef)
	_dispatcher.add_effects(clones)

	_instances.append({"item_id": item.id, "source_id": source_id, "effects": clones})
	_stacks[item.id] = current + 1
	_dispatcher.dispatch(&"on_pickup", null, 0)
	return true

## Remove a ultima instancia adquirida do item informado.
func remove_one(item_id: StringName) -> bool:
	for index in range(_instances.size() - 1, -1, -1):
		var record: Dictionary = _instances[index]
		if record["item_id"] != item_id:
			continue
		var source_id: StringName = record["source_id"]
		var effects: Array[EffectDef] = record["effects"]
		_stats.remove_modifiers_by_source(source_id)
		_dispatcher.remove_effects(effects)
		_instances.remove_at(index)
		_stacks[item_id] = _stacks[item_id] - 1
		if _stacks[item_id] == 0:
			_stacks.erase(item_id)
		return true
	return false

## Devolve quantas instancias do item estao no inventario.
func count(item_id: StringName) -> int:
	return _stacks.get(item_id, 0)

## Devolve os ids dos itens presentes no inventario.
func get_item_ids() -> Array[StringName]:
	var item_ids: Array[StringName] = []
	for item_id in _stacks:
		item_ids.append(item_id)
	return item_ids
