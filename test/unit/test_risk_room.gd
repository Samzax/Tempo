extends GutTest

const RISK := preload("res://resources/loot/risk_pool.tres")
const TREASURE := preload("res://resources/loot/treasure_pool.tres")
const RISK_CHEST := preload("res://scripts/loot/reward_chest.gd")

class RiskPlayer extends Node:
	var can_take := true
	var hp := 2.0
	var luck_calls := 0
	var can_calls := 0
	var spend_calls := 0
	var chest: RewardChest
	var reenter := false
	var mutation := ""
	var external_counts: Dictionary = {}

	func get_luck() -> float:
		luck_calls += 1
		return 0.0

	func can_acquire_item(_item: ItemDef) -> bool:
		can_calls += 1
		if not external_counts.is_empty(): external_counts.can_calls = can_calls
		if reenter and chest != null:
			chest.open_offer()
		if mutation == "queue_free":
			can_take = false
			queue_free()
		if mutation == "node": chest.node_id = 99
		if mutation == "pool": chest.pool = TREASURE
		return can_take

	func try_spend_health(amount: float, minimum: float = 1.0) -> bool:
		spend_calls += 1
		if not external_counts.is_empty(): external_counts.spend_calls = spend_calls
		if hp < amount + minimum: return false
		hp -= amount
		return true

class RiskDirector extends Node:
	signal enemy_spawned(enemy: Enemy)
	signal spawns_finished
	signal spawns_failed(reason: String)
	func start(_limit: int) -> bool: return true

func _risk_fixture(existing: RewardOffer = null, player_slot: int = 0, reward_index: int = 0) -> Dictionary:
	var root := Node2D.new(); add_child_autofree(root)
	var director := RiskDirector.new(); director.name = "Director"; root.add_child(director)
	var controller := RoomController.new(); controller.name = "RoomController"; controller.room_def = RoomDef.new(); controller.director_path = ^"../Director"; root.add_child(controller)
	var player := RiskPlayer.new(); player.name = "Player"; root.add_child(player)
	var counts := {"can_calls": 0, "spend_calls": 0}
	player.external_counts = counts
	var chest := RISK_CHEST.new() as RewardChest
	chest.room_controller_path = ^"../RoomController"; chest.player_path = ^"../Player"; root.add_child(chest)
	chest.configure(player, 2, 24, player_slot, reward_index, RISK, existing, false, true)
	player.chest = chest
	return {"root": root, "controller": controller, "player": player, "chest": chest, "counts": counts}

func _invalid_offer(kind: String) -> RewardOffer:
	var offer := _valid_risk_offer()
	match kind:
		"pool": offer.pool_id = &"treasure"
		"identity": offer.node_id = 999
		"short": offer.options = offer.options.slice(0, 2)
		"duplicate": offer.options[1] = offer.options[0]
		"common":
			offer.options[0] = offer.options[0].duplicate(true)
			offer.options[0].rarity = ItemDef.Rarity.COMMON
		"null": offer.options[0] = null
	return offer

func _valid_risk_offer() -> RewardOffer:
	RunManager.seed_value = 12345
	return LootRoller.roll_offer(RISK, 12345, 2, 24, 0, 0)

func test_room_and_node_ordinals_append_risk_at_four() -> void:
	assert_eq(SectorNode.NodeType.OPENING, 0); assert_eq(SectorNode.NodeType.COMBAT, 1)
	assert_eq(SectorNode.NodeType.BOSS, 2); assert_eq(SectorNode.NodeType.TREASURE, 3)
	assert_eq(SectorNode.NodeType.RISK, 4)
	assert_eq(RoomDef.RoomType.OPENING, 0); assert_eq(RoomDef.RoomType.COMBAT, 1)
	assert_eq(RoomDef.RoomType.BOSS, 2); assert_eq(RoomDef.RoomType.TREASURE, 3)
	assert_eq(RoomDef.RoomType.RISK, 4)

func test_sector_two_risk_is_id_24_and_preserves_profile_and_dag() -> void:
	for sector_index in [0, 1, 2]:
		var sector := SectorGenerator.generate(77, sector_index)
		var lower: SectorNode = sector.get_node(sector_index * 10 + 4)
		var upper: SectorNode = sector.get_node(sector_index * 10 + 3)
		if sector_index == 2:
			assert_eq(lower.id, 24); assert_eq(lower.node_type, SectorNode.NodeType.RISK)
			assert_eq(lower.room_profile, &"default"); assert_eq(sector.get_children(24), [25])
			assert_eq(sector.get_children(25), [26]); assert_eq(upper.node_type, SectorNode.NodeType.TREASURE)
		else:
			assert_eq(lower.node_type, SectorNode.NodeType.COMBAT)
			assert_eq(upper.node_type, SectorNode.NodeType.COMBAT)

func test_session_maps_risk_to_empty_room_and_risk_pool() -> void:
	var session := Session.new(); autofree(session)
	var node := SectorNode.new(); node.id = 24; node.node_type = SectorNode.NodeType.RISK
	var def := session._room_def_for(node)
	assert_eq(def.room_type, RoomDef.RoomType.RISK)
	assert_eq(def.finite_spawn_count, 0); assert_false(def.has_waves()); assert_eq(def.initial_debris.size(), 0)
	assert_same(session._pool_for(node), RISK)

func test_treasure_mapping_remains_treasure() -> void:
	var session := Session.new(); autofree(session)
	var node := SectorNode.new(); node.id = 23; node.node_type = SectorNode.NodeType.TREASURE
	assert_eq(session._room_def_for(node).room_type, RoomDef.RoomType.TREASURE)
	assert_same(session._pool_for(node), TREASURE)

func test_risk_hyperspace_label_and_fallback() -> void:
	var ui := HyperspaceUI.new(); add_child_autofree(ui)
	assert_eq(ui._label_for_node_type(SectorNode.NodeType.RISK), "RISCO")
	assert_eq(ui._label_for_node_type(999), "COMBATE")

func test_risk_unlock_is_available_without_creating_offer() -> void:
	var f := _risk_fixture(); var chest: RewardChest = f.chest; var controller: RoomController = f.controller
	watch_signals(chest); await get_tree().process_frame
	controller.room_cleared.emit(); chest._unlock()
	assert_true(chest._available); assert_null(controller.runtime.reward_offer); assert_signal_not_emitted(chest, &"offer_created")

func test_normal_unlock_still_creates_default_offer() -> void:
	var f := _risk_fixture()
	var chest: RewardChest = f.chest
	chest._risk_mode = false
	chest._unlock()
	assert_true(chest._available)
	assert_not_null(f.controller.runtime.reward_offer)

func test_risk_success_spends_once_stores_and_emits_created_before_requested() -> void:
	var f := _risk_fixture(); var chest: RewardChest = f.chest; var controller: RoomController = f.controller; var player: RiskPlayer = f.player
	await get_tree().process_frame; chest._unlock(); var order: Array[String] = []
	chest.offer_created.connect(func(offer): order.append("created"); assert_same(controller.runtime.reward_offer, offer))
	chest.offer_requested.connect(func(offer, who): order.append("requested"); assert_same(who, player); assert_same(offer, controller.runtime.reward_offer))
	chest.open_offer()
	var offer: RewardOffer = controller.runtime.reward_offer
	assert_not_null(offer); assert_eq(player.hp, 1.0); assert_eq(player.spend_calls, 1); assert_eq(offer.options.size(), 3)
	assert_eq(offer.pool_id, &"risk"); assert_eq(offer.sector_index, 2); assert_eq(offer.node_id, 24); assert_eq(offer.player_slot, 0); assert_eq(offer.reward_index, 0)
	assert_false(offer.paid_with_temporal_echoes); assert_true(offer.option_costs.is_empty()); assert_eq(order, ["created"]); assert_true(chest._activating)
	await get_tree().process_frame
	assert_eq(order, ["created", "requested"])
	await get_tree().process_frame
	assert_false(chest._activating)

func test_risk_insufficient_hp_fails_closed_and_reopen_does_not_reroll() -> void:
	var f := _risk_fixture(); var chest: RewardChest = f.chest; var player: RiskPlayer = f.player; player.hp = 1.0
	await get_tree().process_frame; chest._unlock(); watch_signals(chest); chest.open_offer(); chest.open_offer()
	assert_null(f.controller.runtime.reward_offer); assert_eq(player.spend_calls, 2); assert_signal_not_emitted(chest, &"offer_created"); assert_signal_not_emitted(chest, &"offer_requested"); assert_false(chest._activating)

func test_risk_stored_valid_offer_is_reused_without_roll_or_spend() -> void:
	var stored := _valid_risk_offer(); var f := _risk_fixture(stored); var chest: RewardChest = f.chest; var player: RiskPlayer = f.player
	await get_tree().process_frame; chest._unlock(); watch_signals(chest); chest.open_offer()
	assert_same(f.controller.runtime.reward_offer, stored); assert_eq(player.luck_calls, 0); assert_eq(player.can_calls, 0); assert_eq(player.spend_calls, 0); assert_signal_emit_count(chest, &"offer_requested", 1); assert_true(chest._activating)
	await get_tree().process_frame
	assert_false(chest._activating)

func test_risk_reopen_after_success_reuses_offer_and_requests_once_more() -> void:
	var f := _risk_fixture()
	var chest: RewardChest = f.chest
	var player: RiskPlayer = f.player
	var counts := {"created": 0, "requested": 0}
	chest.offer_created.connect(func(_offer): counts.created += 1)
	chest.offer_requested.connect(func(_offer, _player): counts.requested += 1)
	await get_tree().process_frame
	chest._unlock()
	chest.open_offer()
	var stored: RewardOffer = f.controller.runtime.reward_offer
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(counts.created, 1)
	assert_eq(counts.requested, 1)
	assert_false(chest._activating)
	chest.open_offer()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_same(f.controller.runtime.reward_offer, stored)
	assert_eq(player.spend_calls, 1)
	assert_eq(player.luck_calls, 1)
	assert_eq(player.can_calls, 3)
	assert_eq(counts.created, 1)
	assert_eq(counts.requested, 2)
	await get_tree().process_frame

func test_risk_stored_claimed_offer_has_no_effects() -> void:
	var stored := _valid_risk_offer()
	stored.claimed = true
	var f := _risk_fixture(stored)
	var chest: RewardChest = f.chest
	var player: RiskPlayer = f.player
	await get_tree().process_frame
	chest._unlock()
	chest.open_offer()
	assert_same(f.controller.runtime.reward_offer, stored)
	assert_eq(f.counts.spend_calls, 0)
	assert_eq(player.can_calls, 0)
	assert_eq(player.luck_calls, 0)

func test_risk_malformed_stored_offers_are_preserved_without_effects() -> void:
	for kind in ["pool", "identity", "short", "duplicate", "common", "null"]:
		var stored := _invalid_offer(kind)
		var f := _risk_fixture(stored)
		var chest: RewardChest = f.chest
		var player: RiskPlayer = f.player
		await get_tree().process_frame
		chest._unlock()
		chest.open_offer()
		assert_same(f.controller.runtime.reward_offer, stored, kind)
		assert_false(stored.claimed, kind)
		assert_eq(player.spend_calls, 0, kind)
		assert_eq(player.can_calls, 0, kind)
		assert_eq(player.luck_calls, 0, kind)
		for entry: ItemPoolEntry in RISK.entries:
			assert_eq(entry.item.rarity, ItemDef.Rarity.RARE, kind)

func test_risk_null_pool_wrong_pool_and_short_eligibility_fail_closed() -> void:
	for mode in ["null", "wrong", "short"]:
		var f := _risk_fixture()
		var chest: RewardChest = f.chest
		var player: RiskPlayer = f.player
		if mode == "null":
			chest.pool = null
		elif mode == "wrong":
			chest.pool = TREASURE
		else:
			player.can_take = false
		await get_tree().process_frame
		chest._unlock()
		watch_signals(chest)
		chest.open_offer()
		assert_null(f.controller.runtime.reward_offer, mode)
		assert_eq(player.spend_calls, 0, mode)
		assert_signal_emit_count(chest, &"offer_created", 0)
		assert_signal_emit_count(chest, &"offer_requested", 0)
		assert_false(chest._activating)

func test_risk_reentry_during_can_acquire_is_locked() -> void:
	var f := _risk_fixture()
	var chest: RewardChest = f.chest
	var player: RiskPlayer = f.player
	player.reenter = true
	await get_tree().process_frame
	chest._unlock()
	chest.open_offer()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(player.spend_calls, 1)
	assert_eq(player.can_calls, 3)
	assert_eq(f.controller.runtime.reward_offer != null, true)
	assert_eq(chest._activating, false)

func test_risk_reentry_from_signals_does_not_duplicate_request_or_creation() -> void:
	var f := _risk_fixture()
	var chest: RewardChest = f.chest
	var player: RiskPlayer = f.player
	var counts := {"created": 0, "requested": 0}
	chest.offer_created.connect(func(_offer):
		counts.created += 1
		chest.open_offer()
	)
	chest.offer_requested.connect(func(_offer, _who):
		counts.requested += 1
		chest.open_offer()
	)
	await get_tree().process_frame
	chest._unlock()
	chest.open_offer()
	await get_tree().process_frame
	assert_eq(player.spend_calls, 1)
	assert_eq(counts.created, 1)
	assert_eq(counts.requested, 1)

func test_risk_queue_free_during_can_acquire_has_no_orphan_effects() -> void:
	var f := _risk_fixture()
	var chest: RewardChest = f.chest
	var player: RiskPlayer = f.player
	player.reenter = false
	player.mutation = "queue_free"
	player.can_take = true
	await get_tree().process_frame
	chest._unlock()
	chest.open_offer()
	await get_tree().process_frame
	assert_eq(f.counts.can_calls, 1)
	assert_null(f.controller.runtime.reward_offer)
	assert_eq(f.counts.spend_calls, 0)
	assert_false(chest._activating)

func test_risk_missing_player_methods_and_null_player_have_no_effects() -> void:
	for mode in ["missing_methods", "null_player"]:
		var f := _risk_fixture()
		var chest: RewardChest = f.chest
		if mode == "null_player":
			chest.configure(null, 2, 24, 0, 0, RISK, null, false, true)
		else:
			var candidate := Node.new()
			add_child_autofree(candidate)
			chest.configure(candidate, 2, 24, 0, 0, RISK, null, false, true)
		await get_tree().process_frame
		chest._unlock()
		chest.open_offer()
		assert_null(f.controller.runtime.reward_offer, mode)
		assert_false(chest._activating, mode)

func test_risk_success_preserves_nonzero_identity_and_exact_rare_options() -> void:
	var f := _risk_fixture(null, 2, 7)
	var chest: RewardChest = f.chest
	await get_tree().process_frame
	chest._unlock()
	chest.open_offer()
	var offer: RewardOffer = f.controller.runtime.reward_offer
	assert_eq(offer.sector_index, 2)
	assert_eq(offer.node_id, 24)
	assert_eq(offer.player_slot, 2)
	assert_eq(offer.reward_index, 7)
	assert_eq(offer.options.size(), 3)
	var ids: Array[StringName] = []
	for item: ItemDef in offer.options:
		ids.append(item.id)
		assert_true(item.rarity == ItemDef.Rarity.RARE or item.rarity == ItemDef.Rarity.LEGENDARY)
	assert_eq(ids.size(), 3)
	assert_eq(ids[0] != ids[1], true)
	assert_eq(ids[0] != ids[2], true)
	assert_eq(ids[1] != ids[2], true)

func test_risk_snapshot_mutation_aborts_before_spend() -> void:
	for mutation in ["node", "pool"]:
		var f := _risk_fixture(); var chest: RewardChest = f.chest; var player: RiskPlayer = f.player; player.mutation = mutation
		await get_tree().process_frame; chest._unlock(); chest.open_offer()
		assert_null(f.controller.runtime.reward_offer); assert_eq(player.spend_calls, 0); assert_false(chest._activating)

func test_stored_offer_requested_reentry_is_bounded() -> void:
	var stored := _valid_risk_offer(); var f := _risk_fixture(stored); var chest: RewardChest = f.chest; var player: RiskPlayer = f.player
	var requests := {"n": 0}
	chest.offer_requested.connect(func(_offer, _who): requests.n += 1; chest.open_offer(); assert_true(chest._activating))
	await get_tree().process_frame; chest._unlock(); chest.open_offer()
	assert_eq(requests.n, 1); assert_eq(player.spend_calls, 0); assert_eq(player.luck_calls, 0); assert_eq(player.can_calls, 0)
	await get_tree().process_frame; assert_false(chest._activating)
	chest.open_offer(); assert_eq(requests.n, 2)

func test_stored_wrong_seed_fails_closed_without_mutating_runtime() -> void:
	RunManager.seed_value = 12345
	var stored := _valid_risk_offer(); RunManager.seed_value = 67890
	var f := _risk_fixture(stored); var chest: RewardChest = f.chest; var player: RiskPlayer = f.player
	await get_tree().process_frame; chest._unlock(); chest.open_offer(); await get_tree().process_frame
	assert_same(f.controller.runtime.reward_offer, stored); assert_eq(player.spend_calls, 0); assert_eq(player.luck_calls, 0); assert_eq(player.can_calls, 0); assert_false(chest._activating)

func test_stored_three_rare_external_ids_fail_closed() -> void:
	var stored := _valid_risk_offer()
	var items: Array[ItemDef] = []
	for i in 3:
		var item := ItemDef.new(); item.id = StringName("external_risk_%d" % i); item.rarity = ItemDef.Rarity.RARE; items.append(item)
	stored.options = items
	var f := _risk_fixture(stored); var chest: RewardChest = f.chest; var player: RiskPlayer = f.player
	await get_tree().process_frame; chest._unlock(); chest.open_offer(); await get_tree().process_frame
	assert_same(f.controller.runtime.reward_offer, stored); assert_eq(player.spend_calls, 0); assert_eq(player.luck_calls, 0); assert_eq(player.can_calls, 0)

func test_created_listener_queue_free_controller_stops_request_only() -> void:
	var f := _risk_fixture(); var chest: RewardChest = f.chest; var created := {"n": 0}; var requested := {"n": 0}
	chest.offer_created.connect(func(_offer): created.n += 1; f.controller.queue_free())
	chest.offer_requested.connect(func(_offer, _who): requested.n += 1)
	await get_tree().process_frame; chest._unlock(); chest.open_offer(); await get_tree().process_frame; await get_tree().process_frame
	assert_eq(created.n, 1); assert_eq(requested.n, 0); assert_eq(f.counts.spend_calls, 1); assert_false(chest._activating)

func test_created_listener_queue_free_chest_invalidates_continuation() -> void:
	var f := _risk_fixture(); var chest: RewardChest = f.chest; var player: RiskPlayer = f.player; var created := {"n": 0}
	chest.offer_created.connect(func(_offer): created.n += 1; chest.queue_free())
	await get_tree().process_frame; chest._unlock(); chest.open_offer(); await get_tree().process_frame; await get_tree().process_frame
	assert_eq(created.n, 1); assert_eq(player.spend_calls, 1); assert_true(is_instance_valid(f.controller.runtime.reward_offer))

func test_created_listener_queue_free_player_stops_request_only() -> void:
	var f := _risk_fixture(); var chest: RewardChest = f.chest; var player: RiskPlayer = f.player; var counts := {"created": 0, "requested": 0}
	chest.offer_created.connect(func(_offer): counts.created += 1; player.queue_free())
	chest.offer_requested.connect(func(_offer, _who): counts.requested += 1)
	await get_tree().process_frame; chest._unlock(); chest.open_offer(); await get_tree().process_frame; await get_tree().process_frame
	assert_eq(counts.created, 1); assert_eq(counts.requested, 0); assert_eq(f.counts.spend_calls, 1); assert_true(is_instance_valid(f.chest)); assert_false(chest._activating)

func test_created_listener_mutation_aborts_request_without_rollback() -> void:
	var f := _risk_fixture(); var chest: RewardChest = f.chest; var counts := {"created": 0, "requested": 0}
	chest.offer_created.connect(func(_offer): counts.created += 1; f.controller.runtime.reward_offer.claimed = true)
	chest.offer_requested.connect(func(_offer, _who): counts.requested += 1)
	await get_tree().process_frame; chest._unlock(); chest.open_offer(); await get_tree().process_frame; await get_tree().process_frame
	assert_eq(counts.created, 1); assert_eq(counts.requested, 0); assert_eq(f.counts.spend_calls, 1); assert_false(chest._activating)

func test_requested_listener_queue_free_chest_has_one_request() -> void:
	var f := _risk_fixture(); var chest: RewardChest = f.chest; var requested := {"n": 0}
	chest.offer_requested.connect(func(_offer, _who): requested.n += 1; chest.queue_free())
	await get_tree().process_frame; chest._unlock(); chest.open_offer(); await get_tree().process_frame; await get_tree().process_frame
	assert_eq(requested.n, 1); assert_eq(f.counts.spend_calls, 1)

func test_requested_listener_queue_free_chest_stored_is_not_recursive() -> void:
	var stored := _valid_risk_offer(); var f := _risk_fixture(stored); var chest: RewardChest = f.chest; var requested := {"n": 0}
	chest.offer_requested.connect(func(_offer, _who): requested.n += 1; chest.queue_free())
	await get_tree().process_frame; chest._unlock(); chest.open_offer(); await get_tree().process_frame; await get_tree().process_frame
	assert_eq(requested.n, 1); assert_eq(f.player.spend_calls, 0); assert_eq(f.player.can_calls, 0)

func test_risk_pool_membership_validation_is_read_only() -> void:
	var before: Array[StringName] = []
	for entry: ItemPoolEntry in RISK.entries: before.append(entry.item.id)
	var f := _risk_fixture(); var chest: RewardChest = f.chest
	await get_tree().process_frame; chest._unlock(); chest.open_offer(); await get_tree().process_frame
	var after: Array[StringName] = []
	for entry: ItemPoolEntry in RISK.entries: after.append(entry.item.id)
	assert_eq(after, before)
