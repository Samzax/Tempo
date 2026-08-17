## Pure, server-owned electric graph and DamageInfo-ready event resolver.
## Snapshot hydration is permitted on replicas; graph mutation and simulation are server-only.
class_name ElectricSubnet
extends RefCounted

var is_server := true
var damage_per_tick := 0.0
var stun_duration := 0.5
var stun_immunity_duration := 1.0
var tick_seconds := 0.1
var residual_lifetime_ticks := 0
## Disabled by default so standalone users retain the previous unconstrained graph.
## These are structural gate candidates, not final fairness/tuning values.
var connect_distance := INF
var break_distance := INF
var graph_revision := 0
var state_revision := 0 # Monotonic cursor for every replicated mutation, not just topology.

var _drones: Dictionary = {}
var _forbidden: Dictionary = {}
var _edges: Array = []
var _subnets: Array = []
var _seen_events: Dictionary = {} # Canonical event identity -> serialized structured identity.
var _stun_until: Dictionary = {}
var _immune_until: Dictionary = {}
var _residuals: Array = []
var _topology_signature := ""

func _init(server_authority := true) -> void:
	is_server = server_authority

func register_drone(drone: Dictionary) -> bool:
	if not is_server or not drone.has("id"): return false
	_drones[int(drone.id)] = drone.duplicate(true)
	_recompute()
	_touch_state()
	return true

func remove_drone(drone_id: int) -> bool:
	if not is_server or not _drones.has(drone_id): return false
	_drones.erase(drone_id)
	_remove_forbidden_edges_for(drone_id)
	_recompute()
	_touch_state()
	return true

func set_forbidden_edge(a: int, b: int, forbidden := true) -> bool:
	if not is_server or a == b or not _drones.has(a) or not _drones.has(b): return false
	_set_forbidden(a, b, forbidden)
	_recompute()
	_touch_state()
	return true

func set_formation_open(drone_id: int, open := true) -> bool:
	if not is_server or not _drones.has(drone_id): return false
	_drones[drone_id]["formation_open"] = open
	_recompute()
	_touch_state()
	return true

func edges() -> Array: return _edges.duplicate(true)
func subnets() -> Array: return _subnets.duplicate(true)
func active_drones() -> Array:
	var drones: Array = []
	var ids: Array = _drones.keys()
	ids.sort()
	for id in ids: drones.append(_drones[id].duplicate(true))
	return drones

func add_residual(subnet_id: String, residual_id: String, created_at_tick: int, lifetime_ticks := -1) -> bool:
	## Retransmitting an existing residual is idempotent and cannot extend its lifetime.
	if not is_server or subnet_id.is_empty() or residual_id.is_empty(): return false
	for residual in _residuals:
		if residual.subnet_id == subnet_id and residual.residual_id == residual_id: return true
	var lifetime := residual_lifetime_ticks if lifetime_ticks < 0 else lifetime_ticks
	_residuals.append({"subnet_id": subnet_id, "residual_id": residual_id, "expires_at_tick": created_at_tick + maxi(0, lifetime)})
	_touch_state()
	return true

func resolve_damage_tick(server_tick: int, targets: Array) -> Array:
	if not is_server: return []
	_prune_residuals(server_tick)
	var events: Array = []
	for target in targets:
		var target_id = target.get("network_id", target.get("id", ""))
		for source_value in target.get("subnet_ids", target.get("overlapping_subnet_ids", [])):
			var subnet_id := String(source_value)
			for residual_id in _source_residual_ids(subnet_id, server_tick):
				var identity := _event_identity(target_id, subnet_id, server_tick, residual_id)
				var identity_key := _identity_key(identity)
				if _seen_events.has(identity_key): continue
				_seen_events[identity_key] = identity.duplicate(true)
				var can_stun := bool(target.get("is_player", false)) and server_tick >= int(_immune_until.get(target_id, 0))
				var event := {
					"target_network_id": target_id, "server_tick": server_tick, "graph_revision": graph_revision,
					"subnet_id": subnet_id, "source_id": subnet_id, "source_identity": {"kind": "electric_subnet", "subnet_id": subnet_id},
					"event_identity": identity,
					"damage_amount": damage_per_tick, "damage": damage_per_tick, "damage_type": "electric", "damage_tags": ["electric", "subnet"],
					"stun_candidate": can_stun, "stun_duration": stun_duration if can_stun else 0.0
				}
				if can_stun:
					_stun_until[target_id] = server_tick + _seconds_to_ticks(stun_duration)
					_immune_until[target_id] = server_tick + _seconds_to_ticks(stun_immunity_duration)
				events.append(event)
	if not events.is_empty(): _touch_state()
	return events

func snapshot() -> Dictionary:
	var drones: Array = []
	for id in _drones.keys(): drones.append(_drones[id].duplicate(true))
	drones.sort_custom(func(a, b): return a.id < b.id)
	var forbidden_edges: Array = []
	for a in _forbidden.keys():
		for b in _forbidden[a].keys(): forbidden_edges.append({"a": a, "b": b})
	forbidden_edges.sort_custom(func(x, y): return x.a < y.a or (x.a == y.a and x.b < y.b))
	var seen_events: Array = []
	for identity in _seen_events.keys():
		seen_events.append(_seen_events[identity].duplicate(true))
	seen_events.sort_custom(func(x, y): return _identity_key(x) < _identity_key(y))
	var residuals := _residuals.duplicate(true)
	residuals.sort_custom(func(a, b): return var_to_str([a.subnet_id, a.residual_id]) < var_to_str([b.subnet_id, b.residual_id]))
	var state := {"graph_revision": graph_revision, "state_revision": state_revision, "drones": drones, "edges": edges(), "subnets": subnets(), "forbidden_edges": forbidden_edges, "formation_open_drone_ids": _open_drone_ids(), "residuals": residuals, "stun_until": _canonical_time_map(_stun_until), "immune_until": _canonical_time_map(_immune_until), "seen_events": seen_events}
	state["graph_signature"] = _topology_signature_for(drones, state.edges, state.subnets, forbidden_edges, state.formation_open_drone_ids)
	return state

func apply_snapshot(state: Dictionary) -> bool:
	# Network snapshots hydrate replicas only; the host remains the sole writer.
	if is_server: return false
	if not _valid_raw_snapshot(state): return false
	var canonical := _normalize_snapshot(state)
	if canonical.is_empty() or state != canonical or not _valid_snapshot(canonical): return false
	var revision := int(canonical.graph_revision)
	var cursor := int(canonical.state_revision)
	if cursor < state_revision: return false
	if revision < graph_revision: return false
	if cursor == state_revision: return snapshot() == canonical # Equal cursor is idempotent only.
	_drones.clear()
	for drone in canonical.drones: _drones[int(drone.id)] = drone.duplicate(true)
	_forbidden.clear()
	for edge in canonical.forbidden_edges: _set_forbidden(int(edge.a), int(edge.b), true)
	_edges = canonical.edges.duplicate(true)
	_subnets = canonical.subnets.duplicate(true)
	_residuals = canonical.residuals.duplicate(true)
	_stun_until = canonical.stun_until.duplicate(true)
	_immune_until = canonical.immune_until.duplicate(true)
	_seen_events.clear()
	for identity in canonical.seen_events: _seen_events[_identity_key(identity)] = identity.duplicate(true)
	graph_revision = revision
	state_revision = cursor
	_topology_signature = String(canonical.graph_signature)
	return true

func _valid_snapshot(state: Dictionary) -> bool:
	for key in ["graph_revision", "state_revision", "drones", "edges", "subnets", "forbidden_edges", "formation_open_drone_ids", "residuals", "stun_until", "immune_until", "seen_events", "graph_signature"]:
		if not state.has(key): return false
	for key in ["drones", "edges", "subnets", "forbidden_edges", "formation_open_drone_ids", "residuals", "seen_events"]:
		if not state[key] is Array: return false
	if not state.stun_until is Dictionary or not state.immune_until is Dictionary: return false
	if int(state.graph_revision) < 0 or int(state.state_revision) < 0: return false
	var residual_ids := {}
	var drone_ids := {}
	for drone in state.drones:
		if not drone is Dictionary or not drone.has("id") or drone_ids.has(int(drone.id)): return false
		drone_ids[int(drone.id)] = true
	var edge_keys := {}; var forbidden_keys := {}; var degree := {}
	for edge in state.edges:
		if not _valid_edge(edge, drone_ids): return false
		if bool(_snapshot_drone(state.drones, int(edge.a)).get("formation_open", false)) or bool(_snapshot_drone(state.drones, int(edge.b)).get("formation_open", false)): return false
		var edge_key := str(_edge_pair(int(edge.a), int(edge.b)))
		if edge_keys.has(edge_key): return false
		edge_keys[edge_key] = true
		degree[int(edge.a)] = int(degree.get(int(edge.a), 0)) + 1; degree[int(edge.b)] = int(degree.get(int(edge.b), 0)) + 1
		if degree[int(edge.a)] > 2 or degree[int(edge.b)] > 2: return false
	for edge in state.forbidden_edges:
		if not _valid_edge(edge, drone_ids): return false
		var forbidden_key := str(_edge_pair(int(edge.a), int(edge.b)))
		if forbidden_keys.has(forbidden_key) or edge_keys.has(forbidden_key): return false
		forbidden_keys[forbidden_key] = true
	var expected_open: Array = []
	for drone_id in drone_ids.keys():
		if bool(_snapshot_drone(state.drones, drone_id).get("formation_open", false)): expected_open.append(drone_id)
	expected_open.sort()
	var declared_open = state.formation_open_drone_ids.duplicate()
	declared_open.sort()
	if expected_open != declared_open: return false
	var calculated_subnets := _subnets_for(state.drones, state.edges)
	if calculated_subnets != state.subnets: return false
	if (not state.edges.is_empty() or not state.subnets.is_empty()) and int(state.graph_revision) == 0: return false
	if String(state.graph_signature) != _topology_signature_for(state.drones, state.edges, state.subnets, state.forbidden_edges, state.formation_open_drone_ids): return false
	for subnet in calculated_subnets:
		if subnet.closed:
			for drone_id in subnet.drone_ids:
				if bool(_snapshot_drone(state.drones, drone_id).get("formation_open", false)): return false
	for residual in state.residuals:
		if not residual is Dictionary or not residual.has("residual_id") or not residual.has("subnet_id") or not residual.has("expires_at_tick"): return false
		var residual_key := var_to_str([residual.subnet_id, residual.residual_id])
		if residual_ids.has(residual_key): return false
		residual_ids[residual_key] = true
	var seen_keys := {}
	for identity in state.seen_events:
		if not _valid_identity(identity): return false
		var identity_key := _identity_key(identity)
		if seen_keys.has(identity_key): return false
		seen_keys[identity_key] = true
	return true

func _valid_raw_snapshot(state: Dictionary) -> bool:
	if not state.has_all(["graph_revision", "state_revision", "drones", "edges", "subnets", "forbidden_edges", "formation_open_drone_ids", "residuals", "stun_until", "immune_until", "seen_events", "graph_signature"]): return false
	if not state.graph_revision is int or not state.state_revision is int or not state.graph_signature is String: return false
	for key in ["drones", "edges", "subnets", "forbidden_edges", "formation_open_drone_ids", "residuals", "seen_events"]:
		if not state[key] is Array: return false
	if not state.stun_until is Dictionary or not state.immune_until is Dictionary: return false
	for drone in state.drones:
		if not drone is Dictionary or not drone.has("id") or not drone.id is int: return false
	for edge in state.edges + state.forbidden_edges:
		if not edge is Dictionary or not edge.has_all(["a", "b"]) or not edge.a is int or not edge.b is int: return false
	for drone_id in state.formation_open_drone_ids:
		if not drone_id is int: return false
	for subnet in state.subnets:
		if not subnet is Dictionary or not subnet.has_all(["subnet_id", "source_id", "drone_ids", "edges", "closed"]) or not subnet.subnet_id is String or not subnet.source_id is String or not subnet.drone_ids is Array or not subnet.edges is Array or not subnet.closed is bool: return false
		for drone_id in subnet.drone_ids:
			if not drone_id is int: return false
		for edge in subnet.edges:
			if not edge is Dictionary or not edge.has_all(["a", "b"]) or not edge.a is int or not edge.b is int: return false
	for residual in state.residuals:
		if not residual is Dictionary or not residual.has_all(["subnet_id", "residual_id", "expires_at_tick"]) or not residual.subnet_id is String or not residual.residual_id is String or not residual.expires_at_tick is int: return false
	for identity in state.seen_events:
		if not identity is Dictionary or not identity.has_all(["target_network_id", "source_identity", "subnet_id", "server_tick", "graph_revision", "residual_id"]) or not identity.source_identity is Dictionary or not identity.subnet_id is String or not identity.server_tick is int or not identity.graph_revision is int or not identity.residual_id is String: return false
		if not identity.source_identity.has_all(["kind", "subnet_id"]) or not identity.source_identity.kind is String or not identity.source_identity.subnet_id is String: return false
	for time_map in [state.stun_until, state.immune_until]:
		for key in time_map.keys():
			if not (key is String or key is int) or not time_map[key] is int: return false
	return true

func _snapshot_drone(drones: Array, drone_id: int) -> Dictionary:
	for drone in drones:
		if int(drone.id) == drone_id: return drone
	return {}

func _recompute() -> void:
	# Greedy deterministic selection is a local perimeter approximation, not a global optimum.
	var candidates: Array = []
	var ids: Array = _drones.keys(); ids.sort()
	for left_index in range(ids.size()):
		for right_index in range(left_index + 1, ids.size()):
			var a: int = ids[left_index]; var b: int = ids[right_index]
			# A drone in transit is never an electrical endpoint.
			if bool(_drones[a].get("formation_open", false)) or bool(_drones[b].get("formation_open", false)): continue
			if _is_forbidden(a, b): continue
			var distance := _drones[a].get("position", Vector2.ZERO).distance_to(_drones[b].get("position", Vector2.ZERO))
			var was_active := _has_edge(a, b)
			# Hysteresis is applied before degree/cycle selection: retained links use
			# break_distance, while newly proposed links use connect_distance.
			if (was_active and distance <= break_distance) or (not was_active and distance <= connect_distance):
				candidates.append({"a": a, "b": b, "distance": distance})
	candidates.sort_custom(func(x, y): return x.distance < y.distance if not is_equal_approx(x.distance, y.distance) else (x.a < y.a or (x.a == y.a and x.b < y.b)))
	var selected: Array = []; var degree := {}
	for candidate in candidates:
		if int(degree.get(candidate.a, 0)) >= 2 or int(degree.get(candidate.b, 0)) >= 2: continue
		if _connected(candidate.a, candidate.b, selected) and _component_has_open(candidate.a, selected): continue
		selected.append({"a": candidate.a, "b": candidate.b})
		degree[candidate.a] = int(degree.get(candidate.a, 0)) + 1
		degree[candidate.b] = int(degree.get(candidate.b, 0)) + 1
	var next_subnets := _subnets_for(active_drones(), selected)
	var signature := _topology_signature_for(active_drones(), selected, next_subnets, _forbidden_edges(), _open_drone_ids())
	if signature != _topology_signature:
		_edges = selected; graph_revision += 1; _subnets = next_subnets; _topology_signature = signature

func _make_subnets() -> Array:
	return _subnets_for(active_drones(), _edges)

func _subnets_for(drones: Array, graph_edges: Array) -> Array:
	var adjacency := {}; for drone in drones: adjacency[int(drone.id)] = []
	for edge in graph_edges: adjacency[int(edge.a)].append(int(edge.b)); adjacency[int(edge.b)].append(int(edge.a))
	var seen := {}; var result: Array = []
	for start in adjacency.keys():
		if seen.has(start): continue
		var stack := [start]; var nodes: Array = []; seen[start] = true
		while not stack.is_empty():
			var node = stack.pop_back(); nodes.append(node)
			for next in adjacency[node]:
				if not seen.has(next): seen[next] = true; stack.append(next)
		nodes.sort()
		if nodes.size() > 1:
			var internal_edges: Array = []
			for edge in graph_edges:
				if nodes.has(edge.a) and nodes.has(edge.b): internal_edges.append(edge.duplicate(true))
			var source_id := "subnet:" + _ids_key(nodes)
			result.append({"subnet_id": source_id, "source_id": source_id, "drone_ids": nodes, "edges": internal_edges, "closed": internal_edges.size() == nodes.size()})
	result.sort_custom(func(a, b): return a.subnet_id < b.subnet_id)
	return result

func _source_residual_ids(subnet_id: String, server_tick: int) -> Array:
	var source_ids: Array = []
	for subnet in _subnets:
		if subnet.subnet_id == subnet_id:
			source_ids.append("")
			break
	for residual in _residuals:
		if residual.subnet_id == subnet_id and server_tick <= int(residual.expires_at_tick): source_ids.append(String(residual.residual_id))
	source_ids.sort()
	return source_ids
func _prune_residuals(server_tick: int) -> void:
	var previous_count := _residuals.size()
	_residuals = _residuals.filter(func(item): return server_tick <= int(item.expires_at_tick))
	if _residuals.size() != previous_count: _touch_state()
func _event_identity(target_id, subnet_id: String, server_tick: int, residual_id := "") -> Dictionary:
	return {"target_network_id": target_id, "source_identity": {"kind": "electric_subnet", "subnet_id": subnet_id}, "subnet_id": subnet_id, "server_tick": server_tick, "graph_revision": graph_revision, "residual_id": residual_id}
func _identity_key(identity: Dictionary) -> String:
	return var_to_str([identity.target_network_id, identity.source_identity, identity.subnet_id, identity.server_tick, identity.graph_revision, identity.residual_id])
func _valid_identity(identity) -> bool:
	return identity is Dictionary and identity.has_all(["target_network_id", "source_identity", "subnet_id", "server_tick", "graph_revision", "residual_id"]) and identity.source_identity is Dictionary and identity.source_identity == {"kind": "electric_subnet", "subnet_id": identity.subnet_id}
func _valid_edge(edge, drone_ids: Dictionary) -> bool:
	return edge is Dictionary and edge.has("a") and edge.has("b") and int(edge.a) != int(edge.b) and drone_ids.has(int(edge.a)) and drone_ids.has(int(edge.b))
func _touch_state() -> void: state_revision += 1
func _edge_pair(a: int, b: int) -> Array: return [mini(a, b), maxi(a, b)]
func _is_forbidden(a: int, b: int) -> bool:
	var pair := _edge_pair(a, b); return _forbidden.has(pair[0]) and _forbidden[pair[0]].has(pair[1])
func _set_forbidden(a: int, b: int, forbidden: bool) -> void:
	var pair := _edge_pair(a, b)
	if forbidden:
		if not _forbidden.has(pair[0]): _forbidden[pair[0]] = {}
		_forbidden[pair[0]][pair[1]] = true
	elif _forbidden.has(pair[0]):
		_forbidden[pair[0]].erase(pair[1])
		if _forbidden[pair[0]].is_empty(): _forbidden.erase(pair[0])
func _remove_forbidden_edges_for(drone_id: int) -> void:
	_forbidden.erase(drone_id)
	for a in _forbidden.keys():
		_forbidden[a].erase(drone_id)
		if _forbidden[a].is_empty(): _forbidden.erase(a)
func _seconds_to_ticks(seconds: float) -> int: return maxi(1, ceili(seconds / maxf(tick_seconds, 0.001)))
func _ids_key(ids: Array) -> String:
	var parts := PackedStringArray()
	for id in ids:
		parts.append(str(id))
	return ":".join(parts)
func _open_drone_ids() -> Array:
	var ids: Array = []; for id in _drones.keys(): if bool(_drones[id].get("formation_open", false)): ids.append(id)
	ids.sort(); return ids
func _connected(start: int, goal: int, selected: Array) -> bool:
	var adjacency := {}
	for edge in selected:
		if not adjacency.has(edge.a): adjacency[edge.a] = []
		if not adjacency.has(edge.b): adjacency[edge.b] = []
		adjacency[edge.a].append(edge.b); adjacency[edge.b].append(edge.a)
	var stack := [start]; var seen := {}
	while not stack.is_empty():
		var node = stack.pop_back()
		if node == goal: return true
		if seen.has(node): continue
		seen[node] = true
		for next in adjacency.get(node, []): stack.append(next)
	return false
func _has_edge(a: int, b: int) -> bool:
	var pair := _edge_pair(a, b)
	for edge in _edges:
		if int(edge.a) == pair[0] and int(edge.b) == pair[1]: return true
	return false
func _component_has_open(start: int, selected: Array) -> bool:
	var stack := [start]; var seen := {}
	while not stack.is_empty():
		var node = stack.pop_back()
		if seen.has(node): continue
		seen[node] = true
		if bool(_drones[node].get("formation_open", false)): return true
		for edge in selected:
			if edge.a == node: stack.append(edge.b)
			elif edge.b == node: stack.append(edge.a)
	return false
func _forbidden_edges() -> Array:
	var result: Array = []
	for a in _forbidden.keys():
		for b in _forbidden[a].keys(): result.append({"a": a, "b": b})
	result.sort_custom(func(x, y): return x.a < y.a or (x.a == y.a and x.b < y.b))
	return result

func _topology_signature_for(drones: Array, graph_edges: Array, graph_subnets: Array, forbidden_edges: Array, open_ids: Array) -> String:
	var drone_ids: Array = []
	for drone in drones: drone_ids.append(int(drone.id))
	drone_ids.sort()
	var edge_pairs: Array = []
	for edge in graph_edges: edge_pairs.append(_edge_pair(int(edge.a), int(edge.b)))
	edge_pairs.sort_custom(func(a, b): return int(a[0]) < int(b[0]) or (int(a[0]) == int(b[0]) and int(a[1]) < int(b[1])))
	var forbidden_pairs: Array = []
	for edge in forbidden_edges: forbidden_pairs.append(_edge_pair(int(edge.a), int(edge.b)))
	forbidden_pairs.sort_custom(func(a, b): return int(a[0]) < int(b[0]) or (int(a[0]) == int(b[0]) and int(a[1]) < int(b[1])))
	var subnet_parts: Array = []
	for subnet in graph_subnets:
		var subnet_edges: Array = []
		for edge in subnet.edges: subnet_edges.append(_edge_pair(int(edge.a), int(edge.b)))
		subnet_edges.sort_custom(func(a, b): return int(a[0]) < int(b[0]) or (int(a[0]) == int(b[0]) and int(a[1]) < int(b[1])))
		var subnet_ids: Array = subnet.drone_ids.duplicate(); subnet_ids.sort()
		subnet_parts.append([String(subnet.subnet_id), subnet_ids, subnet_edges, bool(subnet.closed)])
	subnet_parts.sort_custom(func(a, b): return a[0] < b[0])
	var normalized_open := open_ids.duplicate(); normalized_open.sort()
	return var_to_str([drone_ids, edge_pairs, subnet_parts, forbidden_pairs, normalized_open])

func _normalize_snapshot(state: Dictionary) -> Dictionary:
	for key in ["graph_revision", "state_revision", "drones", "edges", "subnets", "forbidden_edges", "formation_open_drone_ids", "residuals", "stun_until", "immune_until", "seen_events", "graph_signature"]:
		if not state.has(key): return {}
	if not state.drones is Array or not state.edges is Array or not state.forbidden_edges is Array or not state.residuals is Array or not state.seen_events is Array: return {}
	var normalized := state.duplicate(true)
	var ids := {}
	for drone in normalized.drones:
		if not drone is Dictionary or not drone.has("id"): return normalized
		ids[int(drone.id)] = true
	for edge in normalized.edges + normalized.forbidden_edges:
		if not _valid_edge(edge, ids): return normalized
	normalized.drones.sort_custom(func(a, b): return int(a.id) < int(b.id))
	for edge in normalized.edges:
		if edge is Dictionary and edge.has_all(["a", "b"]):
			var low := mini(int(edge.a), int(edge.b)); var high := maxi(int(edge.a), int(edge.b)); edge.a = low; edge.b = high
	for edge in normalized.forbidden_edges:
		if edge is Dictionary and edge.has_all(["a", "b"]):
			var low := mini(int(edge.a), int(edge.b)); var high := maxi(int(edge.a), int(edge.b)); edge.a = low; edge.b = high
	normalized.edges.sort_custom(func(a, b): return int(a.a) < int(b.a) or (int(a.a) == int(b.a) and int(a.b) < int(b.b)))
	normalized.forbidden_edges.sort_custom(func(a, b): return int(a.a) < int(b.a) or (int(a.a) == int(b.a) and int(a.b) < int(b.b)))
	normalized.formation_open_drone_ids.sort()
	normalized.subnets = _subnets_for(normalized.drones, normalized.edges)
	normalized.residuals.sort_custom(func(a, b): return var_to_str([a.subnet_id, a.residual_id]) < var_to_str([b.subnet_id, b.residual_id]))
	normalized.seen_events.sort_custom(func(a, b): return _identity_key(a) < _identity_key(b))
	normalized.stun_until = _canonical_time_map(normalized.stun_until)
	normalized.immune_until = _canonical_time_map(normalized.immune_until)
	normalized.graph_signature = _topology_signature_for(normalized.drones, normalized.edges, normalized.subnets, normalized.forbidden_edges, normalized.formation_open_drone_ids)
	return normalized

func _canonical_time_map(time_map: Dictionary) -> Dictionary:
	var keys: Array = time_map.keys()
	keys.sort_custom(func(a, b): return var_to_str(a) < var_to_str(b))
	var canonical := {}
	for key in keys: canonical[key] = time_map[key]
	return canonical
