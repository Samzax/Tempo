class_name Inventory
extends RefCounted
## Mantem os itens adquiridos e suas instancias de execucao.

## Marcador opaco de uma reserva de capacidade. O Inventory e o unico dono
## da associacao entre este objeto e o ItemDef reservado.
class ReservationToken extends RefCounted:
	pass

## Dados privados de uma reserva. O snapshot e o ID sao congelados no
## momento da reserva para que callbacks externos nao possam altera-los.
class ReservationRecord extends RefCounted:
	var item: ItemDef
	var item_id: StringName

	func _init(reserved_item: ItemDef, reserved_item_id: StringName) -> void:
		item = reserved_item
		item_id = reserved_item_id

var _stats: StatBlock
var _dispatcher: EffectDispatcher
var _stacks: Dictionary = {}
var _instances: Array = []
var _next_instance: int = 0
var _reservations: Dictionary = {}
var _reserved_stacks: Dictionary = {}

func _init(stats: StatBlock, dispatcher: EffectDispatcher) -> void:
	_stats = stats
	_dispatcher = dispatcher

## Adquire uma instancia do item, respeitando seu limite de acumulacao.
func acquire(item: ItemDef) -> bool:
	if not can_acquire(item):
		return false
	_guaranteed_acquire(item)
	return true

## Verifica conteudo e capacidade, incluindo vagas reservadas por compras pendentes.
func can_acquire(item: ItemDef) -> bool:
	if _stats == null or _dispatcher == null:
		return false
	if item == null or item.id.is_empty() or item.max_stacks <= 0:
		return false
	if not item.validate_content().is_empty():
		return false
	for modifier in item.modifiers:
		if not _stats.can_apply_modifier(modifier):
			return false
	var current: int = _stacks.get(item.id, 0)
	var reserved: int = _reserved_stacks.get(item.id, 0)
	return current + reserved < item.max_stacks

## Reserva exclusivamente uma vaga. Nenhum modificador, efeito ou evento e aplicado aqui.
func reserve(item: ItemDef) -> ReservationToken:
	if not can_acquire(item):
		return null
	var snapshot := item.duplicate(true) as ItemDef
	if snapshot == null or not can_acquire(snapshot):
		return null
	var token := ReservationToken.new()
	var record := ReservationRecord.new(snapshot, snapshot.id)
	_reservations[token] = record
	_reserved_stacks[record.item_id] = _reserved_stacks.get(record.item_id, 0) + 1
	return token

## Materializa uma reserva deste mesmo Inventory. Um token e utilizavel uma unica vez.
func commit_reservation(token: ReservationToken) -> bool:
	if token == null or not _reservations.has(token):
		return false
	var item: ItemDef = _consume_reservation(token)
	_guaranteed_acquire(item)
	return true

## Cancela uma reserva deste mesmo Inventory. Um token e utilizavel uma unica vez.
func cancel_reservation(token: ReservationToken) -> bool:
	if token == null or not _reservations.has(token):
		return false
	_consume_reservation(token)
	return true

## Devolve quantas vagas estao reservadas para testes e diagnostico de capacidade.
func reserved_count(item_id: StringName) -> int:
	return _reserved_stacks.get(item_id, 0)

func _consume_reservation(token: ReservationToken) -> ItemDef:
	var record: ReservationRecord = _reservations[token]
	_reservations.erase(token)
	var reserved: int = _reserved_stacks[record.item_id] - 1
	if reserved == 0:
		_reserved_stacks.erase(record.item_id)
	else:
		_reserved_stacks[record.item_id] = reserved
	return record.item

## Caminho ja validado para acquire e commit de uma reserva. Registra a
## instancia antes de chamar APIs que possam disparar callbacks sincronamente.
func _guaranteed_acquire(item: ItemDef) -> void:
	var current: int = _stacks.get(item.id, 0)
	var source_id: StringName = "%s#%d" % [item.id, _next_instance]
	_next_instance += 1
	var clones: Array[EffectDef] = []
	for effect in item.effects:
		if effect != null:
			clones.append(effect.duplicate() as EffectDef)

	_instances.append({"item_id": item.id, "source_id": source_id, "effects": clones})
	_stacks[item.id] = current + 1
	for modifier in item.get_runtime_modifiers():
		modifier.source_id = source_id
		_stats.add_modifier(modifier)
	_dispatcher.add_effects(clones)
	_dispatcher.dispatch(&"on_pickup", null, 0)

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
