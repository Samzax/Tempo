extends GutTest

const TREASURE := preload("res://resources/loot/treasure_pool.tres")
const CHEST_SCRIPT := preload("res://scripts/loot/reward_chest.gd")
const CHOICE_SCRIPT := preload("res://scripts/ui/item_choice.gd")
const PRICING := preload("res://scripts/loot/treasure_pricing.gd")

class ChoicePlayer extends Node:
	var can_take := true
	var acquire_calls := 0
	var buy_calls := 0
	var acquired: Array[ItemDef] = []
	var bought: Array[ItemDef] = []
	var buy_costs: Array[int] = []

	func get_luck() -> float: return 0.0
	func can_acquire_item(_item: ItemDef) -> bool: return can_take
	func acquire_item(item: ItemDef) -> bool:
		acquire_calls += 1
		if not can_take: return false
		acquired.append(item)
		return true
	var buy_result := true
	func buy_item(item: ItemDef, cost: int) -> bool:
		buy_calls += 1
		buy_costs.append(cost)
		if not can_take or not buy_result: return false
		bought.append(item)
		return true

class ChestDirector extends Node:
	signal enemy_spawned(enemy: Enemy)
	signal spawns_finished
	signal spawns_failed(reason: String)
	func start(_limit: int) -> bool: return true

class ReentrantFreePlayer extends Node:
	var choice: ItemChoice
	var other_offer: RewardOffer
	var can_acquire_calls := 0
	var acquire_calls := 0
	var armed := false
	var reentered := false

	func can_acquire_item(_item: ItemDef) -> bool:
		can_acquire_calls += 1
		if armed and not reentered:
			reentered = true
			choice._choose(0)
			choice.open_offer(other_offer, self)
		return true

	func acquire_item(_item: ItemDef) -> bool:
		acquire_calls += 1
		choice._choose(0)
		choice.open_offer(other_offer, self)
		return true

class ReentrantPaidPlayer extends Node:
	var choice: ItemChoice
	var other_offer: RewardOffer
	var buy_result := true
	var buy_calls := 0

	func can_acquire_item(_item: ItemDef) -> bool: return true

	func buy_item(_item: ItemDef, _cost: int) -> bool:
		buy_calls += 1
		return buy_result

class PlanMutatingPlayer extends Node:
	var choice: ItemChoice
	var other_offer: RewardOffer
	var armed := false
	var buy_calls := 0
	var buy_costs: Array[int] = []
	var acquire_calls := 0

	func can_acquire_item(_item: ItemDef) -> bool:
		if armed:
			armed = false
			choice.open_offer(other_offer, self)
			choice._choose(0)
			choice._offer.paid_with_temporal_echoes = false
			choice._offer.option_costs.clear()
		return true

	func buy_item(_item: ItemDef, cost: int) -> bool:
		buy_calls += 1
		buy_costs.append(cost)
		return true

	func acquire_item(_item: ItemDef) -> bool:
		acquire_calls += 1
		return true

class RefreshReentrantPlayer extends Node:
	var choice: ItemChoice
	var other_offer: RewardOffer
	var buy_result := false
	var buy_calls := 0
	var attack_refresh := false
	var attack_count := 0

	func can_acquire_item(_item: ItemDef) -> bool:
		if attack_refresh:
			attack_refresh = false
			attack_count += 1
			choice._choose(0)
			choice.open_offer(other_offer, self)
		return true

	func buy_item(_item: ItemDef, _cost: int) -> bool:
		buy_calls += 1
		return buy_result

class RefreshMutationPlayer extends Node:
	var choice: ItemChoice
	var original_offer: RewardOffer
	var other_offer: RewardOffer
	var armed := false
	var mode := ""
	var can_calls := 0
	var acquire_calls := 0
	var buy_calls := 0
	var buy_costs: Array[int] = []
	var emitted := false

	func can_acquire_item(_item: ItemDef) -> bool:
		can_calls += 1
		if armed:
			if mode == "mutate_once" and can_calls == 2:
				original_offer.option_costs.clear()
				choice.open_offer(other_offer, self)
			elif mode == "buy_failure_mutate" and can_calls == 3:
				original_offer.option_costs.clear()
				choice.open_offer(other_offer, self)
			elif mode == "emit_once" and not emitted:
				emitted = true
				GameState.add_temporal_echoes(1)
			elif mode == "emit_every":
				GameState.add_temporal_echoes(1)
		return true

	func acquire_item(_item: ItemDef) -> bool:
		acquire_calls += 1
		return true

	var buy_result := true
	func buy_item(_item: ItemDef, cost: int) -> bool:
		buy_calls += 1
		buy_costs.append(cost)
		return buy_result

class DestructiveRefreshPlayer extends Node:
	var choice: ItemChoice
	var mode := ""
	var armed := true
	var can_calls := 0
	var acquire_calls := 0
	var buy_calls := 0
	var title_host: Node

	func can_acquire_item(_item: ItemDef) -> bool:
		can_calls += 1
		if armed:
			armed = false if mode != "persistent_button" else true
			if mode == "free_button" or mode == "persistent_button":
				choice._buttons[0].free()
			elif mode == "queue_title":
				choice._title.queue_free()
			elif mode == "reparent_title":
				choice._title.reparent(title_host)
			elif mode == "queue_player":
				queue_free()
		return true

	func acquire_item(_item: ItemDef) -> bool:
		acquire_calls += 1
		return true

	func buy_item(_item: ItemDef, _cost: int) -> bool:
		buy_calls += 1
		return true

func _pool_ids(pool: ItemPoolDef) -> Array[StringName]:
	var ids: Array[StringName] = []
	for entry in pool.entries:
		ids.append(entry.item.id)
	return ids

func _item(id: StringName) -> ItemDef:
	return ItemCatalog.get_item(id)

func _local_item(id: StringName, max_stacks := 2) -> ItemDef:
	var item := ItemDef.new()
	item.id = id
	item.max_stacks = max_stacks
	item.effects = []
	item.modifiers = []
	return item

func _offer(item: ItemDef, paid := false, costs: Array[int] = []) -> RewardOffer:
	var offer := RewardOffer.new()
	offer.options = [item]
	offer.paid_with_temporal_echoes = paid
	offer.option_costs = costs
	return offer

func _choice_button(choice: ItemChoice) -> Button:
	for child in choice.get_children():
		if child is VBoxContainer:
			return (child as VBoxContainer).get_child(1) as Button
	return null

func before_each() -> void:
	GameState.temporal_echoes = 0
	_reentrant_choice = null
	_reentrant_other_offer = null
	_reentrant_player = null
	_reentrant_echo_calls = 0
	if GameState.temporal_echoes_changed.is_connected(_on_echoes_changed):
		GameState.temporal_echoes_changed.disconnect(_on_echoes_changed)
	for callback_name in [&"_on_reentrant_echo", &"_on_reattach_echo", &"_on_mutate_item_id"]:
		var callback := Callable(self, callback_name)
		if GameState.temporal_echoes_changed.is_connected(callback):
			GameState.temporal_echoes_changed.disconnect(callback)

func after_each() -> void:
	if GameState.temporal_echoes_changed.is_connected(_on_echoes_changed):
		GameState.temporal_echoes_changed.disconnect(_on_echoes_changed)
	for callback_name in [&"_on_reentrant_echo", &"_on_reattach_echo", &"_on_mutate_item_id"]:
		var callback := Callable(self, callback_name)
		if GameState.temporal_echoes_changed.is_connected(callback):
			GameState.temporal_echoes_changed.disconnect(callback)
	if is_instance_valid(_reentrant_choice) and _reentrant_choice.visibility_changed.is_connected(Callable(self, &"_on_visibility_attack")):
		_reentrant_choice.visibility_changed.disconnect(Callable(self, &"_on_visibility_attack"))
	GameState.temporal_echoes = 0
	_reentrant_choice = null
	_reentrant_other_offer = null
	_reentrant_player = null
	_reentrant_echo_calls = 0

func _on_echoes_changed(_amount: int, _total: int) -> void:
	pass

var _reentrant_choice: ItemChoice
var _reentrant_other_offer: RewardOffer
var _reentrant_player: Node
var _reentrant_echo_calls := 0

func _on_reentrant_echo(amount: int, total: int) -> void:
	_reentrant_echo_calls += 1
	if _reentrant_echo_calls == 1:
		_reentrant_choice._choose(0)
		_reentrant_choice.open_offer(_reentrant_other_offer, _reentrant_player)

func _chest(existing: RewardOffer = null, paid := false) -> Dictionary:
	var root := Node2D.new()
	add_child_autofree(root)
	var director := ChestDirector.new()
	director.name = "ChestDirector"
	root.add_child(director)
	var controller := RoomController.new()
	controller.name = "RoomController"
	controller.room_def = RoomDef.new()
	controller.director_path = ^"../ChestDirector"
	root.add_child(controller)
	var player := ChoicePlayer.new()
	root.add_child(player)
	var chest := CHEST_SCRIPT.new()
	chest.room_controller_path = ^"../RoomController"
	chest.player_path = ^"../ChoicePlayer"
	chest.configure(player, 2, 23, 0, 0, TREASURE, existing, paid)
	root.add_child(chest)
	return {"root": root, "controller": controller, "chest": chest, "player": player}

func test_sector_two_upper_is_only_treasure_and_keeps_dag_and_profile() -> void:
	for sector_index in [0, 1, 2, 3]:
		var sector := SectorGenerator.generate(77, sector_index)
		var upper: SectorNode = sector.nodes.values().filter(func(n): return n.column == 2 and n.row == 0)[0]
		if sector_index == 2:
			assert_eq(upper.id, 23)
			assert_eq(upper.node_type, SectorNode.NodeType.TREASURE)
			assert_eq(upper.room_profile, &"upper")
			var upper_children: Array[int] = sector.get_children(23)
			assert_eq(upper_children, [25])
			var treasure_children: Array[int] = sector.get_children(25)
			assert_eq(treasure_children, [26])
			assert_eq(sector.get_node(upper_children[0]).column, 3)
		else:
			assert_eq(upper.node_type, SectorNode.NodeType.COMBAT)

func test_treasure_pool_is_exactly_ten_positive_treasure_items() -> void:
	assert_eq(TREASURE.id, &"treasure")
	assert_eq(TREASURE.entries.size(), 10)
	var ids := _pool_ids(TREASURE)
	var expected: Array[StringName] = [&"nucleo_superaquecido", &"casco_reforcado", &"recarga_fria", &"reator_instavel", &"lente_de_foco", &"eco_temporal", &"frenesi", &"vinganca", &"sanguessuga", &"estilhaco"]
	ids.sort()
	expected.sort()
	assert_eq(ids, expected)
	var catalog_treasure: Array[StringName] = []
	for item in ItemCatalog.get_all():
		if &"treasure" in item.pools:
			catalog_treasure.append(item.id)
	catalog_treasure.sort()
	assert_eq(ids, catalog_treasure)
	for entry in TREASURE.entries:
		assert_not_null(entry.item)
		assert_gt(entry.base_weight, 0.0)
		assert_true(&"treasure" in entry.item.pools)

func test_room_and_sector_ordinals_are_stable() -> void:
	assert_eq(SectorNode.NodeType.OPENING, 0)
	assert_eq(SectorNode.NodeType.COMBAT, 1)
	assert_eq(SectorNode.NodeType.BOSS, 2)
	assert_eq(SectorNode.NodeType.TREASURE, 3)
	assert_eq(RoomDef.RoomType.OPENING, 0)
	assert_eq(RoomDef.RoomType.COMBAT, 1)
	assert_eq(RoomDef.RoomType.BOSS, 2)
	assert_eq(RoomDef.RoomType.TREASURE, 3)

func test_session_maps_treasure_and_upper_contracts() -> void:
	var session := Session.new()
	autofree(session)
	var node := SectorNode.new()
	node.id = 23
	node.node_type = SectorNode.NodeType.TREASURE
	node.room_profile = &"upper"
	var def := session._room_def_for(node)
	assert_eq(def.room_type, RoomDef.RoomType.TREASURE)
	assert_true(def.has_waves())
	assert_eq(def.wave_specs[0].threat_types.size(), 8)
	assert_eq(def.initial_debris.size(), 3)
	assert_same(session._pool_for(node), TREASURE)
	for kind in [SectorNode.NodeType.COMBAT]:
		var upper := SectorNode.new()
		upper.node_type = kind
		upper.room_profile = &"upper"
		assert_eq(session._room_def_for(upper).room_type, RoomDef.RoomType.COMBAT)
		assert_same(session._pool_for(upper), session.COMBAT_POOL)

func test_treasure_pricing_is_runtime_deterministic_and_balance_independent() -> void:
	assert_eq(PRICING.cost_for(_item(&"nucleo_superaquecido")), PRICING.cost_for_rarity(_item(&"nucleo_superaquecido").rarity))
	assert_eq(PRICING.cost_for_rarity(ItemDef.Rarity.COMMON), 6)
	assert_eq(PRICING.cost_for_rarity(ItemDef.Rarity.RARE), 9)
	assert_eq(PRICING.cost_for_rarity(ItemDef.Rarity.LEGENDARY), 12)
	assert_eq(PRICING.cost_for(null), -1)
	assert_eq(PRICING.cost_for_rarity(999), -1)
	GameState.temporal_echoes = 0
	var low: int = PRICING.cost_for(_item(&"estilhaco"))
	GameState.temporal_echoes = 999
	assert_eq(PRICING.cost_for(_item(&"estilhaco")), low)

func test_paid_chest_publishes_complete_offer_and_restore_keeps_arbitrary_costs() -> void:
	var fixture := _chest(null, true)
	var chest: RewardChest = fixture.chest
	var controller: RoomController = fixture.controller
	watch_signals(chest)
	controller.room_cleared.emit()
	var offer: RewardOffer = controller.runtime.reward_offer
	assert_not_null(offer)
	assert_true(offer.paid_with_temporal_echoes)
	assert_eq(offer.option_costs.size(), offer.options.size())
	for i in offer.options.size(): assert_eq(offer.option_costs[i], PRICING.cost_for(offer.options[i]))
	assert_signal_emitted(chest, &"offer_created")
	assert_signal_emitted_with_parameters(chest, &"offer_created", [offer])
	var saved := RewardOffer.new()
	saved.options = [_item(&"estilhaco")]
	saved.paid_with_temporal_echoes = true
	saved.option_costs = [123]
	var restored := _chest(saved, true)
	var restored_offer: RewardOffer = restored.controller.runtime.reward_offer
	assert_same(restored_offer, saved)
	assert_eq(restored_offer.option_costs, [123])
	watch_signals(restored.chest)
	restored.chest._unlock()
	restored.chest.open_offer()
	assert_signal_not_emitted(restored.chest, &"offer_created")
	assert_eq(restored_offer.option_costs, [123])

func test_chest_is_locked_until_clear_then_creates_paid_offer() -> void:
	var fixture := _chest(null, true)
	var chest: RewardChest = fixture.chest
	var controller: RoomController = fixture.controller
	watch_signals(chest)
	chest.open_offer()
	assert_null(controller.runtime.reward_offer)
	assert_signal_not_emitted(chest, &"offer_created")
	controller.room_cleared.emit()
	assert_not_null(controller.runtime.reward_offer)
	assert_signal_emitted(chest, &"offer_created")

func test_item_choice_invalid_paid_metadata_never_falls_back_to_free() -> void:
	var player := autofree(ChoicePlayer.new()) as ChoicePlayer
	var choice := CHOICE_SCRIPT.new()
	add_child_autofree(choice)
	var offer := RewardOffer.new()
	offer.options = [_item(&"estilhaco")]
	offer.paid_with_temporal_echoes = true
	offer.option_costs = []
	GameState.temporal_echoes = 999
	choice.open_offer(offer, player)
	await get_tree().process_frame
	var button := _choice_button(choice)
	assert_true(button.disabled)
	assert_true(button.text.contains("INDISPONÍVEL"))
	choice._choose(0)
	assert_eq(player.acquire_calls, 0)
	assert_eq(player.buy_calls, 0)
	assert_false(offer.claimed)

func test_item_choice_paid_success_passes_cost_and_closes() -> void:
	var player := ChoicePlayer.new(); add_child_autofree(player)
	var choice := CHOICE_SCRIPT.new(); add_child_autofree(choice)
	var offer := RewardOffer.new(); offer.options = [_item(&"estilhaco")]; offer.paid_with_temporal_echoes = true; offer.option_costs = [123]
	GameState.temporal_echoes = 123
	choice.open_offer(offer, player); await get_tree().process_frame; choice._choose(0)
	assert_eq(player.buy_calls, 1); assert_eq(player.buy_costs, [123]); assert_eq(player.acquire_calls, 0)
	assert_true(offer.claimed); assert_eq(offer.claimed_item_id, &"estilhaco"); assert_false(choice.visible)

func test_player_buy_item_uses_real_transaction_and_debits_exactly_once() -> void:
	var stats := StatBlock.new(StatCatalog.get_all())
	var dispatcher := EffectDispatcher.new(autofree(Node.new()), [])
	var inventory := Inventory.new(stats, dispatcher)
	var player := autofree(Player.new()) as Player
	player._inventory = inventory
	var item := ItemDef.new()
	item.id = &"treasure_transaction"
	item.max_stacks = 1
	item.effects = []
	item.modifiers = []
	GameState.temporal_echoes = 123
	watch_signals(GameState)
	assert_true(player.buy_item(item, 123))
	assert_eq(GameState.temporal_echoes, 0)
	assert_eq(inventory.count(item.id), 1)
	assert_signal_emitted_with_parameters(GameState, &"temporal_echoes_changed", [-123, 0])

func test_item_choice_insufficient_funds_refreshes_then_reacts_to_credit() -> void:
	var player := ChoicePlayer.new(); add_child_autofree(player)
	var choice := CHOICE_SCRIPT.new(); add_child_autofree(choice)
	var offer := RewardOffer.new(); offer.options = [_item(&"estilhaco")]; offer.paid_with_temporal_echoes = true; offer.option_costs = [6]
	GameState.temporal_echoes = 5; choice.open_offer(offer, player); await get_tree().process_frame
	var button := _choice_button(choice)
	assert_true(choice._title.text.contains("ECOS: 5"))
	assert_true(button.disabled)
	assert_true(button.text.contains("ECOS INSUFICIENTES"))
	choice._choose(0); assert_eq(player.buy_calls, 0)
	GameState.add_temporal_echoes(1); await get_tree().process_frame
	assert_true(choice._title.text.contains("ECOS: 6"))
	assert_false(button.disabled)
	assert_true(button.text.contains("(6 ECOS)"))
	assert_false(button.text.contains("INSUFICIENTES"))
	choice._choose(0); assert_eq(player.buy_calls, 1); assert_true(offer.claimed)

func test_item_choice_limit_has_priority_and_no_calls() -> void:
	var player := ChoicePlayer.new(); player.can_take = false; add_child_autofree(player)
	var choice := CHOICE_SCRIPT.new(); add_child_autofree(choice)
	var offer := RewardOffer.new(); offer.options = [_item(&"estilhaco")]; offer.paid_with_temporal_echoes = true; offer.option_costs = [6]
	GameState.temporal_echoes = 999; choice.open_offer(offer, player); await get_tree().process_frame
	var button := choice.get_children().filter(func(n): return n is VBoxContainer)[0].get_child(1) as Button
	assert_true(button.disabled); assert_true(button.text.contains("LIMITE ATINGIDO")); assert_false(button.text.contains("INSUFICIENTES")); choice._choose(0)
	assert_eq(player.buy_calls, 0); assert_eq(player.acquire_calls, 0); assert_false(offer.claimed)

func test_item_choice_invalid_paid_metadata_variants_are_unavailable() -> void:
	for costs in [[], [0], [-1], [1, 2]]:
		var player := ChoicePlayer.new(); add_child_autofree(player)
		var choice := CHOICE_SCRIPT.new(); add_child_autofree(choice)
		var typed_costs: Array[int] = []
		for value in costs: typed_costs.append(int(value))
		var offer := RewardOffer.new(); offer.options = [_item(&"estilhaco")]; offer.paid_with_temporal_echoes = true; offer.option_costs = typed_costs
		GameState.temporal_echoes = 999; choice.open_offer(offer, player); await get_tree().process_frame; choice._choose(0)
		var button := _choice_button(choice)
		assert_true(button.disabled); assert_true(button.text.contains("INDISPONÍVEL"))
		assert_eq(player.buy_calls, 0); assert_eq(player.acquire_calls, 0); assert_false(offer.claimed)

func test_item_choice_revalidates_limit_and_buy_failure_atomically() -> void:
	var player := ChoicePlayer.new(); add_child_autofree(player)
	var choice := CHOICE_SCRIPT.new(); add_child_autofree(choice)
	var offer := RewardOffer.new(); offer.options = [_item(&"estilhaco")]; offer.paid_with_temporal_echoes = true; offer.option_costs = [6]
	GameState.temporal_echoes = 6; choice.open_offer(offer, player); await get_tree().process_frame
	player.can_take = false; choice._choose(0); assert_eq(player.buy_calls, 0); assert_eq(GameState.temporal_echoes, 6); assert_true(choice.visible); assert_false(offer.claimed); assert_true(_choice_button(choice).disabled)
	player.can_take = true; player.buy_result = false; choice._choose(0); assert_eq(player.buy_calls, 1); assert_true(choice.visible); assert_false(offer.claimed)
	assert_eq(GameState.temporal_echoes, 6); assert_false(_choice_button(choice).disabled)

func test_item_choice_connection_is_idempotent_and_free_path_does_not_spend() -> void:
	var player := ChoicePlayer.new(); add_child_autofree(player)
	var choice := CHOICE_SCRIPT.new(); add_child_autofree(choice)
	choice.open_offer(RewardOffer.new(), player); choice.open_offer(RewardOffer.new(), player)
	var connections := GameState.temporal_echoes_changed.get_connections()
	var matching := connections.filter(func(c): return c.callable == Callable(choice, &"_on_temporal_echoes_changed"))
	assert_eq(matching.size(), 1)
	var offer := RewardOffer.new(); offer.options = [_item(&"estilhaco")]; GameState.temporal_echoes = 20; choice.open_offer(offer, player); await get_tree().process_frame; choice._choose(0)
	assert_eq(GameState.temporal_echoes, 20); assert_eq(player.buy_calls, 0); assert_eq(player.acquire_calls, 1)

func test_free_offer_is_governed_by_paid_flag_even_with_malformed_costs() -> void:
	var player := ChoicePlayer.new()
	add_child_autofree(player)
	var choice := CHOICE_SCRIPT.new()
	add_child_autofree(choice)
	var offer := RewardOffer.new()
	offer.options = [_item(&"estilhaco")]
	offer.paid_with_temporal_echoes = false
	offer.option_costs = [-1, 999]
	GameState.temporal_echoes = 20
	choice.open_offer(offer, player)
	await get_tree().process_frame
	choice._choose(0)
	assert_eq(player.acquire_calls, 1)
	assert_eq(player.buy_calls, 0)
	assert_true(offer.claimed)
	assert_eq(GameState.temporal_echoes, 20)

func test_item_choice_null_option_is_unavailable_for_free_and_paid_offers() -> void:
	for paid in [false, true]:
		var player := autofree(ChoicePlayer.new()) as ChoicePlayer
		var choice := CHOICE_SCRIPT.new() as ItemChoice
		add_child_autofree(choice)
		var options: Array[ItemDef] = []
		options.append(null)
		var offer := RewardOffer.new()
		offer.options = options
		offer.paid_with_temporal_echoes = paid
		offer.option_costs = [6]
		GameState.temporal_echoes = 99
		choice.open_offer(offer, player)
		await get_tree().process_frame
		var button := _choice_button(choice)
		assert_true(button.disabled)
		assert_true(button.text.contains("ITEM INVÁLIDO"))
		assert_true(button.text.contains("INDISPONÍVEL"))
		choice._choose(0)
		assert_false(choice._choosing)
		assert_eq(player.acquire_calls, 0)
		assert_eq(player.buy_calls, 0)
		assert_false(offer.claimed)
		assert_eq(GameState.temporal_echoes, 99)

func test_empty_offer_claims_without_presenting_choice() -> void:
	var fixture := _chest()
	var controller: RoomController = fixture.controller
	fixture.chest._unlock()
	var offer := RewardOffer.new()
	controller.runtime.reward_offer = offer
	fixture.chest.open_offer()
	assert_true(offer.claimed)
	assert_eq(offer.claimed_item_id, &"")

func test_paid_reentrancy_uses_original_offer_and_debits_once() -> void:
	var stats := StatBlock.new(StatCatalog.get_all())
	var dispatcher := EffectDispatcher.new(autofree(Node.new()), [])
	var inventory := Inventory.new(stats, dispatcher)
	var player := autofree(Player.new()) as Player
	player._inventory = inventory
	var item := _local_item(&"test_reentrant_treasure")
	var choice := CHOICE_SCRIPT.new() as ItemChoice
	add_child_autofree(choice)
	var offer := _offer(item, true, [6])
	var other := _offer(_local_item(&"test_other_treasure"))
	GameState.temporal_echoes = 12
	_reentrant_choice = choice
	_reentrant_other_offer = other
	_reentrant_player = player
	GameState.temporal_echoes_changed.connect(Callable(self, &"_on_reentrant_echo"))
	choice.open_offer(offer, player)
	await get_tree().process_frame
	watch_signals(GameState)
	choice._choose(0)
	assert_eq(_reentrant_echo_calls, 1)
	assert_signal_emit_count(GameState, &"temporal_echoes_changed", 1)
	assert_signal_emitted_with_parameters(GameState, &"temporal_echoes_changed", [-6, 6])
	assert_eq(GameState.temporal_echoes, 6)
	assert_eq(inventory.count(item.id), 1)
	assert_true(offer.claimed)
	assert_eq(offer.claimed_item_id, item.id)
	assert_same(choice._offer, offer)
	assert_false(other.claimed)
	assert_false(choice._choosing)

func test_paid_buy_failure_releases_lock_and_allows_retry() -> void:
	var player := ReentrantPaidPlayer.new(); player.buy_result = false; add_child_autofree(player)
	var choice := CHOICE_SCRIPT.new() as ItemChoice; add_child_autofree(choice)
	var offer := _offer(_local_item(&"test_paid_retry"), true, [6])
	GameState.temporal_echoes = 6
	choice.open_offer(offer, player); await get_tree().process_frame
	choice._choose(0)
	assert_eq(player.buy_calls, 1); assert_false(offer.claimed); assert_false(choice._choosing); assert_true(choice.visible)
	player.buy_result = true
	choice._choose(0)
	assert_eq(player.buy_calls, 2); assert_true(offer.claimed); assert_false(choice._choosing); assert_false(choice.visible)
	choice._choose(0)
	assert_eq(player.buy_calls, 2)

func test_free_reentrancy_is_locked_before_can_acquire_and_acquire() -> void:
	var player := ReentrantFreePlayer.new(); add_child_autofree(player)
	var choice := CHOICE_SCRIPT.new() as ItemChoice; add_child_autofree(choice)
	player.choice = choice
	var item := _local_item(&"test_free_reentrant")
	var offer := _offer(item)
	player.other_offer = _offer(_local_item(&"test_free_other"))
	choice.open_offer(offer, player); await get_tree().process_frame
	player.armed = true
	choice._choose(0)
	assert_eq(player.acquire_calls, 1)
	assert_true(offer.claimed)
	assert_false(player.other_offer.claimed)
	assert_same(choice._offer, offer)
	assert_false(choice._choosing)

func test_paid_reattach_during_debit_keeps_original_offer_and_single_listener() -> void:
	var stats := StatBlock.new(StatCatalog.get_all())
	var inventory := Inventory.new(stats, EffectDispatcher.new(autofree(Node.new()), []))
	var player := autofree(Player.new()) as Player; player._inventory = inventory
	var host := Node.new(); add_child_autofree(host)
	var choice := CHOICE_SCRIPT.new() as ItemChoice; host.add_child(choice)
	var item := _local_item(&"reattach_item", 2); var original_id := item.id
	var offer := _offer(item, true, [6]); var other := _offer(_local_item(&"reattach_other"))
	_reentrant_choice = choice; _reentrant_other_offer = other; _reentrant_player = player
	GameState.temporal_echoes = 12
	GameState.temporal_echoes_changed.connect(Callable(self, &"_on_reattach_echo"))
	choice.open_offer(offer, player); await get_tree().process_frame
	watch_signals(GameState)
	choice._choose(0)
	assert_eq(_reentrant_echo_calls, 1)
	assert_signal_emit_count(GameState, &"temporal_echoes_changed", 1)
	assert_signal_emitted_with_parameters(GameState, &"temporal_echoes_changed", [-6, 6])
	assert_eq(GameState.temporal_echoes, 6); assert_eq(inventory.count(original_id), 1)
	assert_true(offer.claimed); assert_eq(offer.claimed_item_id, original_id); assert_false(other.claimed)
	assert_same(choice._offer, offer); assert_false(choice._choosing)
	var matches := GameState.temporal_echoes_changed.get_connections().filter(func(c): return c.callable == Callable(choice, &"_on_temporal_echoes_changed"))
	assert_eq(matches.size(), 1)

func _on_reattach_echo(_amount: int, _total: int) -> void:
	if _reentrant_echo_calls == 0:
		_reentrant_echo_calls += 1
		var host := _reentrant_choice.get_parent()
		host.remove_child(_reentrant_choice); host.add_child(_reentrant_choice)
		_reentrant_choice.open_offer(_reentrant_other_offer, _reentrant_player)
		_reentrant_choice._choose(0)

func test_visibility_changed_during_hide_cannot_reenter_choice() -> void:
	var player := ChoicePlayer.new(); add_child_autofree(player)
	var choice := CHOICE_SCRIPT.new() as ItemChoice; add_child_autofree(choice)
	var offer := _offer(_local_item(&"visibility_item"), true, [6]); var other := _offer(_local_item(&"visibility_other"))
	_reentrant_choice = choice; _reentrant_other_offer = other; _reentrant_player = player
	choice.visibility_changed.connect(Callable(self, &"_on_visibility_attack"))
	GameState.temporal_echoes = 6; choice.open_offer(offer, player); await get_tree().process_frame
	assert_eq(_reentrant_echo_calls, 0)
	_reentrant_echo_calls = 0; choice._choose(0)
	assert_eq(_reentrant_echo_calls, 1)
	assert_eq(player.buy_calls, 1); assert_true(offer.claimed); assert_false(other.claimed); assert_false(choice._choosing)
	choice.visibility_changed.disconnect(Callable(self, &"_on_visibility_attack"))

func _on_visibility_attack() -> void:
	if not _reentrant_choice.visible and _reentrant_echo_calls == 0:
		_reentrant_echo_calls += 1
		_reentrant_choice.open_offer(_reentrant_other_offer, _reentrant_player)
		_reentrant_choice._choose(0)

func test_paid_debit_snapshots_item_id_before_echo_listener_mutates_item() -> void:
	var stats := StatBlock.new(StatCatalog.get_all())
	var inventory := Inventory.new(stats, EffectDispatcher.new(autofree(Node.new()), []))
	var player := autofree(Player.new()) as Player; player._inventory = inventory
	var item := _local_item(&"original_id", 2); var original_id := item.id
	var offer := _offer(item, true, [6]); GameState.temporal_echoes = 12
	GameState.temporal_echoes_changed.connect(Callable(self, &"_on_mutate_item_id"))
	_reentrant_choice = CHOICE_SCRIPT.new() as ItemChoice; add_child_autofree(_reentrant_choice)
	_reentrant_choice.open_offer(offer, player); await get_tree().process_frame; _reentrant_choice._choose(0)
	assert_eq(inventory.count(original_id), 1); assert_eq(inventory.count(&"mutated_id"), 0)
	assert_eq(offer.claimed_item_id, original_id); assert_eq(GameState.temporal_echoes, 6)

func test_hyperspace_semantic_labels_have_safe_fallback() -> void:
	var ui := autofree(HyperspaceUI.new()) as HyperspaceUI
	assert_eq(ui._label_for_node_type(SectorNode.NodeType.OPENING), "INICIO")
	assert_eq(ui._label_for_node_type(SectorNode.NodeType.COMBAT), "COMBATE")
	assert_eq(ui._label_for_node_type(SectorNode.NodeType.BOSS), "BOSS")
	assert_eq(ui._label_for_node_type(SectorNode.NodeType.TREASURE), "TESOURO")
	assert_eq(ui._label_for_node_type(999), "COMBATE")

func _on_mutate_item_id(_amount: int, _total: int) -> void:
	if _reentrant_choice != null and _reentrant_choice._offer != null:
		_reentrant_choice._offer.options[0].id = &"mutated_id"

func test_paid_plan_is_frozen_before_can_acquire_mutation() -> void:
	var player := PlanMutatingPlayer.new(); add_child_autofree(player)
	var choice := CHOICE_SCRIPT.new() as ItemChoice; add_child_autofree(choice); player.choice = choice
	var offer := _offer(_local_item(&"plan_item"), true, [6]); player.other_offer = _offer(_local_item(&"plan_other"))
	GameState.temporal_echoes = 6; choice.open_offer(offer, player); await get_tree().process_frame; player.armed = true; choice._choose(0)
	assert_eq(player.buy_calls, 1); assert_eq(player.buy_costs, [6]); assert_eq(player.acquire_calls, 0)

func test_failed_buy_refresh_reentrancy_releases_lock_for_retry() -> void:
	var player := RefreshReentrantPlayer.new(); add_child_autofree(player)
	var choice := CHOICE_SCRIPT.new() as ItemChoice; add_child_autofree(choice); player.choice = choice
	var offer := _offer(_local_item(&"refresh_item"), true, [6]); player.other_offer = _offer(_local_item(&"refresh_other"))
	GameState.temporal_echoes = 6; choice.open_offer(offer, player); await get_tree().process_frame
	player.attack_refresh = true; choice._choose(0)
	assert_eq(player.buy_calls, 1); assert_eq(player.attack_count, 1); assert_false(choice._choosing)
	player.buy_result = true; choice._choose(0); assert_eq(player.buy_calls, 2); assert_true(offer.claimed)

func test_item_choice_exit_tree_disconnects_echo_listener() -> void:
	var choice := CHOICE_SCRIPT.new() as ItemChoice
	add_child(choice)
	await get_tree().process_frame
	assert_true(GameState.temporal_echoes_changed.is_connected(Callable(choice, &"_on_temporal_echoes_changed")))
	var host := choice.get_parent(); host.remove_child(choice)
	assert_false(GameState.temporal_echoes_changed.is_connected(Callable(choice, &"_on_temporal_echoes_changed")))
	host.add_child(choice)
	assert_true(GameState.temporal_echoes_changed.is_connected(Callable(choice, &"_on_temporal_echoes_changed")))
	assert_false(choice._choosing)
	choice.queue_free()
	await get_tree().process_frame
	assert_false(GameState.temporal_echoes_changed.is_connected(Callable(choice, &"_on_temporal_echoes_changed")))

func _refresh_mutation_fixture(mode: String, balance := 6) -> Dictionary:
	var player := RefreshMutationPlayer.new(); add_child_autofree(player)
	var choice := CHOICE_SCRIPT.new() as ItemChoice; add_child_autofree(choice)
	var original := _offer(_local_item(&"refresh_original"), true, [6])
	var other_options: Array[ItemDef] = [_local_item(&"other_a"), _local_item(&"other_b")]
	var other := RewardOffer.new(); other.options = other_options; other.option_costs = []; other.paid_with_temporal_echoes = false
	player.choice = choice; player.original_offer = original; player.other_offer = other; player.mode = mode
	GameState.temporal_echoes = balance
	choice.open_offer(original, player)
	await get_tree().process_frame
	player.armed = true
	return {"player": player, "choice": choice, "original": original, "other": other}

func test_refresh_can_acquire_mutating_costs_keeps_original_snapshot() -> void:
	var fixture := await _refresh_mutation_fixture("mutate_once")
	var player: RefreshMutationPlayer = fixture.player
	var choice: ItemChoice = fixture.choice
	var original: RewardOffer = fixture.original
	var other: RewardOffer = fixture.other
	GameState.add_temporal_echoes(1)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(other.options.size(), 2)
	assert_same(choice._offer, original)
	assert_eq(choice._buttons.size(), 1)
	assert_true(choice._buttons[0].disabled)
	assert_true(choice._buttons[0].text.contains("INDISP"))
	assert_false(choice._refreshing)
	assert_false(choice._refresh_deferred_queued)
	choice._choose(0)
	assert_eq(player.buy_calls, 0); assert_eq(player.acquire_calls, 0)
	assert_false(original.claimed); assert_eq(GameState.temporal_echoes, 7)

func test_failed_buy_refresh_mutation_invalidates_retry_without_reentry() -> void:
	var fixture := await _refresh_mutation_fixture("buy_failure_mutate")
	var player: RefreshMutationPlayer = fixture.player
	var choice: ItemChoice = fixture.choice
	var original: RewardOffer = fixture.original
	player.buy_result = false
	choice._choose(0)
	assert_eq(player.buy_calls, 1); assert_eq(player.buy_costs, [6]); assert_eq(player.acquire_calls, 0)
	assert_false(original.claimed); assert_same(choice._offer, original)
	assert_false(choice._choosing); assert_false(choice._refreshing)
	await get_tree().process_frame
	assert_true(choice._buttons[0].disabled)
	assert_true(choice._buttons[0].text.contains("INDISP"))
	choice._choose(0)
	assert_eq(player.buy_calls, 1)

func test_refresh_coalesces_one_balance_signal_during_can_acquire() -> void:
	var fixture := await _refresh_mutation_fixture("emit_once", 5)
	var player: RefreshMutationPlayer = fixture.player
	var choice: ItemChoice = fixture.choice
	player.armed = true
	var connections := GameState.temporal_echoes_changed.get_connections().filter(func(c): return c.callable == Callable(choice, &"_on_temporal_echoes_changed"))
	assert_eq(connections.size(), 1)
	choice._refresh()
	await get_tree().process_frame
	assert_true(choice._title.text.contains("ECOS: 6"))
	assert_false(choice._buttons[0].disabled)
	assert_true(choice._buttons[0].text.contains("(6 ECOS)"))
	assert_eq(player.can_calls, 3)
	assert_false(choice._refreshing); assert_false(choice._refresh_deferred_queued)

func test_persistent_balance_callback_is_bounded_to_one_followup() -> void:
	var fixture := await _refresh_mutation_fixture("emit_every", 5)
	var player: RefreshMutationPlayer = fixture.player
	var choice: ItemChoice = fixture.choice
	var before := player.can_calls
	choice._refresh()
	for _i in 5: await get_tree().process_frame
	assert_eq(player.can_calls - before, 2)
	assert_false(choice._refreshing)
	assert_false(choice._refresh_deferred_queued)
	var stable_calls := player.can_calls
	for _i in 3: await get_tree().process_frame
	assert_eq(player.can_calls, stable_calls)

func _destructive_refresh_fixture(mode: String, arm := true, paid := true) -> Dictionary:
	var player := DestructiveRefreshPlayer.new(); add_child_autofree(player)
	var choice := CHOICE_SCRIPT.new() as ItemChoice; add_child_autofree(choice)
	var offer := _offer(_local_item(&"destructive_refresh"), paid, [6])
	player.choice = choice; player.mode = mode; player.armed = arm
	if mode == "reparent_title":
		player.title_host = Node.new(); add_child_autofree(player.title_host)
	GameState.temporal_echoes = 6
	choice.open_offer(offer, player)
	return {"player": player, "choice": choice, "offer": offer}

func test_refresh_callback_free_button_rebuilds_safely_and_does_not_claim() -> void:
	var fixture := _destructive_refresh_fixture("free_button")
	var player: DestructiveRefreshPlayer = fixture.player
	var choice: ItemChoice = fixture.choice
	var offer: RewardOffer = fixture.offer
	assert_eq(player.can_calls, 1)
	assert_eq(player.acquire_calls, 0); assert_eq(player.buy_calls, 0)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(player.can_calls <= 2)
	assert_false(offer.claimed); assert_eq(GameState.temporal_echoes, 6)
	assert_false(choice._refreshing); assert_false(choice._refresh_deferred_queued)
	choice._choose(0)
	assert_eq(player.acquire_calls, 0); assert_eq(player.buy_calls, 0); assert_false(offer.claimed)

func test_refresh_callback_queue_free_title_is_safe_and_rebuild_is_coalesced() -> void:
	var fixture := _destructive_refresh_fixture("queue_title")
	var player: DestructiveRefreshPlayer = fixture.player
	var choice: ItemChoice = fixture.choice
	var offer: RewardOffer = fixture.offer
	assert_eq(player.can_calls, 1)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(player.can_calls <= 2)
	assert_false(offer.claimed); assert_false(choice._refreshing)
	assert_false(choice._rebuild_deferred_queued); assert_false(choice._refresh_deferred_queued)

func test_refresh_callback_reparent_title_fails_closed_without_rebuild_loop() -> void:
	var fixture := _destructive_refresh_fixture("reparent_title")
	var player: DestructiveRefreshPlayer = fixture.player
	var choice: ItemChoice = fixture.choice
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(player.can_calls <= 2)
	assert_false(choice._refreshing); assert_false(choice._rebuild_deferred_queued)
	assert_true(choice._buttons.is_empty() or choice._buttons[0].disabled)

func test_refresh_callback_queue_free_player_disables_offer_without_acquire_or_claim() -> void:
	var fixture := _destructive_refresh_fixture("queue_player")
	var choice: ItemChoice = fixture.choice
	var offer: RewardOffer = fixture.offer
	await get_tree().process_frame
	assert_false(offer.claimed); assert_true(choice.visible)
	assert_true(choice._buttons[0].disabled)

func test_choose_can_acquire_queue_free_player_never_buys_or_debits() -> void:
	var fixture := _destructive_refresh_fixture("queue_player", false)
	var player: DestructiveRefreshPlayer = fixture.player
	var choice: ItemChoice = fixture.choice
	var offer: RewardOffer = fixture.offer
	player.armed = false
	await get_tree().process_frame
	player.armed = true
	choice._choose(0)
	assert_eq(player.buy_calls, 0); assert_eq(player.acquire_calls, 0)
	assert_false(offer.claimed); assert_eq(GameState.temporal_echoes, 6)

func test_choose_can_acquire_free_title_fails_closed_without_acquire_or_claim() -> void:
	var fixture := _destructive_refresh_fixture("queue_title", false, false)
	var player: DestructiveRefreshPlayer = fixture.player
	var choice: ItemChoice = fixture.choice
	var offer: RewardOffer = fixture.offer
	await get_tree().process_frame
	player.armed = true
	choice._choose(0)
	assert_eq(player.buy_calls, 0)
	assert_eq(player.acquire_calls, 0)
	assert_false(offer.claimed)
	assert_false(choice._choosing)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(choice._choosing)
	assert_true(choice._buttons.is_empty() or choice._buttons[0].disabled)

func test_choose_can_acquire_paid_title_fails_closed_without_payment_or_claim() -> void:
	var fixture := _destructive_refresh_fixture("queue_title", false, true)
	var player: DestructiveRefreshPlayer = fixture.player
	var choice: ItemChoice = fixture.choice
	var offer: RewardOffer = fixture.offer
	await get_tree().process_frame
	player.armed = true
	choice._choose(0)
	assert_eq(player.buy_calls, 0)
	assert_eq(player.acquire_calls, 0)
	assert_false(offer.claimed)
	assert_eq(GameState.temporal_echoes, 6)
	assert_false(choice._choosing)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(choice._choosing)
	assert_true(choice._buttons.is_empty() or choice._buttons[0].disabled)

func test_choose_can_acquire_paid_button_fails_closed_without_payment_or_claim() -> void:
	var fixture := _destructive_refresh_fixture("free_button", false, true)
	var player: DestructiveRefreshPlayer = fixture.player
	var choice: ItemChoice = fixture.choice
	var offer: RewardOffer = fixture.offer
	await get_tree().process_frame
	var before_generation := choice._ui_generation
	player.armed = true
	choice._choose(0)
	assert_eq(player.buy_calls, 0)
	assert_eq(player.acquire_calls, 0)
	assert_false(offer.claimed)
	assert_eq(GameState.temporal_echoes, 6)
	assert_false(choice._choosing)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(choice._rebuild_deferred_queued)
	assert_true(choice._ui_generation <= before_generation + 1)
	assert_true(choice._buttons.is_empty() or choice._buttons[0].disabled)

func test_choose_pre_callback_queue_free_title_fails_closed_without_payment_or_claim() -> void:
	var fixture := _destructive_refresh_fixture("queue_title", false, true)
	var player: DestructiveRefreshPlayer = fixture.player
	var choice: ItemChoice = fixture.choice
	var offer: RewardOffer = fixture.offer
	await get_tree().process_frame
	var before_generation := choice._ui_generation
	var before_can_calls := player.can_calls
	choice._title.queue_free()
	choice._choose(0)
	assert_eq(player.can_calls, before_can_calls)
	assert_eq(player.buy_calls, 0)
	assert_eq(player.acquire_calls, 0)
	assert_false(offer.claimed)
	assert_eq(GameState.temporal_echoes, 6)
	assert_false(choice._choosing)
	await get_tree().process_frame
	await get_tree().process_frame
	var new_generation := choice._ui_generation
	assert_eq(new_generation, before_generation + 1)
	assert_false(choice._rebuild_deferred_queued)
	assert_eq(choice._terminal_invalidated_generation, new_generation)
	assert_false(choice._choosing)
	assert_false(choice._buttons.is_empty())
	assert_eq(choice._buttons.size(), offer.options.size())
	for button in choice._buttons:
		assert_true(button.disabled)

func test_persistent_ui_destruction_has_bounded_refresh_work() -> void:
	var fixture := _destructive_refresh_fixture("persistent_button")
	var player: DestructiveRefreshPlayer = fixture.player
	var choice: ItemChoice = fixture.choice
	var before := player.can_calls
	for _i in 6: await get_tree().process_frame
	assert_true(player.can_calls - before <= 1)
	assert_false(choice._refreshing); assert_false(choice._refresh_deferred_queued)
