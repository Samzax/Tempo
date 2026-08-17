extends GutTest

const CONTROLLER := preload("res://scripts/enemies/bosses/electric_grid_controller.gd")
const AREA := preload("res://scripts/enemies/bosses/electric_subnet_area.gd")
const BOSS_SCENE := preload("res://scenes/enemies/bosses/regente_dos_ecos.tscn")

class FakePlayer extends CharacterBody2D:
	var health: HealthComponent
	var stun_calls := 0
	var stun_duration := 0.0
	func apply_stun(duration: float) -> void:
		stun_calls += 1
		stun_duration = duration
	func take_damage(_info: DamageInfo) -> int:
		push_error("Electric bridge must use HealthComponent, not Player.take_damage")
		return 0

class FakeEnemy extends CharacterBody2D:
	var health: HealthComponent
	var stun_calls := 0

	func apply_stun(_duration: float) -> void:
		stun_calls += 1

func _controller(host := true) -> ElectricGridController:
	var controller := CONTROLLER.new(host) as ElectricGridController
	add_child_autofree(controller)
	return controller

func _spawn_pair(controller: ElectricGridController) -> void:
	controller.spawn_drone(Vector2.ZERO)
	controller.spawn_drone(Vector2(20.0, 0.0))

func _add_player_shape(player: CharacterBody2D, radius := 2.0) -> void:
	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = radius
	collision.shape = shape
	player.add_child(collision)

func test_tick_accumulator_keeps_remainder_across_sliced_deltas() -> void:
	var controller := _controller()
	controller.tick_seconds = 0.1
	controller._physics_process(0.03)
	controller._physics_process(0.03)
	controller._physics_process(0.04)
	assert_eq(controller._server_tick, 1)
	assert_almost_eq(controller._tick_accumulator, 0.0, 0.00001)
	controller._physics_process(0.25)
	assert_eq(controller._server_tick, 3)
	assert_almost_eq(controller._tick_accumulator, 0.05, 0.00001)

func test_client_never_mutates_drone_or_graph_state() -> void:
	var controller := _controller(false)
	assert_eq(controller.spawn_drone(), {})
	assert_false(controller.update_drone_positions({1: {"position": Vector2.ONE, "formation_open": true}}))
	controller._physics_process(1.0)
	assert_eq(controller.drone_manager.active_drones(), [])
	assert_eq(controller.electric_subnet.graph_revision, 0)
	assert_eq(controller._server_tick, 0)

func test_configure_geometry_validates_injects_limits_and_teardown_is_idempotent() -> void:
	var controller := _controller()
	for invalid in [[0.0, 74.0, 18.0], [75.0, 74.0, 18.0], [58.0, 74.0, 0.0], [NAN, 74.0, 18.0], [58.0, INF, 18.0]]:
		assert_false(controller.configure_geometry(invalid[0], invalid[1], invalid[2]))
	assert_true(controller.configure_geometry(12.0, 20.0, 9.0))
	assert_eq(controller.electric_subnet.connect_distance, 12.0)
	assert_eq(controller.electric_subnet.break_distance, 20.0)
	controller.spawn_drone(Vector2.ZERO)
	controller.spawn_drone(Vector2(10.0, 0.0))
	assert_gt(controller._areas.size(), 0)
	for area in controller._areas.values(): assert_eq((area as ElectricSubnetArea).aura_radius, 9.0)
	controller.teardown(); controller.teardown()
	assert_eq(controller._areas.size(), 0)

func test_each_subnet_has_its_own_area_and_reuses_edge_shapes() -> void:
	var controller := _controller()
	_spawn_pair(controller)
	assert_eq(controller._areas.size(), 1)
	var subnet_id: String = controller._areas.keys()[0]
	var area := controller._areas[subnet_id] as ElectricSubnetArea
	var shape := area._shapes["1:2"] as CollisionShape2D
	controller.update_drone_positions({1: {"position": Vector2(5, 0), "formation_open": false}})
	assert_same(area._shapes["1:2"], shape)
	controller.spawn_drone(Vector2(5, 0))
	controller.spawn_drone(Vector2(25, 0))
	for left in [1, 2]:
		for right in [3, 4]:
			controller.electric_subnet.set_forbidden_edge(left, right)
	controller._sync_graph_from_manager()
	assert_eq(controller._areas.size(), 2)
	assert_true(controller._areas.has(subnet_id))
	for split_id in controller._areas.keys():
		assert_eq((controller._areas[split_id] as ElectricSubnetArea).collision_mask, 6)
	assert_true(controller._areas[subnet_id]._shapes.has("1:2"))
	assert_same(controller._areas[subnet_id]._shapes["1:2"], shape)

func test_real_area_signal_transition_keeps_target_until_last_area_exits() -> void:
	var controller := _controller()
	controller.set_physics_process(false)
	var player := CharacterBody2D.new()
	var health := HealthComponent.new()
	health.name = "HealthComponent"
	health.max_health = 100
	player.collision_layer = 2
	player.collision_mask = 0
	player.add_to_group(&"player")
	player.add_child(health)
	player.set_meta(&"network_id", "real-shared")
	var player_shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 2.0
	player_shape.shape = circle
	player.add_child(player_shape)
	add_child_autofree(player)
	var first := AREA.new() as ElectricSubnetArea
	var second := AREA.new() as ElectricSubnetArea
	add_child_autofree(first)
	add_child_autofree(second)
	first.sync_edges([{"a": 1, "b": 2}], {1: Vector2.ZERO, 2: Vector2(40.0, 0.0)})
	second.sync_edges([{"a": 1, "b": 2}], {1: Vector2(60.0, 0.0), 2: Vector2(100.0, 0.0)})
	controller._areas = {"first": first, "second": second}
	first.target_seen.connect(controller._on_area_target_seen)
	first.target_left.connect(controller._on_area_target_left)
	second.target_seen.connect(controller._on_area_target_seen)
	second.target_left.connect(controller._on_area_target_left)
	var seen: Array[String] = []
	var left: Array[String] = []
	first.target_seen.connect(func(target_id: String, _body: Node2D) -> void: seen.append("first:" + target_id))
	second.target_seen.connect(func(target_id: String, _body: Node2D) -> void: seen.append("second:" + target_id))
	first.target_left.connect(func(target_id: String) -> void: left.append("first:" + target_id))
	second.target_left.connect(func(target_id: String) -> void: left.append("second:" + target_id))
	player.position = Vector2(20.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_true(controller._targets.has("real-shared"))
	assert_true(first.target_ids().has("real-shared"))
	assert_false(second.target_ids().has("real-shared"))
	assert_eq(seen, ["first:real-shared"])
	player.move_and_collide(Vector2(60.0, 0.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_true(controller._targets.has("real-shared"))
	assert_false(first.target_ids().has("real-shared"))
	assert_true(second.target_ids().has("real-shared"))
	assert_eq(seen, ["first:real-shared", "second:real-shared"])
	assert_eq(left, ["first:real-shared"])
	player.move_and_collide(Vector2(-60.0, 80.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_false(controller._targets.has("real-shared"))
	assert_eq(left, ["first:real-shared", "second:real-shared"])

func test_overlapping_subnets_apply_independently_through_health_component_and_only_stun_players() -> void:
	var controller := _controller()
	var player := FakePlayer.new()
	player.add_to_group(&"player")
	var health := HealthComponent.new()
	health.name = "HealthComponent"
	health.max_health = 100
	player.health = health
	player.add_child(health)
	player.collision_layer = 2
	player.collision_mask = 0
	player.set_meta(&"network_id", "damage-player")
	_add_player_shape(player)
	add_child_autofree(player)
	_spawn_pair(controller)
	controller.spawn_drone(Vector2(5, 0))
	controller.spawn_drone(Vector2(25, 0))
	for left in [1, 2]:
		for right in [3, 4]:
			controller.electric_subnet.set_forbidden_edge(left, right)
	controller._sync_graph_from_manager()
	player.position = Vector2(10.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_true(controller._targets.has("damage-player"))
	controller.electric_subnet.damage_per_tick = 7.0
	controller._physics_process(0.1)
	assert_eq(health.health, 86)
	assert_eq(player.stun_calls, 1) # The core marks one event eligible; its immunity is untouched here.

func test_enemy_on_active_subnet_takes_damage_without_stun() -> void:
	var controller := _controller()
	var enemy := FakeEnemy.new()
	enemy.add_to_group(&"enemies")
	enemy.collision_layer = 4
	enemy.collision_mask = 0
	enemy.set_meta(&"network_id", "damage-enemy")
	var health := HealthComponent.new()
	health.name = "HealthComponent"
	health.max_health = 100
	enemy.health = health
	enemy.add_child(health)
	_add_player_shape(enemy)
	add_child_autofree(enemy)
	_spawn_pair(controller)
	enemy.position = Vector2(10.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_true(controller._targets.has("damage-enemy"))
	controller.electric_subnet.damage_per_tick = 7.0
	controller._physics_process(0.1)
	assert_eq(health.health, 93)
	assert_eq(enemy.stun_calls, 0)

func test_unrelated_bodies_are_ignored_and_not_cached() -> void:
	var controller := _controller()
	var ungrouped := CharacterBody2D.new()
	ungrouped.collision_layer = 4
	_add_player_shape(ungrouped)
	add_child_autofree(ungrouped)
	var enemy_without_health := CharacterBody2D.new()
	enemy_without_health.add_to_group(&"enemies")
	enemy_without_health.collision_layer = 4
	_add_player_shape(enemy_without_health)
	add_child_autofree(enemy_without_health)
	_spawn_pair(controller)
	ungrouped.position = Vector2(10.0, 0.0)
	enemy_without_health.position = Vector2(10.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_false(controller._targets.has(str(ungrouped.get_instance_id())))
	assert_false(controller._targets.has(str(enemy_without_health.get_instance_id())))
	assert_eq(controller._targets.size(), 0)

func test_invalid_target_is_ignored_before_damage() -> void:
	var controller := _controller()
	var player := FakePlayer.new()
	player.add_to_group(&"player")
	var health := HealthComponent.new()
	health.max_health = 100
	player.add_child(health)
	add_child_autofree(player)
	controller._targets["gone"] = weakref(player)
	player.queue_free()
	controller._apply_event({"target_network_id": "gone", "damage_amount": 50.0, "stun_candidate": true, "stun_duration": 1.0})
	assert_false(controller._targets.has("gone"))

func test_regente_hook_is_lazy_and_does_not_change_motion_without_drone_configuration() -> void:
	var boss := BOSS_SCENE.instantiate() as RegenteDosEcos
	add_child_autofree(boss)
	boss.set_room_cull_policy(RoomDef.CullPolicy.NONE)
	boss._physics_process(0.1)
	assert_false(boss.has_node("ElectricGridController"))
	assert_false(boss.is_stunned())

func test_regente_hook_creates_host_grid_lazily_when_spawning_a_drone() -> void:
	var boss := BOSS_SCENE.instantiate() as RegenteDosEcos
	add_child_autofree(boss)
	boss.set_room_cull_policy(RoomDef.CullPolicy.NONE)

	assert_false(boss.has_node("ElectricGridController"))
	var spawned := boss.spawn_electric_drone(Vector2.ZERO)

	assert_true(spawned.has("id"))
	assert_true(boss.has_node("ElectricGridController"))

func test_regente_hook_with_client_peer_does_not_create_mutable_host_grid() -> void:
	# Exercise the real controller's client-authority path without constructing
	# the abstract MultiplayerAPI or inventing a fake engine API.
	var controller := _controller(false)
	assert_eq(controller.spawn_drone(), {})
	assert_false(controller.configure_drones({1: {"position": Vector2.ZERO}}))
	controller._physics_process(1.0)
	assert_eq(controller.drone_manager.snapshot().drones, [])
	assert_eq(controller.electric_subnet.snapshot().drones, [])

func test_invalid_tick_seconds_does_not_loop_or_crash() -> void:
	for invalid_tick in [0.0, -1.0, NAN, INF]:
		var controller := _controller()
		controller.tick_seconds = invalid_tick
		controller._physics_process(1.0)
		assert_eq(controller._server_tick, 0)

func test_invalid_physics_delta_does_not_advance_tick_or_accumulator() -> void:
	for invalid_delta in [0.0, -1.0, NAN, INF]:
		var controller := _controller()
		var initial_accumulator := controller._tick_accumulator
		controller._physics_process(invalid_delta)
		assert_eq(controller._server_tick, 0)
		assert_eq(controller._tick_accumulator, initial_accumulator)

func test_huge_finite_delta_is_capped_and_remainder_stays_bounded() -> void:
	var controller := _controller()
	controller.tick_seconds = 0.1
	controller.max_ticks_per_frame = 3
	controller._physics_process(1e20)
	assert_eq(controller._server_tick, 3)
	assert_true(controller._server_tick <= controller.max_ticks_per_frame)
	assert_true(controller._tick_accumulator >= 0.0)
	assert_true(controller._tick_accumulator < controller.tick_seconds)

func test_invalid_max_ticks_per_frame_still_processes_only_safe_tick_count() -> void:
	var controller := _controller()
	controller.tick_seconds = 0.1
	controller.max_ticks_per_frame = 0
	controller._physics_process(1e20)
	assert_eq(controller._server_tick, 1)
	assert_true(controller._tick_accumulator >= 0.0)
	assert_true(controller._tick_accumulator < controller.tick_seconds)

func test_invalid_drone_configuration_does_not_mutate_new_manager() -> void:
	var controller := _controller()
	var before := controller.drone_manager.snapshot()
	for invalid in [
		{2: {"position": Vector2.ZERO}},
		{1: {"position": Vector2.ZERO, "formation_open": "yes"}},
		{1: {"position": {}}},
		{"1": {"position": Vector2.ZERO}},
		{1: {"position": Vector2(INF, 0)}}
	]:
		assert_false(controller.configure_drones(invalid))
		assert_eq(controller.drone_manager.snapshot(), before)
	assert_eq(controller.drone_manager.active_drones(), [])

	assert_true(controller.configure_drones({1: {"position": Vector2.ZERO}}))
	assert_eq(controller.drone_manager.active_drones().size(), 1)
	assert_eq(controller.drone_manager.active_drones()[0].id, 1)
	assert_eq(controller.drone_manager.snapshot().next_id, 2)

func test_destroyed_drone_is_removed_from_manager_and_subnet_snapshot() -> void:
	var controller := _controller()
	_spawn_pair(controller)
	assert_true(controller.electric_subnet.set_forbidden_edge(1, 2))
	controller._sync_graph_from_manager()
	assert_true(controller.destroy_drone(2))
	var state: Dictionary = controller.electric_subnet.snapshot()
	assert_eq(state.forbidden_edges, [])
	for edge in state.edges:
		assert_ne(edge.a, 2)
		assert_ne(edge.b, 2)
	assert_eq(controller.drone_manager.active_drones().map(func(drone): return int(drone.id)), [1])
