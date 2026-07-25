extends GutTest

const COMBAT := preload("res://resources/loot/combat_pool.tres")
const ELITE := preload("res://resources/loot/elite_pool.tres")
const RISK := preload("res://resources/loot/risk_pool.tres")
const BOSS := preload("res://resources/loot/boss_pool.tres")

class FakePlayer extends Node:
	var available := true
	var acquire_calls := 0
	var acquired: Array[ItemDef] = []

	func get_luck() -> float:
		return 0.0

	func can_acquire_item(_item: ItemDef) -> bool:
		return available

	func acquire_item(item: ItemDef) -> bool:
		acquire_calls += 1
		if not available:
			return false
		acquired.append(item)
		return true

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
		var wanted: Array[StringName] = expected[pool.id]
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
	var root := Node2D.new()
	add_child_autofree(root)
	var controller := RoomController.new()
	controller.name = "RoomController"
	controller.runtime = RoomRuntime.new()
	root.add_child(controller)
	var player := FakePlayer.new()
	player.name = "Player"
	root.add_child(player)
	var chest := preload("res://scripts/loot/reward_chest.gd").new()
	chest.room_controller_path = ^"../RoomController"
	chest.player_path = ^"../Player"
	chest.pool = COMBAT
	root.add_child(chest)
	await get_tree().process_frame
	watch_signals(chest)
	chest.open_offer()
	assert_signal_not_emitted(chest, &"offer_requested")
	controller.runtime.start()
	controller.runtime.mark_spawns_finished()
	controller.room_cleared.emit()
	chest.open_offer()
	var first: RewardOffer = controller.runtime.reward_offer
	chest.open_offer()
	assert_same(controller.runtime.reward_offer, first)
	assert_signal_emit_count(chest, &"offer_requested", 2)

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
