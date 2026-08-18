extends GutTest

const CASULO := preload("res://scripts/enemies/bosses/wings/casulo_explosivo.gd")
const FORMACAO := preload("res://scripts/enemies/bosses/wings/formacao_asas_controller.gd")

class DamageTarget extends Node:
	var received: Array[DamageInfo] = []
	func take_damage(info: DamageInfo) -> int:
		received.append(info)
		return info.amount

func _casulo(id: int, amount: int = 0, source: Node = null) -> Node:
	var cocoon: Node = CASULO.new()
	add_child_autofree(cocoon)
	assert_true(cocoon.set_slot_id(id))
	var tags: Array[StringName] = [&"asas_explosivas"]
	assert_true(cocoon.configure_damage(amount, source, tags, Vector2(30, 40)))
	return cocoon

func _formation(amount: int = 0, source: Node = null) -> RefCounted:
	var cocoons: Array = []
	for id in FORMACAO.COCOON_IDS:
		cocoons.append(_casulo(id, amount, source))
	var formation: RefCounted = FORMACAO.new()
	assert_true(formation.configure(cocoons))
	return formation

func _lock_bank(formation: RefCounted, bank: StringName) -> void:
	var positions: Dictionary = {}
	for id in FORMACAO.BANKS[bank]:
		positions[id] = Vector2(id, id * 2)
	assert_true(formation.begin_tracking_bank(bank, positions))
	assert_true(formation.lock_bank(bank, positions))

func test_banks_follow_order_and_active_counts_reconstitute() -> void:
	var formation := _formation()
	assert_eq(formation.get_active_count(), 12)
	assert_false(formation.fire_bank(&"B"))
	assert_false(formation.fire_bank(&"C"))
	_lock_bank(formation, &"A")
	assert_true(formation.advance())
	assert_eq(formation.get_active_count(), 8)
	_lock_bank(formation, &"B")
	assert_true(formation.fire_bank(&"B"))
	assert_eq(formation.get_active_count(), 4)
	_lock_bank(formation, &"C")
	assert_true(formation.advance())
	assert_eq(formation.get_active_count(), 0)
	assert_false(formation.advance())
	assert_true(formation.reconstitute_all())
	assert_eq(formation.get_active_count(), 12)

func test_each_bank_contains_only_its_approved_ids_and_cannot_fire_twice() -> void:
	var formation := _formation()
	_lock_bank(formation, &"A")
	assert_true(formation.fire_bank(&"A"))
	for id in [5, 6, 11, 12]:
		assert_eq(formation.get_cocoon(id).state, CASULO.State.EMPTY)
	for id in [1, 2, 3, 4, 7, 8, 9, 10]:
		assert_eq(formation.get_cocoon(id).state, CASULO.State.IN_SLOT)
	assert_false(formation.fire_bank(&"A"))
	assert_false(formation.fire_bank(&"C"))
	_lock_bank(formation, &"B")
	assert_true(formation.fire_bank(&"B"))
	for id in [2, 3, 8, 9]:
		assert_eq(formation.get_cocoon(id).state, CASULO.State.EMPTY)
	_lock_bank(formation, &"C")
	assert_true(formation.fire_bank(&"C"))
	for id in [1, 4, 7, 10]:
		assert_eq(formation.get_cocoon(id).state, CASULO.State.EMPTY)

func test_casulo_hits_each_target_only_once_per_detonation() -> void:
	var target := DamageTarget.new()
	add_child_autofree(target)
	var cocoon := _casulo(1, 75, self)
	assert_true(cocoon.enter_slot())
	assert_eq(cocoon.detonate([target, target]), 0)
	assert_eq(target.received.size(), 0)
	assert_true(cocoon.start_tracking(Vector2.ZERO))
	assert_true(cocoon.lock_position(Vector2.ZERO))
	assert_eq(cocoon.detonate([target, target]), 1)
	assert_eq(target.received.size(), 1)
	assert_eq(cocoon.hit_targets.size(), 1)
	assert_eq(cocoon.detonate([target]), 0)
	assert_eq(target.received.size(), 1)

func test_two_cocoons_can_accumulate_damage_on_the_same_target() -> void:
	var target := DamageTarget.new()
	add_child_autofree(target)
	var formation := _formation(25, self)
	_lock_bank(formation, &"A")
	assert_true(formation.advance({5: [target], 6: [target]}))
	assert_eq(target.received.size(), 2)
	assert_eq(target.received[0].amount + target.received[1].amount, 50)

func test_damage_info_preserves_injected_fields_and_uses_integer_amount() -> void:
	var target := DamageTarget.new()
	add_child_autofree(target)
	var cocoon := _casulo(1)
	assert_true(cocoon.enter_slot())
	var tags: Array[StringName] = [&"asa", &"explosao"]
	var damage_position := Vector2(70, 80)
	assert_true(cocoon.configure_damage(125, self, tags, damage_position))
	assert_true(cocoon.start_tracking(Vector2.ZERO))
	assert_true(cocoon.lock_position(Vector2.ZERO))
	assert_eq(cocoon.detonate([target]), 1)
	var info := target.received[0]
	assert_typeof(info.amount, TYPE_INT)
	assert_eq(info.amount, 125)
	assert_typeof(info.source, TYPE_OBJECT)
	assert_eq(info.source, self)
	assert_eq(info.tags, tags)
	assert_typeof(info.position.x, TYPE_FLOAT)
	assert_eq(info.position, damage_position)

func test_damage_amount_rejects_negative_values() -> void:
	var cocoon := _casulo(1)
	var invalid_tags: Array[StringName] = [&"invalid"]
	assert_false(cocoon.configure_damage(-1, self, invalid_tags, Vector2.ZERO))

func test_lock_requires_tracking_and_freezes_locked_position() -> void:
	var cocoon := _casulo(1)
	assert_true(cocoon.enter_slot())
	assert_false(cocoon.lock_position(Vector2(1, 2)))
	assert_true(cocoon.start_tracking(Vector2(10, 20)))
	assert_true(cocoon.lock_position(Vector2(12, 24)))
	assert_eq(cocoon.state, CASULO.State.LOCKED)
	assert_eq(cocoon.locked_position, Vector2(12, 24))
	assert_false(cocoon.lock_position(Vector2(99, 99)))
	assert_eq(cocoon.locked_position, Vector2(12, 24))

func test_lock_cannot_be_bypassed_by_slot_entry_or_reconstitution() -> void:
	var formation := _formation()
	var cocoon: Node = formation.get_cocoon(1)
	assert_true(cocoon.start_tracking(Vector2(10, 20)))
	assert_true(cocoon.lock_position(Vector2(12, 24)))
	assert_false(cocoon.start_tracking(Vector2(30, 40)))
	assert_false(cocoon.enter_slot())
	assert_false(cocoon.reset())
	assert_false(formation.reconstitute_all())
	assert_eq(cocoon.state, CASULO.State.LOCKED)

func test_reconstitution_after_empty_preserves_ids() -> void:
	var formation := _formation()
	_lock_bank(formation, &"A")
	assert_true(formation.fire_bank(&"A"))
	_lock_bank(formation, &"B")
	assert_true(formation.fire_bank(&"B"))
	_lock_bank(formation, &"C")
	assert_true(formation.fire_bank(&"C"))
	assert_true(formation.reconstitute_all())
	for id in FORMACAO.COCOON_IDS:
		assert_eq(formation.get_cocoon(id).cocoon_id, id)
		assert_eq(formation.get_cocoon(id).state, CASULO.State.IN_SLOT)

func test_configure_rejects_non_casulo_entries_without_accessing_properties() -> void:
	var formation: RefCounted = FORMACAO.new()
	var cocoons: Array = []
	for id in FORMACAO.COCOON_IDS:
		cocoons.append(_casulo(id))
	var invalid_node := Node.new()
	add_child_autofree(invalid_node)
	cocoons[0] = invalid_node
	assert_false(formation.configure(cocoons))
	assert_eq(formation.get_active_count(), 0)
	cocoons[0] = RefCounted.new()
	assert_false(formation.configure(cocoons))
	assert_eq(formation.get_active_count(), 0)

func test_lock_bank_requires_all_positions_and_locks_only_its_bank() -> void:
	var formation := _formation()
	assert_false(formation.lock_bank(&"A", {5: Vector2(5, 10)}))
	assert_eq(formation.get_cocoon(5).state, CASULO.State.IN_SLOT)
	_lock_bank(formation, &"A")
	for id in FORMACAO.BANKS[&"A"]:
		assert_eq(formation.get_cocoon(id).state, CASULO.State.LOCKED)
	for id in FORMACAO.BANKS[&"B"]:
		assert_eq(formation.get_cocoon(id).state, CASULO.State.IN_SLOT)
