class_name ProceduralChain2D
extends Node2D
## Cadeia procedural com marcadores visuais atlasados. joint_positions continua
## publico para consumidores de gameplay, mas cada elo tambem e desenhado aqui.

enum VisualMarkerRole { ANCHOR = 0, LINK = 1, JOINT = 2, END = 3 }

@export_range(1, 64, 1) var link_count: int = 4:
	set(value):
		link_count = maxi(1, value)
@export_range(0.01, 1000.0, 0.01) var link_length: float = 12.0
@export_range(0.0, 100.0, 0.01) var stiffness: float = 28.0
@export_range(0.0, 100.0, 0.01) var damping: float = 9.0
@export_range(0.0, 1.0, 0.01) var residual_inertia: float = 1.0
@export_range(0.0, 1.0, 0.01) var max_turn_per_step: float = 0.8
## Direcoes de repouso por elo. Vazio preserva o comportamento procedural atual.
@export var rest_directions := PackedVector2Array()
@export_group("Visual Markers")
@export var visual_texture: Texture2D
## Regioes concretas do kit: junta, elo repetivel e ponta/mao.
@export var joint_region := Rect2()
@export var link_region := Rect2()
@export var end_region := Rect2()
@export var link_regions: Array[Rect2] = []
@export var visual_scale := Vector2.ONE
## Compensa a orientacao do recorte no atlas (bracos sao desenhados na vertical).
@export var visual_rotation_offset: float = 0.0
## Vazio preserva o posicionamento visual legado para todos os marcadores.
@export var visual_marker_roles := PackedInt32Array()
@export var visual_marker_spans := PackedVector2Array()
## Ajustes ópticos por marcador, no espaço local da cadeia.
@export var visual_marker_offsets := PackedVector2Array()
## Escalas por marcador; vazio mantém visual_scale para todos os marcadores.
@export var visual_marker_scales := PackedVector2Array()
## Mantém uma ponta no meio do seu trecho e corrige sua orientação sem acoplar ao dono.
@export var visual_terminal_midpoint: bool = false
@export var visual_terminal_rotation_offset: float = 0.0
## Flex visual pós-simulação, configurável para rigs articulados.
@export_range(0.0, 1.0, 0.01) var visual_elbow_flex: float = 0.0
@export_range(0, 63, 1) var visual_elbow_pivot_joint: int = 2

const REFERENCE_STEP_SECONDS := 1.0 / 60.0
const MAX_SUBSTEP_SECONDS := 1.0 / 120.0

var joint_positions := PackedVector2Array()
var _joint_velocities := PackedVector2Array()
var _link_directions := PackedVector2Array()
var _visual_markers: Array[Sprite2D] = []

func _ready() -> void:
	_ensure_visual_markers()

func reset_chain(anchor_position: Vector2, initial_direction: Vector2 = Vector2.DOWN) -> void:
	if not _is_finite_vector(anchor_position):
		return
	var direction := _safe_direction(initial_direction, Vector2.DOWN)
	joint_positions.resize(link_count)
	_joint_velocities.resize(link_count)
	_link_directions.resize(link_count)
	var previous := anchor_position
	for index in link_count:
		direction = _rest_direction(index, direction)
		joint_positions[index] = previous + direction * _safe_link_length()
		previous = joint_positions[index]
		_joint_velocities[index] = Vector2.ZERO
		_link_directions[index] = direction
	_sync_visual_markers()

func step(anchor_position: Vector2, delta: float) -> PackedVector2Array:
	if delta <= 0.0 or not is_finite(delta) or not _is_finite_vector(anchor_position):
		return joint_positions
	if joint_positions.size() != link_count or _joint_velocities.size() != link_count:
		reset_chain(anchor_position)
	var substep_count := maxi(1, ceili(delta / MAX_SUBSTEP_SECONDS))
	var substep_delta := delta / float(substep_count)
	for _substep in substep_count:
		_step_substep(anchor_position, substep_delta)
	_sync_visual_markers()
	return joint_positions

func _ensure_visual_markers() -> void:
	if visual_texture == null:
		return
	while _visual_markers.size() > link_count:
		var removed: Sprite2D = _visual_markers.pop_back()
		if is_instance_valid(removed):
			removed.queue_free()
	while _visual_markers.size() < link_count:
		var index := _visual_markers.size()
		var marker := Sprite2D.new()
		marker.name = "ProceduralLink%02d" % index
		marker.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		marker.texture = _marker_texture_for(index)
		marker.scale = visual_scale
		add_child(marker)
		_visual_markers.append(marker)
	for index in _visual_markers.size():
		_visual_markers[index].texture = _marker_texture_for(index)

func _marker_texture_for(index: int) -> AtlasTexture:
	var atlas_texture := AtlasTexture.new()
	atlas_texture.atlas = visual_texture
	if index >= 0 and index < link_regions.size() and link_regions[index].size != Vector2.ZERO:
		atlas_texture.region = link_regions[index]
	elif index == 0 and joint_region.size != Vector2.ZERO:
		atlas_texture.region = joint_region
	elif index == link_count - 1 and end_region.size != Vector2.ZERO:
		atlas_texture.region = end_region
	else:
		atlas_texture.region = link_region
	return atlas_texture

func _sync_visual_markers() -> void:
	_ensure_visual_markers()
	if _visual_markers.is_empty() or joint_positions.size() != link_count:
		return
	var has_marker_bindings := visual_marker_roles.size() == link_count and visual_marker_spans.size() == link_count
	for index in link_count:
		var marker := _visual_markers[index]
		if not is_instance_valid(marker):
			continue
		if not has_marker_bindings or not _sync_bound_visual_marker(marker, index):
			_sync_legacy_visual_marker(marker, index)
	_apply_elbow_flex()

func _sync_bound_visual_marker(marker: Sprite2D, index: int) -> bool:
	var role := visual_marker_roles[index]
	if role < VisualMarkerRole.ANCHOR or role > VisualMarkerRole.END:
		return false
	var span := visual_marker_spans[index]
	var start := _marker_span_position(int(span.x))
	var end := _marker_span_position(int(span.y))
	var marker_position := end
	if role == VisualMarkerRole.ANCHOR:
		marker_position = start
	elif role == VisualMarkerRole.LINK:
		marker_position = (start + end) * 0.5
	elif role == VisualMarkerRole.END and visual_terminal_midpoint:
		marker_position = (start + end) * 0.5
	var direction := _safe_direction(end - start, _fallback_direction(index))
	_apply_marker_transform(marker, index, marker_position, direction, false)
	return true

func _marker_span_position(raw_index: int) -> Vector2:
	var clamped_index := clampi(raw_index, -1, link_count - 1)
	if clamped_index == -1:
		return global_position
	return joint_positions[clamped_index]

func _sync_legacy_visual_marker(marker: Sprite2D, index: int) -> void:
	var marker_position: Vector2
	var direction: Vector2
	if index == 0:
		marker_position = global_position
		direction = _safe_direction(joint_positions[0] - global_position, _fallback_direction(0))
	elif index == link_count - 1:
		marker_position = joint_positions[index]
		direction = _safe_direction(joint_positions[index] - joint_positions[index - 1], _fallback_direction(index))
	else:
		marker_position = (joint_positions[index - 1] + joint_positions[index]) * 0.5
		direction = _safe_direction(joint_positions[index] - joint_positions[index - 1], _fallback_direction(index))
	_apply_marker_transform(marker, index, marker_position, direction, true)

func _apply_marker_transform(marker: Sprite2D, index: int, marker_position: Vector2, direction: Vector2, legacy: bool) -> void:
	var is_terminal := index == link_count - 1
	if legacy and is_terminal and visual_terminal_midpoint and link_count > 1:
		marker_position = (joint_positions[index - 1] + joint_positions[index]) * 0.5
	var rotation_offset := visual_rotation_offset
	if is_terminal:
		rotation_offset += visual_terminal_rotation_offset
	marker.position = to_local(marker_position) + _marker_visual_offset(index)
	marker.rotation = direction.angle() + rotation_offset
	marker.scale = _marker_visual_scale(index)

func _marker_visual_offset(index: int) -> Vector2:
	if index >= 0 and index < visual_marker_offsets.size():
		return visual_marker_offsets[index]
	return Vector2.ZERO

func _marker_visual_scale(index: int) -> Vector2:
	if index >= 0 and index < visual_marker_scales.size() and visual_marker_scales[index] != Vector2.ZERO:
		return visual_marker_scales[index]
	return visual_scale

func _apply_elbow_flex() -> void:
	if visual_elbow_flex <= 0.0 or _visual_markers.is_empty():
		return
	var pivot_index := visual_elbow_pivot_joint
	if pivot_index < 1 or pivot_index + 1 >= joint_positions.size():
		return
	var upper_direction := _safe_direction(joint_positions[1] - joint_positions[0], _fallback_direction(1))
	var forearm_direction := _safe_direction(joint_positions[pivot_index + 1] - joint_positions[pivot_index], _fallback_direction(pivot_index + 1))
	var extra := angle_difference(upper_direction.angle(), forearm_direction.angle()) * visual_elbow_flex
	if is_zero_approx(extra):
		return
	var pivot := to_local(joint_positions[pivot_index])
	for index in _visual_markers.size():
		if index < pivot_index:
			continue
		var marker := _visual_markers[index]
		if not is_instance_valid(marker):
			continue
		var marker_extra := extra * (0.5 if index == pivot_index else 1.0)
		var marker_transform := marker.transform
		marker_transform.origin = pivot + (marker_transform.origin - pivot).rotated(marker_extra)
		marker_transform.x = marker_transform.x.rotated(marker_extra)
		marker_transform.y = marker_transform.y.rotated(marker_extra)
		marker.transform = marker_transform

func _step_substep(anchor_position: Vector2, delta: float) -> void:
	var drag := exp(-maxf(0.0, damping) * delta)
	var retained_inertia := pow(clampf(residual_inertia, 0.0, 1.0), delta / REFERENCE_STEP_SECONDS)
	var previous := anchor_position
	for index in link_count:
		var current := joint_positions[index]
		if not _is_finite_vector(current):
			current = previous + _fallback_direction(index) * _safe_link_length()
		var desired_direction := _rest_direction(index, _fallback_direction(index))
		var desired := previous + desired_direction * _safe_link_length()
		var velocity := _joint_velocities[index]
		if not _is_finite_vector(velocity):
			velocity = Vector2.ZERO
		velocity += (desired - current) * maxf(0.0, stiffness) * delta
		velocity *= drag * retained_inertia
		velocity = velocity.limit_length(_safe_link_length() / delta * 2.0)
		var candidate := current + velocity * delta
		if not _is_finite_vector(candidate):
			candidate = previous + _fallback_direction(index) * _safe_link_length()
		var offset := candidate - previous
		var direction := _safe_direction(offset, _fallback_direction(index))
		direction = _limit_turn(_fallback_direction(index), direction, delta)
		candidate = previous + direction * _safe_link_length()
		joint_positions[index] = candidate
		_joint_velocities[index] = velocity
		_link_directions[index] = direction
		previous = candidate

func get_joint_position(index: int) -> Vector2:
	if index < 0 or index >= joint_positions.size():
		return global_position
	return joint_positions[index]

func _safe_link_length() -> float:
	return maxf(0.001, link_length)

func _fallback_direction(index: int) -> Vector2:
	if index >= 0 and index < _link_directions.size():
		return _safe_direction(_link_directions[index], Vector2.DOWN)
	return Vector2.DOWN

func _rest_direction(index: int, fallback: Vector2) -> Vector2:
	if not rest_directions.is_empty() and index >= 0 and index < rest_directions.size():
		return _safe_direction(rest_directions[index], fallback)
	return _safe_direction(fallback, Vector2.DOWN)

func _limit_turn(previous: Vector2, next: Vector2, delta: float) -> Vector2:
	var safe_previous := _safe_direction(previous, Vector2.DOWN)
	var safe_next := _safe_direction(next, safe_previous)
	var reference_turn := clampf(max_turn_per_step, 0.0, 1.0)
	if reference_turn >= 1.0:
		return safe_next
	var turn_rate := -log(maxf(0.000001, 1.0 - reference_turn)) / REFERENCE_STEP_SECONDS
	var temporal_turn := 1.0 - exp(-turn_rate * delta)
	return _safe_direction(safe_previous.lerp(safe_next, temporal_turn), safe_previous)

func _safe_direction(value: Vector2, fallback: Vector2) -> Vector2:
	if _is_finite_vector(value) and value.length_squared() > 0.000001:
		return value.normalized()
	if _is_finite_vector(fallback) and fallback.length_squared() > 0.000001:
		return fallback.normalized()
	return Vector2.DOWN

func _is_finite_vector(value: Vector2) -> bool:
	return is_finite(value.x) and is_finite(value.y)
