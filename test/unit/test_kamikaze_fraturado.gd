extends GutTest

const SCENE := preload("res://scenes/enemies/kamikaze_fraturado.tscn")
const SCRIPT := preload("res://scripts/enemies/kamikaze_fraturado.gd")
const FX_SCENE := preload("res://scenes/effects/kamikaze_detonate_fx.tscn")
const STRIP_PATHS := [
	"res://assets/sprites/enemies/kamikaze_mina/approach_strip.png",
	"res://assets/sprites/enemies/kamikaze_mina/warning_strip.png",
	"res://assets/sprites/enemies/kamikaze_mina/dash_strip.png",
	"res://assets/sprites/enemies/kamikaze_mina/detonate_fx_strip.png",
]

func _enemy() -> Node:
	var enemy := SCENE.instantiate()
	add_child_autofree(enemy)
	await get_tree().process_frame
	return enemy

func test_telegraph_is_point_four_five_seconds() -> void:
	var enemy := await _enemy()
	enemy._enter_state(SCRIPT.AttackState.TELEGRAPH)
	assert_eq(enemy.telegraph_duration, 0.45)
	enemy._physics_process(0.44)
	assert_eq(enemy.attack_state, SCRIPT.AttackState.TELEGRAPH)
	enemy._physics_process(0.01)
	assert_eq(enemy.attack_state, SCRIPT.AttackState.DASH)

func test_dash_duration_and_visual_cycle_are_aligned() -> void:
	var enemy := await _enemy()
	var frames := enemy.animation_sprite.sprite_frames
	assert_almost_eq(enemy.dash_duration, 0.55, 0.001)
	assert_eq(frames.get_frame_count(&"dash"), 6)
	assert_almost_eq(frames.get_animation_speed(&"dash"), 11.0, 0.001)
	assert_almost_eq(6.0 / frames.get_animation_speed(&"dash"), enemy.dash_duration, 0.02)

func test_dash_orientation_uses_direction_angle_plus_pi_for_cardinals() -> void:
	var enemy := await _enemy()
	enemy.dash_direction = Vector2.RIGHT
	enemy._enter_state(SCRIPT.AttackState.DASH)
	assert_almost_eq(enemy.animation_sprite.rotation, PI, 0.001)
	enemy.dash_direction = Vector2.DOWN
	enemy._enter_state(SCRIPT.AttackState.DASH)
	assert_almost_eq(enemy.animation_sprite.rotation, Vector2.DOWN.angle() + PI, 0.001)

func test_non_dash_states_reset_visual_rotation() -> void:
	var enemy := await _enemy()
	for state in [SCRIPT.AttackState.APPROACH, SCRIPT.AttackState.TELEGRAPH, SCRIPT.AttackState.RECOVER]:
		enemy.animation_sprite.rotation = 0.73
		enemy._enter_state(state)
		assert_almost_eq(enemy.animation_sprite.rotation, 0.0, 0.001)

func test_kamikaze_strips_load_as_128_pixel_cells_and_nearest_filtered() -> void:
	for path in STRIP_PATHS:
		var texture := load(path) as Texture2D
		assert_not_null(texture, path + " deve carregar")
		assert_eq(texture.get_height(), 128, path + " deve ter 128px de altura")
		assert_eq(texture.get_width() % 128, 0, path + " deve ser divisível em células de 128px")

	var enemy := await _enemy()
	var body := enemy.animation_sprite as AnimatedSprite2D
	assert_eq(body.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)
	var fx := FX_SCENE.instantiate() as AnimatedSprite2D
	add_child_autofree(fx)
	assert_eq(fx.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)

func test_kamikaze_collision_scale_and_regions_are_preserved() -> void:
	var enemy := await _enemy()
	var collision := enemy.get_node("CollisionShape2D") as CollisionShape2D
	var shape := collision.shape as CircleShape2D
	assert_eq(enemy.collision_layer, 4)
	assert_eq(enemy.collision_mask, 0)
	assert_almost_eq(shape.radius, 10.0, 0.001)
	assert_eq(enemy.animation_sprite.scale, Vector2(0.25, 0.25))
	var frames := enemy.animation_sprite.sprite_frames
	for index in range(6):
		var atlas := frames.get_frame_texture(&"dash", index) as AtlasTexture
		assert_not_null(atlas)
		assert_eq(atlas.region, Rect2(index * 128, 0, 128, 128))
		assert_eq(atlas.atlas.get_width(), 768)
		assert_eq(atlas.atlas.get_height(), 128)

func test_state_transitions_select_approach_telegraph_and_dash_animations() -> void:
	var enemy := await _enemy()
	enemy._enter_state(SCRIPT.AttackState.APPROACH)
	assert_eq(enemy.animation_sprite.animation, &"approach")
	enemy._enter_state(SCRIPT.AttackState.TELEGRAPH)
	assert_eq(enemy.animation_sprite.animation, &"warning")
	enemy._enter_state(SCRIPT.AttackState.DASH)
	assert_eq(enemy.animation_sprite.animation, &"dash")

func test_detonation_uses_eight_independent_128_pixel_frames() -> void:
	var fx := FX_SCENE.instantiate() as AnimatedSprite2D
	add_child_autofree(fx)
	var frames := fx.sprite_frames
	assert_eq(frames.get_frame_count(&"detonate"), 8)
	assert_false(frames.get_animation_loop(&"detonate"))
	for index in [4, 5]:
		var atlas := frames.get_frame_texture(&"detonate", index) as AtlasTexture
		assert_not_null(atlas)
		assert_eq(atlas.region, Rect2(index * 128, 0, 128, 128))
		assert_eq(atlas.atlas.get_width(), 1024)
		assert_eq(atlas.atlas.get_height(), 128)

func test_detonation_fx_frees_after_finishing_all_eight_frames() -> void:
	var fx := FX_SCENE.instantiate() as AnimatedSprite2D
	add_child(fx)
	fx.play(&"detonate")
	await get_tree().create_timer(0.47).timeout
	assert_false(is_instance_valid(fx))

func test_dash_direction_is_captured_once_without_homing() -> void:
	var enemy := await _enemy()
	var player := Node2D.new()
	add_child_autofree(player)
	enemy._player = player
	enemy.global_position = Vector2.ZERO
	player.global_position = Vector2.RIGHT * 100.0
	enemy._enter_state(SCRIPT.AttackState.TELEGRAPH)
	enemy._physics_process(0.46)
	assert_eq(enemy.attack_state, SCRIPT.AttackState.DASH)
	var captured: Vector2 = enemy.dash_direction
	player.global_position = Vector2.LEFT * 100.0
	enemy._physics_process(0.01)
	assert_eq(enemy.dash_direction, captured)
	assert_eq(enemy.velocity.normalized(), captured.normalized())

func test_death_adds_only_existing_burst_feedback() -> void:
	var enemy := await _enemy()
	var effects := Node2D.new()
	effects.add_to_group("effects")
	add_child_autofree(effects)
	enemy._effects = effects
	enemy._on_died(DamageInfo.new())
	# Duas rajadas deslocadas representam os fragmentos; a terceira e a
	# explosao normal da classe Enemy.
	assert_eq(effects.get_child_count(), 3)
	var detonation := effects.get_parent().get_node_or_null("KamikazeDetonateFx") as AnimatedSprite2D
	assert_not_null(detonation)
	assert_eq(detonation.animation, &"detonate")
	await get_tree().create_timer(0.5).timeout
	assert_false(is_instance_valid(detonation))
