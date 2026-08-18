extends GutTest

const ORCHESTRATOR := preload("res://scripts/enemies/bosses/regente_encounter_orchestrator.gd")
const CASULO := preload("res://scripts/enemies/bosses/wings/casulo_explosivo.gd")

class NonAuthority extends RegenteEncounterOrchestrator:
	func _has_host_authority() -> bool:
		return false

class HealthTarget extends Node2D:
	var health: HealthComponent
	var received: Array[DamageInfo] = []
	func take_damage(info: DamageInfo) -> int:
		received.append(info)
		return info.amount

func _fixture(host := true) -> Dictionary:
	var o := ORCHESTRATOR.new() if host else NonAuthority.new()
	var enemies := Node2D.new()
	add_child_autofree(o)
	add_child_autofree(enemies)
	o.set_enemy_container(enemies)
	return {"o": o, "enemies": enemies}

func _start() -> Dictionary:
	var f := _fixture()
	var o: RegenteEncounterOrchestrator = f.o
	assert_true(o.start(0))
	return f

func _complete_electric_cycle(o: RegenteEncounterOrchestrator) -> void:
	o._physics_process(o.ELECTRIC_COOLDOWN_SECONDS)
	o._physics_process(o.ELECTRIC_TELEGRAPH_SECONDS)
	o._physics_process(o.ELECTRIC_ATTACK_PULSE_SECONDS)
	o._physics_process(o.ELECTRIC_SETTLE_SECONDS)

func _advance_explosive(o: RegenteEncounterOrchestrator) -> void:
	for duration in [o.EXPLOSIVE_TRANSITION_SECONDS, o.EXPLOSIVE_TRACKING_SECONDS, o.EXPLOSIVE_LOCKED_SECONDS, o.EXPLOSIVE_DETONATION_SECONDS, o.EXPLOSIVE_BANK_INTERVAL_SECONDS, o.EXPLOSIVE_TRACKING_SECONDS, o.EXPLOSIVE_LOCKED_SECONDS, o.EXPLOSIVE_DETONATION_SECONDS, o.EXPLOSIVE_BANK_INTERVAL_SECONDS, o.EXPLOSIVE_TRACKING_SECONDS, o.EXPLOSIVE_LOCKED_SECONDS, o.EXPLOSIVE_DETONATION_SECONDS, o.EXPLOSIVE_RECONSTITUTE_SECONDS]:
		o._physics_process(duration)

func test_host_initializes_twelve_cocoons_and_non_host_does_not_mutate() -> void:
	var f := _start()
	var snapshot: Dictionary = f.o.explosive_runtime_snapshot()
	assert_eq(snapshot.formation.cocoons.size(), 12)
	assert_eq(snapshot.formation.cocoons.keys(), range(1, 13))
	assert_eq(f.o._explosive_cocoons.size(), 12)
	for cocoon in f.o._explosive_cocoons:
		assert_true(cocoon.get_parent() == f.o)
		assert_true(f.o.is_ancestor_of(cocoon))
	var remote := _fixture(false)
	assert_true(remote.o.start(0))
	assert_eq(remote.enemies.get_child_count(), 0)
	assert_eq(remote.o.explosive_runtime_snapshot().cycle, RegenteEncounterOrchestrator.ExplosiveCycle.INACTIVE)

func test_explosive_transition_runs_full_duration_before_tracking() -> void:
	var f := _start()
	var o: RegenteEncounterOrchestrator = f.o
	_complete_electric_cycle(o)
	assert_eq(o._explosive_cycle, RegenteEncounterOrchestrator.ExplosiveCycle.TRANSITION)
	assert_eq(o._explosive_elapsed, 0.0)
	o._physics_process(o.EXPLOSIVE_TRANSITION_SECONDS - 0.001)
	assert_eq(o._explosive_cycle, RegenteEncounterOrchestrator.ExplosiveCycle.TRANSITION)
	o._physics_process(0.001)
	assert_eq(o._explosive_cycle, RegenteEncounterOrchestrator.ExplosiveCycle.TRACKING)

func test_cleanup_releases_owned_cocoons_without_orphans() -> void:
	var f := _start()
	var o: RegenteEncounterOrchestrator = f.o
	assert_eq(o._explosive_cocoons.size(), 12)
	o.stop()
	assert_true(o._explosive_cocoons.is_empty())
	await get_tree().process_frame
	for child in o.get_children():
		assert_false(child is CasuloExplosivo)

func test_full_electric_cycle_enters_transition_then_all_explosive_states() -> void:
	var f := _start()
	var o: RegenteEncounterOrchestrator = f.o
	_complete_electric_cycle(o)
	assert_eq(o._explosive_cycle, RegenteEncounterOrchestrator.ExplosiveCycle.TRANSITION)
	for wanted in [RegenteEncounterOrchestrator.ExplosiveCycle.TRACKING, RegenteEncounterOrchestrator.ExplosiveCycle.LOCKED, RegenteEncounterOrchestrator.ExplosiveCycle.DETONATION, RegenteEncounterOrchestrator.ExplosiveCycle.BANK_INTERVAL]:
		for _step in range(200):
			if o._explosive_cycle == wanted: break
			o._physics_process(0.01)
		assert_eq(o._explosive_cycle, wanted)

func test_explosive_sequence_is_ordered_and_reconstitutes_12_ids() -> void:
	var f := _start()
	var o: RegenteEncounterOrchestrator = f.o
	_complete_electric_cycle(o)
	_advance_explosive(o)
	var snapshot: Dictionary = o.explosive_runtime_snapshot()
	assert_eq(snapshot.cycle, RegenteEncounterOrchestrator.ExplosiveCycle.INACTIVE)
	assert_eq(snapshot.formation.cocoons.size(), 12)
	assert_eq(snapshot.formation.next_bank_index, 0)
	for id in range(1, 13):
		assert_eq(snapshot.formation.cocoons[id].id, id)
		assert_eq(snapshot.formation.cocoons[id].state, CASULO.State.IN_SLOT)

func test_tracking_is_deterministic_and_lock_freezes_position() -> void:
	var f := _start()
	var o: RegenteEncounterOrchestrator = f.o
	_complete_electric_cycle(o)
	for _step in range(100):
		if o._explosive_cycle == RegenteEncounterOrchestrator.ExplosiveCycle.TRACKING: break
		o._physics_process(0.01)
	var origin: Vector2 = o._explosive_formation.get_cocoon(5).global_position
	o._physics_process(o.EXPLOSIVE_TRACKING_SECONDS * 0.5)
	var tracked: Vector2 = o._explosive_formation.get_cocoon(5).global_position
	for _step in range(100):
		if o._explosive_cycle == RegenteEncounterOrchestrator.ExplosiveCycle.LOCKED: break
		o._physics_process(0.01)
	assert_eq(o._explosive_cycle, RegenteEncounterOrchestrator.ExplosiveCycle.LOCKED)
	var locked: Vector2 = o._explosive_formation.get_cocoon(5).locked_position
	assert_ne(tracked, origin)
	assert_eq(locked, o._explosive_formation.get_cocoon(5).global_position)
	o._explosive_formation.get_cocoon(5).global_position = Vector2(999, 999)
	assert_eq(o._explosive_formation.get_cocoon(5).locked_position, locked)

func test_damage_contract_and_target_filter_are_explicit() -> void:
	var f := _start()
	var o: RegenteEncounterOrchestrator = f.o
	assert_eq(o.EXPLOSIVE_COLLISION_MASK, 6)
	assert_eq(o.EXPLOSIVE_RADIUS_PX, 24.0)
	assert_eq(o.EXPLOSIVE_DAMAGE_HEALTH_UNITS, 25)
	var no_health := Node.new()
	no_health.add_to_group("player")
	assert_false(o._is_explosive_damage_target(no_health))
	var boss: Node = f.enemies.get_child(0)
	assert_true(o._is_explosive_damage_target(boss))

func test_missing_electric_id_aborts_without_crash_and_cleans_query() -> void:
	var f := _start()
	var o: RegenteEncounterOrchestrator = f.o
	_complete_electric_cycle(o)
	assert_true(o.destroy_electric_drone(int(o._electric_slots[0].drone_id)))
	o._physics_process(0.1)
	assert_eq(o._explosive_cycle, o.ExplosiveCycle.INACTIVE)
	assert_eq(o._explosive_formation.runtime_snapshot().next_bank_index, 0)
	o.stop()
	assert_eq(o.explosive_runtime_snapshot().formation, {})
	o._physics_process(99.0)
	assert_eq(o._explosive_cycle, o.ExplosiveCycle.INACTIVE)

func test_two_cocoons_hit_same_health_target_twice_at_25_and_boss_accepts_damage() -> void:
	var f := _start()
	var target := HealthTarget.new()
	add_child_autofree(target)
	var c1 := CASULO.new()
	var c2 := CASULO.new()
	add_child_autofree(c1); add_child_autofree(c2)
	for pair in [[c1, 1], [c2, 2]]:
		assert_true(pair[0].set_slot_id(pair[1]))
		assert_true(pair[0].enter_slot())
		var tags: Array[StringName] = [&"explosive"]
		assert_true(pair[0].configure_damage(25, self, tags, Vector2.ZERO))
		assert_true(pair[0].start_tracking(Vector2.ZERO))
		assert_true(pair[0].lock_position(Vector2.ZERO))
	assert_eq(c1.detonate([target, target]), 1)
	assert_eq(c2.detonate([target]), 1)
	assert_eq(target.received.size(), 2)
	assert_eq(target.received[0].amount, 25)
	assert_true(f.o._is_explosive_damage_target(f.enemies.get_child(0)))
