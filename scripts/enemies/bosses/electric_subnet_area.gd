## Invisible collision representation of a single electric subnet.
## It intentionally has no rendering responsibility and only remembers target IDs.
class_name ElectricSubnetArea
extends Area2D

signal target_seen(target_id: String, body: Node2D)
signal target_left(target_id: String)

var subnet_id := ""
var network_id_resolver: Callable
var _shapes: Dictionary = {}
var _target_ids: Dictionary = {}

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2 # Player layer from the gameplay scenes.
	monitoring = true
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func sync_edges(edges: Array, drone_positions: Dictionary) -> void:
	var wanted: Dictionary = {}
	for edge in edges:
		if not edge is Dictionary:
			continue
		var a := int(edge.get("a", -1))
		var b := int(edge.get("b", -1))
		if not drone_positions.has(a) or not drone_positions.has(b):
			continue
		var key := _edge_key(a, b)
		wanted[key] = true
		var collision := _shapes.get(key) as CollisionShape2D
		if collision == null:
			collision = CollisionShape2D.new()
			collision.shape = SegmentShape2D.new()
			add_child(collision)
			_shapes[key] = collision
		var segment := collision.shape as SegmentShape2D
		# The Area is a child of the controller, so these remain world-correct if it moves.
		segment.a = to_local(drone_positions[a])
		segment.b = to_local(drone_positions[b])
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
	if not is_instance_valid(body) or body.is_queued_for_deletion() or not body.is_in_group(&"player"):
		return
	var target_id := _target_id(body)
	_target_ids[target_id] = true
	target_seen.emit(target_id, body)

func _on_body_exited(body: Node2D) -> void:
	if not is_instance_valid(body):
		return
	var target_id := _target_id(body)
	_target_ids.erase(target_id)
	target_left.emit(target_id)

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
