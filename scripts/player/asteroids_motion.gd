class_name AsteroidsMotion
extends RefCounted


static func calculate_velocity(
	current_velocity: Vector2,
	heading: Vector2,
	is_thrusting: bool,
	acceleration: float,
	friction: float,
	max_speed: float,
	delta: float,
) -> Vector2:
	if not max_speed.is_finite() or max_speed <= 0.0:
		return Vector2.ZERO

	var velocity := _finite_vector_or_zero(current_velocity)
	if not delta.is_finite() or delta <= 0.0:
		return velocity

	var heading_direction := _normalized_or_zero(heading)
	if is_thrusting and heading_direction != Vector2.ZERO:
		var valid_acceleration := _non_negative_finite(acceleration)
		var acceleration_distance := _safe_positive_product(valid_acceleration, delta)
		if not acceleration_distance.is_finite():
			return heading_direction * max_speed
		velocity = _add_and_clamp_speed(
			velocity,
			heading_direction * acceleration_distance,
			max_speed,
		)
	else:
		var valid_friction := _non_negative_finite(friction)
		velocity = _move_toward_zero(
			velocity,
			_safe_positive_product(valid_friction, delta),
		)

	return _clamp_speed(velocity, max_speed)


static func _finite_vector_or_zero(value: Vector2) -> Vector2:
	return value if value.is_finite() else Vector2.ZERO


static func _non_negative_finite(value: float) -> float:
	return maxf(value, 0.0) if value.is_finite() else 0.0


static func _normalized_or_zero(value: Vector2) -> Vector2:
	var finite_value := _finite_vector_or_zero(value)
	var scale := maxf(absf(finite_value.x), absf(finite_value.y))
	if scale == 0.0:
		return Vector2.ZERO
	var scaled_value := finite_value / scale
	return scaled_value / scaled_value.length()


static func _clamp_speed(velocity: Vector2, max_speed: float) -> Vector2:
	var scale := maxf(absf(velocity.x), absf(velocity.y))
	if scale == 0.0:
		return velocity

	var scaled_velocity := velocity / scale
	var scaled_length := scaled_velocity.length()
	if scaled_length <= max_speed / scale:
		return velocity
	return scaled_velocity / scaled_length * max_speed


static func _safe_positive_product(first: float, second: float) -> float:
	var product := first * second
	return product if product.is_finite() else INF


static func _add_and_clamp_speed(
	first: Vector2,
	second: Vector2,
	max_speed: float,
) -> Vector2:
	var scale := maxf(
		maxf(absf(first.x), absf(first.y)),
		maxf(absf(second.x), absf(second.y)),
	)
	if scale == 0.0:
		return Vector2.ZERO

	var scaled_sum := first / scale + second / scale
	var scaled_length := scaled_sum.length()
	if scaled_length == 0.0:
		return Vector2.ZERO
	if scaled_length <= max_speed / scale:
		return scaled_sum * scale
	return scaled_sum / scaled_length * max_speed


static func _move_toward_zero(velocity: Vector2, distance: float) -> Vector2:
	var scale := maxf(absf(velocity.x), absf(velocity.y))
	if scale == 0.0:
		return velocity

	var scaled_length := (velocity / scale).length()
	var scaled_distance := distance / scale
	if not scaled_distance.is_finite() or scaled_distance >= scaled_length:
		return Vector2.ZERO
	return velocity - velocity * (scaled_distance / scaled_length)
