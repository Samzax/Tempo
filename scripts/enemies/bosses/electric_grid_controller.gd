## Host-only adapter between the pure electric graph and Godot collision/damage nodes.
class_name ElectricGridController
extends Node2D

const SUBNET_AREA := preload("res://scripts/enemies/bosses/electric_subnet_area.gd")

@export_range(0.001, 10.0, 0.001) var tick_seconds := 0.1
## Safety ceiling for catch-up work in one physics frame; skipped whole ticks are discarded.
@export_range(1, 256, 1) var max_ticks_per_frame := 8

var is_host := true
var drone_manager: DroneManager
var electric_subnet: ElectricSubnet
var target_id_resolver: Callable
var _tick_accumulator := 0.0
var _server_tick := 0
var _areas: Dictionary = {}
var _targets: Dictionary = {} # ID -> WeakRef; never retained by the RefCounted core.
var _registered_drones: Dictionary = {}

func _init(host_authority: bool = true) -> void:
	is_host = host_authority
	drone_manager = DroneManager.new(host_authority)
	electric_subnet = ElectricSubnet.new(host_authority)

func _ready() -> void:
	set_physics_process(is_host)

func spawn_drone(position := Vector2.ZERO, formation_open := false) -> Dictionary:
	if not is_host:
		return {}
	var drone := drone_manager.spawn_drone(position, formation_open)
	if not drone.is_empty():
		_sync_graph_from_manager()
	return drone

func destroy_drone(drone_id: int) -> bool:
	if not is_host or not drone_manager.destroy_drone(drone_id):
		return false
	_sync_graph_from_manager()
	return true

## Positions are keyed by the IDs issued by DroneManager. Unknown IDs are ignored.
func update_drone_positions(active_drones: Dictionary) -> bool:
	if not is_host:
		return false
	var changed := false
	for drone in drone_manager.active_drones():
		var drone_id := int(drone.id)
		if not active_drones.has(drone_id):
			continue
		var update: Variant = active_drones[drone_id]
		if not update is Dictionary or not update.get("position", null) is Vector2:
			continue
		var formation_open := bool(update.get("formation_open", drone.formation_open))
		if drone.position != update.position or bool(drone.formation_open) != formation_open:
			drone_manager.update_drone(drone_id, update.position, formation_open)
			changed = true
	if changed:
		_sync_graph_from_manager()
	return changed

func configure_drones(active_drones: Dictionary) -> bool:
	if not is_host:
		return false
	if not _valid_drone_configuration(active_drones):
		return false
	# Initial configuration may be supplied before the host has emitted its IDs.
	# Only the next sequential ID issued by DroneManager is accepted; callers cannot
	# manufacture an ID or overwrite a tombstone.
	var configured := false
	var ids: Array = active_drones.keys()
	ids.sort()
	for raw_id in ids:
		var drone_id := int(raw_id)
		if drone_manager.active_drones().any(func(drone): return int(drone.id) == drone_id):
			continue
		var record: Variant = active_drones[raw_id]
		if not record is Dictionary or not record.get("position", null) is Vector2:
			continue
		var issued := drone_manager.spawn_drone(record.position, bool(record.get("formation_open", false)))
		if issued.is_empty() or int(issued.id) != drone_id:
			if not issued.is_empty():
				drone_manager.destroy_drone(int(issued.id))
			continue
		configured = true
	var updated := update_drone_positions(active_drones)
	if configured and not updated:
		_sync_graph_from_manager()
	return configured or updated

## Validate the entire payload before DroneManager receives any mutation.
func _valid_drone_configuration(active_drones: Dictionary) -> bool:
	var existing: Dictionary = {}
	for drone in drone_manager.active_drones():
		existing[int(drone.id)] = true
	var snapshot := drone_manager.snapshot()
	var next_expected_id := int(snapshot.next_id)
	var new_drone_count := 0
	var ids: Array = active_drones.keys()
	for raw_id in ids:
		if not raw_id is int:
			return false
	ids.sort()
	for raw_id in ids:
		var drone_id: int = raw_id
		if drone_id < 1:
			return false
		var record: Variant = active_drones[raw_id]
		if not record is Dictionary or not record.has("position") or not record.position is Vector2:
			return false
		var position: Vector2 = record.position
		if not is_finite(position.x) or not is_finite(position.y):
			return false
		if record.has("formation_open") and not record.formation_open is bool:
			return false
		if existing.has(drone_id):
			continue
		# An unknown ID must be the next unissued ID. This also rejects tombstones.
		if drone_id != next_expected_id:
			return false
		next_expected_id += 1
		new_drone_count += 1
	return drone_manager.active_drones().size() + new_drone_count <= DroneManager.MAX_DRONES

func _physics_process(delta: float) -> void:
	if not is_host:
		return
	electric_subnet.tick_seconds = tick_seconds
	_sync_graph_from_manager()
	if tick_seconds <= 0.0 or not is_finite(tick_seconds):
		return
	if delta <= 0.0 or not is_finite(delta):
		return
	_tick_accumulator += delta
	var tick_cap: int = maxi(1, max_ticks_per_frame)
	var processed_ticks := 0
	while processed_ticks < tick_cap and _tick_accumulator + 0.0000001 >= tick_seconds:
		# The tolerance may admit a value just below one tick; never retain a negative remainder.
		_tick_accumulator = maxf(0.0, _tick_accumulator - tick_seconds)
		_server_tick += 1
		_resolve_damage_tick()
		processed_ticks += 1
	if _tick_accumulator + 0.0000001 >= tick_seconds:
		# Deliberately discard skipped whole ticks: retain only a bounded phase remainder.
		_tick_accumulator = fposmod(_tick_accumulator, tick_seconds)
		if _tick_accumulator + 0.0000001 >= tick_seconds:
			_tick_accumulator = 0.0

func _sync_graph_from_manager() -> void:
	if not is_host:
		return
	var active: Dictionary = {}
	var positions: Dictionary = {}
	for drone in drone_manager.active_drones():
		var drone_id := int(drone.id)
		active[drone_id] = drone
		positions[drone_id] = drone.position
		if not _registered_drones.has(drone_id) or _registered_drones[drone_id] != drone:
			electric_subnet.register_drone(drone)
			_registered_drones[drone_id] = drone.duplicate(true)
	for drone_id in _registered_drones.keys():
		if not active.has(drone_id):
			electric_subnet.remove_drone(int(drone_id))
			_registered_drones.erase(drone_id)
	_sync_areas(electric_subnet.subnets(), positions)

func _sync_areas(subnets: Array, positions: Dictionary) -> void:
	var alive: Dictionary = {}
	for subnet in subnets:
		var subnet_id := String(subnet.subnet_id)
		alive[subnet_id] = true
		var area := _areas.get(subnet_id) as ElectricSubnetArea
		if area == null:
			area = SUBNET_AREA.new() as ElectricSubnetArea
			area.name = "ElectricSubnetArea_%s" % subnet_id.replace(":", "_")
			area.subnet_id = subnet_id
			area.network_id_resolver = target_id_resolver
			area.target_seen.connect(_on_area_target_seen)
			area.target_left.connect(_on_area_target_left)
			add_child(area)
			_areas[subnet_id] = area
		area.sync_edges(subnet.edges, positions)
	for subnet_id in _areas.keys():
		if not alive.has(subnet_id):
			var stale := _areas[subnet_id] as ElectricSubnetArea
			_areas.erase(subnet_id)
			if is_instance_valid(stale):
				_disconnect_area_signals(stale)
				stale.queue_free()
			_forget_targets_without_active_area()

func _on_area_target_seen(target_id: String, body: Node2D) -> void:
	if is_instance_valid(body) and not body.is_queued_for_deletion():
		_targets[target_id] = weakref(body)

func _on_area_target_left(target_id: String) -> void:
	# A target can be inside multiple subnet areas. Remove its cached node only
	# after the area which emitted this signal has removed the ID and no active
	# sibling still reports it.
	if not _target_is_in_active_area(target_id):
		_targets.erase(target_id)

func _target_is_in_active_area(target_id: String) -> bool:
	for area_value in _areas.values():
		var area := area_value as ElectricSubnetArea
		if area != null and target_id in area.target_ids():
			return true
	return false

func _forget_targets_without_active_area() -> void:
	for target_id in _targets.keys():
		if not _target_is_in_active_area(String(target_id)):
			_targets.erase(target_id)

func _disconnect_area_signals(area: ElectricSubnetArea) -> void:
	if area.target_seen.is_connected(_on_area_target_seen):
		area.target_seen.disconnect(_on_area_target_seen)
	if area.target_left.is_connected(_on_area_target_left):
		area.target_left.disconnect(_on_area_target_left)

func _resolve_damage_tick() -> void:
	var targets_by_id: Dictionary = {}
	for subnet_id in _areas.keys():
		var area := _areas[subnet_id] as ElectricSubnetArea
		if area == null:
			continue
		for target_id in area.target_ids():
			if not targets_by_id.has(target_id):
				targets_by_id[target_id] = {"network_id": target_id, "is_player": true, "subnet_ids": []}
			targets_by_id[target_id].subnet_ids.append(subnet_id)
	var targets: Array = targets_by_id.values()
	for event in electric_subnet.resolve_damage_tick(_server_tick, targets):
		_apply_event(event)

func _apply_event(event: Dictionary) -> void:
	var target_id := String(event.get("target_network_id", ""))
	var reference := _targets.get(target_id) as WeakRef
	var target: Node = reference.get_ref() as Node if reference != null else null
	if target == null or not is_instance_valid(target) or target.is_queued_for_deletion():
		_targets.erase(target_id)
		return
	var health := _health_component(target)
	if health == null:
		return
	var info := DamageInfo.new()
	info.amount = roundi(float(event.get("damage_amount", event.get("damage", 0.0))))
	info.source = self
	info.tags = [&"electric", &"subnet"]
	info.position = global_position
	health.apply_damage(info)
	if bool(event.get("stun_candidate", false)) and target.is_in_group(&"player") and target.has_method(&"apply_stun"):
		target.call(&"apply_stun", float(event.get("stun_duration", 0.0)))

func _health_component(target: Node) -> HealthComponent:
	var property: Variant = target.get("health")
	if property is HealthComponent:
		return property
	var child := target.get_node_or_null("HealthComponent")
	return child as HealthComponent
