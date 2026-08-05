extends GutTest

const AsteroidsMotionCalculator := preload("res://scripts/player/asteroids_motion.gd")


func test_thrust_from_rest_accelerates_along_heading() -> void:
	var velocity := AsteroidsMotionCalculator.calculate_velocity(
		Vector2.ZERO, Vector2.RIGHT, true, 100.0, 0.0, 1000.0, 0.25
	)

	assert_eq(velocity, Vector2(25.0, 0.0))


func test_friction_larger_than_speed_stops_exactly() -> void:
	var velocity := AsteroidsMotionCalculator.calculate_velocity(
		Vector2(3.0, 4.0), Vector2.ZERO, false, 0.0, 10.0, 1000.0, 1.0
	)

	assert_eq(velocity, Vector2.ZERO)


func test_partial_friction_reduces_magnitude_without_changing_direction() -> void:
	var velocity := AsteroidsMotionCalculator.calculate_velocity(
		Vector2(10.0, 0.0), Vector2.ZERO, false, 0.0, 3.0, 1000.0, 1.0
	)

	assert_eq(velocity, Vector2(7.0, 0.0))


func test_thrust_preserves_existing_perpendicular_inertia() -> void:
	var velocity := AsteroidsMotionCalculator.calculate_velocity(
		Vector2(10.0, 0.0), Vector2.DOWN, true, 20.0, 0.0, 1000.0, 0.5
	)

	assert_eq(velocity, Vector2(10.0, 10.0))


func test_result_is_clamped_to_max_speed() -> void:
	var velocity := AsteroidsMotionCalculator.calculate_velocity(
		Vector2.ZERO, Vector2.RIGHT, true, 100.0, 0.0, 30.0, 1.0
	)

	assert_eq(velocity, Vector2(30.0, 0.0))


func test_non_positive_max_speed_stops_motion() -> void:
	var velocity := AsteroidsMotionCalculator.calculate_velocity(
		Vector2(12.0, -5.0), Vector2.RIGHT, true, 100.0, 0.0, 0.0, 1.0
	)

	assert_eq(velocity, Vector2.ZERO)


func test_invalid_inputs_are_safely_normalized() -> void:
	var velocity := AsteroidsMotionCalculator.calculate_velocity(
		Vector2(INF, -INF), Vector2(NAN, 1.0), true, NAN, INF, 100.0, 1.0
	)

	assert_eq(velocity, Vector2.ZERO)


func test_zero_heading_with_thrust_applies_only_friction() -> void:
	var velocity := AsteroidsMotionCalculator.calculate_velocity(
		Vector2(3.0, 4.0), Vector2.ZERO, true, 100.0, 1.0, 1000.0, 1.0
	)

	assert_eq(velocity, Vector2(2.4, 3.2))


func test_zero_delta_preserves_current_velocity() -> void:
	var velocity := AsteroidsMotionCalculator.calculate_velocity(
		Vector2(12.0, -5.0), Vector2.RIGHT, true, 100.0, 5.0, 10.0, 0.0
	)

	assert_eq(velocity, Vector2(12.0, -5.0))


func test_non_unit_heading_is_normalized_before_acceleration() -> void:
	var velocity := AsteroidsMotionCalculator.calculate_velocity(
		Vector2.ZERO, Vector2(3.0, 4.0), true, 10.0, 0.0, 100.0, 0.5
	)

	assert_eq(velocity, Vector2(3.0, 4.0))


func test_non_finite_delta_preserves_finite_current_velocity() -> void:
	var expected := Vector2(12.0, -5.0)

	assert_eq(
		AsteroidsMotionCalculator.calculate_velocity(
			expected, Vector2.RIGHT, true, 100.0, 5.0, 10.0, NAN
		),
		expected,
	)
	assert_eq(
		AsteroidsMotionCalculator.calculate_velocity(
			expected, Vector2.RIGHT, true, 100.0, 5.0, 10.0, INF
		),
		expected,
	)


func test_non_finite_or_invalid_max_speed_stops_motion() -> void:
	var current_velocity := Vector2(12.0, -5.0)

	assert_eq(
		AsteroidsMotionCalculator.calculate_velocity(
			current_velocity, Vector2.RIGHT, true, 100.0, 0.0, NAN, 1.0
		),
		Vector2.ZERO,
	)
	assert_eq(
		AsteroidsMotionCalculator.calculate_velocity(
			current_velocity, Vector2.RIGHT, true, 100.0, 0.0, INF, 1.0
		),
		Vector2.ZERO,
	)
	assert_eq(
		AsteroidsMotionCalculator.calculate_velocity(
			current_velocity, Vector2.RIGHT, true, 100.0, 0.0, -1.0, 1.0
		),
		Vector2.ZERO,
	)


func test_normal_acceleration_and_friction_behavior_remains_unchanged() -> void:
	var accelerated := AsteroidsMotionCalculator.calculate_velocity(
		Vector2(10.0, 0.0), Vector2.UP, true, 20.0, 0.0, 100.0, 0.5
	)
	var slowed := AsteroidsMotionCalculator.calculate_velocity(
		Vector2(10.0, 0.0), Vector2.ZERO, false, 0.0, 3.0, 100.0, 1.0
	)

	assert_eq(accelerated, Vector2(10.0, -10.0))
	assert_eq(slowed, Vector2(7.0, 0.0))
