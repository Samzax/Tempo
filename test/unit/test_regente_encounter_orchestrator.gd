extends GutTest

const ROOM_SCENE := preload("res://scenes/rooms/room.tscn")
const GENERATOR := preload("res://scripts/run/sector_generator.gd")
const SESSION := preload("res://scripts/run/session.gd")
const ORCHESTRATOR := preload("res://scripts/enemies/bosses/regente_encounter_orchestrator.gd")
const DAMAGE_INFO := preload("res://scripts/combat/damage_info.gd")
const REGENTE_SCENE := preload("res://scenes/enemies/bosses/regente_dos_ecos.tscn")
const CASULO_SCENE := preload("res://scenes/enemies/bosses/wings/casulo_explosivo.tscn")
const LASER_SCENE := preload("res://scenes/enemies/bosses/wings/laser_beam_2d.tscn")

class NonAuthorityOrchestrator extends RegenteEncounterOrchestrator:
	func _has_host_authority() -> bool:
		return false

func test_n6_materializes_regente_profile_without_generic_waves() -> void:
	var sector := GENERATOR.generate(20260814, 0)
	var session := SESSION.new()
	autofree(session)
	var room_def := session._room_def_for(sector.get_node(6))
	assert_eq(sector.get_node(6).encounter_profile, &"regente_dos_ecos")
	assert_eq(room_def.encounter_profile, &"regente_dos_ecos")
	assert_eq(room_def.finite_spawn_count, 0)
	assert_eq(room_def.cull_policy, RoomDef.CullPolicy.NONE)
	assert_false(room_def.has_waves())

func test_host_spawns_one_core_and_finishes_once_without_attacks() -> void:
	var fixture := _regente_orchestrator()
	var orchestrator: RegenteEncounterOrchestrator = fixture.orchestrator
	var enemies: Node = fixture.enemies
	var spawned := [0]
	var finished := [0]
	orchestrator.enemy_spawned.connect(func(_enemy: Enemy): spawned[0] += 1)
	orchestrator.spawns_finished.connect(func(): finished[0] += 1)
	assert_true(orchestrator.start(0))
	assert_eq(orchestrator.state, RegenteEncounterOrchestrator.State.ATTACK_HANDOFF)
	assert_eq(enemies.get_child_count(), 1)
	assert_eq(spawned[0], 1)
	assert_eq(finished[0], 1)

func test_core_resolution_clears_room_once_and_tears_down_owned_children() -> void:
	var room := _regente_room()
	var controller := room.get_node("RoomController") as RoomController
	watch_signals(controller)
	await get_tree().process_frame
	var core := room.get_node("Enemies").get_child(0) as RegenteDosEcos
	var grid := ElectricGridController.new()
	core.add_child(grid)
	var owned := Node.new()
	owned.set_meta(&"regente_encounter_owned", true)
	core.add_child(owned)
	var health_component: HealthComponent = core.get_node_or_null("HealthComponent") as HealthComponent
	assert_not_null(health_component)
	if health_component == null:
		return
	var info := DAMAGE_INFO.new()
	info.amount = health_component.max_health
	core.take_damage(info)
	for _frame in range(8):
		if controller.runtime.is_cleared():
			break
		await get_tree().process_frame
	assert_true(controller.runtime.is_cleared())
	await get_tree().process_frame
	assert_eq(controller.runtime.active_enemy_count(), 0)
	assert_signal_emit_count(controller, &"room_cleared", 1)
	assert_signal_emit_count(controller, &"room_completed", 1)
	assert_eq(room.get_node("Enemies").get_child_count(), 0)
	assert_false(is_instance_valid(grid))
	assert_false(is_instance_valid(owned))
	assert_eq(room.get_node("Directors").get_child_count(), 2)
	assert_true(controller.exit_is_unlocked)

func test_start_resolution_and_stop_twice_are_idempotent() -> void:
	var fixture := _regente_orchestrator()
	var orchestrator: RegenteEncounterOrchestrator = fixture.orchestrator
	var core_events := [0]
	var finishes := [0]
	orchestrator.enemy_spawned.connect(func(_enemy: Enemy): core_events[0] += 1)
	orchestrator.spawns_finished.connect(func(): finishes[0] += 1)
	assert_true(orchestrator.start(0))
	var core := fixture.enemies.get_child(0) as Enemy
	orchestrator.notify_core_resolved(core, 0)
	orchestrator.notify_core_resolved(core, 0)
	orchestrator.stop()
	orchestrator.stop()
	assert_eq(core_events[0], 1)
	assert_eq(finishes[0], 1)
	assert_eq(orchestrator.state, RegenteEncounterOrchestrator.State.VICTORY)

func test_none_culling_does_not_resolve_core_outside_arena() -> void:
	var room := _regente_room()
	var controller := room.get_node("RoomController") as RoomController
	await get_tree().process_frame
	var core := room.get_node("Enemies").get_child(0) as RegenteDosEcos
	core.global_position = Vector2(-10000.0, 10000.0)
	await get_tree().process_frame
	assert_true(is_instance_valid(core))
	assert_false(controller.runtime.is_cleared())
	assert_eq(controller.runtime.active_enemy_count(), 1)

func test_non_authority_public_host_flag_does_not_mutate() -> void:
	var orchestrator := NonAuthorityOrchestrator.new()
	var enemies := Node2D.new()
	add_child_autofree(orchestrator)
	add_child_autofree(enemies)
	orchestrator.set_enemy_container(enemies)
	assert_true(orchestrator.start(0))
	assert_eq(enemies.get_child_count(), 0)
	assert_eq(orchestrator.state, RegenteEncounterOrchestrator.State.INTRO)

func test_regente_scene_binds_dynamic_grid_controller_and_renders_snapshot_without_mutation() -> void:
	var core := REGENTE_SCENE.instantiate() as RegenteDosEcos
	add_child_autofree(core)
	await get_tree().process_frame
	var visual := core.get_node("ElectricGridVisual") as ElectricGridVisual
	assert_not_null(visual)
	assert_true(core.configure_electric_geometry(58.0, 74.0, 18.0))
	var controller := core.electric_grid_controller()
	assert_not_null(controller)
	if controller == null:
		return
	assert_true(core.spawn_electric_drone(Vector2(20.0, 30.0)).has("id"))
	var before := controller.active_snapshot()
	await get_tree().process_frame
	await get_tree().process_frame
	var after := controller.active_snapshot()
	var snapshot := visual.runtime_snapshot()
	assert_true(snapshot.controller_bound)
	assert_eq(snapshot.drone_count, 1)
	assert_gt(snapshot.visual_node_count, 0)
	assert_eq(after, before)
	assert_eq(controller.active_snapshot(), after)

func test_orchestrator_uses_visual_packed_scenes_for_core_cocoons_and_all_laser_creation_paths() -> void:
	var fixture := _regente_orchestrator()
	var orchestrator: RegenteEncounterOrchestrator = fixture.orchestrator
	assert_true(orchestrator.start(0))
	var core := fixture.enemies.get_child(0) as RegenteDosEcos
	assert_true(core.get_node("ElectricGridVisual") is ElectricGridVisual)
	assert_eq(orchestrator._explosive_cocoons.size(), 12)
	for cocoon in orchestrator._explosive_cocoons:
		assert_true(cocoon is CasuloExplosivo)
		assert_true(cocoon.scene_file_path.ends_with("casulo_explosivo.tscn"))
		assert_true(cocoon.get_node("Visual") is CasuloExplosivoVisual)
		assert_eq(cocoon.damage_amount, orchestrator.EXPLOSIVE_DAMAGE_HEALTH_UNITS)
	for pattern in [orchestrator.LaserPattern.SHIELD, orchestrator.LaserPattern.HALO]:
		orchestrator._initialize_laser_beams(pattern)
		assert_gt(orchestrator._laser_beams.size(), 0)
		for beam in orchestrator._laser_beams:
			assert_true(beam is LaserBeam2D)
			assert_true(beam.scene_file_path.ends_with("laser_beam_2d.tscn"))
			assert_not_null(beam.get_node_or_null("ActiveBeam"))
			assert_eq(beam.damage_amount, orchestrator.LASER_DAMAGE_HEALTH_UNITS)
			assert_eq(beam.collision_mask, 6)

func test_dynamic_rift_and_whip_beams_keep_visual_children_and_logical_snapshots() -> void:
	var fixture := _regente_orchestrator()
	var orchestrator: RegenteEncounterOrchestrator = fixture.orchestrator
	assert_true(orchestrator.start(0))
	orchestrator._next_laser_pattern = orchestrator.LaserPattern.RIFT
	assert_true(orchestrator._begin_laser_cycle())
	orchestrator._activate_rift_links([Vector2i(0, 1), Vector2i(1, 2)])
	assert_gt(orchestrator._laser_beams.size(), 0)
	for beam in orchestrator._laser_beams:
		assert_not_null(beam.get_node_or_null("Telegraph"))
		assert_eq(beam.runtime_snapshot().state, LaserBeam2D.State.FIRING)
	orchestrator._release_laser_beams()
	orchestrator._whip_current_offsets = orchestrator.LASER_WHIP_OFFSETS.duplicate()
	orchestrator._start_whip_crack()
	assert_gt(orchestrator._laser_beams.size(), 0)
	for beam in orchestrator._laser_beams:
		assert_not_null(beam.get_node_or_null("Emitter"))
		assert_eq(beam.damage_amount, orchestrator.LASER_DAMAGE_HEALTH_UNITS)

func test_stop_cleans_scene_instances_without_new_orphans_and_preserves_childless_compatibility() -> void:
	var fixture := _regente_orchestrator()
	var orchestrator: RegenteEncounterOrchestrator = fixture.orchestrator
	assert_true(orchestrator.start(0))
	assert_eq(fixture.enemies.get_child_count(), 1)
	assert_eq(orchestrator._explosive_cocoons.size(), 12)
	assert_gt(orchestrator._laser_beams.size(), 0)
	orchestrator.stop()
	orchestrator.stop()
	await get_tree().process_frame
	assert_eq(orchestrator._explosive_cocoons.size(), 0)
	assert_eq(orchestrator._laser_beams.size(), 0)
	assert_eq(orchestrator.get_child_count(), 0)
	assert_eq(fixture.enemies.get_child_count(), 1)
	for node in fixture.enemies.get_children():
		assert_true(node is RegenteDosEcos)

func _regente_orchestrator() -> Dictionary:
	var orchestrator := ORCHESTRATOR.new()
	var enemies := Node2D.new()
	add_child_autofree(orchestrator)
	add_child_autofree(enemies)
	orchestrator.set_enemy_container(enemies)
	return {"orchestrator": orchestrator, "enemies": enemies}

func _regente_room() -> Node:
	var room := ROOM_SCENE.instantiate()
	var def := RoomDef.new()
	def.configure_regente_dos_ecos_encounter()
	room.get_node("RoomController").room_def = def
	add_child_autofree(room)
	return room
