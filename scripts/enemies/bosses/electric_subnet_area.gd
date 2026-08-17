## Invisible collision representation of a single electric subnet.
## It intentionally has no rendering responsibility and only remembers target IDs.
class_name ElectricSubnetArea
extends Area2D

signal target_seen(target_id: String, body: Node2D)
signal target_left(target_id: String)

const DEFAULT_AURA_RADIUS := 18.0

@export var aura_radius := DEFAULT_AURA_RADIUS

var subnet_id := ""
var network_id_resolver: Callable
var _shapes: Dictionary = {}
var _target_ids: Dictionary = {}

func _ready() -> void:
	collision_layer = 0
	collision_mask = 6 # Player (2) and enemy (4) layers from the gameplay scenes.
	monitoring = true
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func sync_edges(edges: Array, drone_positions: Dictionary) -> void:
	var radius := _resolved_aura_radius()
	var wanted: Dictionary = {}
	for edge in edges:
		if not edge is Dictionary:
			continue
		var a := int(edge.get("a", -1))
		var b := int(edge.get("b", -1))
		if not drone_positions.has(a) or not drone_positions.has(b):
			continue
		var start_world: Variant = drone_positions[a]
		var end_world: Variant = drone_positions[b]
		if not start_world is Vector2 or not end_world is Vector2:
			continue
		if not _is_finite_vector(start_world) or not _is_finite_vector(end_world):
			continue
		var key := _edge_key(a, b)
		# The Area is a child of the controller, so these remain world-correct if it moves.
		var start: Vector2 = to_local(start_world)
		var end: Vector2 = to_local(end_world)
		var link := end - start
		var height := link.length() + radius * 2.0
		if not is_finite(height) or height <= 0.0:
			continue
		wanted[key] = true
		var collision := _shapes.get(key) as CollisionShape2D
		if collision == null:
			collision = CollisionShape2D.new()
			collision.shape = CapsuleShape2D.new()
			add_child(collision)
			_shapes[key] = collision
		var capsule := collision.shape as CapsuleShape2D
		if capsule == null:
			capsule = CapsuleShape2D.new()
			collision.shape = capsule
		capsule.radius = radius
		# CapsuleShape2D's height includes its round end caps.
		capsule.height = height
		collision.position = start.lerp(end, 0.5)
		# Capsules are vertical by default, so rotate their long axis onto the link.
		collision.rotation = link.angle() + PI * 0.5
	for key in _shapes.keys():
		if not wanted.has(key):
			var stale := _shapes[key] as CollisionShape2D
			_shapes.erase(key)
			if is_instance_valid(stale):
				stale.queue_free()

func target_ids() -> Array[String]:
	var ids: Array[String] = []
	for target_id in _target_ids.keys():
		ids.append(String(target_id))
	ids.sort()
	return ids

func _on_body_entered(body: Node2D) -> void:
	if not _is_damageable_target(body):
		return
	var target_id := _target_id(body)
	_target_ids[target_id] = true
	target_seen.emit(target_id, body)

func _on_body_exited(body: Node2D) -> void:
	if not is_instance_valid(body):
		return
	var target_id := _target_id(body)
	if not _target_ids.has(target_id):
		return
	_target_ids.erase(target_id)
	target_left.emit(target_id)

func _is_damageable_target(body: Node2D) -> bool:
	if not is_instance_valid(body) or body.is_queued_for_deletion():
		return false
	if not body.is_in_group(&"player") and not body.is_in_group(&"enemies"):
		return false
	var property: Variant = body.get("health")
	return property is HealthComponent or body.get_node_or_null("HealthComponent") is HealthComponent

func _target_id(body: Node2D) -> String:
	if network_id_resolver.is_valid():
		var resolved: Variant = network_id_resolver.call(body)
		if resolved != null and not String(resolved).is_empty():
			return String(resolved)
	if body.has_meta(&"network_id"):
		return String(body.get_meta(&"network_id"))
	if body.has_method(&"get_network_id"):
		return String(body.call(&"get_network_id"))
	return str(body.get_instance_id())

func _edge_key(a: int, b: int) -> String:
	return "%d:%d" % [min(a, b), max(a, b)]

func _resolved_aura_radius() -> float:
	if is_finite(aura_radius) and aura_radius > 0.0:
		return aura_radius
	return DEFAULT_AURA_RADIUS

func _is_finite_vector(value: Vector2) -> bool:
	return is_finite(value.x) and is_finite(value.y)
