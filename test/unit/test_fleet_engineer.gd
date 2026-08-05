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

func test_loadout_uses_catalogued_ship_and_character_defaults() -> void:
	var player := preload("res://scenes/player/player.tscn").instantiate() as Player
	add_child_autofree(player)
	var ship := ShipCatalog.get_ship(&"nave_base")
	assert_true(player.configure_ship(ship))
	assert_eq(player.ship, ship)
	assert_eq(player.character.id, &"piloto_base")
	assert_eq(player._stats.get_stat(&"max_health"), 3.0)

func test_engineer_ability_has_stable_id_and_failed_activation_has_no_effect() -> void:
	var ability := AbilityCatalog.get_ability(&"engenheira_deploy")
	assert_true(ability is EngineerDeployAbility)
	assert_eq(ability.id, &"engenheira_deploy")
	assert_true(AbilityCatalog.is_valid(&"engenheira_deploy"))
	assert_eq(ability.cooldown, 2.0)
	var player := Node2D.new()
	add_child_autofree(player)
	assert_false(ability.try_activate(player))

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

class TestSession extends Session:
	func _ready() -> void:
		add_to_group(&"session")
