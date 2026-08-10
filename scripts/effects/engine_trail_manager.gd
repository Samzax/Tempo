class_name EngineTrailManager
extends Node2D
## Rastro continuo do propulsor. Um unico CanvasItem mantem os segmentos e o dano.

var segments: Array[Dictionary] = []
var target_next_damage: Dictionary = {}

var _source: Node = null
var _damage := 0.0
var _width := 0.0
var _duration := 0.8
var _damage_cooldown := 0.5
var _spacing := 32.0
var _color := Color.WHITE
var _elapsed := 0.0
var _has_last_anchors := false
var _last_left := Vector2.ZERO
var _last_right := Vector2.ZERO

func configure(source: Node, damage: float, width: float, duration: float, damage_cooldown: float, spacing: float, thrust_color: Color) -> void:
	_source = source
	_damage = damage
	_width = width
	_duration = duration
	_damage_cooldown = damage_cooldown
	_spacing = spacing
	_color = thrust_color

## Recebe as duas ancoras traseiras em coordenadas globais. A emissao e limitada por distancia.
func emit_from_anchors(left: Vector2, right: Vector2) -> void:
	if not _has_last_anchors:
		_last_left = left
		_last_right = right
		_has_last_anchors = true
		return
	var previous_center := (_last_left + _last_right) * 0.5
	var current_center := (left + right) * 0.5
	if previous_center.distance_to(current_center) < _spacing:
		return
	segments.append({"origin": _last_left, "end": left, "age": 0.0})
	segments.append({"origin": _last_right, "end": right, "age": 0.0})
	_last_left = left
	_last_right = right
	queue_redraw()

## Interrompe apenas a emissao; os segmentos existentes continuam seu fade normal.
func stop_emission() -> void:
	_has_last_anchors = false

func clear_segments() -> void:
	segments.clear()
	target_next_damage.clear()
	_has_last_anchors = false
	queue_redraw()

func active_segment_count() -> int:
	return segments.size()

func _physics_process(delta: float) -> void:
	_elapsed += delta
	_age_segments(delta)
	_prune_target_cooldowns()
	_resolve_damage()
	queue_redraw()

func _age_segments(delta: float) -> void:
	for index in range(segments.size() - 1, -1, -1):
		var segment: Dictionary = segments[index]
		segment["age"] = float(segment["age"]) + delta
		if float(segment["age"]) >= _duration:
			segments.remove_at(index)

func _prune_target_cooldowns() -> void:
	for target_id in target_next_damage.keys():
		var target := instance_from_id(int(target_id))
		if _elapsed >= float(target_next_damage[target_id]) or not is_instance_valid(target):
			target_next_damage.erase(target_id)

func _resolve_damage() -> void:
	if _damage <= 0.0 or _width <= 0.0 or segments.is_empty() or not is_instance_valid(_source):
		return
	var radius := _width * 0.5
	for node in get_tree().get_nodes_in_group(&"enemies"):
		if not is_instance_valid(node) or node.is_queued_for_deletion() or not node.has_method(&"take_damage"):
			continue
		var target := node as Node2D
		if target == null:
			continue
		var target_id := target.get_instance_id()
		if target_next_damage.has(target_id) and _elapsed < float(target_next_damage[target_id]):
			continue
		if not _touches_any_segment(target.global_position, radius):
			continue
		var info := DamageInfo.new()
		info.amount = _damage
		info.source = _source
		info.position = target.global_position
		info.tags = [&"engine_trail", &"interestelar_engine_trail"]
		target.take_damage(info)
		target_next_damage[target_id] = _elapsed + _damage_cooldown

func _touches_any_segment(position: Vector2, radius: float) -> bool:
	for segment in segments:
		var origin: Vector2 = segment["origin"]
		var ending: Vector2 = segment["end"]
		var direction := ending - origin
		var length_squared := direction.length_squared()
		var closest := origin
		if length_squared > 0.001:
			var projection := clampf((position - origin).dot(direction) / length_squared, 0.0, 1.0)
			closest = origin + direction * projection
		if position.distance_to(closest) <= radius:
			return true
	return false

func _draw() -> void:
	if _duration <= 0.0 or _width <= 0.0:
		return
	for segment in segments:
		var alpha := 1.0 - clampf(float(segment["age"]) / _duration, 0.0, 1.0)
		var draw_color := _color
		draw_color.a *= alpha
		var origin: Vector2 = segment["origin"]
		var ending: Vector2 = segment["end"]
		draw_line(to_local(origin), to_local(ending), draw_color, _width * 0.5, true)
