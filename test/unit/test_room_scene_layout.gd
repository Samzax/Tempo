extends GutTest

const ROOM_SCENE := preload("res://scenes/rooms/room.tscn")

func test_reward_chest_static_position_matches_arena_preview() -> void:
	var room := ROOM_SCENE.instantiate()
	add_child_autofree(room)

	var reward_chest := room.get_node("RewardChest") as Node2D
	assert_eq(reward_chest.position, Vector2(360, 353))
