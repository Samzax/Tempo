class_name ProceduralChain2D
extends Node2D
## Cadeia procedural sem geometria ou fisica. Os consumidores podem usar
## joint_positions para posicionar seus proprios marcadores visuais.

@export_range(1, 64, 1) var link_count: int = 4:
	set(value):
		link_count = maxi(1, value)
@export_range(0.01, 1000.0, 0.01) var link_length: float = 12.0
@export_range(0.0, 100.0, 0.01) var stiffness: float = 28.0
@export_range(0.0, 100.0, 0.01) var damping: float = 9.0
@export_range(0.0, 1.0, 0.01) var residual_inertia: float = 1.0
@export_range(0.0, 1.0, 0.01) var max_turn_per_step: float = 0.8

const REFERENCE_STEP_SECONDS := 1.0 / 60.0
const MAX_SUBSTEP_SECONDS := 1.0 / 120.0

var joint_positions := PackedVector2Array()
var _joint_velocities := PackedVector2Array()
var _link_directions := PackedVector2Array()

func reset_chain(anchor_position: Vector2, initial_direction: Vector2 = Vector2.DOWN) -> void:
	if not _is_finite_vector(anchor_position):
		return
	var direction := _safe_direction(initial_direction, Vector2.DOWN)
	joint_positions.resize(link_count)
	_joint_velocities.resize(link_count)
	_link_directions.resize(link_count)
	for index in link_count:
		joint_positions[index] = anchor_position + direction * _safe_link_length() * float(index + 1)
		_joint_velocities[index] = Vector2.ZERO
		_link_directions[index] = direction

func step(anchor_position: Vector2, delta: float) -> PackedVector2Array:
	if delta <= 0.0 or not is_finite(delta) or not _is_finite_vector(anchor_position):
		return joint_positions
	if joint_positions.size() != link_count or _joint_velocities.size() != link_count:
		reset_chain(anchor_position)
	var substep_count := maxi(1, ceili(delta / MAX_SUBSTEP_SECONDS))
	var substep_delta := delta / float(substep_count)
	for _substep in substep_count:
		_step_substep(anchor_position, substep_delta)
	return joint_positions

func _step_substep(anchor_position: Vector2, delta: float) -> void:
	var drag := exp(-maxf(0.0, damping) * delta)
	var retained_inertia := pow(clampf(residual_inertia, 0.0, 1.0), delta / REFERENCE_STEP_SECONDS)
	var previous := anchor_position
	for index in link_count:
		var current := joint_positions[index]
		if not _is_finite_vector(current):
			current = previous + _fallback_direction(index) * _safe_link_length()
		var desired := previous + _fallback_direction(index) * _safe_link_length()
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
