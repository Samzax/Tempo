extends GutTest

const ORCHESTRATOR := preload("res://scripts/enemies/bosses/regente_encounter_orchestrator.gd")

class NonAuthorityOrchestrator extends RegenteEncounterOrchestrator:
	func _has_host_authority() -> bool:
		return false

func _fixture(host := true) -> Dictionary:
	var orchestrator := ORCHESTRATOR.new() if host else NonAuthorityOrchestrator.new()
	var enemies := Node2D.new()
	add_child_autofree(orchestrator)
	add_child_autofree(enemies)
	orchestrator.set_enemy_container(enemies)
	return {"orchestrator": orchestrator, "enemies": enemies}

func test_host_start_enters_cooldown_with_only_electric_core() -> void:
	var f := _fixture()
	var o: RegenteEncounterOrchestrator = f.orchestrator
	assert_true(o.start(0))
	assert_eq(o.state, RegenteEncounterOrchestrator.State.ATTACK_HANDOFF)
	assert_eq(o._combat_cycle, RegenteEncounterOrchestrator.CombatCycle.COOLDOWN)
	assert_true(o._combat_loop_active)
	assert_eq(f.enemies.get_child_count(), 1)
	assert_eq(o._electric_slots.size(), 12)

func test_delta_advances_full_cycle_back_to_cooldown() -> void:
	var f := _fixture()
	var o: RegenteEncounterOrchestrator = f.orchestrator
	o.start(0)
	o._physics_process(o.ELECTRIC_COOLDOWN_SECONDS)
	assert_eq(o._combat_cycle, RegenteEncounterOrchestrator.CombatCycle.TELEGRAPH)
	o._physics_process(o.ELECTRIC_TELEGRAPH_SECONDS)
	assert_eq(o._combat_cycle, RegenteEncounterOrchestrator.CombatCycle.ATTACK_PULSE)
	o._physics_process(o.ELECTRIC_ATTACK_PULSE_SECONDS)
	assert_eq(o._combat_cycle, RegenteEncounterOrchestrator.CombatCycle.SETTLE)
	o._physics_process(o.ELECTRIC_SETTLE_SECONDS)
	assert_eq(o._combat_cycle, RegenteEncounterOrchestrator.CombatCycle.COOLDOWN)

func test_telegraph_and_pulse_open_all_twelve_slots_deterministically() -> void:
	var f := _fixture()
	var o: RegenteEncounterOrchestrator = f.orchestrator
	o.start(0)
	o._physics_process(o.ELECTRIC_COOLDOWN_SECONDS)
	o._physics_process(0.0)
	var core: RegenteDosEcos = f.enemies.get_child(0)
	var snapshot := core.electric_grid_controller().electric_subnet.snapshot()
	assert_eq(snapshot.formation_open_drone_ids.size(), 12)
	for slot in o._electric_slots:
		var id := int(slot.drone_id)
		assert_true(snapshot.formation_open_drone_ids.has(id))
		assert_eq(_drone(snapshot, id).position, core.global_position + Vector2(slot.offset) * o.ELECTRIC_OPEN_OFFSET_SCALE)
	o._physics_process(o.ELECTRIC_TELEGRAPH_SECONDS)
	assert_eq(o._combat_cycle, RegenteEncounterOrchestrator.CombatCycle.ATTACK_PULSE)
	o._physics_process(0.0)
	assert_eq(core.electric_grid_controller().electric_subnet.snapshot().formation_open_drone_ids.size(), 12)

func test_settle_restores_base_offsets_and_closes_formation_atomically() -> void:
	var f := _fixture()
	var o: RegenteEncounterOrchestrator = f.orchestrator
	o.start(0)
	o._physics_process(o.ELECTRIC_COOLDOWN_SECONDS + o.ELECTRIC_TELEGRAPH_SECONDS + o.ELECTRIC_ATTACK_PULSE_SECONDS)
	assert_eq(o._combat_cycle, RegenteEncounterOrchestrator.CombatCycle.SETTLE)
	o._physics_process(0.0)
	var core: RegenteDosEcos = f.enemies.get_child(0)
	var snapshot := core.electric_grid_controller().electric_subnet.snapshot()
	assert_true(snapshot.formation_open_drone_ids.is_empty())
	for slot in o._electric_slots:
		assert_eq(_drone(snapshot, int(slot.drone_id)).position, core.global_position + Vector2(slot.offset))

func test_non_authority_does_not_advance_cycle_or_mutate_drones() -> void:
	var f := _fixture(false)
	var o: RegenteEncounterOrchestrator = f.orchestrator
	o.start(0)
	o._physics_process(99.0)
	assert_eq(o._combat_cycle, RegenteEncounterOrchestrator.CombatCycle.COOLDOWN)
	assert_false(o._combat_loop_active)
	assert_eq(f.enemies.get_child_count(), 0)

func _drone(snapshot: Dictionary, drone_id: int) -> Dictionary:
	for drone in snapshot.drones:
		if int(drone.id) == drone_id:
			return drone
	return {}

func test_defeat_and_stop_cancel_loop_without_later_updates() -> void:
	var f := _fixture()
	var o: RegenteEncounterOrchestrator = f.orchestrator
	o.start(0)
	var core: Enemy = f.enemies.get_child(0)
	o.notify_core_resolved(core, 0)
	assert_eq(o.state, RegenteEncounterOrchestrator.State.VICTORY)
	assert_false(o._combat_loop_active)
	assert_true(o._electric_slots.is_empty())
	o._physics_process(99.0)
	# A fixture bare não tem RoomController para remover o core do container.
	# O contrato desta fixture é o cancelamento do loop e o teardown do
	# orchestrator; a remoção da árvore de inimigos pertence à sala real.
	assert_eq(o.state, RegenteEncounterOrchestrator.State.VICTORY)
	assert_eq(o._electric_slots.size(), 0)
	assert_eq(f.enemies.get_child_count(), 1)
