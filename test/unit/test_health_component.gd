extends GutTest

const HEALTH_COMPONENT := preload("res://scripts/components/health_component.gd")

func _health(max_health: float = 10.0) -> HealthComponent:
	var health := HEALTH_COMPONENT.new() as HealthComponent
	health.max_health = max_health
	add_child_autofree(health)
	await get_tree().process_frame
	return health

func _damage(amount: float) -> DamageInfo:
	var info := DamageInfo.new()
	info.amount = amount
	return info

func test_partial_damage_returns_actual_applied_amount() -> void:
	var health := await _health()
	assert_eq(health.apply_damage(_damage(3.5)), 3.5)
	assert_eq(health.health, 6.5)

func test_overkill_returns_only_remaining_health() -> void:
	var health := await _health(10.0)
	assert_eq(health.apply_damage(_damage(25.0)), 10.0)
	assert_eq(health.health, 0.0)

func test_invalid_damage_and_dead_target_return_zero() -> void:
	var health := await _health()
	assert_eq(health.apply_damage(null), 0.0)
	assert_eq(health.apply_damage(_damage(0.0)), 0.0)
	assert_eq(health.apply_damage(_damage(-2.0)), 0.0)
	assert_eq(health.apply_damage(_damage(10.0)), 10.0)
	assert_eq(health.apply_damage(_damage(1.0)), 0.0)

func test_non_finite_damage_returns_zero_without_health_or_signals() -> void:
	var health := await _health()
	watch_signals(health)
	assert_eq(health.apply_damage(_damage(NAN)), 0.0)
	assert_eq(health.apply_damage(_damage(INF)), 0.0)
	assert_eq(health.health, 10.0)
	assert_signal_emit_count(health, &"damaged", 0)
	assert_signal_emit_count(health, &"died", 0)

func test_damage_and_death_signals_keep_single_application_behavior() -> void:
	var health := await _health(10.0)
	var first_hit := _damage(3.0)
	var fatal_hit := _damage(20.0)
	watch_signals(health)
	assert_eq(health.apply_damage(first_hit), 3.0)
	assert_signal_emitted_with_parameters(health, &"damaged", [first_hit, 3.0])
	assert_eq(health.apply_damage(fatal_hit), 7.0)
	assert_signal_emitted_with_parameters(health, &"damaged", [fatal_hit, 7.0])
	assert_signal_emitted_with_parameters(health, &"died", [fatal_hit])
	assert_eq(health.apply_damage(_damage(1.0)), 0.0)
	assert_signal_emit_count(health, &"died", 1)
