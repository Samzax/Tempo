extends GutTest

const ROOM_SCENE := preload("res://scenes/rooms/room.tscn")
const GENERATOR := preload("res://scripts/run/sector_generator.gd")
const SESSION := preload("res://scripts/run/session.gd")
const ORCHESTRATOR := preload("res://scripts/enemies/bosses/regente_encounter_orchestrator.gd")
const DAMAGE_INFO := preload("res://scripts/combat/damage_info.gd")

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
