extends GutTest

const COMBAT := preload("res://resources/loot/combat_pool.tres")
const ELITE := preload("res://resources/loot/elite_pool.tres")
const RISK := preload("res://resources/loot/risk_pool.tres")
const BOSS := preload("res://resources/loot/boss_pool.tres")

class FakePlayer extends Node:
	var available := true
	var acquire_calls := 0
	var eligibility_calls := 0
	var acquired: Array[ItemDef] = []

	func get_luck() -> float:
		return 0.0

	func can_acquire_item(_item: ItemDef) -> bool:
		eligibility_calls += 1
		return available

	func acquire_item(item: ItemDef) -> bool:
		acquire_calls += 1
		if not available:
			return false
		acquired.append(item)
		return true

class FakeDirector extends Node:
	signal enemy_spawned(enemy: Enemy)
	signal spawns_finished
	signal spawns_failed(reason: String)

	func start(_spawn_limit: int) -> bool:
		return true

func _reward_chest_fixture(existing_offer: RewardOffer = null) -> Dictionary:
	var root := Node2D.new()
	add_child_autofree(root)
	var director := FakeDirector.new()
	director.name = "Director"
	root.add_child(director)
	var controller := RoomController.new()
	controller.name = "RoomController"
	controller.room_def = RoomDef.new()
	controller.director_path = ^"../Director"
	root.add_child(controller)
	var player := FakePlayer.new()
	player.name = "Player"
	root.add_child(player)
	var chest := preload("res://scripts/loot/reward_chest.gd").new()
	chest.room_controller_path = ^"../RoomController"
	chest.player_path = ^"../Player"
	if existing_offer == null:
		chest.pool = COMBAT
	else:
		chest.configure(player, 0, 0, 0, 0, COMBAT, existing_offer)
	root.add_child(chest)
	return {"root": root, "director": director, "controller": controller, "player": player, "chest": chest}

func _ids(offer: RewardOffer) -> Array[StringName]:
	var result: Array[StringName] = []
	for item in offer.options:
		result.append(item.id)
	return result

func _pool(ids: Array[StringName]) -> ItemPoolDef:
	var pool := ItemPoolDef.new()
	pool.id = &"test"
	for id in ids:
		var entry := ItemPoolEntry.new()
		entry.item = ItemCatalog.get_item(id)
		entry.base_weight = 1.0
		pool.entries.append(entry)
	return pool

func test_mixer_fixed_vector_is_stable_and_tuple_components_are_independent() -> void:
	var fixed := LootRoller._mix_tuple(123456789, 7, 19, 2, 4)
	assert_eq(fixed, 1846497774)
	assert_eq(fixed, LootRoller._mix_tuple(123456789, 7, 19, 2, 4))
	assert_ne(fixed, LootRoller._mix_tuple(123456789, 7, 19, 3, 4))
	assert_ne(fixed, LootRoller._mix_tuple(123456789, 7, 20, 2, 4))
	assert_ne(fixed, LootRoller._mix_tuple(123456789, 7, 19, 2, 5))
	assert_ne(fixed, LootRoller._mix_tuple(123456789, 8, 19, 2, 4))

func test_roll_is_deterministic_and_does_not_consume_run_manager_rng() -> void:
	RunManager.start_run(9123)
	var before := RunManager.rng.randf()
	RunManager.start_run(9123)
	var first := LootRoller.roll_offer(COMBAT, 44, 2, 8, 0, 1)
	var after := RunManager.rng.randf()
	RunManager.start_run(9123)
	assert_eq(_ids(first), _ids(LootRoller.roll_offer(COMBAT, 44, 2, 8, 0, 1)))
	assert_eq(before, after)

func test_negative_luck_matches_zero_and_rarity_bonus_is_nonnegative() -> void:
	var zero := LootRoller.roll_offer(_pool([&"convergencia", &"cronometro_perfeito", &"estilhaco"]), 9, 1, 1, 0, 0, 0.0)
	var negative := LootRoller.roll_offer(_pool([&"convergencia", &"cronometro_perfeito", &"estilhaco"]), 9, 1, 1, 0, 0, -100.0)
	assert_eq(_ids(zero), _ids(negative))
	for rarity in [ItemDef.Rarity.COMMON, ItemDef.Rarity.RARE, ItemDef.Rarity.LEGENDARY]:
		assert_gte(LootRoller._rarity_bonus(rarity), 0.0)

func test_nonpositive_weights_are_excluded_and_offer_has_no_duplicates() -> void:
	var pool := _pool([&"convergencia", &"cronometro_perfeito", &"estilhaco"])
	pool.entries[0].base_weight = 0.0
	pool.entries[1].base_weight = -2.0
	var offer := LootRoller.roll_offer(pool, 1, 1, 1, 1, 1)
	assert_eq(offer.options.size(), 1)
	assert_eq(offer.options[0].id, &"estilhaco")

func test_three_or_more_eligible_items_are_distinct_and_small_pool_is_smaller() -> void:
	var three := LootRoller.roll_offer(_pool([&"convergencia", &"cronometro_perfeito", &"estilhaco"]), 1, 1, 1, 1, 1)
	assert_eq(three.options.size(), 3)
	var ids := _ids(three)
	assert_ne(ids[0], ids[1])
	assert_ne(ids[0], ids[2])
	assert_ne(ids[1], ids[2])
	var one := LootRoller.roll_offer(_pool([&"convergencia"]), 1, 1, 1, 1, 1)
	assert_eq(one.options.size(), 1)
	var empty := LootRoller.roll_offer(ItemPoolDef.new(), 1, 1, 1, 1, 1)
	assert_eq(empty.options.size(), 0)

func test_eligibility_callable_default_or_invalid_preserves_legacy_offer() -> void:
	# Legado (commit 358d7705): tuple (33, 2, 4, 1, 8), pool
	# [convergencia, cronometro_perfeito, estilhaco] => [cronometro_perfeito, estilhaco, convergencia].
	var pool := _pool([&"convergencia", &"cronometro_perfeito", &"estilhaco"])
	var expected: Array[StringName] = [&"cronometro_perfeito", &"estilhaco", &"convergencia"]
	var legacy := LootRoller.roll_offer(pool, 33, 2, 4, 1, 8)
	var default_filter := LootRoller.roll_offer(pool, 33, 2, 4, 1, 8, 0.0, Callable())
	var invalid_object := Object.new()
	var invalid_callable := Callable(invalid_object, &"missing_predicate")
	assert_false(invalid_callable.is_valid())
	var invalid_filter := LootRoller.roll_offer(pool, 33, 2, 4, 1, 8, 0.0, invalid_callable)
	assert_eq(_ids(legacy), expected)
	assert_eq(_ids(default_filter), expected)
	assert_eq(_ids(invalid_filter), expected)
	invalid_object.free()
	assert_false(invalid_callable.is_valid())
	var freed_object_filter := LootRoller.roll_offer(pool, 33, 2, 4, 1, 8, 0.0, invalid_callable)
	assert_eq(_ids(freed_object_filter), expected)

func test_eligibility_filters_before_rng_without_empty_slots() -> void:
	var pool := _pool([&"convergencia", &"cronometro_perfeito", &"estilhaco"])
	var none := LootRoller.roll_offer(pool, 7, 1, 3, 0, 2, 0.0, func(_item: ItemDef) -> bool:
		return false
	)
	var one := LootRoller.roll_offer(pool, 7, 1, 3, 0, 2, 0.0, func(item: ItemDef) -> bool:
		return item.id == &"convergencia"
	)
	var two := LootRoller.roll_offer(pool, 7, 1, 3, 0, 2, 0.0, func(item: ItemDef) -> bool:
		return item.id != &"estilhaco"
	)
	assert_eq(none.options.size(), 0)
	assert_eq(_ids(one), [&"convergencia"])
	assert_eq(two.options.size(), 2)
	assert_false(&"estilhaco" in _ids(two))

func test_eligibility_calls_once_per_intrinsically_valid_entry_and_keeps_first_eligible_duplicate() -> void:
	var pool := ItemPoolDef.new()
	var first := ItemDef.new()
	first.id = &"duplicate_id"
	var second := ItemDef.new()
	second.id = &"duplicate_id"
	var other := ItemCatalog.get_item(&"estilhaco")
	for item in [first, second, other]:
		var entry := ItemPoolEntry.new()
		entry.item = item
		entry.base_weight = 1.0
		pool.entries.append(entry)
	var invalid_weight := ItemPoolEntry.new()
	invalid_weight.item = other
	invalid_weight.base_weight = 0.0
	pool.entries.append(invalid_weight)
	pool.entries.append(null)
	var counter := {"count": 0}
	var offer := LootRoller.roll_offer(pool, 5, 1, 1, 0, 0, 0.0, func(item: ItemDef) -> bool:
		counter.count += 1
		return item != first
	)
	assert_eq(counter.count, 3)
	assert_eq(offer.options.size(), 2)
	var selected_duplicate: ItemDef = null
	for item in offer.options:
		if item.id == first.id:
			selected_duplicate = item
	assert_same(selected_duplicate, second)

func test_eligible_duplicate_aggregates_weight_and_keeps_first_definition() -> void:
	var pool := ItemPoolDef.new()
	var first := ItemDef.new()
	first.id = &"duplicate_id"
	var second := ItemDef.new()
	second.id = &"duplicate_id"
	var other := ItemCatalog.get_item(&"estilhaco")
	for item in [first, second, other]:
		var entry := ItemPoolEntry.new()
		entry.item = item
		entry.base_weight = 1.0
		pool.entries.append(entry)
	var offer := LootRoller.roll_offer(pool, 5, 1, 1, 0, 0, 0.0, func(_item: ItemDef) -> bool:
		return true
	)
	assert_eq(offer.options.size(), 2)
	var selected_duplicate: ItemDef = null
	for item in offer.options:
		if item.id == first.id:
			selected_duplicate = item
	assert_same(selected_duplicate, first)

func test_eligibility_same_state_and_tuple_produce_same_offer() -> void:
	var pool := _pool([&"convergencia", &"cronometro_perfeito", &"estilhaco"])
	var allowed := {&"convergencia": true, &"estilhaco": true}
	var filter := func(item: ItemDef) -> bool:
		return allowed.has(item.id)
	assert_eq(_ids(LootRoller.roll_offer(pool, 91, 4, 2, 1, 3, 0.0, filter)), _ids(LootRoller.roll_offer(pool, 91, 4, 2, 1, 3, 0.0, filter)))

func test_eligibility_coerces_predicate_result_and_skips_intrinsically_invalid_entries() -> void:
	var pool := ItemPoolDef.new()
	var valid := ItemCatalog.get_item(&"convergencia")
	var invalid_item := ItemDef.new()
	var invalid_content := ItemPoolEntry.new()
	invalid_content.item = invalid_item
	invalid_content.base_weight = 1.0
	var invalid_weight := ItemPoolEntry.new()
	invalid_weight.item = valid
	invalid_weight.base_weight = 0.0
	var valid_entry := ItemPoolEntry.new()
	valid_entry.item = valid
	valid_entry.base_weight = 1.0
	pool.entries = [null, invalid_content, invalid_weight, valid_entry]
	var counter := {"count": 0}
	var rejected := LootRoller.roll_offer(pool, 3, 2, 1, 0, 0, 0.0, func(_item: ItemDef):
		counter.count += 1
		return 0
	)
	assert_eq(counter.count, 1)
	assert_eq(rejected.options.size(), 0)
	var accepted := LootRoller.roll_offer(pool, 3, 2, 1, 0, 0, 0.0, func(_item: ItemDef):
		return 1
	)
	assert_eq(_ids(accepted), [&"convergencia"])

func test_pool_candidate_cardinality_is_zero_one_two_or_three_and_invalid_entries_are_ignored() -> void:
	var empty := ItemPoolDef.new()
	var null_entry := ItemPoolEntry.new()
	empty.entries = [null, null_entry]
	assert_eq(LootRoller.roll_offer(empty, 1, 1, 1, 1, 1).options.size(), 0)
	assert_eq(LootRoller.roll_offer(_pool([&"convergencia"]), 1, 1, 1, 1, 1).options.size(), 1)
	assert_eq(LootRoller.roll_offer(_pool([&"convergencia", &"estilhaco"]), 1, 1, 1, 1, 1).options.size(), 2)
	assert_eq(LootRoller.roll_offer(_pool([&"convergencia", &"estilhaco", &"cronometro_perfeito"]), 1, 1, 1, 1, 1).options.size(), 3)

func test_player_can_acquire_item_handles_null_inventory_and_incompatible_statblock() -> void:
	var player := Player.new()
	var item := ItemCatalog.get_item(&"convergencia")
	assert_false(player.can_acquire_item(null))
	assert_false(player.can_acquire_item(item))
	player._inventory = Inventory.new(null, null)
	assert_false(player.can_acquire_item(item))
	var stat_block := StatBlock.new([])
	var dispatcher_root := Node.new()
	add_child_autofree(dispatcher_root)
	var dispatcher := EffectDispatcher.new(dispatcher_root, [])
	player._inventory = Inventory.new(stat_block, dispatcher)
	assert_false(player.can_acquire_item(item))
	player.free()

func test_all_t31_pools_load_with_exact_expected_items_and_positive_entries() -> void:
	var expected := {
		&"combat": [&"nucleo_superaquecido", &"casco_reforcado", &"recarga_fria", &"eco_temporal", &"frenesi"],
		&"elite": [&"reator_instavel", &"lente_de_foco", &"vinganca", &"sanguessuga", &"estilhaco"],
		&"risk": [&"maldicao_do_peso", &"reator_instavel", &"lente_de_foco"],
		&"boss": [&"convergencia", &"cronometro_perfeito", &"estilhaco"]
	}
	for pool in [COMBAT, ELITE, RISK, BOSS]:
		assert_true(expected.has(pool.id))
		var actual: Array[StringName] = []
		for entry in pool.entries:
			assert_not_null(entry)
			assert_not_null(entry.item)
			assert_gt(entry.base_weight, 0.0)
			actual.append(entry.item.id)
		actual.sort()
		var wanted: Array[StringName] = []
		for expected_id in expected[pool.id]:
			wanted.append(expected_id)
		wanted.sort()
		assert_eq(actual, wanted)

func test_offer_identity_serialization_and_room_runtime_keep_same_instance() -> void:
	var offer := LootRoller.roll_offer(COMBAT, 8, 3, 5, 1, 7)
	var restored := offer.duplicate(true) as RewardOffer
	assert_eq(restored.run_seed, 8)
	assert_eq(restored.pool_id, &"combat")
	assert_eq(_ids(restored), _ids(offer))
	restored.claimed = true
	restored.claimed_item_id = restored.options[0].id
	var runtime := RoomRuntime.new()
	runtime.reward_offer = restored
	assert_same(runtime.reward_offer, restored)
	assert_true(runtime.reward_offer.claimed)

func test_item_choice_revalidates_limit_and_acquires_once_only_after_success() -> void:
	var player := FakePlayer.new()
	add_child_autofree(player)
	var choice := preload("res://scripts/ui/item_choice.gd").new()
	add_child_autofree(choice)
	var offer := RewardOffer.new()
	var item := ItemCatalog.get_item(&"convergencia")
	offer.options = [item]
	choice.open_offer(offer, player)
	player.available = false
	choice._choose(0)
	assert_eq(player.acquire_calls, 0)
	assert_false(offer.claimed)
	player.available = true
	choice._choose(0)
	assert_true(offer.claimed)
	assert_eq(player.acquire_calls, 1)
	choice._choose(0)
	assert_eq(player.acquire_calls, 1)
	assert_eq(choice.process_mode, Node.PROCESS_MODE_INHERIT)
	assert_false(get_tree().paused)

func test_reward_chest_unlocks_only_on_clear_and_reuses_runtime_offer() -> void:
	var fixture := _reward_chest_fixture()
	var controller: RoomController = fixture.controller
	var chest: RewardChest = fixture.chest
	await get_tree().process_frame
	watch_signals(chest)
	chest.open_offer()
	assert_signal_not_emitted(chest, &"offer_requested")
	controller.room_cleared.emit()
	chest.open_offer()
	var first: RewardOffer = controller.runtime.reward_offer
	chest.open_offer()
	assert_same(controller.runtime.reward_offer, first)
	assert_signal_emit_count(chest, &"offer_requested", 2)

func test_reward_chest_existing_pending_offer_is_not_filtered_again() -> void:
	var pending := RewardOffer.new()
	pending.options = [ItemCatalog.get_item(&"convergencia")]
	var fixture := _reward_chest_fixture(pending)
	var controller: RoomController = fixture.controller
	var chest: RewardChest = fixture.chest
	var player: FakePlayer = fixture.player
	await get_tree().process_frame
	controller.room_cleared.emit()
	player.available = false
	chest._ensure_offer()
	assert_same(controller.runtime.reward_offer, pending)
	assert_eq(player.eligibility_calls, 0)

func test_reward_chest_empty_offer_claims_once_without_requesting_ui() -> void:
	var empty_offer := RewardOffer.new()
	var fixture := _reward_chest_fixture(empty_offer)
	var controller: RoomController = fixture.controller
	var chest: RewardChest = fixture.chest
	await get_tree().process_frame
	watch_signals(chest)
	controller.room_cleared.emit()
	chest.open_offer()
	assert_true(empty_offer.claimed)
	assert_eq(empty_offer.claimed_item_id, &"")
	assert_signal_not_emitted(chest, &"offer_requested")
	chest.open_offer()
	assert_signal_not_emitted(chest, &"offer_requested")

func test_reward_chest_one_or_two_options_still_request_offer() -> void:
	var offer := RewardOffer.new()
	offer.options = [ItemCatalog.get_item(&"convergencia")]
	var fixture := _reward_chest_fixture(offer)
	var controller: RoomController = fixture.controller
	var chest: RewardChest = fixture.chest
	await get_tree().process_frame
	watch_signals(chest)
	controller.room_cleared.emit()
	chest.open_offer()
	assert_signal_emit_count(chest, &"offer_requested", 1)
	offer.options.append(ItemCatalog.get_item(&"estilhaco"))
	chest.open_offer()
	assert_signal_emit_count(chest, &"offer_requested", 2)

func test_reward_chest_late_restore_after_ready_uses_saved_offer_without_generating() -> void:
	var saved_offer := RewardOffer.new()
	saved_offer.options = [ItemCatalog.get_item(&"convergencia")]
	var fixture := _reward_chest_fixture()
	var controller: RoomController = fixture.controller
	var chest: RewardChest = fixture.chest
	var player: FakePlayer = fixture.player
	await get_tree().process_frame
	watch_signals(chest)
	chest.configure(player, 0, 0, 0, 0, COMBAT, saved_offer)
	controller.room_cleared.emit()
	chest._ensure_offer()
	chest.open_offer()
	assert_same(controller.runtime.reward_offer, saved_offer)
	assert_signal_not_emitted(chest, &"offer_created")
	assert_signal_emit_count(chest, &"offer_requested", 1)
	assert_eq(player.eligibility_calls, 0)

func test_reward_chest_late_configure_does_not_overwrite_existing_runtime_offer() -> void:
	var offer_a := RewardOffer.new()
	offer_a.options = [ItemCatalog.get_item(&"convergencia")]
	var offer_b := RewardOffer.new()
	offer_b.options = [ItemCatalog.get_item(&"estilhaco")]
	var fixture := _reward_chest_fixture()
	var controller: RoomController = fixture.controller
	var chest: RewardChest = fixture.chest
	var player: FakePlayer = fixture.player
	await get_tree().process_frame
	controller.runtime.reward_offer = offer_a
	watch_signals(chest)
	chest.configure(player, 0, 0, 0, 0, COMBAT, offer_b)
	chest._ensure_offer()
	controller.room_cleared.emit()
	chest._ensure_offer()
	assert_same(controller.runtime.reward_offer, offer_a)
	assert_ne(controller.runtime.reward_offer, offer_b)
	assert_signal_not_emitted(chest, &"offer_created")
	assert_eq(player.eligibility_calls, 0)

func test_reward_chest_late_null_configure_preserves_pending_offer_and_opens_normally() -> void:
	var pending := RewardOffer.new()
	pending.options = [ItemCatalog.get_item(&"convergencia")]
	var fixture := _reward_chest_fixture()
	var controller: RoomController = fixture.controller
	var chest: RewardChest = fixture.chest
	var player: FakePlayer = fixture.player
	await get_tree().process_frame
	watch_signals(chest)
	chest.configure(player, 0, 0, 0, 0, COMBAT, pending)
	chest.configure(player, 0, 0, 0, 0, COMBAT, null)
	controller.room_cleared.emit()
	chest._ensure_offer()
	chest.open_offer()
	assert_same(controller.runtime.reward_offer, pending)
	assert_signal_emit_count(chest, &"offer_requested", 1)
	assert_signal_not_emitted(chest, &"offer_created")
	assert_eq(player.eligibility_calls, 0)

func test_main_scene_and_reward_paths_smoke_load() -> void:
	assert_not_null(load("res://scenes/main/main.tscn"))
	assert_not_null(load("res://scripts/loot/reward_chest.gd"))
	assert_not_null(load("res://scripts/ui/item_choice.gd"))

func test_room_runtime_zero_spawns_clears_once_and_exit_remains_unlocked() -> void:
	var runtime := RoomRuntime.new()
	runtime.start()
	runtime.mark_spawns_finished()
	runtime.mark_spawns_finished()
	assert_true(runtime.is_cleared())
	assert_eq(runtime.state, RoomRuntime.State.CLEARED)
