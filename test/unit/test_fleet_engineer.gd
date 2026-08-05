extends GutTest

func test_ship_catalog_exposes_canonical_ship_and_lookup_contract() -> void:
	var ships := ShipCatalog.all()
	assert_gt(ships.size(), 0)
	assert_true(ShipCatalog.is_valid(&"nave_base"))
	var canonical_ship := ShipCatalog.get_ship(&"nave_base")
	assert_true(ships.has(canonical_ship))
	assert_eq(canonical_ship.id, &"nave_base")
	assert_false(ShipCatalog.is_valid(&"nave_de_track_b_inexistente"))
	assert_null(ShipCatalog.get_ship(&"nave_de_track_b_inexistente"))

func test_ship_catalog_normalizes_ship_filenames() -> void:
	assert_eq(ShipCatalog.normalize_ship_filename("nave.tres"), "nave.tres")
	assert_eq(ShipCatalog.normalize_ship_filename("nave.tres.remap"), "nave.tres")
	assert_eq(ShipCatalog.normalize_ship_filename("arquivo.txt.remap"), "arquivo.txt.remap")

func test_loadout_uses_catalogued_ship_and_character_defaults() -> void:
	var player := preload("res://scenes/player/player.tscn").instantiate() as Player
	add_child_autofree(player)
	var ship := ShipCatalog.get_ship(&"nave_base")
	assert_true(player.configure_ship(ship))
	assert_eq(player.ship, ship)
	assert_eq(player.character.id, &"piloto_base")
	assert_eq(player._stats.get_stat(&"max_health"), 3.0)

func test_base_ship_is_a_valid_shipdef_with_expected_loadout_contract() -> void:
	var base_ship := load("res://resources/ships/base.tres") as ShipDef
	assert_not_null(base_ship)
	assert_eq(base_ship.id, &"nave_base")
	assert_false(base_ship.ability_q.is_empty())
	assert_eq(base_ship.validate_content(), [])

func test_configure_ship_reapplies_stats_ability_and_preserves_atlas_regions() -> void:
	var player := preload("res://scenes/player/player.tscn").instantiate() as Player
	add_child_autofree(player)
	var frames_before := player.sprite.sprite_frames
	var regions_before: Array[Rect2] = []
	for animation_name in frames_before.get_animation_names():
		for frame_index in frames_before.get_frame_count(animation_name):
			var atlas := frames_before.get_frame_texture(animation_name, frame_index) as AtlasTexture
			if atlas != null:
				regions_before.append(atlas.region)
	var base_ship := ShipCatalog.get_ship(&"nave_base")
	assert_true(player.configure_ship(base_ship))
	assert_eq(player._stats.get_stat(&"max_health"), 3.0)
	assert_eq(player._ability_q.id, base_ship.ability_q)
	assert_eq(player.health.max_health, 3.0)
	var regions_after: Array[Rect2] = []
	for animation_name in player.sprite.sprite_frames.get_animation_names():
		for frame_index in player.sprite.sprite_frames.get_frame_count(animation_name):
			var atlas := player.sprite.sprite_frames.get_frame_texture(animation_name, frame_index) as AtlasTexture
			if atlas != null:
				regions_after.append(atlas.region)
	assert_eq(regions_after, regions_before)

func test_textured_ship_switch_back_restores_base_sprite_frames() -> void:
	var player := preload("res://scenes/player/player.tscn").instantiate() as Player
	add_child_autofree(player)
	var base_frames := player.sprite.sprite_frames
	var base_frame := base_frames.get_frame_texture(&"neutral", 0) as AtlasTexture
	assert_not_null(base_frame)

	assert_true(player.configure_ship(ShipCatalog.get_ship(&"nave_bruta")))
	var textured_frame := player.sprite.sprite_frames.get_frame_texture(&"neutral", 0) as AtlasTexture
	assert_ne(player.sprite.sprite_frames, base_frames)
	assert_not_null(textured_frame)
	assert_eq(textured_frame.atlas.resource_path, "res://assets/sprites/bruta.png")
	assert_eq(textured_frame.region, Rect2(0, 0, 16, 24))

	assert_true(player.configure_ship(ShipCatalog.get_ship(&"nave_base")))
	var restored_frame := player.sprite.sprite_frames.get_frame_texture(&"neutral", 0) as AtlasTexture
	assert_ne(player.sprite.sprite_frames, base_frames)
	assert_not_null(restored_frame)
	assert_eq(restored_frame.atlas.resource_path, base_frame.atlas.resource_path)
	assert_eq(restored_frame.region, base_frame.region)

func test_engineer_ability_has_stable_id_and_failed_activation_has_no_effect() -> void:
	var ability := AbilityCatalog.get_ability(&"engenheira_deploy")
	assert_true(ability is EngineerDeployAbility)
	assert_eq(ability.id, &"engenheira_deploy")
	assert_true(AbilityCatalog.is_valid(&"engenheira_deploy"))
	assert_eq(ability.cooldown, 2.0)
	var player := Node2D.new()
	add_child_autofree(player)
	assert_false(ability.try_activate(player))

func test_engineer_ability_try_activate_reports_success_and_deploy_failure() -> void:
	var ability := AbilityCatalog.get_ability(&"engenheira_deploy") as EngineerDeployAbility
	var player := DeployPlayerStub.new()
	add_child_autofree(player)

	assert_true(ability.try_activate(player))
	assert_eq(player.deploy_calls, 1)
	player.should_deploy = false
	assert_false(ability.try_activate(player))
	assert_eq(player.deploy_calls, 2)

func _session_with_room() -> TestSession:
	var host := Node2D.new()
	add_child_autofree(host)
	var session := TestSession.new()
	session.player_path = NodePath("Player")
	session.room_host_path = NodePath("RoomHost")
	session.hyperspace_path = NodePath("Hyperspace")
	var player := Node2D.new()
	player.name = "Player"
	host.add_child(player)
	host.add_child(Node2D.new())
	host.get_child(1).name = "RoomHost"
	var hyperspace := HyperspaceUI.new()
	hyperspace.name = "Hyperspace"
	host.add_child(hyperspace)
	host.add_child(session)
	var room := Node2D.new()
	room.name = "Room"
	var deployables := Node2D.new()
	deployables.name = "Deployables"
	room.add_child(deployables)
	room.add_child(Node2D.new())
	room.get_child(1).name = "Enemies"
	host.add_child(room)
	session._active_room = room
	session._room_active = true
	return session

func test_engineer_deployable_limit_is_three_and_cycles_all_modes() -> void:
	var session := _session_with_room()
	var player := session.get_node("../Player") as Node2D
	for _index in 4:
		assert_true(session.deploy_engineer_deployable(player))
	var deployables := session._active_room.get_node("Deployables")
	assert_eq(deployables.get_child_count(), 3)
	var kinds: Array[int] = []
	for index in 3:
		var deployable := deployables.get_child(index) as EngineerDeployable
		assert_eq(deployable.deploying_player, player)
		kinds.append(deployable.kind)
		assert_true(deployable.influence.collision_mask in [2, 4])
	assert_true(kinds.has(EngineerDeployable.Kind.TRAP))
	assert_true(kinds.has(EngineerDeployable.Kind.DRONE))
	assert_true(kinds.has(EngineerDeployable.Kind.GADGET))

func test_room_disposal_removes_deployables_and_active_room() -> void:
	var session := _session_with_room()
	var player := session.get_node("../Player") as Node2D
	assert_true(session.deploy_engineer_deployable(player))
	var room := session._active_room
	session._dispose_active_room()
	assert_null(session._active_room)
	assert_true(room.is_queued_for_deletion())

func test_room_clear_dispatches_once_and_not_again_on_revisit() -> void:
	var session := _session_with_room()
	session.run_state = RunState.new()
	session.run_state.sector_index = 0
	session._room_generation = 1
	var player := RoomClearPlayerStub.new()
	player.name = "Player"
	session.get_node("../Player").replace_by(player)
	session._player = player
	var node_def := SectorNode.new()
	node_def.id = 17

	session._on_room_cleared(node_def, 1)
	assert_eq(player.room_clear_calls, 1)
	assert_false(session._room_active)

	# Re-entry/revisit of an already completed node must not dispatch again.
	session._room_active = true
	session._on_room_cleared(node_def, 1)
	assert_eq(player.room_clear_calls, 1)

class TestSession extends Session:
	func _ready() -> void:
		add_to_group(&"session")

class DeployPlayerStub extends Node2D:
	var should_deploy := true
	var deploy_calls := 0

	func deploy_engineer_gadget() -> bool:
		deploy_calls += 1
		return should_deploy

class RoomClearPlayerStub extends Node2D:
	var room_clear_calls := 0

	func on_room_clear() -> void:
		room_clear_calls += 1
