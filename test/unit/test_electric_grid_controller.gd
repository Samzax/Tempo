extends GutTest

const CONTROLLER := preload("res://scripts/enemies/bosses/electric_grid_controller.gd")
const AREA := preload("res://scripts/enemies/bosses/electric_subnet_area.gd")
const BOSS_SCENE := preload("res://scenes/enemies/bosses/regente_dos_ecos.tscn")

class FakePlayer extends Node2D:
	var health: HealthComponent
	var stun_calls := 0
	var stun_duration := 0.0
	func apply_stun(duration: float) -> void:
		stun_calls += 1
		stun_duration = duration
	func take_damage(_info: DamageInfo) -> int:
		push_error("Electric bridge must use HealthComponent, not Player.take_damage")
		return 0

func _controller(host := true) -> ElectricGridController:
	var controller := CONTROLLER.new(host) as ElectricGridController
	add_child_autofree(controller)
	return controller

func _spawn_pair(controller: ElectricGridController) -> void:
	controller.spawn_drone(Vector2.ZERO)
	controller.spawn_drone(Vector2(20.0, 0.0))

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

func test_each_subnet_has_its_own_area_and_reuses_edge_shapes() -> void:
	var controller := _controller()
	_spawn_pair(controller)
	assert_eq(controller._areas.size(), 1)
	var subnet_id: String = controller._areas.keys()[0]
	var area := controller._areas[subnet_id] as ElectricSubnetArea
	var shape := area._shapes["1:2"] as CollisionShape2D
	controller.update_drone_positions({1: {"position": Vector2(5, 0), "formation_open": false}})
	assert_same(area._shapes["1:2"], shape)
	controller.spawn_drone(Vector2(100, 0))
	controller.spawn_drone(Vector2(120, 0))
	for left in [1, 2]:
		for right in [3, 4]:
			controller.electric_subnet.set_forbidden_edge(left, right)
	controller._sync_graph_from_manager()
	assert_eq(controller._areas.size(), 2)
	assert_true(controller._areas.has(subnet_id))
	for split_id in controller._areas.keys():
		assert_eq((controller._areas[split_id] as ElectricSubnetArea).collision_mask, 2)
	assert_true(controller._areas[subnet_id]._shapes.has("1:2"))
	assert_ne(controller._areas[subnet_id]._shapes["1:2"], shape)

func test_area_uses_fake_overlap_and_resolver_without_physics_server() -> void:
	var area := AREA.new() as ElectricSubnetArea
	add_child_autofree(area)
	area.network_id_resolver = func(_body: Node2D) -> String: return "resolved-player"
	var player := FakePlayer.new()
	player.add_to_group(&"player")
	add_child_autofree(player)
	area._on_body_entered(player)
	assert_eq(area.target_ids(), ["resolved-player"])
	area._on_body_exited(player)
	assert_eq(area.target_ids(), [])

func test_area_rejects_non_player_fake_overlap() -> void:
	var area := AREA.new() as ElectricSubnetArea
	add_child_autofree(area)
	var body := Node2D.new()
	add_child_autofree(body)
	area._on_body_entered(body)
	assert_eq(area.target_ids(), [])

func test_overlapping_subnets_apply_independently_through_health_component_and_only_stun_players() -> void:
	var controller := _controller()
	var player := FakePlayer.new()
	player.add_to_group(&"player")
	var health := HealthComponent.new()
	health.name = "HealthComponent"
	health.max_health = 100
	player.health = health
	player.add_child(health)
	add_child_autofree(player)
	_spawn_pair(controller)
	controller.spawn_drone(Vector2(100, 0))
	controller.spawn_drone(Vector2(120, 0))
	for left in [1, 2]:
		for right in [3, 4]:
			controller.electric_subnet.set_forbidden_edge(left, right)
	controller._sync_graph_from_manager()
	for area in controller._areas.values():
		(area as ElectricSubnetArea)._on_body_entered(player)
	controller.electric_subnet.damage_per_tick = 7.0
	controller._physics_process(0.1)
	assert_eq(health.health, 86)
	assert_eq(player.stun_calls, 1) # The core marks one event eligible; its immunity is untouched here.

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
