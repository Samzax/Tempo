extends GutTest

const BULLET_SCRIPT := preload("res://scripts/projectiles/bullet.gd")

class DamageTarget extends Node:
	var health: float
	var calls := 0
	func _init(initial_health: float) -> void:
		health = initial_health
	func take_damage(info: DamageInfo) -> float:
		calls += 1
		var consumed := minf(health, info.amount)
		health -= consumed
		return consumed

class ConfigurableDamageTarget extends Node:
	var reported_consumption: Variant
	func _init(consumption: Variant) -> void:
		reported_consumption = consumption
	func take_damage(_info: DamageInfo) -> Variant:
		return reported_consumption

class PassiveTarget extends Node:
	pass

func _bullet() -> Node:
	var bullet := BULLET_SCRIPT.new()
	add_child_autofree(bullet)
	return bullet

func _activate(bullet: Node, damage_amount: float = 25.0) -> void:
	bullet.activate(Vector2.ZERO, Vector2.UP, self, damage_amount)

func test_damage_crosses_targets_with_remaining_balance() -> void:
	var bullet := _bullet()
	var first := DamageTarget.new(6.0)
	var second := DamageTarget.new(5.0)
	_activate(bullet)
	bullet._on_hit(first)
	bullet._on_hit(second)
	assert_almost_eq(first.health, 0.0, 0.001)
	assert_almost_eq(second.health, 0.0, 0.001)
	assert_almost_eq(bullet._remaining_damage, 14.0, 0.001)

func test_duplicate_target_is_hit_only_once() -> void:
	var bullet := _bullet()
	var target := DamageTarget.new(100.0)
	_activate(bullet)
	bullet._on_hit(target)
	bullet._on_hit(target)
	assert_eq(target.calls, 1)
	assert_almost_eq(bullet._remaining_damage, 0.0, 0.001)

func test_invalid_damage_return_fails_closed() -> void:
	var bullet := _bullet()
	_activate(bullet, 7.0)
	bullet._on_hit(ConfigurableDamageTarget.new(null))
	assert_false(bullet._active)

func test_non_damage_target_despawns_bullet() -> void:
	var bullet := _bullet()
	_activate(bullet, 7.0)
	bullet._on_hit(PassiveTarget.new())
	assert_false(bullet._active)

func test_despawn_state_resets_and_old_epoch_cannot_disable_reactivation() -> void:
	var bullet := _bullet()
	var target := DamageTarget.new(6.0)
	_activate(bullet)
	bullet._on_hit(target)
	bullet._despawn()
	var old_epoch: int = bullet._activation_epoch
	_activate(bullet, 3.0)
	bullet._disable_collision_after_despawn(old_epoch)
	bullet._release_if_still_despawned(old_epoch)
	assert_true(bullet._active)
	assert_true(bullet.monitoring)
	assert_eq(bullet._remaining_damage, 3.0)

func test_physics_process_stops_at_most_restrictive_travel_limit() -> void:
	var bullet := _bullet()
	bullet.activate(Vector2.ZERO, Vector2.UP, self, 1.0, 10.0, 0.5)
	bullet._physics_process(1.0)
	assert_almost_eq(bullet.global_position.y, -5.0, 0.001)
	assert_false(bullet._active)
