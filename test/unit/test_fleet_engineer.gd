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
	var textured_frame := player.sprite.sprite_frames.get_frame_texture(&"neutral", 0)
	assert_ne(player.sprite.sprite_frames, base_frames)
	assert_not_null(textured_frame)
	assert_eq(textured_frame, ShipCatalog.get_ship(&"nave_bruta").hull_texture)

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
	session.camera_path = NodePath("Camera")
	session.room_host_path = NodePath("RoomHost")
	session.hyperspace_path = NodePath("Hyperspace")
	var player := EngineerRoomPlayer.new()
	player.name = "Player"
	host.add_child(player)
	host.add_child(Node2D.new())
	host.get_child(1).name = "RoomHost"
	host.add_child(Camera2D.new())
	host.get_child(2).name = "Camera"
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

func test_first_q_deploys_drone_and_next_q_skips_live_drone() -> void:
	var session := _session_with_room()
	var player := session.get_node("../Player") as Node2D
	assert_true(session.deploy_engineer_deployable(player))
	var deployables := session._active_room.get_node("Deployables")
	assert_eq((deployables.get_child(0) as EngineerDeployable).kind, EngineerDeployable.Kind.DRONE)
	assert_true(session.deploy_engineer_deployable(player))
	assert_eq((deployables.get_child(1) as EngineerDeployable).kind, EngineerDeployable.Kind.TRAP)

func test_five_qs_with_live_drone_resume_sequence_after_skip() -> void:
	var session := _session_with_room()
	var player := session.get_node("../Player") as Node2D
	var deployables := session._active_room.get_node("Deployables")
	var expected := [
		EngineerDeployable.Kind.DRONE,
		EngineerDeployable.Kind.TRAP,
		EngineerDeployable.Kind.OVERCLOCK_STATION,
		EngineerDeployable.Kind.TRAP,
		EngineerDeployable.Kind.OVERCLOCK_STATION,
	]

	for expected_kind in expected:
		assert_true(session.deploy_engineer_deployable(player))
		await get_tree().process_frame
		var deployed_kind := (deployables.get_child(deployables.get_child_count() - 1) as EngineerDeployable).kind
		assert_eq(deployed_kind, expected_kind)

	assert_eq(deployables.get_child_count(), 3)
	var live_kinds: Array[int] = []
	for deployable in deployables.get_children():
		live_kinds.append((deployable as EngineerDeployable).kind)
	assert_eq(live_kinds.count(EngineerDeployable.Kind.DRONE), 1)
	assert_eq(live_kinds.count(EngineerDeployable.Kind.TRAP), 1)
	assert_eq(live_kinds.count(EngineerDeployable.Kind.OVERCLOCK_STATION), 1)

func test_engineer_deploy_sequence_is_per_player_and_resets_per_room() -> void:
	var session := _session_with_room()
	var first_player := session.get_node("../Player") as Node2D
	var second_player := Node2D.new()
	first_player.name = "FirstPlayer"
	second_player.name = "SecondPlayer"
	first_player.add_to_group(&"player")
	second_player.add_to_group(&"player")
	first_player.get_parent().add_child(second_player)
	assert_true(session.deploy_engineer_deployable(first_player))
	assert_true(session.deploy_engineer_deployable(second_player))
	var deployables := session._active_room.get_node("Deployables")
	assert_eq((deployables.get_child(0) as EngineerDeployable).kind, EngineerDeployable.Kind.DRONE)
	assert_eq((deployables.get_child(1) as EngineerDeployable).kind, EngineerDeployable.Kind.DRONE)

	# A troca real de sala e a API de entrada devem resetar a sequência; não
	# manipule o dicionário interno diretamente, pois isso não cobre o fluxo real.
	var next_node := SectorNode.new()
	next_node.id = 2
	next_node.node_type = SectorNode.NodeType.COMBAT
	var sector := SectorDef.new()
	sector.nodes = {2: next_node}
	sector.start_node_id = 2
	session.sector = sector
	session.run_state = RunState.new()
	session.run_state.sector_index = 0
	# _enter_node() is a real room transition; provide every runtime dependency
	# normally populated by Session._ready() before invoking it directly.
	session._player = first_player
	session._camera = session.get_node("../Camera") as Camera2D
	session._room_host = session.get_node("../RoomHost")
	session._hyperspace = session.get_node("../Hyperspace") as HyperspaceUI
	session._dispose_active_room()
	session._room_active = false
	session._enter_node(2)
	await get_tree().process_frame
	deployables = session._active_room.get_node("Deployables")
	assert_true(session.deploy_engineer_deployable(first_player))
	assert_eq((deployables.get_child(0) as EngineerDeployable).kind, EngineerDeployable.Kind.DRONE)

func test_player_death_clears_owned_deployables_and_resets_sequence() -> void:
	var session := _session_with_room()
	var player := preload("res://scenes/player/player.tscn").instantiate() as Player
	player.name = "Player"
	session.get_node("../").add_child(player)
	var second_player := preload("res://scenes/player/player.tscn").instantiate() as Player
	second_player.name = "SecondPlayer"
	session.get_node("../").add_child(second_player)
	await get_tree().process_frame
	assert_true(player.configure_ship(ShipCatalog.get_ship(&"nave_engenheira")))
	assert_true(second_player.configure_ship(ShipCatalog.get_ship(&"nave_engenheira")))
	assert_true(session.deploy_engineer_deployable(player))
	assert_true(session.deploy_engineer_deployable(player))
	assert_true(session.deploy_engineer_deployable(second_player))
	var deployables := session._active_room.get_node("Deployables")
	assert_eq(deployables.get_child_count(), 3)
	var prior_lives := GameState.player_lives
	GameState.player_lives = 2
	player._on_died(DamageInfo.new())
	await get_tree().process_frame
	assert_eq(GameState.player_lives, 1)
	assert_eq(deployables.get_child_count(), 1)
	assert_eq((deployables.get_child(0) as EngineerDeployable).deploying_player, second_player)
	assert_eq((deployables.get_child(0) as EngineerDeployable).kind, EngineerDeployable.Kind.DRONE)
	assert_true(session.deploy_engineer_deployable(player))
	assert_eq(deployables.get_child_count(), 2)
	assert_eq((deployables.get_child(1) as EngineerDeployable).kind, EngineerDeployable.Kind.DRONE)
	GameState.player_lives = prior_lives

func test_last_player_life_clears_owned_deployables_before_game_over_state() -> void:
	var session := _session_with_room()
	var player := preload("res://scenes/player/player.tscn").instantiate() as Player
	player.name = "Player"
	session.get_node("../").add_child(player)
	await get_tree().process_frame
	assert_true(player.configure_ship(ShipCatalog.get_ship(&"nave_engenheira")))
	assert_true(session.deploy_engineer_deployable(player))
	var deployables := session._active_room.get_node("Deployables")
	var prior_lives := GameState.player_lives
	GameState.player_lives = 1
	player._on_died(DamageInfo.new())
	await get_tree().process_frame
	assert_eq(deployables.get_child_count(), 0)
	assert_eq(GameState.player_lives, 0)
	assert_false(player.visible)
	assert_false(player.is_physics_processing())
	GameState.player_lives = prior_lives

func test_command_target_fallback_keeps_minimal_mock_safe() -> void:
	var session := _session_with_room()
	var player := MinimalEngineerPlayer.new()
	player.global_position = Vector2(100.0, 100.0)
	session.get_node("../").add_child(player)
	assert_eq(session._engineer_command_target_for(player), player.global_position + Vector2.UP * EngineerDeployable.DEPLOY_RANGE)

func test_command_keeps_current_drone_target_until_command_is_dispatched() -> void:
	var session := _session_with_room()
	var player := session.get_node("../Player") as Node2D
	assert_true(session.deploy_engineer_deployable(player))
	var drone := session._active_room.get_node("Deployables").get_child(0) as EngineerDeployable
	var deployed_target := drone._target_position
	player.command_target = Vector2(600.0, 300.0)

	assert_eq(drone._target_position, deployed_target)
	assert_true(session.command_engineer_drone(player))
	assert_eq(drone._target_position, player.command_target)
	assert_ne(drone._target_position, deployed_target)

func test_limit_fifo_preserves_drone_and_replaces_oldest_non_drone() -> void:
	var session := _session_with_room()
	var player := session.get_node("../Player") as Node2D
	for _index in 3:
		assert_true(session.deploy_engineer_deployable(player))
	await get_tree().process_frame
	var deployables := session._active_room.get_node("Deployables")
	var oldest_trap := deployables.get_child(1)
	assert_true(session.deploy_engineer_deployable(player))
	await get_tree().process_frame
	assert_eq(deployables.get_child_count(), 3)
	assert_true(is_instance_valid(deployables.get_child(0)))
	assert_eq((deployables.get_child(0) as EngineerDeployable).kind, EngineerDeployable.Kind.DRONE)
	assert_false(is_instance_valid(oldest_trap))

func test_trap_detonates_on_enemy_with_burst_and_does_not_slow() -> void:
	var trap := preload("res://scenes/deployables/engineer_deployable.tscn").instantiate() as EngineerDeployable
	add_child_autofree(trap)
	await get_tree().process_frame
	trap.configure(EngineerDeployable.Kind.TRAP, Node2D.new(), Vector2.ZERO)
	var enemy := EnemyContactStub.new()
	add_child_autofree(enemy)
	enemy.global_position = trap.global_position
	var second_enemy := EnemyContactStub.new()
	add_child_autofree(second_enemy)
	second_enemy.global_position = trap.global_position + Vector2(8.0, 0.0)
	await get_tree().physics_frame
	assert_true(trap.is_queued_for_deletion())
	assert_eq(enemy.received_damage.size(), 1)
	assert_eq(second_enemy.received_damage.size(), 1)
	for target in [enemy, second_enemy]:
		var info: DamageInfo = target.received_damage[0]
		assert_eq(info.amount, 3.0)
		assert_true(info.tags.has(&"engineer_deployable"))
		assert_false(info.tags.has(&"slow"))
		assert_eq(target.slow_calls, 0)

func test_overclock_station_ignores_player_damage_and_accepts_enemy_damage() -> void:
	var station := preload("res://scenes/deployables/engineer_deployable.tscn").instantiate() as EngineerDeployable
	add_child_autofree(station)
	await get_tree().process_frame
	station.configure(EngineerDeployable.Kind.OVERCLOCK_STATION, Node2D.new(), Vector2.ZERO)
	# Layer 6 keeps the Station outside the player's bullet mask (layers 1 and 3).
	assert_eq(station.hurtbox.collision_layer, 32)
	assert_eq(station.hurtbox.collision_mask, 20)
	var player_bullet := preload("res://scenes/projectiles/bullet.tscn").instantiate() as Area2D
	add_child_autofree(player_bullet)
	assert_eq(player_bullet.collision_mask, 5)
	assert_eq(station.hurtbox.collision_layer & player_bullet.collision_mask, 0)
	assert_eq(station.hurtbox.collision_mask & 4, 4)
	assert_eq(station.hurtbox.collision_mask & 16, 16)
	var player_source := Node2D.new()
	player_source.add_to_group(&"player")
	var info := DamageInfo.new()
	info.amount = 2.0
	info.source = player_source
	station.take_damage(info)
	assert_eq(station.health.health, station.health.max_health)
	var enemy_source := Node2D.new()
	enemy_source.add_to_group(&"enemies")
	info.source = enemy_source
	station.take_damage(info)
	assert_lt(station.health.health, station.health.max_health)

func test_overclock_station_grants_fire_rate_modifier_and_consumable_shield() -> void:
	var station := preload("res://scenes/deployables/engineer_deployable.tscn").instantiate() as EngineerDeployable
	add_child_autofree(station)
	await get_tree().process_frame
	station.configure(EngineerDeployable.Kind.OVERCLOCK_STATION, Node2D.new(), Vector2.ZERO)
	var player := preload("res://scenes/player/player.tscn").instantiate() as Player
	add_child_autofree(player)
	await get_tree().process_frame
	station._buff_ally(player)
	assert_true(player._shield_charges.size() == 1)
	assert_eq(player._shield_charges.size(), 1)
	assert_almost_eq(player._stats.get_stat(&"fire_rate"), 7.2, 0.001)
	var enemy := EnemyContactStub.new()
	add_child_autofree(enemy)
	var damage := DamageInfo.new()
	damage.amount = station.health.max_health
	damage.source = enemy
	station.take_damage(damage)
	await get_tree().process_frame
	assert_eq(player._shield_charges.size(), 0)
	assert_almost_eq(player._stats.get_stat(&"fire_rate"), 6.0, 0.001)
	station.queue_free()
	await get_tree().process_frame
	assert_eq(player._shield_charges.size(), 0)
	assert_almost_eq(player._stats.get_stat(&"fire_rate"), 6.0, 0.001)

func test_overclock_station_cleanup_tolerates_invalid_player_reference() -> void:
	var station := preload("res://scenes/deployables/engineer_deployable.tscn").instantiate() as EngineerDeployable
	add_child_autofree(station)
	await get_tree().process_frame
	station.configure(EngineerDeployable.Kind.OVERCLOCK_STATION, Node2D.new(), Vector2.ZERO)
	var player := preload("res://scenes/player/player.tscn").instantiate() as Player
	add_child(player)
	await get_tree().process_frame
	station._buff_ally(player)
	player.queue_free()
	await get_tree().process_frame
	station.queue_free()
	await get_tree().process_frame
	assert_true(station.is_queued_for_deletion())

func test_overclock_station_takes_enemy_contact_damage_and_enemy_projectile_damage() -> void:
	var station := preload("res://scenes/deployables/engineer_deployable.tscn").instantiate() as EngineerDeployable
	add_child_autofree(station)
	await get_tree().process_frame
	station.configure(EngineerDeployable.Kind.OVERCLOCK_STATION, Node2D.new(), Vector2.ZERO)
	var enemy := EnemyContactStub.new()
	add_child_autofree(enemy)
	enemy.contact_damage = 1.0
	station.global_position = Vector2.ZERO
	enemy.global_position = Vector2.ZERO
	await get_tree().physics_frame
	assert_almost_eq(station.health.health, 5.0, 0.001)

	var projectile := Area2D.new()
	projectile.add_to_group(&"enemy_projectiles")
	projectile.collision_layer = 16
	var projectile_shape := CollisionShape2D.new()
	projectile_shape.shape = CircleShape2D.new()
	(projectile_shape.shape as CircleShape2D).radius = 4.0
	projectile.add_child(projectile_shape)
	add_child_autofree(projectile)
	projectile.global_position = station.global_position
	await get_tree().physics_frame
	assert_almost_eq(station.health.health, 4.0, 0.001)
	assert_true(projectile.is_queued_for_deletion())

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

func _drone_fixture() -> Array:
	var projectiles := Node2D.new()
	projectiles.name = "Projectiles"
	projectiles.add_to_group(&"projectiles")
	add_child_autofree(projectiles)
	var owner := DroneOwnerStub.new()
	owner.global_position = Vector2(100, 100)
	add_child_autofree(owner)
	var drone := preload("res://scenes/deployables/engineer_deployable.tscn").instantiate() as EngineerDeployable
	add_child_autofree(drone)
	drone.configure(EngineerDeployable.Kind.DRONE, owner, Vector2.ZERO)
	drone.global_position = Vector2(200, 150)
	await get_tree().process_frame
	return [drone, owner, projectiles]

func test_drone_fires_from_muzzle_immediately_and_only_once_per_second() -> void:
	var fixture := await _drone_fixture()
	var drone: EngineerDeployable = fixture[0]
	var projectiles: Node2D = fixture[2]
	drone._fire_drone(0.0)
	assert_eq(projectiles.get_child_count(), 1)
	var first := projectiles.get_child(0) as Area2D
	assert_eq(first.global_position, drone.muzzle.global_position)
	drone._fire_drone(0.99)
	assert_eq(projectiles.get_child_count(), 1)
	drone._fire_drone(0.01)
	assert_eq(projectiles.get_child_count(), 2)

func test_drone_uses_owner_aim_damage_and_projectile_contract() -> void:
	var fixture := await _drone_fixture()
	var drone: EngineerDeployable = fixture[0]
	var owner: DroneOwnerStub = fixture[1]
	var projectiles: Node2D = fixture[2]
	drone._fire_drone(0.0)
	var bullet := projectiles.get_child(0) as Area2D
	assert_almost_eq(bullet.rotation, owner.aim_direction.angle() + PI / 2.0, 0.001)
	assert_eq(bullet.damage, EngineerDeployable.DRONE_DAMAGE)
	assert_eq(bullet._shooter, owner)
	assert_almost_eq(bullet.scale.x, 0.5, 0.001)
	assert_almost_eq(bullet.scale.y, 0.5, 0.001)
	assert_eq((bullet.get_node("CollisionShape2D") as CollisionShape2D).scale, Vector2.ONE)
	assert_eq(bullet.collision_layer & 8, 8)
	assert_true(bullet._despawn_on_valid_hit)
	# The aim comes from the owner input contract (the same path used by
	# mouse/joystick aim), while the spawn point remains the drone muzzle.
	owner.aim_direction = Vector2.DOWN
	drone._drone_fire_cooldown = 0.0
	drone._fire_drone(1.0)
	var joystick_bullet := projectiles.get_child(1) as Area2D
	assert_eq(joystick_bullet.global_position, drone.muzzle.global_position)
	assert_almost_eq(joystick_bullet.rotation, PI, 0.001)

func test_drone_aim_is_not_command_target_and_is_isolated_per_owner() -> void:
	var fixture := await _drone_fixture()
	var drone: EngineerDeployable = fixture[0]
	var owner: DroneOwnerStub = fixture[1]
	owner.command_target = Vector2.LEFT
	assert_eq(owner.get_aim_direction(), Vector2.RIGHT)
	assert_ne(owner.get_engineer_drone_command_target(), owner.get_aim_direction())
	var other := DroneOwnerStub.new()
	other.aim_direction = Vector2.DOWN
	add_child_autofree(other)
	assert_ne(owner.get_aim_direction(), other.get_aim_direction())
	drone.deploying_player = owner

func test_bullet_reactivation_resets_drone_scale_lifetime_and_range() -> void:
	var bullet := preload("res://scenes/projectiles/bullet.tscn").instantiate()
	add_child_autofree(bullet)
	var shooter := Node2D.new()
	bullet.activate(Vector2.ZERO, Vector2.RIGHT, shooter, 1.0, 100.0, 0.5, 0.5)
	assert_eq(bullet.scale, Vector2.ONE * 0.5)
	assert_almost_eq(bullet.lifetime, 0.5, 0.001)
	bullet._on_hit(EnemyContactStub.new())
	bullet.activate(Vector2.ZERO, Vector2.RIGHT, shooter, 7.0, 200.0, 2.0)
	assert_eq(bullet.scale, Vector2.ONE)
	assert_almost_eq(bullet.lifetime, 2.0, 0.001)
	assert_almost_eq(bullet._range_remaining, 400.0, 0.001)
	assert_eq(bullet._hit_targets.size(), 0)
	assert_false(bullet._despawn_on_valid_hit)
	assert_eq(bullet._shooter, shooter)

func test_drone_flag_despawns_on_first_valid_hit_but_normal_bullet_pierces() -> void:
	var target_a := DamageTargetStub.new()
	var target_b := DamageTargetStub.new()
	add_child_autofree(target_a)
	add_child_autofree(target_b)
	var bullet := preload("res://scenes/projectiles/bullet.tscn").instantiate()
	add_child_autofree(bullet)
	var shooter := Node2D.new()
	bullet.activate(Vector2.ZERO, Vector2.RIGHT, shooter, 1.0, 100.0, 2.0, 0.5, true)
	bullet._on_hit(target_a)
	bullet._on_hit(target_b)
	assert_eq(target_a.calls, 1)
	assert_eq(target_b.calls, 0)
	assert_false(bullet._active)
	assert_null(bullet._shooter)

	bullet.activate(Vector2.ZERO, Vector2.RIGHT, shooter, 2.0, 100.0, 2.0, 1.0, false)
	bullet._on_hit(target_a)
	bullet._on_hit(target_b)
	assert_eq(target_a.calls, 2)
	assert_eq(target_b.calls, 1)
	assert_true(bullet._active)

func test_bullet_pool_reuse_resets_all_drone_state() -> void:
	var projectiles := Node2D.new()
	add_child_autofree(projectiles)
	var scene := preload("res://scenes/projectiles/bullet.tscn")
	var shooter := Node2D.new()
	var bullet := Pools.acquire(scene) as Area2D
	projectiles.add_child(bullet)
	bullet.activate(Vector2.ZERO, Vector2.RIGHT, shooter, 1.0, 100.0, 0.5, 0.5, true)
	bullet._on_hit(DamageTargetStub.new())
	await get_tree().process_frame
	var reused := Pools.acquire(scene) as Area2D
	projectiles.add_child(reused)
	reused.activate(Vector2.ZERO, Vector2.RIGHT, shooter, 1.0, 100.0, 2.0, 1.0, false)
	assert_eq(reused, bullet)
	assert_eq(reused.scale, Vector2.ONE)
	assert_almost_eq(reused.lifetime, 2.0, 0.001)
	assert_almost_eq(reused._range_remaining, 200.0, 0.001)
	assert_false(reused._despawn_on_valid_hit)
	assert_eq(reused._hit_targets.size(), 0)
	assert_eq(reused._shooter, shooter)
	reused._despawn()
	await get_tree().process_frame

func test_drone_bullet_range_is_half_normal_and_despawns_at_limit() -> void:
	var bullet := preload("res://scenes/projectiles/bullet.tscn").instantiate()
	add_child_autofree(bullet)
	bullet.activate(Vector2.ZERO, Vector2.RIGHT, Node2D.new(), 1.0, 100.0, 1.0, 0.5)
	bullet._physics_process(0.6)
	assert_false(bullet.is_queued_for_deletion())
	bullet._physics_process(0.4)
	assert_false(bullet._active)
	assert_almost_eq(bullet.global_position.x, 100.0, 0.001)

func test_drone_keeps_contact_health_and_stops_firing_after_death() -> void:
	var fixture := await _drone_fixture()
	var drone: EngineerDeployable = fixture[0]
	var projectiles: Node2D = fixture[2]
	drone._fire_drone(0.0)
	var before := projectiles.get_child_count()
	var damage := DamageInfo.new()
	damage.amount = drone.health.max_health
	damage.source = EnemyContactStub.new()
	drone.take_damage(damage)
	assert_lte(drone.health.health, 0.0)
	assert_true(drone.is_queued_for_deletion())
	drone._fire_drone(1.0)
	assert_eq(projectiles.get_child_count(), before)
	drone._physics_process(1.0)
	assert_eq(projectiles.get_child_count(), before)

func test_drone_contact_damage_preserves_player_source_and_damage() -> void:
	var fixture := await _drone_fixture()
	var drone: EngineerDeployable = fixture[0]
	var owner: DroneOwnerStub = fixture[1]
	var enemy := EnemyContactStub.new()
	add_child_autofree(enemy)
	assert_true(drone._damage_enemy(enemy, EngineerDeployable.DRONE_DAMAGE))
	assert_eq(enemy.received_damage.size(), 1)
	assert_eq(enemy.received_damage[0].source, owner)
	assert_eq(enemy.received_damage[0].amount, EngineerDeployable.DRONE_DAMAGE)

func test_drone_contact_does_not_damage_when_deploying_player_is_queued() -> void:
	var fixture := await _drone_fixture()
	var drone: EngineerDeployable = fixture[0]
	var owner: DroneOwnerStub = fixture[1]
	var projectiles: Node2D = fixture[2]
	var enemy := EnemyContactStub.new()
	add_child_autofree(enemy)
	enemy.global_position = drone.global_position
	var projectiles_before := projectiles.get_child_count()
	owner.queue_free()
	await get_tree().physics_frame
	assert_eq(enemy.received_damage.size(), 0)
	assert_eq(projectiles.get_child_count(), projectiles_before)

class TestSession extends Session:
	func _ready() -> void:
		add_to_group(&"session")

class EngineerRoomPlayer extends Node2D:
	var command_target := Vector2.ZERO

	func set_room_bounds(_bounds: Rect2) -> void:
		pass

	func get_engineer_drone_command_target() -> Vector2:
		return command_target

class EnemyContactStub extends CharacterBody2D:
	var contact_damage := 1.0
	var received_damage: Array[DamageInfo] = []
	var slow_calls := 0

	func _ready() -> void:
		add_to_group(&"enemies")
		collision_layer = 4
		var shape := CollisionShape2D.new()
		shape.shape = CircleShape2D.new()
		(shape.shape as CircleShape2D).radius = 6.0
		add_child(shape)

	func take_damage(info: DamageInfo) -> void:
		received_damage.append(info)

	func apply_slow(_amount: float, _duration: float) -> void:
		slow_calls += 1

class DamageTargetStub extends Node:
	var calls := 0

	func take_damage(_info: DamageInfo) -> float:
		calls += 1
		return 0.0

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

class MinimalEngineerPlayer extends Node2D:
	func get_engineer_deploy_target(distance: float) -> Vector2:
		return global_position + Vector2.UP * distance

class DroneOwnerStub extends Node2D:
	var aim_direction := Vector2.RIGHT
	var command_target := Vector2.ZERO

	func get_aim_direction() -> Vector2:
		return aim_direction

	func get_projectile_stat(stat_id: StringName, fallback: float) -> float:
		if stat_id == &"projectile_speed":
			return 100.0
		if stat_id == &"projectile_lifetime":
			return 2.0
		return fallback

	func get_room_bounds() -> Rect2:
		return Rect2(Vector2.ZERO, Vector2(720, 405))

	func get_engineer_drone_command_target() -> Vector2:
		return command_target
