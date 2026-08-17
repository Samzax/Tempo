extends GutTest

const ORCHESTRATOR := preload("res://scripts/enemies/bosses/regente_encounter_orchestrator.gd")

class NonHostOrchestrator extends RegenteEncounterOrchestrator:
	func _has_host_authority() -> bool: return false

func _fixture(host := true) -> Dictionary:
	var orchestrator := (NonHostOrchestrator.new() if not host else ORCHESTRATOR.new())
	var enemies := Node2D.new()
	add_child_autofree(orchestrator); add_child_autofree(enemies)
	orchestrator.set_enemy_container(enemies)
	return {"orchestrator": orchestrator, "enemies": enemies}

func test_start_creates_open_wings_then_settles_into_subnets() -> void:
	var f := _fixture(); var o: RegenteEncounterOrchestrator = f.orchestrator
	assert_true(o.start(0)); var core := f.enemies.get_child(0) as RegenteDosEcos
	assert_eq(o._electric_slots.size(), 12); assert_eq(core.electric_drone_ids().size(), 12)
	assert_eq(core.electric_grid_controller().electric_subnet.edges().size(), 0)
	assert_eq(core.electric_grid_controller()._areas.size(), 0)
	o._physics_process(0.0)
	assert_gt(core.electric_grid_controller().electric_subnet.subnets().size(), 0)
	assert_gt(core.electric_grid_controller()._areas.size(), 0)

func test_destroy_tombstones_id_and_replaces_once_per_interval_with_monotonic_id() -> void:
	var f := _fixture(); var o: RegenteEncounterOrchestrator = f.orchestrator
	o.start(0); var core := f.enemies.get_child(0) as RegenteDosEcos
	var old_id := core.electric_drone_ids()[0]; assert_true(o.destroy_electric_drone(old_id)); assert_false(core.electric_drone_ids().has(old_id))
	o._physics_process(0.99); assert_eq(core.electric_drone_ids().size(), 11)
	o._physics_process(0.01); assert_eq(core.electric_drone_ids().size(), 12)
	var new_id := core.electric_drone_ids().max(); assert_gt(new_id, old_id)
	assert_true(o._electric_slots.any(func(slot): return int(slot.drone_id) == new_id and bool(slot.transition) and int(slot.index) == 0))
	var before_settle := core.electric_grid_controller().electric_subnet.snapshot()
	assert_true(before_settle.formation_open_drone_ids.has(new_id))
	assert_false(before_settle.subnets.any(func(subnet): return subnet.drone_ids.has(new_id)))
	assert_false(core.electric_grid_controller()._areas.has(str(new_id)))
	assert_eq(core.electric_grid_controller()._areas.size(), 2)
	o._physics_process(0.0)
	var after_settle := core.electric_grid_controller().electric_subnet.snapshot()
	assert_false(after_settle.formation_open_drone_ids.has(new_id))
	assert_true(after_settle.subnets.any(func(subnet): return subnet.drone_ids.has(new_id)))
	assert_gt(core.electric_grid_controller()._areas.size(), 0)
	o._physics_process(1.0); assert_eq(core.electric_drone_ids().size(), 12)

func test_non_host_and_stop_resolution_are_lifecycle_noops_and_idempotent() -> void:
	var f := _fixture(false); var o: RegenteEncounterOrchestrator = f.orchestrator
	assert_true(o.start(0)); assert_eq(f.enemies.get_child_count(), 0)
	var g := _fixture(); var host: RegenteEncounterOrchestrator = g.orchestrator
	host.start(0); var core := g.enemies.get_child(0) as RegenteDosEcos
	host._physics_process(0.0)
	var area_count_before_stop := core.electric_grid_controller()._areas.size()
	assert_gt(area_count_before_stop, 0)
	host.stop(); host.stop(); assert_eq(host._electric_slots.size(), 0)
	assert_null(core.electric_grid_controller())
