class_name EngineTrailManager
extends Node2D
## Um unico CanvasItem guarda a geometria logica e desenha a decoracao do rastro.

const HEALTH_UNITS := preload("res://scripts/components/health_units.gd")

const MAX_SAMPLES_PER_STRAND := 22
const MAX_LOGICAL_SEGMENTS := MAX_SAMPLES_PER_STRAND * 2

var segments: Array[Dictionary] = []
var target_next_damage: Dictionary = {}

var _source: Node = null
var _damage: int = 0
var _width := 0.0
var _duration := 0.8
var _damage_cooldown := 0.5
var _spacing := 7.0
var _color := Color.WHITE
var _elapsed := 0.0
var _has_last_anchors := false
var _last_left := Vector2.ZERO
var _last_right := Vector2.ZERO
var _movement_state := &"CRUISE"
var _ignition_pending := false

func configure(source: Node, damage: float, width: float, duration: float, damage_cooldown: float, spacing: float, thrust_color: Color) -> void:
	_source = source
	_damage = HEALTH_UNITS.from_hp(damage)
	_width = width
	_duration = duration
	_damage_cooldown = damage_cooldown
	_spacing = spacing
	_color = thrust_color

## Mantem compatibilidade com chamadas antigas; o estado afeta somente a leitura visual.
func emit_from_anchors(left: Vector2, right: Vector2, movement_state: StringName = &"CRUISE") -> void:
	_movement_state = movement_state
	if not _has_last_anchors:
		_last_left = left
		_last_right = right
		_has_last_anchors = true
		# A primeira chamada apenas fixa as ancoras; guarda a ignicao para o primeiro trecho real.
		_ignition_pending = movement_state == &"IGNITION"
		return
	# Cada ancora percorre seu proprio curso. _last_* e o cursor do ultimo
	# segmento emitido, portanto tambem conserva o resto de cada trilha.
	var left_samples := _sample_strand(_last_left, left)
	var right_samples := _sample_strand(_last_right, right)
	if not left_samples.is_empty():
		var last_left_sample: Dictionary = left_samples.back()
		_last_left = last_left_sample["end"] as Vector2
	if not right_samples.is_empty():
		var last_right_sample: Dictionary = right_samples.back()
		_last_right = last_right_sample["end"] as Vector2
	var has_real_pair := not left_samples.is_empty() and not right_samples.is_empty()
	var sample_count := maxi(left_samples.size(), right_samples.size())
	for sample_index in sample_count:
		# A ordem continua esquerda/direita em cada indice compartilhado.
		# IGNITION pertence somente ao primeiro par que de fato existe.
		var sample_state := &"IGNITION" if _ignition_pending and has_real_pair and sample_index == 0 else _movement_state
		if sample_index < left_samples.size():
			var left_sample: Dictionary = left_samples[sample_index]
			_add_sample(left_sample["origin"], left_sample["end"], sample_state, &"left")
		if sample_index < right_samples.size():
			var right_sample: Dictionary = right_samples[sample_index]
			_add_sample(right_sample["origin"], right_sample["end"], sample_state, &"right")
	if _ignition_pending and has_real_pair:
		_ignition_pending = false
	queue_redraw()

func _sample_strand(cursor: Vector2, destination: Vector2) -> Array[Dictionary]:
	var samples: Array[Dictionary] = []
	var remaining_distance := cursor.distance_to(destination)
	# O teto por chamada evita arrays gigantes em teleporte/movimento extremo.
	# O cursor permanece no ultimo ponto emitido para continuar a distancia restante depois.
	while remaining_distance >= _spacing and samples.size() < MAX_SAMPLES_PER_STRAND:
		var ending := cursor.lerp(destination, _spacing / remaining_distance)
		samples.append({"origin": cursor, "end": ending})
		cursor = ending
		remaining_distance = cursor.distance_to(destination)
	return samples

func _add_sample(origin: Vector2, ending: Vector2, state: StringName, strand: StringName) -> void:
	# Esta lista e a unica geometria consultada para dano; largura visual nunca entra no calculo.
	var strand_count := 0
	var oldest_strand_index := -1
	for index in segments.size():
		var segment: Dictionary = segments[index]
		if segment.get("strand", strand) == strand:
			strand_count += 1
			if oldest_strand_index < 0:
				oldest_strand_index = index
	if strand_count >= MAX_SAMPLES_PER_STRAND:
		segments.remove_at(oldest_strand_index)
	segments.append({"origin": origin, "end": ending, "age": 0.0, "state": state, "strand": strand})

## Interrompe apenas a emissao; os segmentos existentes continuam seu fade normal.
func stop_emission() -> void:
	_has_last_anchors = false
	_ignition_pending = false

func clear_segments() -> void:
	segments.clear()
	target_next_damage.clear()
	_has_last_anchors = false
	_ignition_pending = false
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
	if _damage <= 0 or _width <= 0.0 or segments.is_empty() or not is_instance_valid(_source):
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
		_draw_visual_sample(segment)

func _draw_visual_sample(segment: Dictionary) -> void:
	var age_ratio := clampf(float(segment["age"]) / _duration, 0.0, 1.0)
	var fade := pow(1.0 - age_ratio, 0.76)
	var response := _state_response(segment.get("state", &"CRUISE"))
	var origin := to_local(segment["origin"] as Vector2)
	var ending := to_local(segment["end"] as Vector2)
	var visual_endpoints := _visual_endpoints(origin, ending, segment.get("state", &"CRUISE"))
	var visual_origin: Vector2 = visual_endpoints["origin"]
	var visual_ending: Vector2 = visual_endpoints["end"]
	var depth := clampf(age_ratio, 0.0, 1.0)
	var halo := Color(_color.r * 0.22, _color.g * 0.32, _color.b * 0.55, 0.24 * fade * response.x)
	var energy := Color(_color.r, _color.g, _color.b, 0.80 * fade * response.x)
	var core := Color(1.0, 1.0, 1.0, 0.97 * fade * response.x)
	draw_line(visual_origin, visual_ending, halo, lerpf(12.0, 1.0, depth) * response.y, false)
	draw_line(visual_origin, visual_ending, energy, lerpf(7.0, 0.8, depth) * response.y, false)
	draw_line(visual_origin, visual_ending, core, lerpf(2.8, 0.45, depth), false)
	# Clusters e motes usam somente a cor do personagem; branco fica restrito ao nucleo quente.
	var cluster_size := lerpf(5.2, 1.0, depth) * response.y
	if int(_elapsed * 60.0 + depth * 31.0) % 2 == 0 and depth > 0.08:
		draw_rect(Rect2(visual_origin - Vector2(cluster_size * 0.5, cluster_size * 0.32), Vector2(cluster_size, cluster_size * 0.64)), Color(_color.r, _color.g, _color.b, 0.68 * fade))
		draw_rect(Rect2(visual_origin - Vector2(cluster_size * 0.24, cluster_size * 0.22), Vector2(cluster_size * 0.48, cluster_size * 0.44)), Color.WHITE * Color(1.0, 1.0, 1.0, 0.76 * fade))
	if int(depth * 100.0) % 5 == 0 and depth > 0.22:
		var perpendicular := (visual_ending - visual_origin).normalized().rotated(PI * 0.5)
		draw_rect(Rect2(visual_origin + perpendicular * 4.0 - Vector2.ONE, Vector2(2.0, 2.0)), Color(_color.r, _color.g, _color.b, 0.55 * fade))

func _visual_endpoints(origin: Vector2, ending: Vector2, state: StringName) -> Dictionary:
	# Encurta somente a apresentacao: os segmentos logicos continuam intactos para dano.
	match state:
		&"IGNITION": return {"origin": origin.lerp(ending, 0.38), "end": ending}
		&"BRAKE": return {"origin": origin.lerp(ending, 0.46), "end": ending}
		_: return {"origin": origin, "end": ending}

func _state_response(state: StringName) -> Vector2:
	match state:
		&"IGNITION": return Vector2(1.25, 1.12)
		&"TURN": return Vector2(1.05, 0.94)
		&"BRAKE": return Vector2(0.72, 0.78)
		_: return Vector2(1.0, 1.0)
