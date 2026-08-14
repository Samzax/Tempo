extends GutTest

const CORE := preload("res://scripts/rooms/sector3_core_presentation.gd")
const CHEST := preload("res://scripts/loot/reward_chest.gd")
const ITEM_CHOICE := preload("res://scripts/ui/item_choice.gd")

class ChoicePlayer extends Node2D:
	func can_acquire_item(_item: ItemDef) -> bool:
		return true

	func acquire_item(_item: ItemDef) -> bool:
		return true

var _owned_nodes: Array[Node] = []
var _offer_requests := 0
var _requested_offers: Array[RewardOffer] = []

func _make_visual_player() -> CharacterBody2D:
	var player := CharacterBody2D.new()
	player.name = "PlayerDouble"
	player.position = Vector2(360, 108)
	player.scale = Vector2(0.081, 0.081)
	player.rotation = 0.17
	player.collision_layer = 4
	player.collision_mask = 8
	var visual_root := Node2D.new()
	visual_root.name = "VisualRoot"
	visual_root.position = Vector2(7, -4)
	visual_root.rotation = -0.31
	visual_root.scale = Vector2(1.35, 0.82)
	player.add_child(visual_root)
	var visual := AnimatedSprite2D.new()
	visual.name = "AnimatedSprite2D"
	var frames := SpriteFrames.new()
	var image := Image.create(4, 6, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	frames.add_frame(&"default", texture)
	visual.sprite_frames = frames
	visual.animation = &"default"
	visual.frame = 0
	visual.offset = Vector2(3, -5)
	visual.flip_h = true
	visual.flip_v = true
	visual.rotation = 0.23
	visual.position = Vector2(-2, 6)
	visual.modulate = Color(0.7, 0.8, 1.0, 0.9)
	visual.self_modulate = Color(0.9, 1.0, 0.8, 0.95)
	visual_root.add_child(visual)
	return player

func _count_offer_request(offer: RewardOffer, _player: Node) -> void:
	_offer_requests += 1
	_requested_offers.append(offer)

func before_each() -> void:
	_offer_requests = 0
	_requested_offers.clear()

func _track_node(node: Node) -> Node:
	_owned_nodes.append(node)
	return node

func _track_core(core: Node) -> Node:
	add_child(core)
	return _track_node(core)

func after_each() -> void:
	for node in _owned_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_owned_nodes.clear()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

func test_core_counts_only_confirmed_deaths_and_caps_at_eight() -> void:
	var core := CORE.new()
	var chest: RewardChest = _track_node(CHEST.new()) as RewardChest
	var player: Node2D = _track_node(Node2D.new()) as Node2D
	core.configure(chest, player)
	_track_core(core)
	await get_tree().process_frame
	for index in 20:
		core.record_enemy_resolved(Enemy.ResolveReason.CULLED)
	assert_eq(core._kills, 0)
	for index in 12:
		core.record_enemy_resolved(Enemy.ResolveReason.DIED)
	assert_eq(core._kills, 8)

func test_core_activation_is_unique_and_does_not_move_room_actors() -> void:
	var core := CORE.new()
	var chest: RewardChest = _track_node(CHEST.new()) as RewardChest
	var player: Node2D = _track_node(Node2D.new()) as Node2D
	player.position = Vector2(120, 300)
	core.configure(chest, player)
	_track_core(core)
	await get_tree().process_frame
	var before := player.position
	core.activate()
	core.activate()
	assert_eq(core._state, CORE.State.ACTIVATABLE)
	assert_eq(player.position, before)
	assert_eq(core._generation, 0)
	core.queue_free()
	await get_tree().process_frame

func test_prompt_requires_activatable_state_and_nearby_player() -> void:
	var core := CORE.new()
	var chest: RewardChest = _track_node(CHEST.new()) as RewardChest
	var player: Node2D = _track_node(Node2D.new()) as Node2D
	core.configure(chest, player)
	_track_core(core)
	await get_tree().process_frame

	core._state = CORE.State.ACTIVATABLE
	player.global_position = Vector2(360, 108)
	core._refresh_prompt()
	assert_true(core._prompt.visible)
	assert_eq(core._prompt.text, "ATIVAR  [Enter]")

	player.global_position = Vector2(360 + CORE.INTERACTION_RADIUS + 1.0, 108)
	core._refresh_prompt()
	assert_false(core._prompt.visible)
	for state in [CORE.State.CHANNELING, CORE.State.OFFER_PENDING, CORE.State.RELEASING, CORE.State.FINISHED]:
		core._state = state
		core._refresh_prompt()
		assert_false(core._prompt.visible)

func test_afterimages_are_discrete_during_approved_mid_lifetime_window_and_clean_up() -> void:
	var core := CORE.new()
	var chest: RewardChest = _track_node(CHEST.new()) as RewardChest
	var player := _make_visual_player()
	_track_node(player)
	add_child(player)
	core.configure(chest, player)
	_track_core(core)
	await get_tree().process_frame
	var visual := player.get_node("VisualRoot/AnimatedSprite2D") as AnimatedSprite2D
	core._spawn_afterimage()
	assert_eq(core._afterimages.size(), 1)
	var ghost := core._afterimages.back() as AnimatedSprite2D
	var ghost_instance_id := ghost.get_instance_id()
	var tween := core._afterimage_tweens[ghost_instance_id] as Tween
	assert_true(is_instance_valid(tween))
	tween.pause()
	assert_true(is_instance_valid(ghost))
	_assert_transform_almost_eq(ghost.global_transform, visual.global_transform)
	assert_eq(ghost.offset, visual.offset)
	assert_eq(ghost.flip_h, visual.flip_h)
	assert_eq(ghost.flip_v, visual.flip_v)
	assert_eq(ghost.sprite_frames, visual.sprite_frames)
	assert_true(ghost.visible)
	assert_true(tween.custom_step(0.115))
	assert_eq(core._afterimages.size(), 1)
	assert_true(is_instance_valid(ghost))
	assert_eq(core._afterimages.back().get_instance_id(), ghost_instance_id)
	assert_true(ghost.visible)
	var effective_alpha := ghost.modulate.a * ghost.self_modulate.a
	assert_true(effective_alpha >= 0.02, "ghost remains visible in the approved 110–115ms window")
	assert_true(effective_alpha < 0.10, "ghost is visually discrete in the approved window")
	# Completion may discard the tween synchronously from its callback; do not
	# assert its return value as an ordering contract.
	tween.custom_step(0.05)
	for _callback_step in 3:
		if is_instance_valid(tween):
			tween.custom_step(0.001)
	assert_false(ghost.visible, "expired ghost is hidden before queue_free")
	assert_eq(core._afterimages.size(), 0)
	assert_eq(core._afterimage_tweens.size(), 0)
	await get_tree().process_frame
	assert_false(is_instance_valid(ghost))

func test_afterimage_burst_replaces_oldest_safely_without_exceeding_one() -> void:
	var core := CORE.new()
	var chest: RewardChest = _track_node(CHEST.new()) as RewardChest
	var player := _make_visual_player()
	_track_node(player)
	add_child(player)
	core.configure(chest, player)
	_track_core(core)
	await get_tree().process_frame
	core._spawn_afterimage()
	var first: Node2D = core._afterimages.back()
	core._spawn_afterimage()
	assert_false(first.visible, "old ghost is hidden before the replacement is added")
	assert_eq(core._afterimages.size(), 1)
	var second: Node2D = core._afterimages.back()
	core._spawn_afterimage()
	assert_false(second.visible, "old ghost is hidden before the replacement is added")
	assert_eq(core._afterimages.size(), 1)
	assert_true(is_instance_valid(core._afterimages.back()))
	var current_tween := core._afterimage_tweens[core._afterimages.back().get_instance_id()] as Tween
	var current_ghost: Node2D = core._afterimages.back()
	current_tween.pause()
	current_tween.custom_step(0.17)
	assert_false(current_ghost.visible, "expired ghost is hidden before queue_free")
	await get_tree().process_frame
	assert_false(is_instance_valid(first))
	assert_false(is_instance_valid(second))
	assert_eq(core._afterimages.size(), 0)
	assert_eq(core._afterimage_tweens.size(), 0)

func test_real_ejection_spawns_at_steps_two_four_six_and_cleans_up() -> void:
	var core := CORE.new()
	var chest: RewardChest = _track_node(CHEST.new()) as RewardChest
	var player := _make_visual_player()
	_track_node(player)
	add_child(player)
	core.configure(chest, player)
	_track_core(core)
	await get_tree().process_frame
	core._state = CORE.State.RELEASING
	core._generation = 1
	var observed_origins: Array[Vector2] = []
	var had_ghost := false
	var last_ghost_origin := Vector2.INF
	var source := player.get_node("VisualRoot/AnimatedSprite2D") as AnimatedSprite2D
	var initial_x := player.global_position.x
	core.call("_run_ejection", 1)
	for _sample in 15:
		await wait_seconds(0.04)
		var current := core._afterimages.size()
		if current > 0 and core._afterimages.back().global_position != last_ghost_origin:
			had_ghost = true
			observed_origins.append(core._afterimages.back().global_position)
			var ghost := core._afterimages.back() as AnimatedSprite2D
			_assert_basis_almost_eq(ghost.global_transform, source.global_transform)
			assert_true(ghost.visible)
			last_ghost_origin = ghost.global_position
		assert_true(current <= 1)
	assert_eq(observed_origins.size(), 3)
	assert_true(player.global_position.x > initial_x)
	assert_almost_eq(player.global_position.x, initial_x + 190.0, 1.0)
	assert_true(absf(player.global_position.y - 108.0) <= 2.0)
	await wait_seconds(0.12 + 0.08)
	assert_eq(core._afterimages.size(), 0)

	var core_ref: WeakRef = weakref(core)
	core.queue_free()
	await get_tree().process_frame
	assert_false(is_instance_valid(core_ref.get_ref()))

func _assert_transform_almost_eq(actual: Transform2D, expected: Transform2D) -> void:
	assert_almost_eq(actual.origin.x, expected.origin.x, 0.001)
	assert_almost_eq(actual.origin.y, expected.origin.y, 0.001)
	assert_almost_eq(actual.x.x, expected.x.x, 0.001)
	assert_almost_eq(actual.x.y, expected.x.y, 0.001)
	assert_almost_eq(actual.y.x, expected.y.x, 0.001)
	assert_almost_eq(actual.y.y, expected.y.y, 0.001)

func _assert_basis_almost_eq(actual: Transform2D, expected: Transform2D) -> void:
	assert_almost_eq(actual.x.x, expected.x.x, 0.001)
	assert_almost_eq(actual.x.y, expected.x.y, 0.001)
	assert_almost_eq(actual.y.x, expected.y.x, 0.001)
	assert_almost_eq(actual.y.y, expected.y.y, 0.001)

func test_core_channels_twelve_ticks_then_opens_one_offer() -> void:
	var core := CORE.new()
	var chest: RewardChest = _track_node(CHEST.new()) as RewardChest
	var player: Node2D = _track_node(Node2D.new()) as Node2D
	player.position = Vector2(360, 108)
	core.configure(chest, player)
	_track_core(core)
	await get_tree().process_frame
	for index in 8:
		core.record_enemy_resolved(Enemy.ResolveReason.DIED)
	core.activate()
	var started := Time.get_ticks_msec()
	core._begin_channel()
	await wait_seconds(1.08)
	assert_true(Time.get_ticks_msec() - started >= 900)
	assert_eq(core._state, CORE.State.OFFER_PENDING)
	assert_eq(core._generation, 1)
	assert_eq(chest.current_offer(), null)

func test_release_ejection_restores_player_and_persists_plane_offsets() -> void:
	var core := CORE.new()
	var chest: RewardChest = _track_node(CHEST.new()) as RewardChest
	var player: CharacterBody2D = _track_node(CharacterBody2D.new()) as CharacterBody2D
	player.position = Vector2(360, 108)
	player.collision_layer = 4
	player.collision_mask = 8
	player.set_physics_process(false)
	core.configure(chest, player)
	_track_core(core)
	await get_tree().process_frame
	core._state = CORE.State.RELEASING
	core._generation = 1
	core._run_ejection(1)
	await wait_seconds(0.65)
	assert_eq(core._plane_ejection_offsets, [-2.0, -8.0, -18.0])
	assert_eq(player.global_position.x, 550.0)
	assert_true(absf(player.global_position.y - 108.0) <= 2.0)
	assert_eq(player.collision_layer, 4)
	assert_eq(player.collision_mask, 8)
	assert_false(player.is_physics_processing())

func test_teardown_during_ejection_restores_once_and_late_coroutine_cannot_overwrite() -> void:
	var core := CORE.new()
	var chest: RewardChest = _track_node(CHEST.new()) as RewardChest
	var player: CharacterBody2D = _track_node(CharacterBody2D.new()) as CharacterBody2D
	player.position = Vector2(360, 108)
	player.collision_layer = 4
	player.collision_mask = 8
	player.set_physics_process(true)
	core.configure(chest, player)
	_track_core(core)
	await get_tree().process_frame
	core._state = CORE.State.RELEASING
	core._generation = 1
	core._run_ejection(1)
	await wait_seconds(0.10)
	assert_true(core._ejection_restore_pending)
	assert_eq(player.collision_layer, 0)
	assert_false(player.is_physics_processing())
	core._exit_tree()
	assert_eq(player.collision_layer, 4)
	assert_eq(player.collision_mask, 8)
	assert_true(player.is_physics_processing())
	player.collision_layer = 32
	player.collision_mask = 64
	player.set_physics_process(false)
	await wait_seconds(0.60)
	assert_eq(player.collision_layer, 32)
	assert_eq(player.collision_mask, 64)
	assert_false(player.is_physics_processing())
	assert_false(is_instance_valid(core._ejection_player))
	assert_false(core._ejection_restore_pending)
	assert_eq(core._player_collision_layer, 0)
	assert_eq(core._player_collision_mask, 0)
	assert_eq(core._afterimages.size(), 0)
	assert_eq(core._afterimage_tweens.size(), 0)
	core.queue_free()

func test_sector3_core_wires_chest_as_core_managed() -> void:
	var room: Node = _track_node(preload("res://scenes/rooms/room.tscn").instantiate())
	var def := preload("res://scripts/rooms/room_def.gd").new()
	def.transition_profile = &"sector3_upper_transition"
	def.environment_profile = &"sector3_upper_core"
	var chest := room.get_node("RewardChest") as RewardChest
	var player: Node2D = _track_node(Node2D.new()) as Node2D
	player.name = "Player"
	room.add_child(player)
	chest.configure(player, 2, 23, 0, 0, preload("res://resources/loot/treasure_pool.tres"), null, true)
	room.get_node("RoomController").room_def = def
	add_child_autofree(room)
	await get_tree().process_frame
	room.get_node("RoomController")._apply_sector3_core()
	await get_tree().process_frame
	assert_true(chest._core_managed, "core offer must be owned by the nucleus flow")

func test_core_managed_chest_ignores_own_mouse_and_interact_but_normal_chest_opens() -> void:
	var room: Node = _track_node(preload("res://scenes/rooms/room.tscn").instantiate())
	var def := preload("res://scripts/rooms/room_def.gd").new()
	var chest := room.get_node("RewardChest") as RewardChest
	var player: Node2D = _track_node(Node2D.new()) as Node2D
	room.add_child(player)
	def.finite_spawn_count = 0
	room.get_node("RoomController").room_def = def
	add_child_autofree(room)
	await get_tree().process_frame
	chest.configure(player, 0, 1, 0, 0, preload("res://resources/loot/treasure_pool.tres"), null)
	var offer := RewardOffer.new()
	offer.options = [preload("res://resources/items/vinganca.tres")]
	chest.configure(player, 0, 1, 0, 0, preload("res://resources/loot/treasure_pool.tres"), offer)
	chest.configure_core_managed()
	chest.offer_requested.connect(_count_offer_request)
	assert_eq(chest.current_offer(), offer)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = chest.global_position
	player.global_position = chest.global_position
	chest._input(click)
	var action := InputEventAction.new()
	action.action = &"interact"
	action.pressed = true
	chest._input(action)
	assert_eq(_offer_requests, 0)
	chest.unlock_for_core()
	chest.open_offer()
	assert_eq(_offer_requests, 1)
	assert_eq(_requested_offers[0], offer)
	assert_eq(chest.current_offer(), offer)
	chest._core_managed = false
	chest._input(click)
	assert_eq(_offer_requests, 2)
	assert_eq(_requested_offers[1], offer)

func test_completed_revisit_reopens_same_unclaimed_offer_and_finishes_claimed_without_signals() -> void:
	var room: Node = _track_node(preload("res://scenes/rooms/room.tscn").instantiate())
	var def := preload("res://scripts/rooms/room_def.gd").new()
	var chest := room.get_node("RewardChest") as RewardChest
	var player: Node2D = _track_node(Node2D.new()) as Node2D
	room.add_child(player)
	room.get_node("RoomController").room_def = def
	add_child_autofree(room)
	await get_tree().process_frame
	chest.configure(player, 0, 23, 0, 0, preload("res://resources/loot/treasure_pool.tres"), null)
	var offer := RewardOffer.new()
	offer.options = [preload("res://resources/items/vinganca.tres")]
	chest.configure(player, 0, 23, 0, 0, preload("res://resources/loot/treasure_pool.tres"), offer)
	chest.configure_core_managed()
	chest.offer_requested.connect(_count_offer_request)
	var core := CORE.new()
	core.configure(chest, player, true)
	_track_node(core)
	core.sequence_completed.connect(func(): _offer_requests += 100)
	add_child(core)
	await get_tree().process_frame
	assert_eq(core._state, CORE.State.OFFER_PENDING)
	assert_eq(chest.current_offer(), offer)
	assert_eq(_offer_requests, 1)
	assert_eq(_requested_offers[0], offer)
	core.queue_free()
	await get_tree().process_frame
	var reopened_requests := _offer_requests
	offer.claimed = true
	var finished := CORE.new()
	finished.configure(chest, player, true)
	_track_node(finished)
	add_child(finished)
	await get_tree().process_frame
	assert_eq(finished._state, CORE.State.FINISHED)
	assert_false(finished._state_sprite.visible)
	assert_false(finished._prompt.visible)
	assert_eq(_offer_requests, reopened_requests)
	assert_eq(_requested_offers.size(), 1)

func test_core_managed_item_choice_escape_hides_without_resolving_and_reopens_same_offer() -> void:
	var room: Node = _track_node(preload("res://scenes/rooms/room.tscn").instantiate())
	var def := preload("res://scripts/rooms/room_def.gd").new()
	var chest := room.get_node("RewardChest") as RewardChest
	var player: Node2D = _track_node(ChoicePlayer.new()) as Node2D
	player.position = Vector2(360, 108)
	room.add_child(player)
	room.get_node("RoomController").room_def = def
	add_child_autofree(room)
	await get_tree().process_frame
	chest.configure(player, 0, 31, 0, 0, preload("res://resources/loot/treasure_pool.tres"), null)
	var offer := RewardOffer.new()
	offer.options = [preload("res://resources/items/vinganca.tres")]
	chest.configure(player, 0, 31, 0, 0, preload("res://resources/loot/treasure_pool.tres"), offer)
	chest.configure_core_managed()
	var choice := _track_node(ITEM_CHOICE.new()) as ItemChoice
	var hidden_ancestor := Control.new()
	hidden_ancestor.name = "HiddenOfferAncestor"
	hidden_ancestor.hide()
	_track_node(hidden_ancestor)
	var core := CORE.new()
	core.configure(chest, player, true)
	_track_node(core)
	var resolved := 0
	var completed := 0
	choice.offer_resolved.connect(func(_offer: RewardOffer, _refused: bool): resolved += 1)
	core.sequence_completed.connect(func(): completed += 1)
	chest.offer_requested.connect(choice.open_offer)
	add_child(hidden_ancestor)
	hidden_ancestor.add_child(choice)
	add_child(core)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(choice.visible)
	assert_false(choice.is_visible_in_tree())
	assert_eq(choice._offer, offer)
	core._refresh_prompt()
	assert_true(core._prompt.visible, "OFERTA prompt appears when ItemChoice is hidden by an ancestor")
	hidden_ancestor.show()
	core._refresh_prompt()
	assert_true(choice.is_visible_in_tree())
	assert_false(core._prompt.visible, "OFERTA prompt is hidden while ItemChoice is visible in the tree")
	assert_false(offer.claimed)
	assert_eq(resolved, 0)
	assert_eq(completed, 0)

	var cancel := InputEventAction.new()
	cancel.action = &"ui_cancel"
	cancel.pressed = true
	choice._unhandled_input(cancel)
	await get_tree().process_frame
	assert_false(choice.visible)
	assert_false(offer.claimed)
	assert_eq(resolved, 0)
	assert_eq(completed, 0)
	assert_eq(core._state, CORE.State.OFFER_PENDING)
	assert_eq(core._generation, 0)
	core._refresh_prompt()
	assert_true(core._prompt.visible)
	assert_eq(core._prompt.text, "OFERTA  [Enter]")
	player.global_position = Vector2(360 + CORE.INTERACTION_RADIUS + 1.0, 108)
	core._refresh_prompt()
	assert_false(core._prompt.visible)
	player.global_position = Vector2(360, 108)
	core._refresh_prompt()
	assert_true(core._prompt.visible)

	var interact := InputEventAction.new()
	interact.action = &"interact"
	interact.pressed = true
	core._input(interact)
	await get_tree().process_frame
	assert_true(choice.visible)
	assert_true(choice.is_visible_in_tree())
	assert_eq(choice._offer, offer)
	assert_eq(chest.current_offer(), offer)
	assert_false(offer.claimed)
	assert_eq(_offer_requests, 0)
	assert_eq(resolved, 0)
	assert_eq(completed, 0)
	assert_eq(core._generation, 0)
	core._refresh_prompt()
	assert_false(core._prompt.visible, "reopened ItemChoice hides the offer prompt")
	choice.hide()

func test_offer_ui_visibility_traverses_real_canvas_layer_hierarchy() -> void:
	var core := CORE.new()
	var chest: RewardChest = _track_node(CHEST.new()) as RewardChest
	var player: Node2D = _track_node(Node2D.new()) as Node2D
	player.position = Vector2(360, 108)
	core.configure(chest, player)
	_track_node(core)
	var layer := CanvasLayer.new()
	var ancestor := Control.new()
	var choice: ItemChoice = ITEM_CHOICE.new() as ItemChoice
	_track_node(layer)
	_track_node(ancestor)
	_track_node(choice)
	add_child(layer)
	layer.add_child(ancestor)
	ancestor.add_child(choice)
	add_child(core)
	await get_tree().process_frame

	core._state = CORE.State.OFFER_PENDING
	layer.visible = false
	choice.visible = true
	core._refresh_prompt()
	assert_false(core._has_visible_offer_ui(layer), "hidden CanvasLayer makes the offer UI unavailable")
	assert_true(core._prompt.visible, "hidden CanvasLayer shows the OFERTA prompt")

	layer.visible = true
	ancestor.visible = true
	core._refresh_prompt()
	assert_true(core._has_visible_offer_ui(layer), "visible CanvasLayer and controls expose the offer UI")
	assert_false(core._prompt.visible, "visible offer UI hides the OFERTA prompt")

	ancestor.visible = false
	core._refresh_prompt()
	assert_false(core._has_visible_offer_ui(layer), "hidden Control ancestor hides the offer UI")
	assert_true(core._prompt.visible, "hidden Control ancestor shows the OFERTA prompt")

	ancestor.visible = true
	ancestor.remove_child(choice)
	core._refresh_prompt()
	assert_false(core._has_visible_offer_ui(layer), "removed ItemChoice is not an offer UI")
	assert_true(core._prompt.visible, "removed ItemChoice shows the OFERTA prompt")
