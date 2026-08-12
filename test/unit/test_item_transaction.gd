extends GutTest

const ItemTransactionManagerScript := preload("res://scripts/items/item_transaction_manager.gd")

class SpyAction extends ActionDef:
	static var sink := {"called": 0, "count": -1, "echoes": -1, "marker": ""}
	static var observation_inventory: Inventory
	static var observation_item_id: StringName
	var called := 0
	var inventory: Inventory
	var item_id: StringName
	var observed_count := -1
	var observed_echoes := -1

	func execute(_context) -> void:
		called += 1
		SpyAction.sink["called"] += 1
		SpyAction.sink["marker"] = "snapshot"
		var observed_inventory := SpyAction.observation_inventory if SpyAction.observation_inventory != null else inventory
		var observed_id := SpyAction.observation_item_id if not SpyAction.observation_item_id.is_empty() else item_id
		if observed_inventory != null:
			observed_count = observed_inventory.count(observed_id)
			observed_echoes = GameState.temporal_echoes
			SpyAction.sink["count"] = observed_count
			SpyAction.sink["echoes"] = observed_echoes

class SynchronousConsumeAction extends ActionDef:
	static var sink := {"called": 0, "removed": false, "count_in_callback": -1}
	static var executed_action_ref: WeakRef
	static var inventory: Inventory
	static var item_id: StringName

	func execute(_context) -> void:
		SynchronousConsumeAction.sink["called"] += 1
		SynchronousConsumeAction.executed_action_ref = weakref(self)
		SynchronousConsumeAction.sink["count_in_callback"] = inventory.count(item_id)
		SynchronousConsumeAction.sink["removed"] = inventory.remove_one(item_id)

var _inventory: Inventory
var _stats: StatBlock
var _dispatcher: EffectDispatcher
var _reenter_item: ItemDef
var _reenter_cost := 0
var _reenter_results: Array[bool] = []
var _callback_snapshots: Array = []
var _mutate_item: ItemDef
var _mutated := false

func before_each() -> void:
	if GameState.temporal_echoes_changed.is_connected(_on_echoes_changed):
		GameState.temporal_echoes_changed.disconnect(_on_echoes_changed)
	if GameState.temporal_echoes_changed.is_connected(_observe_purchase):
		GameState.temporal_echoes_changed.disconnect(_observe_purchase)
	if GameState.temporal_echoes_changed.is_connected(_mutate_external_item):
		GameState.temporal_echoes_changed.disconnect(_mutate_external_item)
	GameState.temporal_echoes = 0
	_stats = StatBlock.new(StatCatalog.get_all())
	_dispatcher = EffectDispatcher.new(autofree(Node.new()), [])
	_inventory = Inventory.new(_stats, _dispatcher)
	_reenter_item = null
	_reenter_cost = 0
	_reenter_results.clear()
	_callback_snapshots.clear()
	_mutate_item = null
	_mutated = false
	SpyAction.sink = {"called": 0, "count": -1, "echoes": -1, "marker": ""}
	SpyAction.observation_inventory = null
	SpyAction.observation_item_id = &""
	SynchronousConsumeAction.sink = {"called": 0, "removed": false, "count_in_callback": -1}
	SynchronousConsumeAction.executed_action_ref = null
	SynchronousConsumeAction.inventory = _inventory
	SynchronousConsumeAction.item_id = &""
	watch_signals(GameState)

func after_each() -> void:
	if GameState.temporal_echoes_changed.is_connected(_on_echoes_changed):
		GameState.temporal_echoes_changed.disconnect(_on_echoes_changed)
	if GameState.temporal_echoes_changed.is_connected(_observe_purchase):
		GameState.temporal_echoes_changed.disconnect(_observe_purchase)
	if GameState.temporal_echoes_changed.is_connected(_mutate_external_item):
		GameState.temporal_echoes_changed.disconnect(_mutate_external_item)
	GameState.temporal_echoes = 0
	SpyAction.sink = {"called": 0, "count": -1, "echoes": -1, "marker": ""}
	SpyAction.observation_inventory = null
	SpyAction.observation_item_id = &""
	SynchronousConsumeAction.sink = {"called": 0, "removed": false, "count_in_callback": -1}
	SynchronousConsumeAction.executed_action_ref = null
	SynchronousConsumeAction.inventory = null
	SynchronousConsumeAction.item_id = &""

func _item(id: StringName = &"item_transaction", max_stacks: int = 1) -> ItemDef:
	var item := ItemDef.new()
	item.id = id
	item.max_stacks = max_stacks
	return item

func _stat_definition(id: StringName, allowed_ops: Array[int]) -> StatDef:
	var definition := StatDef.new()
	definition.id = id
	definition.allowed_ops = allowed_ops
	return definition

func _item_with_modifier(id: StringName, stat: StringName, op: StatDef.Op) -> ItemDef:
	var item := _item(id)
	var modifier := StatModifierDef.new()
	modifier.stat = stat
	modifier.op = op
	item.modifiers = [modifier]
	return item

func _on_echoes_changed(_amount: int, _total: int) -> void:
	if _reenter_item == null:
		return
	_reenter_results.append(ItemTransactionManagerScript.purchase(_inventory, _reenter_item, _reenter_cost))
	_reenter_results.append(_inventory.acquire(_reenter_item))
	_reenter_item = null

func _observe_purchase(_amount: int, _total: int) -> void:
	if _reenter_item != null:
		_callback_snapshots.append([GameState.temporal_echoes, _inventory.count(_reenter_item.id)])

func _mutate_external_item(_amount: int, _total: int) -> void:
	if _mutate_item == null or _mutated:
		return
	_mutated = true
	_mutate_item.id = &"mutated_id"
	_mutate_item.max_stacks = 99
	_mutate_item.modifiers.clear()
	_mutate_item.effects.clear()

func test_purchase_success_debits_once_and_preserves_runtime_instance() -> void:
	var item := _item()
	var modifier := StatModifierDef.new()
	modifier.stat = &"fire_rate"
	modifier.op = StatDef.Op.ADD_PCT
	modifier.value = 1.0
	var spy := SpyAction.new()
	var effect := EffectDef.new()
	effect.event = &"on_pickup"
	effect.action = spy
	item.modifiers = [modifier]
	item.effects = [effect]
	GameState.temporal_echoes = 10

	assert_true(ItemTransactionManagerScript.purchase(_inventory, item, 4))
	assert_eq(GameState.temporal_echoes, 6)
	assert_eq(_inventory.count(item.id), 1)
	assert_eq(_inventory.reserved_count(item.id), 0)
	assert_eq(_stats.get_stat(&"fire_rate"), 12.0)
	assert_eq(SpyAction.sink["called"], 1)
	assert_true(_inventory.remove_one(item.id))
	assert_eq(_stats.get_stat(&"fire_rate"), 6.0)
	_dispatcher.dispatch(&"on_pickup", null, 0)
	assert_eq(SpyAction.sink["called"], 1)

func test_commit_with_effect_and_no_modifiers_dispatches_pickup_once_and_removes_it() -> void:
	var item := _item(&"effect_without_modifiers")
	var spy := SpyAction.new()
	var effect := EffectDef.new()
	effect.event = &"on_pickup"
	effect.action = spy
	item.effects = [effect]

	assert_true(_inventory.acquire(item))
	assert_eq(SpyAction.sink["called"], 1)

func test_acquire_dispatch_allows_on_pickup_to_remove_new_instance_synchronously() -> void:
	var item := _item(&"synchronous_consume", 1)
	var modifier := StatModifierDef.new()
	modifier.stat = &"fire_rate"
	modifier.op = StatDef.Op.ADD_PCT
	modifier.value = 1.0
	var action := SynchronousConsumeAction.new()
	var effect := EffectDef.new()
	effect.event = &"on_pickup"
	effect.action = action
	item.modifiers = [modifier]
	item.effects = [effect]
	SynchronousConsumeAction.item_id = item.id

	assert_true(_inventory.acquire(item))
	assert_eq(SynchronousConsumeAction.sink["called"], 1)
	assert_eq(SynchronousConsumeAction.sink["count_in_callback"], 1)
	assert_true(SynchronousConsumeAction.sink["removed"])
	assert_eq(_inventory.count(item.id), 0)
	# Reservas low-level devem sempre ser resolvidas; acquire concluiu o commit.
	assert_eq(_inventory.reserved_count(item.id), 0)
	assert_eq(_stats.get_stat(&"fire_rate"), 6.0)
	assert_eq(_stats.get_active_modifiers().size(), 0)

	_dispatcher.dispatch(&"on_pickup", null, 0)
	assert_eq(SynchronousConsumeAction.sink["called"], 1)
	assert_eq(_inventory.count(item.id), 0)
	assert_eq(_inventory.reserved_count(item.id), 0)

func test_purchase_snapshot_auto_consumes_only_new_lifo_instance_and_leaves_no_cooldown() -> void:
	var item_id := &"same_id_lifo"
	var previous := _item(item_id, 2)
	var previous_modifier := StatModifierDef.new()
	previous_modifier.stat = &"fire_rate"
	previous_modifier.op = StatDef.Op.ADD_PCT
	previous_modifier.value = 1.0
	previous.modifiers = [previous_modifier]
	var previous_action := SpyAction.new()
	var previous_effect := EffectDef.new()
	previous_effect.event = &"on_pickup"
	previous_effect.action = previous_action
	previous.effects = [previous_effect]
	assert_true(_inventory.acquire(previous))

	var purchased := _item(item_id, 2)
	var purchased_modifier := StatModifierDef.new()
	purchased_modifier.stat = &"damage"
	purchased_modifier.op = StatDef.Op.ADD_PCT
	purchased_modifier.value = 1.0
	purchased.modifiers = [purchased_modifier]
	var consume_action := SynchronousConsumeAction.new()
	var purchased_effect := EffectDef.new()
	purchased_effect.event = &"on_pickup"
	purchased_effect.cooldown = 5.0
	purchased_effect.action = consume_action
	purchased.effects = [purchased_effect]
	SynchronousConsumeAction.item_id = item_id
	GameState.temporal_echoes = 9

	assert_true(ItemTransactionManagerScript.purchase(_inventory, purchased, 4))
	assert_eq(GameState.temporal_echoes, 5)
	assert_eq(_inventory.count(item_id), 1)
	assert_eq(_inventory.reserved_count(item_id), 0)
	assert_eq(SynchronousConsumeAction.sink["called"], 1)
	assert_eq(SynchronousConsumeAction.sink["count_in_callback"], 2)
	assert_true(SynchronousConsumeAction.sink["removed"])
	assert_eq(_stats.get_stat(&"fire_rate"), 12.0)
	assert_eq(_stats.get_stat(&"damage"), 1.0)
	assert_eq(previous_action.called, 2)
	assert_eq(_dispatcher._effects.size(), 1)
	assert_true(_dispatcher._effects[0].action == previous_action)
	assert_eq(_dispatcher._cooldowns.size(), 0)

	var executed_ref: WeakRef = SynchronousConsumeAction.executed_action_ref
	SynchronousConsumeAction.executed_action_ref = null
	assert_null(executed_ref.get_ref())
	_dispatcher.dispatch(&"on_pickup", null, 0)
	assert_eq(SynchronousConsumeAction.sink["called"], 1)
	assert_eq(previous_action.called, 3)

func test_commit_with_two_modifiers_registers_one_effect_and_remove_reverts_all() -> void:
	var item := _item(&"two_modifiers_one_effect")
	var first := StatModifierDef.new()
	first.stat = &"fire_rate"
	first.op = StatDef.Op.ADD_PCT
	first.value = 1.0
	var second := StatModifierDef.new()
	second.stat = &"damage"
	second.op = StatDef.Op.ADD_PCT
	second.value = 1.0
	item.modifiers = [first, second]
	var spy := SpyAction.new()
	var effect := EffectDef.new()
	effect.event = &"on_pickup"
	effect.action = spy
	item.effects = [effect]

	assert_true(_inventory.acquire(item))
	assert_eq(SpyAction.sink["called"], 1)
	assert_eq(_stats.get_stat(&"fire_rate"), 12.0)
	assert_eq(_stats.get_stat(&"damage"), 2.0)
	assert_eq(_stats.get_active_modifiers().size(), 2)
	assert_true(_inventory.remove_one(item.id))
	assert_eq(_stats.get_stat(&"fire_rate"), 6.0)
	assert_eq(_stats.get_stat(&"damage"), 1.0)
	assert_eq(_stats.get_active_modifiers().size(), 0)
	_dispatcher.dispatch(&"on_pickup", null, 0)
	assert_eq(SpyAction.sink["called"], 1)

func test_invalid_inputs_insufficient_funds_and_capacity_do_not_mutate() -> void:
	var item := _item()
	GameState.temporal_echoes = 3
	assert_false(ItemTransactionManagerScript.purchase(_inventory, item, 0))
	assert_false(ItemTransactionManagerScript.purchase(_inventory, item, -1))
	assert_false(ItemTransactionManagerScript.purchase(null, item, 1))
	assert_false(ItemTransactionManagerScript.purchase(_inventory, null, 1))
	var empty_id := _item(&"", 1)
	var no_stacks := _item(&"no_stacks", 0)
	assert_false(ItemTransactionManagerScript.purchase(_inventory, empty_id, 1))
	assert_false(ItemTransactionManagerScript.purchase(_inventory, no_stacks, 1))
	assert_false(ItemTransactionManagerScript.purchase(_inventory, item, 4))
	assert_true(_inventory.acquire(item))
	assert_false(ItemTransactionManagerScript.purchase(_inventory, item, 1))
	assert_eq(GameState.temporal_echoes, 3)
	assert_eq(_inventory.count(item.id), 1)

func test_null_dependencies_fail_without_debit_reservation_or_signal() -> void:
	var item := _item(&"null_dependencies")
	GameState.temporal_echoes = 7
	var no_stats := Inventory.new(null, _dispatcher)
	var no_dispatcher := Inventory.new(_stats, null)
	assert_false(ItemTransactionManagerScript.purchase(no_stats, item, 3))
	assert_false(ItemTransactionManagerScript.purchase(no_dispatcher, item, 3))
	assert_eq(GameState.temporal_echoes, 7)
	assert_eq(no_stats.reserved_count(item.id), 0)
	assert_eq(no_dispatcher.reserved_count(item.id), 0)
	assert_eq(SpyAction.sink["called"], 0)
	assert_signal_not_emitted(GameState, &"temporal_echoes_changed")

func test_purchase_commits_original_snapshot_when_external_item_mutates_during_debit() -> void:
	var item := _item(&"snapshot_original", 1)
	var modifier := StatModifierDef.new()
	modifier.stat = &"fire_rate"
	modifier.op = StatDef.Op.ADD_PCT
	modifier.value = 1.0
	var spy := SpyAction.new()
	var effect := EffectDef.new()
	effect.event = &"on_pickup"
	effect.action = spy
	item.modifiers = [modifier]
	item.effects = [effect]
	_mutate_item = item
	GameState.temporal_echoes = 8
	GameState.temporal_echoes_changed.connect(_mutate_external_item)
	assert_true(ItemTransactionManagerScript.purchase(_inventory, item, 3))
	assert_eq(_inventory.reserved_count(&"snapshot_original"), 0)
	assert_eq(_inventory.count(&"snapshot_original"), 1)
	assert_eq(_inventory.count(&"mutated_id"), 0)
	assert_eq(_stats.get_stat(&"fire_rate"), 12.0)
	assert_eq(SpyAction.sink["called"], 1)
	assert_eq(SpyAction.sink["marker"], "snapshot")

func test_cancel_snapshot_after_external_mutation_clears_original_id() -> void:
	var item := _item(&"cancel_snapshot", 1)
	var token := _inventory.reserve(item)
	assert_not_null(token)
	item.id = &"cancel_mutated"
	item.max_stacks = 99
	assert_true(_inventory.cancel_reservation(token))
	assert_eq(_inventory.reserved_count(&"cancel_snapshot"), 0)
	assert_eq(_inventory.reserved_count(&"cancel_mutated"), 0)

func test_external_mutation_after_reserve_does_not_change_commit_result() -> void:
	var item := _item(&"commit_snapshot", 1)
	var token := _inventory.reserve(item)
	assert_not_null(token)
	item.id = &"commit_mutated"
	item.max_stacks = 99
	assert_true(_inventory.commit_reservation(token))
	assert_eq(_inventory.count(&"commit_snapshot"), 1)
	assert_eq(_inventory.count(&"commit_mutated"), 0)
	assert_eq(_inventory.reserved_count(&"commit_snapshot"), 0)

func test_reservation_is_silent_and_free_acquire_respects_its_capacity() -> void:
	var spy := SpyAction.new()
	var effect := EffectDef.new()
	effect.event = &"on_pickup"
	effect.action = spy
	var item := _item(&"reserved", 1)
	item.effects = [effect]
	var token := _inventory.reserve(item)
	assert_not_null(token)
	assert_eq(_inventory.count(item.id), 0)
	assert_eq(_inventory.reserved_count(item.id), 1)
	assert_eq(spy.called, 0)
	assert_false(_inventory.acquire(item))
	assert_true(_inventory.commit_reservation(token))
	assert_eq(_inventory.count(item.id), 1)
	assert_eq(_inventory.reserved_count(item.id), 0)
	assert_eq(SpyAction.sink["called"], 1)

func test_free_acquire_can_use_unreserved_slot_and_commit_completes() -> void:
	var item := _item(&"two_slots", 2)
	var token := _inventory.reserve(item)
	assert_not_null(token)
	assert_true(_inventory.acquire(item))
	assert_true(_inventory.commit_reservation(token))
	assert_eq(_inventory.count(item.id), 2)
	assert_eq(_inventory.reserved_count(item.id), 0)

func test_reentrant_purchase_and_free_acquire_cannot_take_reserved_slot() -> void:
	var item := _item(&"reentrant", 1)
	GameState.temporal_echoes = 10
	_reenter_item = item
	_reenter_cost = 4
	GameState.temporal_echoes_changed.connect(_on_echoes_changed)

	assert_true(ItemTransactionManagerScript.purchase(_inventory, item, 4))
	assert_eq(_reenter_results, [false, false])
	assert_eq(GameState.temporal_echoes, 6)
	assert_eq(_inventory.count(item.id), 1)

func test_cancel_cross_inventory_reuse_and_one_shot_commit_cleanup() -> void:
	var item := _item(&"tokens", 1)
	var token := _inventory.reserve(item)
	var other := Inventory.new(StatBlock.new(StatCatalog.get_all()), EffectDispatcher.new(autofree(Node.new()), []))
	assert_false(other.commit_reservation(token))
	assert_true(_inventory.cancel_reservation(token))
	assert_eq(_inventory.reserved_count(item.id), 0)
	assert_false(_inventory.cancel_reservation(null))
	assert_false(_inventory.commit_reservation(null))
	assert_true(_inventory.acquire(item))
	assert_true(_inventory.remove_one(item.id))
	var commit_token := _inventory.reserve(item)
	assert_true(_inventory.commit_reservation(commit_token))
	assert_false(_inventory.commit_reservation(commit_token))
	assert_eq(_inventory.reserved_count(item.id), 0)

func test_two_reservations_consume_max2_and_orders_are_one_shot() -> void:
	var item := _item(&"two_reservations", 2)
	var first := _inventory.reserve(item)
	var second := _inventory.reserve(item)
	assert_not_null(first)
	assert_not_null(second)
	assert_null(_inventory.reserve(item))
	assert_eq(_inventory.reserved_count(item.id), 2)
	assert_true(_inventory.cancel_reservation(second))
	assert_eq(_inventory.reserved_count(item.id), 1)
	assert_true(_inventory.commit_reservation(first))
	assert_eq(_inventory.count(item.id), 1)
	assert_eq(_inventory.reserved_count(item.id), 0)
	assert_false(_inventory.cancel_reservation(first))
	assert_false(_inventory.commit_reservation(second))
	assert_true(_inventory.acquire(item))
	assert_false(_inventory.acquire(item))

func test_purchase_callback_sees_debit_and_materialized_stack() -> void:
	var item := _item(&"callback_observation")
	var spy := SpyAction.new()
	spy.inventory = _inventory
	spy.item_id = item.id
	SpyAction.observation_inventory = _inventory
	SpyAction.observation_item_id = item.id
	var effect := EffectDef.new()
	effect.event = &"on_pickup"
	effect.action = spy
	item.effects = [effect]
	GameState.temporal_echoes = 9
	assert_true(ItemTransactionManagerScript.purchase(_inventory, item, 4))
	assert_eq(SpyAction.sink["count"], 1)
	assert_eq(SpyAction.sink["echoes"], 5)
	assert_eq(_inventory.count(item.id), 1)
	assert_eq(GameState.temporal_echoes, 5)
	_reenter_item = null

func test_cancel_restores_capacity_and_does_not_apply_runtime_state() -> void:
	var item := _item(&"cancel_restore", 1)
	var modifier := StatModifierDef.new()
	modifier.stat = &"fire_rate"
	modifier.op = StatDef.Op.ADD_PCT
	modifier.value = 1.0
	item.modifiers = [modifier]
	var token := _inventory.reserve(item)
	assert_false(_inventory.acquire(item))
	assert_true(_inventory.cancel_reservation(token))
	assert_eq(_inventory.reserved_count(item.id), 0)
	assert_true(_inventory.acquire(item))
	assert_eq(_inventory.count(item.id), 1)
	assert_eq(_stats.get_stat(&"fire_rate"), 12.0)

func test_purchase_defensive_commit_result_does_not_claim_success_after_failed_commit() -> void:
	var item := _item(&"defensive_result")
	GameState.temporal_echoes = 8
	assert_true(ItemTransactionManagerScript.purchase(_inventory, item, 3))
	assert_eq(GameState.temporal_echoes, 5)
	assert_eq(_inventory.count(item.id), 1)

func test_purchase_rejects_global_modifier_missing_from_concrete_stat_block_without_mutation() -> void:
	var stats := StatBlock.new([])
	var inventory := Inventory.new(stats, _dispatcher)
	var item := _item_with_modifier(&"missing_concrete_stat", &"fire_rate", StatDef.Op.ADD_PCT)
	var effect := EffectDef.new()
	effect.event = &"on_pickup"
	effect.action = SpyAction.new()
	item.effects = [effect]
	GameState.temporal_echoes = 9

	assert_false(ItemTransactionManagerScript.purchase(inventory, item, 4))
	assert_eq(GameState.temporal_echoes, 9)
	assert_eq(inventory.count(item.id), 0)
	assert_eq(inventory.reserved_count(item.id), 0)
	assert_eq(item.effects.size(), 1)
	assert_eq(stats.get_active_modifiers().size(), 0)
	assert_signal_not_emitted(GameState, &"temporal_echoes_changed")

func test_purchase_rejects_disallowed_operation_in_concrete_stat_block() -> void:
	var stats := StatBlock.new([_stat_definition(&"fire_rate", [StatDef.Op.FLAT])])
	var inventory := Inventory.new(stats, _dispatcher)
	var item := _item_with_modifier(&"disallowed_concrete_op", &"fire_rate", StatDef.Op.ADD_PCT)
	var effect := EffectDef.new()
	effect.event = &"on_pickup"
	effect.action = SpyAction.new()
	item.effects = [effect]
	GameState.temporal_echoes = 9

	assert_false(ItemTransactionManagerScript.purchase(inventory, item, 4))
	assert_eq(GameState.temporal_echoes, 9)
	assert_eq(inventory.count(item.id), 0)
	assert_eq(inventory.reserved_count(item.id), 0)
	assert_eq(item.effects.size(), 1)
	assert_eq(stats.get_active_modifiers().size(), 0)
	assert_signal_not_emitted(GameState, &"temporal_echoes_changed")

func test_purchase_accepts_modifier_compatible_with_concrete_stat_block() -> void:
	var stats := StatBlock.new([_stat_definition(&"fire_rate", [StatDef.Op.ADD_PCT])])
	var inventory := Inventory.new(stats, _dispatcher)
	var item := _item_with_modifier(&"compatible_concrete_stat", &"fire_rate", StatDef.Op.ADD_PCT)
	GameState.temporal_echoes = 9

	assert_true(ItemTransactionManagerScript.purchase(inventory, item, 4))
	assert_eq(GameState.temporal_echoes, 5)
	assert_eq(inventory.count(item.id), 1)
	assert_eq(inventory.reserved_count(item.id), 0)
