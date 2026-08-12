extends GutTest

var _events: Array[String] = []
var _changed_totals: Array[int] = []
var _spent_totals: Array[int] = []
var _credited_totals: Array[int] = []
var _reenter_on_change := false


func before_each() -> void:
	_disconnect_own_callbacks()
	GameState.temporal_echoes = 0
	_events.clear()
	_changed_totals.clear()
	_spent_totals.clear()
	_credited_totals.clear()
	_reenter_on_change = false


func after_each() -> void:
	_disconnect_own_callbacks()
	GameState.temporal_echoes = 0


func _disconnect_own_callbacks() -> void:
	var changed_callback := Callable(self, "_on_temporal_echoes_changed")
	if GameState.temporal_echoes_changed.is_connected(changed_callback):
		GameState.temporal_echoes_changed.disconnect(changed_callback)
	var spent_callback := Callable(self, "_on_temporal_echoes_spent")
	if EventBus.temporal_echoes_spent.is_connected(spent_callback):
		EventBus.temporal_echoes_spent.disconnect(spent_callback)
	var credited_callback := Callable(self, "_on_temporal_echoes_credited")
	if EventBus.temporal_echoes_credited.is_connected(credited_callback):
		EventBus.temporal_echoes_credited.disconnect(credited_callback)


func _connect_own_callbacks() -> void:
	var changed_callback := Callable(self, "_on_temporal_echoes_changed")
	if not GameState.temporal_echoes_changed.is_connected(changed_callback):
		GameState.temporal_echoes_changed.connect(changed_callback)
	var spent_callback := Callable(self, "_on_temporal_echoes_spent")
	if not EventBus.temporal_echoes_spent.is_connected(spent_callback):
		EventBus.temporal_echoes_spent.connect(spent_callback)
	var credited_callback := Callable(self, "_on_temporal_echoes_credited")
	if not EventBus.temporal_echoes_credited.is_connected(credited_callback):
		EventBus.temporal_echoes_credited.connect(credited_callback)


func _on_temporal_echoes_changed(amount: int, total: int) -> void:
	_changed_totals.append(GameState.temporal_echoes)
	_events.append("changed:%d:%d" % [amount, total])
	if _reenter_on_change:
		_reenter_on_change = false
		GameState.spend_temporal_echoes(1)


func _on_temporal_echoes_spent(amount: int, total: int) -> void:
	_spent_totals.append(GameState.temporal_echoes)
	_events.append("spent:%d:%d" % [amount, total])

func _on_temporal_echoes_credited(amount: int, total: int) -> void:
	_credited_totals.append(total)
	_events.append("credited:%d:%d" % [amount, total])


func test_has_temporal_echoes_accepts_only_positive_affordable_amounts() -> void:
	GameState.temporal_echoes = 10

	assert_true(GameState.has_temporal_echoes(5))
	assert_true(GameState.has_temporal_echoes(10))
	assert_false(GameState.has_temporal_echoes(11))
	assert_false(GameState.has_temporal_echoes(0))
	assert_false(GameState.has_temporal_echoes(-1))


func test_spend_temporal_echoes_supports_partial_exact_and_sequential_debits() -> void:
	GameState.temporal_echoes = 20

	assert_true(GameState.spend_temporal_echoes(5))
	assert_eq(GameState.temporal_echoes, 15)
	assert_true(GameState.spend_temporal_echoes(10))
	assert_eq(GameState.temporal_echoes, 5)
	assert_true(GameState.spend_temporal_echoes(5))
	assert_eq(GameState.temporal_echoes, 0)


func test_failed_spends_preserve_balance_and_emit_no_signals() -> void:
	GameState.temporal_echoes = 10
	clear_signal_watcher()
	watch_signals(GameState)
	watch_signals(EventBus)

	assert_false(GameState.spend_temporal_echoes(11))
	assert_false(GameState.spend_temporal_echoes(0))
	assert_false(GameState.spend_temporal_echoes(-1))
	assert_eq(GameState.temporal_echoes, 10)
	assert_signal_not_emitted(GameState, &"temporal_echoes_changed")
	assert_signal_not_emitted(EventBus, &"temporal_echoes_spent")


func test_successful_spend_mutates_before_callbacks_and_orders_changed_before_spent() -> void:
	GameState.temporal_echoes = 10
	_connect_own_callbacks()
	watch_signals(GameState)
	watch_signals(EventBus)

	assert_true(GameState.spend_temporal_echoes(4))
	assert_eq(GameState.temporal_echoes, 6)
	assert_eq(_changed_totals, [6])
	assert_eq(_spent_totals, [6])
	assert_eq(_events, ["changed:-4:6", "spent:4:6"])
	assert_signal_emitted_with_parameters(GameState, &"temporal_echoes_changed", [-4, 6])
	assert_signal_emitted_with_parameters(EventBus, &"temporal_echoes_spent", [4, 6])


func test_add_temporal_echoes_preserves_credit_contract_and_rejects_invalid_values() -> void:
	_connect_own_callbacks()
	watch_signals(GameState)
	watch_signals(EventBus)

	GameState.add_temporal_echoes(7)
	assert_eq(GameState.temporal_echoes, 7)
	assert_signal_emitted_with_parameters(GameState, &"temporal_echoes_changed", [7, 7])
	assert_signal_emitted_with_parameters(EventBus, &"temporal_echoes_credited", [7, 7])
	assert_eq(_events, ["changed:7:7", "credited:7:7"])

	clear_signal_watcher()
	watch_signals(GameState)
	watch_signals(EventBus)
	GameState.add_temporal_echoes(0)
	GameState.add_temporal_echoes(-3)
	assert_eq(GameState.temporal_echoes, 7)
	assert_signal_not_emitted(GameState, &"temporal_echoes_changed")
	assert_signal_not_emitted(EventBus, &"temporal_echoes_credited")


func test_add_temporal_echoes_reentrant_credit_preserves_external_snapshot_and_order() -> void:
	GameState.temporal_echoes = 5
	_reenter_on_change = true
	_connect_own_callbacks()

	GameState.add_temporal_echoes(2)

	assert_eq(_events, ["changed:2:7", "changed:-1:6", "spent:1:6", "credited:2:7"])
	assert_eq(_changed_totals, [7, 6])
	assert_eq(_spent_totals, [6])
	assert_eq(_credited_totals, [7])
	assert_eq(GameState.temporal_echoes, 6)


func test_add_temporal_echoes_rejects_int64_overflow_without_signals_or_wrap() -> void:
	GameState.temporal_echoes = 9223372036854775800
	watch_signals(GameState)
	watch_signals(EventBus)

	GameState.add_temporal_echoes(10)

	assert_eq(GameState.temporal_echoes, 9223372036854775800)
	assert_signal_not_emitted(GameState, &"temporal_echoes_changed")
	assert_signal_not_emitted(EventBus, &"temporal_echoes_credited")
	assert_push_error("overflow do saldo")

func test_add_temporal_echoes_accepts_exact_int64_max_without_overflow() -> void:
	GameState.temporal_echoes = GameState.MAX_TEMPORAL_ECHOES - 1
	watch_signals(GameState)
	watch_signals(EventBus)

	GameState.add_temporal_echoes(1)

	assert_eq(GameState.temporal_echoes, GameState.MAX_TEMPORAL_ECHOES)
	assert_signal_emitted_with_parameters(GameState, &"temporal_echoes_changed", [1, GameState.MAX_TEMPORAL_ECHOES])
	assert_signal_emitted_with_parameters(EventBus, &"temporal_echoes_credited", [1, GameState.MAX_TEMPORAL_ECHOES])


func test_reset_for_new_run_keeps_its_zero_delta_contract_without_economy_events() -> void:
	GameState.temporal_echoes = 9
	watch_signals(GameState)
	watch_signals(EventBus)

	GameState.reset_for_new_run()

	assert_eq(GameState.temporal_echoes, 0)
	assert_signal_emitted_with_parameters(GameState, &"temporal_echoes_changed", [0, 0])
	assert_signal_not_emitted(EventBus, &"temporal_echoes_credited")
	assert_signal_not_emitted(EventBus, &"temporal_echoes_spent")


func test_changed_callback_can_spend_again_after_the_first_debit_is_committed() -> void:
	GameState.temporal_echoes = 5
	_reenter_on_change = true
	_connect_own_callbacks()

	assert_true(GameState.spend_temporal_echoes(2))
	assert_eq(GameState.temporal_echoes, 2)
	assert_eq(_changed_totals, [3, 2])
	# The callback observes the current balance (2), but each payload retains
	# the total belonging to its own synchronous transaction.
	assert_eq(_spent_totals, [2, 2])
	assert_eq(_events, ["changed:-2:3", "changed:-1:2", "spent:1:2", "spent:2:3"])
	assert_eq(GameState.temporal_echoes, 2)
