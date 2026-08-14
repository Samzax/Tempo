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

func _count_offer_request(offer: RewardOffer, _player: Node) -> void:
	_offer_requests += 1
	_requested_offers.append(offer)

func before_each() -> void:
	_offer_requests = 0
	_requested_offers.clear()

func _track_node(node: Node) -> Node:
	_owned_nodes.append(node)
	return node

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
	add_child_autofree(core)
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
	add_child_autofree(core)
	await get_tree().process_frame
	var before := player.position
	core.activate()
	core.activate()
	assert_eq(core._state, CORE.State.ACTIVATABLE)
	assert_eq(player.position, before)
	assert_eq(core._generation, 0)
	core.queue_free()
	await get_tree().process_frame

func test_core_channels_twelve_ticks_then_opens_one_offer() -> void:
	var core := CORE.new()
	var chest: RewardChest = _track_node(CHEST.new()) as RewardChest
	var player: Node2D = _track_node(Node2D.new()) as Node2D
	player.position = Vector2(360, 108)
	core.configure(chest, player)
	add_child_autofree(core)
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
	add_child_autofree(core)
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
	var core := CORE.new()
	core.configure(chest, player, true)
	_track_node(core)
	var resolved := 0
	var completed := 0
	choice.offer_resolved.connect(func(_offer: RewardOffer, _refused: bool): resolved += 1)
	core.sequence_completed.connect(func(): completed += 1)
	chest.offer_requested.connect(choice.open_offer)
	add_child(choice)
	add_child(core)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(choice.visible)
	assert_eq(choice._offer, offer)
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

	var interact := InputEventAction.new()
	interact.action = &"interact"
	interact.pressed = true
	core._input(interact)
	await get_tree().process_frame
	assert_true(choice.visible)
	assert_eq(choice._offer, offer)
	assert_eq(chest.current_offer(), offer)
	assert_false(offer.claimed)
	assert_eq(_offer_requests, 0)
	assert_eq(resolved, 0)
	assert_eq(completed, 0)
	assert_eq(core._generation, 0)
	choice.hide()
