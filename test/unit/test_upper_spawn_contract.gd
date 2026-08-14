extends GutTest

const ROOM_DEF := preload("res://scripts/rooms/room_def.gd")
const DIRECTOR := preload("res://scripts/directors/spawn_director.gd")
const ROOM := preload("res://scenes/rooms/room.tscn")
const SECTOR_GENERATOR := preload("res://scripts/run/sector_generator.gd")

func _session_with_room(room: Node) -> Session:
	var session := Session.new()
	var player := Node2D.new()
	player.name = "Player"
	var camera := Camera2D.new()
	camera.name = "Camera2D"
	var room_host := Node.new()
	room_host.name = "RoomHost"
	var hyperspace := HyperspaceUI.new()
	hyperspace.name = "HyperspaceUI"
	session.add_child(player)
	session.add_child(camera)
	session.add_child(room_host)
	session.add_child(hyperspace)
	session.room_host_path = NodePath("RoomHost")
	session.hyperspace_path = NodePath("HyperspaceUI")
	session.player_path = NodePath("Player")
	session.camera_path = NodePath("Camera2D")
	session.run_state = RunState.new()
	room_host.add_child(room)
	session._active_room = room
	session._room_active = true
	add_child_autofree(session)
	await get_tree().process_frame
	return session

func test_upper_profile_is_eight_entries_in_approved_order() -> void:
	var waves: Array[RoomDef.WaveSpec] = ROOM_DEF.new().get_upper_waves()
	assert_eq(waves.size(), 1)
	assert_eq(waves[0].threat_types, [&"common", &"common", &"atirador", &"common", &"common", &"kamikaze", &"atirador", &"kamikaze"])
	var director := DIRECTOR.new()
	add_child_autofree(director)
	RunManager.start_run(424242)
	var agenda: Array[Dictionary] = director.build_spawn_agenda(waves)
	assert_eq(agenda.size(), 8)
	var types: Array[StringName] = []
	for entry in agenda:
		types.append(StringName(entry.threat_type))
	assert_eq(types, waves[0].threat_types)
	RunManager.start_run(424242)
	var repeat_agenda: Array[Dictionary] = director.build_spawn_agenda(waves)
	assert_eq(repeat_agenda.size(), agenda.size())
	for index in agenda.size():
		assert_eq(repeat_agenda[index].threat_type, agenda[index].threat_type)
		assert_eq(repeat_agenda[index].edge, agenda[index].edge)
		assert_eq(repeat_agenda[index].point, agenda[index].point)

func test_room_profiles_select_upper_environment_by_topology_and_keep_defaults() -> void:
	var session := Session.new()
	session.run_state = RunState.new()
	session.run_state.sector_index = 1
	var sector := SECTOR_GENERATOR.generate(1234, 1)
	var upper := sector.get_node(13)
	var upper_def: RoomDef = session._room_def_for(upper)
	assert_eq(upper.room_profile, &"upper")
	assert_eq(upper_def.encounter_profile, &"upper")
	assert_eq(upper_def.environment_profile, &"upper_background_human_s2")
	assert_eq(upper_def.transition_profile, &"default")
	var treasure := SECTOR_GENERATOR.generate(1234, 2).get_node(23)
	session.run_state.sector_index = 2
	var treasure_def: RoomDef = session._room_def_for(treasure)
	assert_eq(treasure.node_type, SectorNode.NodeType.TREASURE)
	assert_eq(treasure.room_profile, &"upper")
	assert_eq(treasure_def.environment_profile, &"sector3_upper_core")
	assert_eq(treasure_def.transition_profile, &"sector3_upper_transition")
	var ordinary := RoomDef.new()
	assert_eq(ordinary.encounter_profile, &"default")
	assert_eq(ordinary.environment_profile, &"default")
	assert_eq(ordinary.transition_profile, &"default")

func test_upper_profile_uses_one_point_one_second_cadence() -> void:
	var waves: Array[RoomDef.WaveSpec] = ROOM_DEF.new().get_upper_waves()
	assert_eq(waves[0].cadence, 1.1)

func test_upper_profile_has_three_deterministic_in_bounds_debris() -> void:
	var room_def := ROOM_DEF.new()
	room_def.configure_upper_waves()
	room_def.environment_profile = &"upper_background_human_s2"
	assert_eq(room_def.initial_debris.size(), 3)
	for spec in room_def.initial_debris:
		assert_true(room_def.get_bounds().has_point(spec.position))
	assert_eq(room_def.initial_debris[0].position, Vector2(180.0, 132.0))

func test_upper_room_spawns_only_the_configured_debris() -> void:
	var room_def := ROOM_DEF.new()
	room_def.configure_upper_waves()
	room_def.environment_profile = &"upper_background_human_s2"
	var room := ROOM.instantiate()
	room.get_node("RoomController").room_def = room_def
	add_child_autofree(room)
	await get_tree().process_frame
	var debris_container := room.get_node_or_null("Debris")
	assert_not_null(debris_container)
	assert_eq(debris_container.get_child_count(), 3)
	for debris in debris_container.get_children():
		assert_true(room_def.get_bounds().has_point(debris.global_position))
		assert_eq(debris.drift_velocity, room_def.initial_debris[debris_container.get_children().find(debris)].drift_velocity)
	assert_eq(room.get_node("Directors/SpawnDirector")._container, room.get_node("Enemies"))
	assert_eq(room.get_node("Directors/SpawnDirector")._local_container, room.get_node("Enemies"))
	var presentation := room.get_node_or_null("Environment/EnvironmentPresentation") as EnvironmentPresentation
	assert_not_null(presentation)
	var extension := room.get_node_or_null("Environment/EnvironmentPresentation/UpperSpaceExtension") as Sprite2D
	assert_not_null(extension)
	assert_eq(extension.position, Vector2(360.0, 202.5))
	assert_eq(extension.scale, Vector2(1.5, 1.5))
	assert_eq(extension.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)
	assert_not_null(extension.texture)
	assert_true(presentation.z_index + extension.z_index > room.get_node("Environment").z_index)

func test_default_room_keeps_global_background_and_revisit_teardown_is_local() -> void:
	var room_def := RoomDef.new()
	var room := ROOM.instantiate()
	room.get_node("RoomController").room_def = room_def
	add_child_autofree(room)
	await get_tree().process_frame
	assert_null(room.get_node_or_null("Environment/EnvironmentPresentation"))
	var debris := room.get_node_or_null("Debris")
	assert_null(debris)
	room.queue_free()
	await get_tree().process_frame
	assert_eq(get_tree().get_nodes_in_group("debris").size(), 0)

func test_upper_room_disposal_removes_all_debris_nodes() -> void:
	var room_def := ROOM_DEF.new()
	room_def.configure_upper_waves()
	var room := ROOM.instantiate()
	room.get_node("RoomController").room_def = room_def
	var session := await _session_with_room(room)
	await get_tree().process_frame
	var debris_container := room.get_node_or_null("Debris")
	assert_not_null(debris_container)
	assert_eq(debris_container.get_child_count(), 3)

	session.reset_run()
	await get_tree().process_frame
	assert_eq(get_tree().get_nodes_in_group("debris").size(), 0)

func test_explicit_common_uses_and_advances_regular_configuration() -> void:
	var room_root := Node.new()
	add_child_autofree(room_root)
	var container := Node.new()
	container.add_to_group(&"enemies_container")
	room_root.add_child(container)
	var director := DIRECTOR.new()
	room_root.add_child(director)
	await get_tree().process_frame
	var first := director._spawn_configured(false, 0, Vector2(100.0, 100.0), &"common")
	var second := director._spawn_configured(false, 0, Vector2(120.0, 100.0), &"common")
	assert_eq(first.movement, Enemy.Movement.CHASE)
	assert_eq(first.max_health, 3.0)
	assert_eq(second.movement, Enemy.Movement.DESCEND)
	assert_eq(second.max_health, 2.0)
