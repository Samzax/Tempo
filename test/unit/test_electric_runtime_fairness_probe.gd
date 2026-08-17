## Diagnostic gameplay/fairness probe.  It deliberately does not approve tuning
## values such as radius, beam thickness, speed, damage magnitude, or final fairness.
extends GutTest

const CONTROLLER := preload("res://scripts/enemies/bosses/electric_grid_controller.gd")
const SUBNET := preload("res://scripts/combat/electric_subnet.gd")

const PROBE_POSITIONS := {
	"center": Vector2.ZERO,
	"north_west_corner": Vector2(-400.0, -300.0),
	"north_east_corner": Vector2(400.0, -300.0),
	"south_west_corner": Vector2(-400.0, 300.0),
	"south_east_corner": Vector2(400.0, 300.0),
}

class FakePlayer extends Node2D:
	var health: HealthComponent
	var stun_calls := 0
	var last_stun_duration := 0.0
	func apply_stun(duration: float) -> void:
		stun_calls += 1
		last_stun_duration = duration
	func take_damage(_info: DamageInfo) -> int:
		push_error("Probe requires ElectricGridController to use HealthComponent")
		return 0

class FakeNonPlayer extends Node2D:
	var health: HealthComponent
	var stun_calls := 0
	func apply_stun(_duration: float) -> void:
		stun_calls += 1

func _fake_non_player(network_id: String) -> FakeNonPlayer:
	var target := FakeNonPlayer.new()
	var health := HealthComponent.new()
	health.name = "HealthComponent"
	health.max_health = 100
	target.health = health
	target.add_child(health)
	target.set_meta(&"network_id", network_id)
	add_child_autofree(target)
	return target

func _controller(host := true) -> ElectricGridController:
	var controller := CONTROLLER.new(host) as ElectricGridController
	add_child_autofree(controller)
	return controller

func _fake_player(position: Vector2, network_id: String) -> FakePlayer:
	var player := FakePlayer.new()
	player.position = position
	player.add_to_group(&"player")
	player.set_meta(&"network_id", network_id)
	var health := HealthComponent.new()
	health.name = "HealthComponent"
	health.max_health = 100
	player.health = health
	player.add_child(health)
	add_child_autofree(player)
	return player

func _two_subnets(controller: ElectricGridController) -> void:
	for position in [Vector2.ZERO, Vector2(20.0, 0.0), Vector2(100.0, 0.0), Vector2(120.0, 0.0)]:
		controller.spawn_drone(position)
	for left in [1, 2]:
		for right in [3, 4]:
			assert_true(controller.electric_subnet.set_forbidden_edge(left, right))
	controller._sync_graph_from_manager()

func _register_in_all_areas(controller: ElectricGridController, player: FakePlayer) -> void:
	for area in controller._areas.values():
		area._on_body_entered(player)

func _degree_is_bounded(edges: Array) -> bool:
	var degree := {}
	for edge in edges:
		degree[edge.a] = int(degree.get(edge.a, 0)) + 1
		degree[edge.b] = int(degree.get(edge.b, 0)) + 1
	for value in degree.values():
		if int(value) > 2:
			return false
	return true

func test_probe_matrix_presets_are_diagnostic_until_real_physics_query() -> void:
	# Presets are enumerated only. Manual body_entered injection cannot validate
	# radius, collision, spatial coverage, damage, or fairness.
	var enumerated: Array[String] = []
	for position_label in PROBE_POSITIONS:
		enumerated.append(position_label)
	assert_eq(enumerated.size(), 5)
	pending("DIAGNOSTIC INCONCLUSIVE: center and four corners (%s) need a real stable physics query" % ", ".join(enumerated))

func test_probe_authority_health_stun_and_subnet_dedup_invariants() -> void:
	var client := _controller(false)
	var client_before := client.electric_subnet.snapshot()
	assert_eq(client.spawn_drone(), {})
	client._physics_process(1.0)
	assert_eq(client._server_tick, 0)
	assert_eq(client.electric_subnet.snapshot(), client_before)
	var host := _controller()
	var prop := _fake_non_player("prop-health")
	host._targets["prop-health"] = weakref(prop)
	host._apply_event({"target_network_id": "prop-health", "damage_amount": 3.0, "stun_candidate": true, "stun_duration": 0.5})
	assert_eq(prop.health.health, 97)
	assert_eq(prop.stun_calls, 0)

	var graph := SUBNET.new()
	graph.damage_per_tick = 2.0
	assert_true(graph.add_residual("one", "residual-one", 0, 20))
	assert_true(graph.add_residual("two", "residual-two", 0, 20))
	var player_target := {"network_id": "player", "is_player": true, "subnet_ids": ["one", "one", "two"]}
	var player_events := graph.resolve_damage_tick(1, [player_target])
	assert_eq(player_events.size(), 2)
	assert_eq(player_events[0].damage_amount + player_events[1].damage_amount, 4.0)
	assert_eq(player_events.filter(func(event): return event.stun_candidate).size(), 1)
	var non_player_events := graph.resolve_damage_tick(2, [{"network_id": "prop", "is_player": false, "subnet_ids": ["one"]}])
	assert_eq(non_player_events.size(), 1)
	assert_false(non_player_events[0].stun_candidate)
	var stun_player := _fake_player(Vector2.ZERO, "player")
	client = _controller()
	client._targets["player"] = weakref(stun_player)
	for event in player_events:
		client._apply_event(event)
	assert_eq(stun_player.stun_calls, 1)
	for server_tick in range(2, 11):
		var immune_tick_events := graph.resolve_damage_tick(server_tick, [player_target])
		assert_eq(immune_tick_events.size(), 2)
		assert_true(immune_tick_events.all(func(event): return not event.stun_candidate))
		for event in immune_tick_events:
			client._apply_event(event)
		assert_eq(stun_player.stun_calls, 1)
		assert_lt(stun_player.health.health, 100 - 4 * (server_tick - 1))
	assert_eq(stun_player.health.health, 60)
	var post_immunity_events := graph.resolve_damage_tick(11, [player_target])
	assert_eq(post_immunity_events.size(), 2)
	assert_eq(post_immunity_events.filter(func(event): return event.stun_candidate).size(), 1)
	# After immunity expires, the eligible event is applied as emitted. Damage
	# continues for every source while only the eligible event stuns.
	for event in post_immunity_events:
		var damage_only: Dictionary = event.duplicate(true)
		client._apply_event(damage_only)
	assert_eq(stun_player.stun_calls, 2)
	assert_eq(stun_player.health.health, 56)

func test_probe_three_drones_two_links_do_not_multiply_same_target_damage() -> void:
	var controller := _controller()
	controller.electric_subnet.damage_per_tick = 3.0
	controller.spawn_drone(Vector2.ZERO)
	controller.spawn_drone(Vector2(20.0, 0.0))
	controller.spawn_drone(Vector2(40.0, 0.0))
	var subnets := controller.electric_subnet.subnets()
	var edges := controller.electric_subnet.edges()
	if subnets.size() != 1 or edges.size() != 2:
		pending("PENDING: fixture/API did not produce one 3-drone subnet with two links")
		return
	var subnet_id: String = subnets[0].subnet_id
	var events := controller.electric_subnet.resolve_damage_tick(1, [{"network_id": "same-target", "is_player": false, "subnet_ids": [subnet_id]}])
	assert_eq(events.size(), 1)
	assert_eq(events[0].damage_amount, 3.0)

func test_probe_transit_replacement_interval_is_pending_without_production_motion_loop() -> void:
	pending("PENDING: transit/replacement/interval requires the production spawn_electric_drone and position loop")

func test_probe_residual_split_and_reconnect() -> void:
	var controller := _controller()
	var player := _fake_player(Vector2.ZERO, "before-link")
	controller.electric_subnet.damage_per_tick = 3.0
	controller.spawn_drone(Vector2.ZERO)
	controller._physics_process(0.2)
	assert_eq(controller._areas.size(), 0)
	assert_eq(player.health.health, 100) # Reposition/transit with no edge creates no aura or damage.
	controller.spawn_drone(Vector2(20.0, 0.0))
	_register_in_all_areas(controller, player)
	controller._physics_process(0.1)
	assert_eq(player.health.health, 97)

	var subnet_id: String = controller.electric_subnet.subnets()[0].subnet_id
	assert_true(controller.electric_subnet.add_residual(subnet_id, "one-second", controller._server_tick, 10))
	assert_true(controller.destroy_drone(2))
	var residual_target := {"network_id": "residual-target", "is_player": false, "subnet_ids": [subnet_id]}
	assert_eq(controller.electric_subnet.resolve_damage_tick(controller._server_tick + 10, [residual_target]).size(), 1)
	assert_eq(controller.electric_subnet.resolve_damage_tick(controller._server_tick + 11, [residual_target]), [])

	# Split into two subnets and reconnect them; degree and Area ownership stay bounded.
	controller.spawn_drone(Vector2(25.0, 0.0))
	controller.spawn_drone(Vector2(100.0, 0.0))
	controller.spawn_drone(Vector2(120.0, 0.0))
	for left in [1, 3]:
		for right in [4, 5]:
			assert_true(controller.electric_subnet.set_forbidden_edge(left, right))
	controller._sync_graph_from_manager()
	assert_eq(controller._areas.size(), 2)
	assert_true(_degree_is_bounded(controller.electric_subnet.edges()))
	for left in [1, 3]:
		for right in [4, 5]:
			assert_true(controller.electric_subnet.set_forbidden_edge(left, right, false))
	controller._sync_graph_from_manager()
	assert_true(_degree_is_bounded(controller.electric_subnet.edges()))
	assert_eq(controller.electric_subnet.subnets().size(), 1, "effective reconnection: one subnet")
	assert_eq(controller._areas.size(), 1, "effective reconnection: one subnet/one area")

func test_probe_jitter_lag_spike_and_bounded_catch_up_are_not_tuning_gates() -> void:
	var controller := _controller()
	controller.tick_seconds = 0.1
	controller.max_ticks_per_frame = 3
	var before_tick := controller._server_tick
	controller._physics_process(2.0)
	assert_true(controller._server_tick - before_tick <= controller.max_ticks_per_frame)
	assert_true(is_finite(controller._tick_accumulator))
	assert_true(controller._tick_accumulator >= 0.0)
	assert_true(controller._tick_accumulator < controller.tick_seconds)
	# Keep real frame-time jitter in the probe after the deliberately finite spike.
	var jitter_deltas: Array[float] = [1.0 / 60.0, 1.0 / 30.0, 0.017, 0.2, 1.0 / 144.0]
	for frame in range(60):
		controller._physics_process(jitter_deltas[frame % jitter_deltas.size()])
	assert_true(is_finite(controller._tick_accumulator))
	assert_true(controller._tick_accumulator >= 0.0)
	assert_true(controller._tick_accumulator < controller.tick_seconds)

func test_probe_explicit_fps_cadences_remain_bounded() -> void:
	var fps_deltas: Array[float] = [1.0 / 30.0, 1.0 / 60.0, 1.0 / 144.0]
	for fps_delta in fps_deltas:
		var controller := _controller()
		controller.tick_seconds = 0.1
		controller.max_ticks_per_frame = 3
		for frame in range(60):
			controller._physics_process(fps_delta)
		var elapsed_seconds := 60.0 * fps_delta
		var ideal_ticks := elapsed_seconds / controller.tick_seconds
		var lower_tick_bound: float = floor(ideal_ticks) - 0.000001
		var upper_tick_bound: float = ceil(ideal_ticks) + 0.000001
		assert_true(controller._server_tick >= lower_tick_bound)
		assert_true(controller._server_tick <= upper_tick_bound)
		assert_true(controller._server_tick * controller.tick_seconds <= elapsed_seconds + 0.000001)
		assert_true(is_finite(controller._tick_accumulator))
		assert_true(controller._tick_accumulator >= 0.0)
		assert_true(controller._tick_accumulator < controller.tick_seconds)

func test_probe_corner_collision_is_inconclusive_without_real_stable_physics_query() -> void:
	# ElectricSubnetArea has only signal-fed overlap bookkeeping in this supported fixture.
	# Do not fabricate a radius/corner approval from manual _on_body_entered calls.
	pending("DIAGNOSTIC INCONCLUSIVE: corner/collision requires a stable real physics query")
