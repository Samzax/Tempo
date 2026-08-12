class_name LootRoller
extends RefCounted
## Rolagens puras: cada oferta possui seu proprio RNG temporario e deterministico.

## Primos abaixo de 2^31: os produtos intermediarios ficam dentro do int64
## assinado de Godot mesmo com componentes de 64 bits.
const MODULUS: int = 2147483647
const MULTIPLIER: int = 48271
const COMPONENT_MULTIPLIER: int = 69621

static func roll_offer(pool: ItemPoolDef, run_seed: int, sector_index: int, node_id: int, player_slot: int, reward_index: int, luck: float = 0.0, is_eligible: Callable = Callable()) -> RewardOffer:
	var offer := RewardOffer.new()
	offer.run_seed = run_seed
	offer.sector_index = sector_index
	offer.node_id = node_id
	offer.player_slot = player_slot
	offer.reward_index = reward_index
	offer.pool_id = pool.id if pool != null else &""
	if pool == null:
		return offer

	var rng := RandomNumberGenerator.new()
	rng.seed = _mix_tuple(run_seed, sector_index, node_id, player_slot, reward_index)
	var candidates: Array[Dictionary] = []
	var candidate_by_id: Dictionary = {}
	for entry in pool.entries:
		if entry == null or entry.item == null or entry.item.id.is_empty() or entry.base_weight <= 0.0:
			continue
		if not entry.item.validate_content().is_empty():
			continue
		# Predicados devem ser puros e somente leitura: sao avaliados uma vez por entrada valida antes do RNG.
		if is_eligible.is_valid() and not bool(is_eligible.call(entry.item)):
			continue
		var weight := entry.base_weight * (1.0 + maxf(luck, 0.0) * _rarity_bonus(entry.item.rarity))
		if weight <= 0.0:
			continue
		# Entradas repetidas se somam, mas a oferta continua contendo itens distintos.
		if candidate_by_id.has(entry.item.id):
			var existing_index: int = candidate_by_id[entry.item.id]
			candidates[existing_index]["weight"] = float(candidates[existing_index]["weight"]) + weight
		else:
			candidate_by_id[entry.item.id] = candidates.size()
			candidates.append({"item": entry.item, "weight": weight})

	while offer.options.size() < 3 and not candidates.is_empty():
		var total_weight := 0.0
		for candidate in candidates:
			total_weight += float(candidate["weight"])
		if total_weight <= 0.0:
			break
		var pick := rng.randf() * total_weight
		var selected: ItemDef = null
		var selected_index := candidates.size() - 1
		for index in candidates.size():
			var candidate: Dictionary = candidates[index]
			pick -= float(candidate["weight"])
			if pick <= 0.0:
				selected = candidate["item"] as ItemDef
				selected_index = index
				break
		if selected == null:
			selected = candidates.back()["item"] as ItemDef
		offer.options.append(selected)
		candidates.remove_at(selected_index)
	return offer

static func _rarity_bonus(rarity: ItemDef.Rarity) -> float:
	match rarity:
		ItemDef.Rarity.RARE:
			return 1.0
		ItemDef.Rarity.LEGENDARY:
			return 2.0
	return 0.0

static func _mix_tuple(run_seed: int, sector_index: int, node_id: int, player_slot: int, reward_index: int) -> int:
	var state := _normalize(run_seed)
	for component in [sector_index, node_id, player_slot, reward_index]:
		state = ((state * MULTIPLIER) + (_normalize(component) * COMPONENT_MULTIPLIER) + 1) % (MODULUS - 1)
		state += 1
	return state

static func _normalize(value: int) -> int:
	var normalized := value % (MODULUS - 1)
	if normalized < 0:
		normalized += MODULUS - 1
	return normalized + 1
