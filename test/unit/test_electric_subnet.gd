extends GutTest

const ElectricSubnetScript = preload("res://scripts/combat/electric_subnet.gd")

func _drone(id: int, pos: Vector2) -> Dictionary: return {"id": id, "position": pos}

func test_authority_and_deterministic_graph_degree_and_open_rule() -> void:
	var client = ElectricSubnetScript.new(false)
	assert_false(client.register_drone(_drone(1, Vector2.ZERO)))
	assert_false(client.remove_drone(1))
	assert_false(client.set_forbidden_edge(1, 2))
	assert_false(client.set_formation_open(1))
	assert_false(client.add_residual("s", "r", 0))
	assert_eq(client.resolve_damage_tick(1, []), [])
	var graph = ElectricSubnetScript.new()
	for record in [_drone(3, Vector2(1, 1)), _drone(1, Vector2.ZERO), _drone(2, Vector2(1, 0))]: assert_true(graph.register_drone(record))
	assert_eq(graph.edges().size(), 3)
	assert_eq(graph.edges(), [{"a": 1, "b": 2}, {"a": 2, "b": 3}, {"a": 1, "b": 3}])
	for edge in graph.edges():
		assert_lte(graph.edges().filter(func(item): return item.a == edge.a or item.b == edge.a).size(), 2)
		assert_lte(graph.edges().filter(func(item): return item.a == edge.b or item.b == edge.b).size(), 2)
	assert_true(graph.subnets()[0].closed)
	assert_true(graph.set_formation_open(3, true))
	assert_eq(graph.edges().size(), 1)
	for edge in graph.edges(): assert_ne(edge.a, 3); assert_ne(edge.b, 3)
	for subnet in graph.subnets(): assert_false(subnet.closed)

func test_structural_distance_hysteresis_and_deterministic_ties() -> void:
	var graph := ElectricSubnetScript.new()
	graph.connect_distance = 58.0; graph.break_distance = 74.0
	graph.register_drone(_drone(1, Vector2.ZERO)); graph.register_drone(_drone(2, Vector2(58, 0)))
	assert_eq(graph.edges(), [{"a": 1, "b": 2}])
	graph.register_drone(_drone(3, Vector2(0, 58))); graph.register_drone(_drone(4, Vector2(58, 58)))
	assert_lte(graph.edges().filter(func(edge): return edge.a == 1 or edge.b == 1).size(), 2)
	assert_eq(graph.edges()[0], {"a": 1, "b": 2})
	var hysteresis := ElectricSubnetScript.new(); hysteresis.connect_distance = 58.0; hysteresis.break_distance = 74.0
	hysteresis.register_drone(_drone(1, Vector2.ZERO)); hysteresis.register_drone(_drone(5, Vector2(58, 0)))
	assert_eq(hysteresis.edges(), [{"a": 1, "b": 5}])
	hysteresis.register_drone(_drone(5, Vector2(74.01, 0)))
	assert_eq(hysteresis.edges(), [])
	var retained := ElectricSubnetScript.new(); retained.connect_distance = 58.0; retained.break_distance = 74.0
	retained.register_drone(_drone(5, Vector2.ZERO)); retained.register_drone(_drone(6, Vector2(58.0, 0)))
	assert_eq(retained.edges(), [{"a": 5, "b": 6}])
	retained.register_drone(_drone(6, Vector2(74.0, 0)))
	assert_eq(retained.edges(), [{"a": 5, "b": 6}])
	retained.register_drone(_drone(5, Vector2(74.01, 0)))
	assert_eq(retained.edges(), [{"a": 5, "b": 6}])
	assert_true(graph.set_formation_open(2, true))
	assert_false(graph.edges().any(func(edge): return edge.a == 2 or edge.b == 2))
	assert_true(graph.set_formation_open(2, false))
	assert_true(graph.edges().any(func(edge): return edge.a == 1 and edge.b == 2))

func test_formation_open_endpoints_are_absent_from_edges_subnets_and_areas() -> void:
	var graph := ElectricSubnetScript.new()
	graph.connect_distance = 58.0; graph.break_distance = 74.0
	for record in [_drone(1, Vector2.ZERO), _drone(2, Vector2(20, 0)), _drone(3, Vector2(40, 0))]: graph.register_drone(record)
	graph.set_formation_open(2, true)
	for edge in graph.edges(): assert_ne(edge.a, 2); assert_ne(edge.b, 2)
	for subnet in graph.subnets(): assert_false(subnet.drone_ids.has(2))
	assert_true(graph.snapshot().formation_open_drone_ids.has(2))

func test_revision_changes_only_for_topology() -> void:
	var graph = ElectricSubnetScript.new()
	graph.register_drone(_drone(1, Vector2.ZERO)); var revision = graph.graph_revision
	graph.register_drone(_drone(2, Vector2.RIGHT)); assert_gt(graph.graph_revision, revision)
	revision = graph.graph_revision
	assert_false(graph.set_forbidden_edge(8, 9, true))
	assert_eq(graph.graph_revision, revision)
	graph.set_formation_open(1, false)
	assert_eq(graph.graph_revision, revision)

func test_overlap_dedup_and_player_stun() -> void:
	var graph = ElectricSubnetScript.new(); graph.damage_per_tick = 2.0
	for record in [_drone(1, Vector2.ZERO), _drone(2, Vector2.RIGHT), _drone(3, Vector2(4, 0)), _drone(4, Vector2(5, 0))]: graph.register_drone(record)
	for a in [1, 2]:
		for b in [3, 4]: graph.set_forbidden_edge(a, b)
	var ids := [graph.subnets()[0].subnet_id, graph.subnets()[1].subnet_id]
	var target := {"network_id": "p", "is_player": true, "subnet_ids": ids}
	var first_tick = graph.resolve_damage_tick(1, [target])
	assert_eq(first_tick.size(), 2)
	assert_eq(first_tick[0].damage + first_tick[1].damage, 4.0)
	assert_eq(first_tick[0].damage_amount, 2.0)
	assert_eq(first_tick[0].damage_type, "electric")
	assert_eq(first_tick[0].damage_tags, ["electric", "subnet"])
	assert_eq(first_tick[0].source_id, first_tick[0].subnet_id)
	assert_eq(first_tick[0].source_identity, {"kind": "electric_subnet", "subnet_id": first_tick[0].subnet_id})
	assert_true(first_tick[0].has("damage")) # DamageInfo-ready amount alias
	assert_true(first_tick[0].has("stun_candidate"))
	assert_eq(first_tick[0].source_identity.kind, "electric_subnet")
	assert_eq(first_tick[0].target_network_id, "p")
	assert_eq(first_tick[0].server_tick, 1)
	assert_eq(first_tick[0].graph_revision, graph.graph_revision)
	assert_eq(first_tick[0].event_identity.target_network_id, "p")
	assert_eq(first_tick[0].event_identity.server_tick, 1)
	assert_eq(first_tick[0].event_identity.graph_revision, graph.graph_revision)
	assert_eq(first_tick[0].stun_duration, 0.5)
	assert_true(first_tick[0].stun_candidate)
	assert_eq(graph._stun_until["p"], 6) # 0.5s at 0.1s/tick
	assert_eq(graph._immune_until["p"], 11) # 1.0s at 0.1s/tick
	assert_eq(graph.resolve_damage_tick(1, [target]).size(), 0)
	var events = graph.resolve_damage_tick(2, [target])
	assert_false(events[0].stun_candidate)
	assert_eq(events.size(), 2) # immunity suppresses stun, not damage events
	assert_eq(graph._stun_until["p"], 6)
	assert_eq(graph._immune_until["p"], 11)
	assert_eq(graph.resolve_damage_tick(3, [{"network_id":"e", "is_player":false, "subnet_ids":ids}])[0].stun_candidate, false)
	assert_eq(graph.resolve_damage_tick(3, [{"network_id":"e", "is_player":false, "subnet_ids":ids}]).size(), 0)
	var immune_player_events = graph.resolve_damage_tick(3, [{"network_id":"q", "is_player":true, "subnet_ids":ids}])
	assert_eq(immune_player_events.size(), 2)
	assert_true(immune_player_events[0].stun_candidate) # Immunity belongs to p, never the whole graph.
	assert_eq(graph.resolve_damage_tick(14, [{"network_id":"q", "is_player":true, "subnet_ids":ids}])[0].stun_candidate, true)

func test_snapshot_is_idempotent_and_complete_for_late_join() -> void:
	var graph = ElectricSubnetScript.new(); graph.damage_per_tick = 1.0
	graph.register_drone(_drone(1, Vector2.ZERO)); graph.register_drone(_drone(2, Vector2.RIGHT)); graph.set_formation_open(1, true)
	graph.add_residual("subnet:1:2", "r", 0, 8)
	graph.resolve_damage_tick(1, [{"network_id":"p", "is_player":true, "subnet_ids":["subnet:1:2"]}])
	var state = graph.snapshot(); var late_join = ElectricSubnetScript.new(false)
	assert_true(late_join.apply_snapshot(state)); assert_eq(late_join.snapshot(), state)
	assert_true(late_join.apply_snapshot(state)); assert_eq(late_join.snapshot(), state)
	assert_false(graph.apply_snapshot(state)) # The authoritative instance never applies a remote snapshot.
	var non_canonical = state.duplicate(true)
	non_canonical.drones.reverse()
	assert_false(ElectricSubnetScript.new(false).apply_snapshot(non_canonical))
	# A client can hydrate, but cannot turn that state into a local simulation or mutation.
	assert_false(late_join.register_drone(_drone(3, Vector2(2, 0))))
	assert_false(late_join.add_residual("subnet:1:2", "client", 1))
	assert_eq(late_join.resolve_damage_tick(2, []), [])

func test_duplicate_residual_is_idempotent_but_distinct_subnets_are_cumulative() -> void:
	var graph = ElectricSubnetScript.new(); graph.damage_per_tick = 3.0
	assert_true(graph.add_residual("a", "same", 0, 5))
	assert_true(graph.add_residual("a", "same", 0, 99))
	assert_true(graph.add_residual("b", "same", 0, 5))
	assert_eq(graph.snapshot().residuals.size(), 2)
	var target := {"network_id":"target", "is_player":false, "subnet_ids":["a", "b"]}
	var events = graph.resolve_damage_tick(1, [target])
	assert_eq(events.size(), 2)
	assert_eq(events[0].damage_amount + events[1].damage_amount, 6.0)
	assert_eq(graph.resolve_damage_tick(1, [target]), [])
	assert_eq(graph.resolve_damage_tick(6, [target]), [])

func test_multiple_residuals_per_subnet_are_distinct_and_state_only() -> void:
	var graph = ElectricSubnetScript.new(); graph.damage_per_tick = 3.0
	var graph_cursor: int = graph.graph_revision; var state_cursor: int = graph.state_revision
	assert_true(graph.add_residual("a", "r1", 0, 5))
	assert_eq(graph.graph_revision, graph_cursor); assert_gt(graph.state_revision, state_cursor)
	assert_true(graph.add_residual("a", "r2", 0, 5))
	assert_true(graph.add_residual("a", "r2", 0, 99))
	var events = graph.resolve_damage_tick(1, [{"network_id":"target", "subnet_ids":["a"]}])
	assert_eq(events.size(), 2)
	assert_eq([events[0].event_identity.residual_id, events[1].event_identity.residual_id], ["r1", "r2"])
	assert_eq(graph.resolve_damage_tick(1, [{"network_id":"target", "subnet_ids":["a"]}]), [])

func test_malformed_snapshot_is_rejected_before_normalization() -> void:
	var source = ElectricSubnetScript.new(); source.register_drone(_drone(1, Vector2.ZERO)); source.register_drone(_drone(2, Vector2.RIGHT))
	var malformed: Array = []
	var bad_drones = source.snapshot(); bad_drones.drones = ["not-a-drone"]; malformed.append(bad_drones)
	var missing_id = source.snapshot(); missing_id.drones = [{}]; malformed.append(missing_id)
	var bad_map = source.snapshot(); bad_map.stun_until = []; malformed.append(bad_map)
	var bad_residual = source.snapshot(); bad_residual.residuals = ["not-a-map"]; malformed.append(bad_residual)
	var bad_subnet = source.snapshot(); bad_subnet.subnets = [{"subnet_id": "x", "source_id": "x", "drone_ids": "bad", "edges": [], "closed": false}]; malformed.append(bad_subnet)
	var bad_time_value = source.snapshot(); bad_time_value.stun_until = {"p": "not-an-int"}; malformed.append(bad_time_value)
	var bad_seen_identity = source.snapshot(); bad_seen_identity.seen_events = [{"target_network_id": "p", "source_identity": [], "subnet_id": "x", "server_tick": 1, "graph_revision": 1, "residual_id": "r"}]; malformed.append(bad_seen_identity)
	for state in malformed: assert_false(ElectricSubnetScript.new(false).apply_snapshot(state))

func test_time_maps_canonicalize_and_remain_idempotent() -> void:
	var source = ElectricSubnetScript.new(); source.add_residual("arc", "r", 0, 10)
	source.resolve_damage_tick(1, [{"network_id":"z", "is_player":true, "subnet_ids":["arc"]}])
	source.resolve_damage_tick(2, [{"network_id":"a", "is_player":true, "subnet_ids":["arc"]}])
	var state = source.snapshot(); var reordered = state.duplicate(true)
	reordered.stun_until = {"z": state.stun_until["z"], "a": state.stun_until["a"]}
	reordered.immune_until = {"z": state.immune_until["z"], "a": state.immune_until["a"]}
	var client = ElectricSubnetScript.new(false)
	assert_true(client.apply_snapshot(reordered))
	assert_eq(client.snapshot().stun_until.keys(), ["a", "z"])
	assert_eq(client.snapshot().immune_until.keys(), ["a", "z"])
	assert_true(client.apply_snapshot(client.snapshot()))

func test_old_snapshot_is_rejected_without_regressing_revision() -> void:
	var graph = ElectricSubnetScript.new()
	graph.register_drone(_drone(1, Vector2.ZERO)); graph.register_drone(_drone(2, Vector2.RIGHT))
	var client = ElectricSubnetScript.new(false); assert_true(client.apply_snapshot(graph.snapshot()))
	var current_revision: int = client.graph_revision
	var stale = graph.snapshot(); stale.graph_revision = current_revision - 1
	stale.state_revision = graph.state_revision - 1
	assert_false(client.apply_snapshot(stale))
	assert_eq(client.graph_revision, current_revision)

func test_snapshot_rejects_regressive_seen_event_state_and_preserves_graph() -> void:
	var graph = ElectricSubnetScript.new()
	graph.register_drone(_drone(1, Vector2.ZERO)); graph.register_drone(_drone(2, Vector2.RIGHT))
	var state = graph.snapshot()
	var client = ElectricSubnetScript.new(false); assert_true(client.apply_snapshot(state))
	var stale = state.duplicate(true)
	stale.state_revision = graph.state_revision - 1
	assert_false(client.apply_snapshot(stale))
	assert_eq(client.snapshot(), state)

func test_snapshot_cursor_rejects_old_and_same_cursor_non_idempotent_state() -> void:
	var graph = ElectricSubnetScript.new()
	graph.register_drone(_drone(1, Vector2.ZERO)); graph.register_drone(_drone(2, Vector2.RIGHT))
	var current = graph.snapshot()
	var client = ElectricSubnetScript.new(false); assert_true(client.apply_snapshot(current))
	var same_cursor_different = current.duplicate(true)
	same_cursor_different.residuals.append({"subnet_id":"x", "residual_id":"bad", "expires_at_tick":9})
	assert_false(client.apply_snapshot(same_cursor_different))
	var old = current.duplicate(true); old.state_revision -= 1
	assert_false(client.apply_snapshot(old))

func test_late_tick_retransmission_remains_deduplicated_and_serialized() -> void:
	var graph = ElectricSubnetScript.new(); graph.add_residual("arc", "r1", 0, 20)
	var target = {"network_id":"p", "is_player":false, "subnet_ids":["arc"]}
	assert_eq(graph.resolve_damage_tick(5, [target]).size(), 1)
	assert_eq(graph.resolve_damage_tick(6, [target]).size(), 1)
	assert_eq(graph.resolve_damage_tick(5, [target]), [])
	var state = graph.snapshot()
	assert_true(state.seen_events[0] is Dictionary)
	assert_true(state.seen_events[0].has("residual_id"))

func test_event_identity_contains_target_source_tick_revision_and_residual() -> void:
	var graph = ElectricSubnetScript.new(); graph.damage_per_tick = 1.0
	assert_true(graph.add_residual("residual-subnet", "residual-7", 0, 10))
	var events = graph.resolve_damage_tick(3, [{"network_id":"target-1", "subnet_ids":["residual-subnet"]}])
	assert_eq(events.size(), 1)
	var identity: Dictionary = events[0].event_identity
	assert_eq(identity.target_network_id, "target-1")
	assert_eq(identity.source_identity, {"kind":"electric_subnet", "subnet_id":"residual-subnet"})
	assert_eq(identity.subnet_id, "residual-subnet")
	assert_eq(identity.server_tick, 3)
	assert_eq(identity.graph_revision, graph.graph_revision)
	assert_eq(identity.residual_id, "residual-7")

func test_event_identity_is_unambiguous_when_ids_contain_pipes() -> void:
	var graph = ElectricSubnetScript.new()
	assert_true(graph.add_residual("arc|one", "r|1", 0, 10))
	assert_true(graph.add_residual("arc", "one|r|1", 0, 10))
	var events = graph.resolve_damage_tick(3, [{"network_id":"p|q", "subnet_ids":["arc|one", "arc"]}])
	assert_eq(events.size(), 2)
	assert_ne(graph._identity_key(events[0].event_identity), graph._identity_key(events[1].event_identity))
	assert_eq(graph._identity_key(events[0].event_identity), var_to_str([events[0].event_identity.target_network_id, events[0].event_identity.source_identity, events[0].event_identity.subnet_id, events[0].event_identity.server_tick, events[0].event_identity.graph_revision, events[0].event_identity.residual_id]))
	assert_eq(graph._identity_key(events[1].event_identity), var_to_str([events[1].event_identity.target_network_id, events[1].event_identity.source_identity, events[1].event_identity.subnet_id, events[1].event_identity.server_tick, events[1].event_identity.graph_revision, events[1].event_identity.residual_id]))

func test_client_rejects_graph_signature_conflict() -> void:
	var source = ElectricSubnetScript.new()
	source.register_drone(_drone(1, Vector2.ZERO)); source.register_drone(_drone(2, Vector2.RIGHT))
	var state = source.snapshot(); state.graph_signature = "conflict"; state.state_revision += 1
	assert_false(ElectricSubnetScript.new(false).apply_snapshot(state))
	var zero_revision = source.snapshot(); zero_revision.graph_revision = 0; zero_revision.state_revision += 1
	assert_false(ElectricSubnetScript.new(false).apply_snapshot(zero_revision))

func test_graph_signature_covers_edges_subnets_forbidden_and_formation() -> void:
	var graph = ElectricSubnetScript.new()
	graph.register_drone(_drone(1, Vector2.ZERO)); graph.register_drone(_drone(2, Vector2(20, 0))); graph.register_drone(_drone(3, Vector2(40, 0))); graph.register_drone(_drone(4, Vector2(60, 0)))
	graph.set_formation_open(4, true)
	graph.set_forbidden_edge(1, 2)
	var state = graph.snapshot()
	# Each payload changes one signed dimension while retaining the original signature.
	var edge_changed = state.duplicate(true); edge_changed.edges = []; edge_changed.state_revision += 1
	var subnet_changed = state.duplicate(true); subnet_changed.subnets = []; subnet_changed.state_revision += 1
	var forbidden_changed = state.duplicate(true); forbidden_changed.forbidden_edges = []; forbidden_changed.state_revision += 1
	var formation_changed = state.duplicate(true); formation_changed.formation_open_drone_ids = []; formation_changed.state_revision += 1
	for changed in [edge_changed, subnet_changed, forbidden_changed, formation_changed]:
		assert_false(ElectricSubnetScript.new(false).apply_snapshot(changed))

func test_older_snapshot_preserves_residual_timers_and_seen_event_cache() -> void:
	var graph = ElectricSubnetScript.new(); graph.damage_per_tick = 1.0
	assert_true(graph.add_residual("arc", "r", 0, 20))
	var first = graph.resolve_damage_tick(2, [{"network_id":"p", "subnet_ids":["arc"]}])
	assert_eq(first.size(), 1)
	var current = graph.snapshot()
	var client = ElectricSubnetScript.new(false); assert_true(client.apply_snapshot(current))
	var stale = current.duplicate(true); stale.state_revision = current.state_revision - 1
	stale.residuals[0].expires_at_tick = 3; stale.seen_events = []
	assert_false(client.apply_snapshot(stale))
	assert_eq(client.snapshot().residuals, current.residuals)
	assert_eq(client.snapshot().seen_events, current.seen_events)
	assert_eq(graph.resolve_damage_tick(2, [{"network_id":"p", "subnet_ids":["arc"]}]), [])

func test_snapshot_rejects_self_edge() -> void:
	var source = ElectricSubnetScript.new()
	for id in [1, 2, 3, 4]: source.register_drone(_drone(id, Vector2(id, 0)))
	var self_edge = source.snapshot(); self_edge.edges = [{"a":1,"b":1}]
	assert_false(ElectricSubnetScript.new(false).apply_snapshot(self_edge))

func test_snapshot_rejects_duplicate_edge() -> void:
	var source = ElectricSubnetScript.new()
	for id in [1, 2, 3, 4]: source.register_drone(_drone(id, Vector2(id, 0)))
	var duplicate = source.snapshot(); duplicate.edges = [{"a":1,"b":2},{"a":2,"b":1}]
	assert_false(ElectricSubnetScript.new(false).apply_snapshot(duplicate))

func test_snapshot_rejects_missing_edge_endpoint() -> void:
	var source = ElectricSubnetScript.new()
	for id in [1, 2, 3, 4]: source.register_drone(_drone(id, Vector2(id, 0)))
	var missing_endpoint = source.snapshot(); missing_endpoint.edges = [{"a":1,"b":99}]
	assert_false(ElectricSubnetScript.new(false).apply_snapshot(missing_endpoint))

func test_removing_drone_clears_forbidden_edges_and_snapshot_topology() -> void:
	var graph = ElectricSubnetScript.new()
	for id in [1, 2, 3]: graph.register_drone(_drone(id, Vector2(id, 0)))
	assert_true(graph.set_forbidden_edge(1, 3))
	assert_true(graph.remove_drone(3))
	var state: Dictionary = graph.snapshot()
	assert_eq(state.forbidden_edges, [])
	for edge in state.edges:
		assert_ne(edge.a, 3)
		assert_ne(edge.b, 3)
	assert_eq(state.drones.map(func(drone): return int(drone.id)), [1, 2])

func test_snapshot_rejects_degree_three() -> void:
	var source = ElectricSubnetScript.new()
	for id in [1, 2, 3, 4]: source.register_drone(_drone(id, Vector2(id, 0)))
	var degree_three = source.snapshot(); degree_three.edges = [{"a":1,"b":2},{"a":1,"b":3},{"a":1,"b":4}]
	assert_false(ElectricSubnetScript.new(false).apply_snapshot(degree_three))

func test_snapshot_rejects_incoherent_subnet() -> void:
	var source = ElectricSubnetScript.new()
	for id in [1, 2, 3, 4]: source.register_drone(_drone(id, Vector2(id, 0)))
	var incoherent = source.snapshot(); incoherent.subnets = []
	incoherent.graph_signature = source._topology_signature_for(incoherent.drones, incoherent.edges, incoherent.subnets, incoherent.forbidden_edges, incoherent.formation_open_drone_ids)
	assert_false(ElectricSubnetScript.new(false).apply_snapshot(incoherent))

func test_snapshot_rejects_invalid_graph_topology() -> void:
	var graph = ElectricSubnetScript.new()
	for id in [1, 2, 3, 4]: graph.register_drone(_drone(id, Vector2(id, 0)))
	var invalid = graph.snapshot()
	invalid.edges = [{"a":1,"b":2}, {"a":1,"b":3}, {"a":1,"b":4}]
	invalid.subnets = []
	invalid.state_revision += 1
	assert_false(ElectricSubnetScript.new(false).apply_snapshot(invalid))
