extends GutTest

const GENERATOR := preload("res://scripts/run/sector_generator.gd")
const SESSION := preload("res://scripts/run/session.gd")

class PlayerFixture extends Node2D:

	func set_room_bounds(_bounds: Rect2) -> void:
		pass

func test_single_sector_topology_types_profiles_and_disconnected_nodes() -> void:
	var sector := GENERATOR.generate(20260814, 0)
	assert_not_null(sector)
	assert_eq(sector.sector_index, 0)
	assert_eq(sector.nodes.keys(), [0, 1, 2, 3, 4, 5, 6])
	assert_eq(sector.get_children(0), [1])
	assert_eq(sector.get_children(1), [3])
	assert_eq(sector.get_children(3), [6])
	for node_id in [2, 4, 5, 6]:
		assert_eq(sector.get_children(node_id), [])
	assert_eq(sector.get_node(0).node_type, SectorNode.NodeType.OPENING)
	assert_eq(sector.get_node(1).node_type, SectorNode.NodeType.COMBAT)
	assert_eq(sector.get_node(3).node_type, SectorNode.NodeType.TREASURE)
	assert_eq(sector.get_node(6).node_type, SectorNode.NodeType.BOSS)
	assert_eq(sector.get_node(0).encounter_profile, &"phase_one")
	assert_eq(sector.get_node(1).encounter_profile, &"upper")
	assert_eq(sector.get_node(1).environment_profile, &"upper_background_human_s2")
	assert_eq(sector.get_node(3).encounter_profile, &"sector3_upper")
	assert_eq(sector.get_node(3).environment_profile, &"sector3_upper_core")
	assert_eq(sector.get_node(3).transition_profile, &"sector3_upper_transition")

func test_generator_rejects_nonzero_sector_and_warp_accepts_only_typed_nodes() -> void:
	assert_null(GENERATOR.generate(7, 1))
	var session := SESSION.new()
	var fixture_root := Node.new()
	var world := Node.new(); world.name = "World"
	var ui := Node.new(); ui.name = "UI"
	fixture_root.add_child(world); fixture_root.add_child(session); fixture_root.add_child(ui)
	var player := PlayerFixture.new(); player.name = "Player"
	var camera := Camera2D.new(); camera.name = "Camera2D"
	var room_host := Node.new(); room_host.name = "RoomHost"
	var hyperspace := HyperspaceUI.new(); hyperspace.name = "HyperspaceUI"
	var choice := ItemChoice.new(); choice.name = "ItemChoice"; ui.add_child(choice)
	world.add_child(player); world.add_child(camera)
	session.add_child(room_host); session.add_child(hyperspace)
	session.player_path = ^"../World/Player"; session.camera_path = ^"../World/Camera2D"; session.room_host_path = ^"RoomHost"; session.hyperspace_path = ^"HyperspaceUI"
	add_child_autofree(fixture_root)
	await get_tree().process_frame
	for pair in [[0, SectorNode.NodeType.OPENING], [1, SectorNode.NodeType.COMBAT], [3, SectorNode.NodeType.TREASURE], [6, SectorNode.NodeType.BOSS]]:
		assert_true(session.sandbox_warp(99, 0, pair[0], pair[1]))
		await get_tree().process_frame
	assert_false(session.sandbox_warp(99, 1, 0, SectorNode.NodeType.OPENING))
	assert_false(session.sandbox_warp(99, 0, 1, SectorNode.NodeType.OPENING))
	assert_false(session.sandbox_warp(99, 0, 99, SectorNode.NodeType.BOSS))

func test_room_profiles_are_materialized_from_nodes_without_sector_inference() -> void:
	var session := SESSION.new()
	autofree(session)
	session.run_state = RunState.new()
	var sector := GENERATOR.generate(1, 0)
	var upper := session._room_def_for(sector.get_node(1))
	assert_eq(upper.encounter_profile, &"upper")
	assert_eq(upper.environment_profile, &"upper_background_human_s2")
	assert_eq(upper.wave_specs[0].threat_types.size(), 8)
	var core := session._room_def_for(sector.get_node(3))
	assert_eq(core.encounter_profile, &"sector3_upper")
	assert_eq(core.transition_profile, &"sector3_upper_transition")
	assert_eq(core.environment_profile, &"sector3_upper_core")
