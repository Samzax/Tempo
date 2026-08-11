extends GutTest

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var _root: Node2D
var _projectiles: Node2D
var _player: Player

func before_each() -> void:
	_root = Node2D.new()
	add_child_autofree(_root)
	_projectiles = Node2D.new()
	_projectiles.add_to_group("projectiles")
	_root.add_child(_projectiles)

	var enemy := Node2D.new()
	enemy.add_to_group("enemies")
	enemy.position = Vector2.RIGHT.rotated(deg_to_rad(3.0)) * 100.0
	_root.add_child(enemy)

	_player = PLAYER_SCENE.instantiate() as Player
	_root.add_child(_player)
	await get_tree().process_frame

func test_fire_uses_aim_vector_for_all_aim_tiers_even_with_enemy_in_legacy_cone() -> void:
	for aim_tier in [1, 2, 3]:
		_player._stats.set_base(&"aim_tier", float(aim_tier))
		_player._aim_vector = Vector2.RIGHT
		_player._fire()

		assert_gt(_projectiles.get_child_count(), 0)
		var bullet := _projectiles.get_child(_projectiles.get_child_count() - 1)
		assert_true(bullet._active)
		assert_true(bullet._velocity.normalized().is_equal_approx(Vector2.RIGHT))
