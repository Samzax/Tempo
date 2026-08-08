extends GutTest

const ENEMY_SCENE := preload("res://scenes/enemies/enemy.tscn")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const SPAWN_DIRECTOR := preload("res://scripts/directors/spawn_director.gd")
const SESSION_SCRIPT := preload("res://scripts/run/session.gd")
const MAIN_SCENE := preload("res://scenes/main/main.tscn")

const ARENA := Rect2(Vector2.ZERO, Vector2(720, 405))
const VIEWPORT_SIZE := Vector2(480, 270)

func test_room_default_and_configured_size_expose_center_and_bounds() -> void:
	var room := RoomDef.new()
	assert_eq(room.size, Vector2(720, 405))
	assert_eq(room.get_bounds(), ARENA)
	assert_eq(room.get_bounds().get_center(), Vector2(360, 202.5))

	room.size = Vector2(900, 600)
	assert_eq(room.get_bounds(), Rect2(Vector2.ZERO, Vector2(900, 600)))
	assert_eq(room.get_bounds().get_center(), Vector2(450, 300))

func test_main_scene_starts_player_and_camera_at_room_center_without_sprite_scale() -> void:
	var main := MAIN_SCENE.instantiate()
	add_child_autofree(main)
	await get_tree().process_frame

	var expected_center := ARENA.get_center()
	var camera := main.get_node("World/Camera2D") as Camera2D
	var player := main.get_node("World/Player") as Player
	var visual_root := player.get_node("VisualRoot") as Node2D
	var animated_sprite := visual_root.get_node("AnimatedSprite2D") as AnimatedSprite2D

	assert_eq(camera.position, expected_center)
	assert_eq(player.position, expected_center)
	assert_eq(player.global_position, expected_center)
	assert_eq(player.scale, Vector2.ONE)
	assert_eq(visual_root.scale, Vector2.ONE)
	assert_eq(animated_sprite.scale, Vector2.ONE)

func test_session_start_new_run_configures_real_room_geometry() -> void:
	var main := MAIN_SCENE.instantiate()
	add_child_autofree(main)
	await get_tree().process_frame

	var session := main.get_node("Session") as Session
	session.start_new_run(12345)
	await get_tree().process_frame

	var room_host := session.get_node("RoomHost")
	assert_eq(room_host.get_child_count(), 1)
	var room := room_host.get_child(0)
	var controller := room.get_node("RoomController") as RoomController
	var chest := room.get_node("RewardChest") as RewardChest
	var director := room.get_node("Directors/SpawnDirector") as Node

	assert_eq(controller.room_def.size, Vector2(720, 405))
	assert_eq(chest.position, Vector2(360, 353))
	assert_eq(director.get("_room_bounds"), ARENA)

	var player := main.get_node("World/Player") as Player
	var camera := main.get_node("World/Camera2D") as Camera2D
	assert_eq(player.get("_room_bounds"), ARENA)
	assert_eq(camera.limit_left, 0)
	assert_eq(camera.limit_top, 0)
	assert_eq(camera.limit_right, 720)
	assert_eq(camera.limit_bottom, 405)
	assert_eq(camera.global_position, ARENA.get_center())
	assert_eq(camera.get_viewport_rect().size, VIEWPORT_SIZE)

func test_bullet_keeps_room_bounds_while_crossing_viewport_extent() -> void:
	var bullet_scene := preload("res://scenes/projectiles/bullet.tscn")
	var bullet := bullet_scene.instantiate() as Area2D
	add_child_autofree(bullet)
	await get_tree().process_frame

	bullet.set_room_bounds(ARENA)
	bullet.activate(Vector2(610, 135), Vector2.RIGHT, self)
	bullet._physics_process(0.05)

	assert_true(bullet.visible)
	assert_true(bullet.global_position.x > ARENA.get_center().x + VIEWPORT_SIZE.x / 2.0)
	assert_true(bullet.global_position.x <= ARENA.end.x + 16.0)
	assert_true(bullet.global_position.y >= ARENA.position.y - 16.0)
	assert_true(bullet.global_position.y <= ARENA.end.y + 16.0)

func test_spawn_uses_room_horizontal_bounds_and_passes_bounds_to_enemy() -> void:
	var room := Node.new()
	var container := Node.new()
	container.add_to_group(&"enemies_container")
	room.add_child(container)
	var director := SPAWN_DIRECTOR.new()
	room.add_child(director)
	add_child_autofree(room)
	await get_tree().process_frame
	director.interval = 0.0
	var custom := Rect2(Vector2(100, 50), Vector2(300, 200))
	director.set_room_bounds(custom)
	director.start(1)
	await get_tree().physics_frame

	assert_eq(container.get_child_count(), 1)
	var enemy := container.get_child(0) as Enemy
	assert_true(enemy.global_position.x >= 124.0)
	assert_true(enemy.global_position.x <= 376.0)
	assert_eq(enemy.global_position.y, 34.0)

func test_enemy_culls_against_configured_room_bottom() -> void:
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	add_child_autofree(enemy)
	watch_signals(enemy)
	await get_tree().process_frame
	enemy.set_room_bounds(Rect2(Vector2(100, 50), Vector2(300, 200)))
	enemy.global_position = Vector2(200, 291)
	enemy.set_physics_process(true)
	await get_tree().physics_frame

	assert_signal_emitted_with_parameters(enemy, &"resolved", [enemy, Enemy.ResolveReason.CULLED])
	assert_true(enemy.is_queued_for_deletion())

func test_player_clamp_uses_configured_bounds_and_keeps_ship_geometry() -> void:
	var player := PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	await get_tree().process_frame
	var visual_root := player.get_node("VisualRoot") as Node2D
	var animated_sprite := visual_root.get_node("AnimatedSprite2D") as AnimatedSprite2D
	player.set_room_bounds(Rect2(Vector2(100, 50), Vector2(300, 200)))
	player.global_position = Vector2(0, 0)
	player.call("_clamp_to_bounds")

	assert_eq(player.global_position, Vector2(110, 60))
	assert_eq(player.scale, Vector2.ONE)
	assert_eq(visual_root.scale, Vector2.ONE)
	assert_eq(animated_sprite.scale, Vector2.ONE)
