class_name FormacaoAsasController
extends RefCounted

const CASULO_EXPLOSIVO := preload("res://scripts/enemies/bosses/wings/casulo_explosivo.gd")
const BANK_ORDER: Array[StringName] = [&"A", &"B", &"C"]
const BANKS: Dictionary = {
	&"A": [5, 6, 11, 12], # franja
	&"B": [2, 3, 8, 9], # pontas
	&"C": [1, 4, 7, 10], # raízes
}
const COCOON_IDS: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]

var _cocoons: Dictionary = {}
var _next_bank_index := 0
var _fired_banks: Dictionary = {}

## A formação só aceita exatamente os doze IDs canônicos, sem duplicatas.
func configure(cocoons: Array) -> bool:
	if cocoons.size() != COCOON_IDS.size():
		return false
	var by_id: Dictionary = {}
	for cocoon in cocoons:
		if not cocoon is CasuloExplosivo:
			return false
		var explosive_cocoon: CasuloExplosivo = cocoon
		if explosive_cocoon.cocoon_id <= 0 or by_id.has(explosive_cocoon.cocoon_id):
			return false
		if explosive_cocoon.state != CASULO_EXPLOSIVO.State.IDLE and explosive_cocoon.state != CASULO_EXPLOSIVO.State.EMPTY:
			return false
		by_id[explosive_cocoon.cocoon_id] = explosive_cocoon
	for cocoon_id in COCOON_IDS:
		if not by_id.has(cocoon_id):
			return false
	_cocoons = by_id
	for cocoon_id in COCOON_IDS:
		var cocoon: CasuloExplosivo = _cocoons[cocoon_id]
		if cocoon.state == CASULO_EXPLOSIVO.State.IDLE:
			if not cocoon.enter_slot():
				return false
		elif not cocoon.reset():
			return false
	_next_bank_index = 0
	_fired_banks.clear()
	return true

## Avanço determinístico para integração: cada posição inicia o tracking e é
## imediatamente travada. Não modela tempo, movimento ou aquisição por física.
func lock_bank(bank: StringName, positions_by_cocoon: Dictionary) -> bool:
	if not BANKS.has(bank):
		return false
	var ids: Array = BANKS[bank]
	for cocoon_id in ids:
		var cocoon: Node = _cocoons.get(cocoon_id)
		var position: Variant = positions_by_cocoon.get(cocoon_id)
		if cocoon == null or cocoon.state != CASULO_EXPLOSIVO.State.IN_SLOT or not position is Vector2:
			return false
	for cocoon_id in ids:
		var position: Vector2 = positions_by_cocoon[cocoon_id]
		var cocoon: Node = _cocoons[cocoon_id]
		if not cocoon.start_tracking(position) or not cocoon.lock_position(position):
			return false
	return true

func fire_bank(bank: StringName, overlaps_by_cocoon: Dictionary = {}) -> bool:
	if _next_bank_index >= BANK_ORDER.size() or bank != BANK_ORDER[_next_bank_index] or _fired_banks.has(bank):
		return false
	var ids: Array = BANKS[bank]
	for cocoon_id in ids:
		var cocoon: Node = _cocoons.get(cocoon_id)
		if cocoon == null or not cocoon.can_detonate():
			return false
	for cocoon_id in ids:
		var targets: Array[Node] = []
		var supplied: Variant = overlaps_by_cocoon.get(cocoon_id, [])
		if supplied is Array:
			for target in supplied:
				if target is Node:
					targets.append(target)
		(_cocoons[cocoon_id] as Node).detonate(targets)
	_fired_banks[bank] = true
	_next_bank_index += 1
	return true

## Avança sempre para o próximo banco permitido: A, depois B, depois C.
func advance(overlaps_by_cocoon: Dictionary = {}) -> bool:
	if _next_bank_index >= BANK_ORDER.size():
		return false
	return fire_bank(BANK_ORDER[_next_bank_index], overlaps_by_cocoon)

func get_active_count() -> int:
	var count := 0
	for cocoon_id in COCOON_IDS:
		var cocoon: Node = _cocoons.get(cocoon_id)
		if cocoon != null and cocoon.state != CASULO_EXPLOSIVO.State.EMPTY and cocoon.state != CASULO_EXPLOSIVO.State.DESTROYED:
			count += 1
	return count

func is_active() -> bool:
	return get_active_count() > 0

func is_empty() -> bool:
	return not _cocoons.is_empty() and get_active_count() == 0

func reconstitute_all() -> bool:
	if _cocoons.size() != COCOON_IDS.size():
		return false
	for cocoon_id in COCOON_IDS:
		var cocoon: Node = _cocoons.get(cocoon_id)
		if cocoon == null or cocoon.state != CASULO_EXPLOSIVO.State.EMPTY:
			return false
	for cocoon_id in COCOON_IDS:
		var cocoon: Node = _cocoons[cocoon_id]
		if not cocoon.reset():
			return false
	_next_bank_index = 0
	_fired_banks.clear()
	return true

func get_cocoon(cocoon_id: int) -> Node:
	return _cocoons.get(cocoon_id) as Node
