class_name RewardChest
extends Node2D
## Baú local da sala: só fica disponível após o clear e não refaz sua oferta.

signal offer_requested(offer: RewardOffer, player: Node)
signal offer_created(offer: RewardOffer)

const TreasurePricing := preload("res://scripts/loot/treasure_pricing.gd")

@export var room_controller_path: NodePath
@export var player_path: NodePath
@export var pool: ItemPoolDef
@export var sector_index: int = 0
@export var node_id: int = 0
@export var player_slot: int = 0
@export var reward_index: int = 0

var _room_controller: RoomController
var _player: Node
var _available := false
var _pending_offer: RewardOffer
var _paid_with_temporal_echoes := false
var _risk_mode := false
var _activating := false
var _activation_serial := 0
var _active_activation_token := 0
var _core_managed := false

const INTERACTION_RADIUS := 42.0
const CLICK_RADIUS := 16.0

func _ready() -> void:
	_room_controller = get_node_or_null(room_controller_path) as RoomController
	if _player == null:
		_player = get_node_or_null(player_path)
	if _room_controller == null:
		push_error("RewardChest requires a RoomController.")
		return
	_restore_pending_offer_if_possible()
	if not _core_managed:
		_room_controller.room_cleared.connect(_unlock)
	# Uma sala sem spawns pode ser limpa durante o _ready do controlador.
	if not _core_managed and _room_controller.runtime != null and _room_controller.runtime.is_cleared():
		_unlock.call_deferred()
	queue_redraw()

func _unlock() -> void:
	if not _risk_mode:
		_ensure_offer()
	_available = true
	queue_redraw()

## O nucleo usa exatamente a mesma RewardOffer, mas controla quando ela fica visivel.
func configure_core_managed() -> void:
	_core_managed = true

func unlock_for_core() -> void:
	if not _core_managed:
		return
	_ensure_offer()
	_available = true
	queue_redraw()

func current_offer() -> RewardOffer:
	return _room_controller.runtime.reward_offer if _has_live_runtime() else null

func player_node() -> Node2D:
	return _player as Node2D

func _input(event: InputEvent) -> void:
	if _core_managed:
		return
	if not _available or not _is_player_nearby():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and _is_chest_click(event.position):
		open_offer()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"interact"):
		open_offer()
		get_viewport().set_input_as_handled()

func _is_player_nearby() -> bool:
	var player_body := _player as Node2D
	return player_body != null and player_body.global_position.distance_to(global_position) <= INTERACTION_RADIUS

func _is_chest_click(viewport_position: Vector2) -> bool:
	var local_position := get_global_transform_with_canvas().affine_inverse() * viewport_position
	return local_position.length() <= CLICK_RADIUS

func open_offer() -> void:
	if _activating or not _available or not _has_live_runtime() or not _is_live(_player):
		return
	var offer := _room_controller.runtime.reward_offer
	if _risk_mode:
		_open_risk_offer(offer)
		return
	if not _is_live(offer) or offer.claimed:
		return
	if offer.options.is_empty():
		offer.claimed = true
		offer.claimed_item_id = &""
		queue_redraw()
		return
	offer_requested.emit(offer, _player)

func configure(player: Node, new_sector_index: int, new_node_id: int, new_player_slot: int, new_reward_index: int, new_pool: ItemPoolDef, existing_offer: RewardOffer, new_paid_with_temporal_echoes: bool = false, new_is_risk_mode: bool = false) -> void:
	_player = player
	sector_index = new_sector_index
	node_id = new_node_id
	player_slot = new_player_slot
	reward_index = new_reward_index
	pool = new_pool
	_paid_with_temporal_echoes = new_paid_with_temporal_echoes
	_risk_mode = new_is_risk_mode
	if _is_live(existing_offer):
		_pending_offer = existing_offer
		_restore_pending_offer_if_possible()

func _restore_pending_offer_if_possible() -> void:
	if not _is_live(_pending_offer) or not _has_live_runtime() or _room_controller.runtime.reward_offer != null:
		return
	_room_controller.runtime.reward_offer = _pending_offer

func _ensure_offer() -> void:
	if _risk_mode or not _has_live_runtime() or _room_controller.runtime.reward_offer != null or not _is_live(_player):
		return
	var offer := LootRoller.roll_offer(pool, RunManager.seed_value, sector_index, node_id, player_slot, reward_index, _player.get_luck(), Callable(_player, &"can_acquire_item"))
	if _paid_with_temporal_echoes:
		offer.paid_with_temporal_echoes = true
		for item in offer.options:
			offer.option_costs.append(TreasurePricing.cost_for(item))
	_room_controller.runtime.reward_offer = offer
	offer_created.emit(offer)

func _open_risk_offer(offer: Variant) -> void:
	if _activating:
		return
	if offer == null:
		_activate_risk_offer()
		return
	var snapshot_controller := _room_controller
	var snapshot_runtime: Variant = snapshot_controller.runtime if _is_live(snapshot_controller) else null
	var snapshot_player: Variant = _player
	var snapshot_pool: Variant = pool
	var snapshot_sector_index := sector_index
	var snapshot_node_id := node_id
	var snapshot_player_slot := player_slot
	var snapshot_reward_index := reward_index
	var snapshot_seed := RunManager.seed_value
	var allowed_ids := _risk_allowed_ids(snapshot_pool)
	if not _risk_snapshot_is_current(snapshot_controller, snapshot_runtime, snapshot_player, snapshot_pool, snapshot_sector_index, snapshot_node_id, snapshot_player_slot, snapshot_reward_index, snapshot_seed, offer):
		return
	if not _is_live(offer) or offer.claimed or not _is_valid_risk_offer(offer, snapshot_seed, snapshot_sector_index, snapshot_node_id, snapshot_player_slot, snapshot_reward_index, snapshot_pool.id, allowed_ids):
		return
	var token := _begin_activation()
	call_deferred("_release_activation", token)
	offer_requested.emit(offer, snapshot_player)

func _activate_risk_offer() -> void:
	if _activating:
		return
	# Eligibility can invoke user code, so hold the lock before taking any external path.
	var token := _begin_activation()
	var snapshot_controller := _room_controller
	var snapshot_runtime: Variant = snapshot_controller.runtime if _is_live(snapshot_controller) else null
	var snapshot_player: Variant = _player
	var snapshot_pool: Variant = pool
	var snapshot_sector_index := sector_index
	var snapshot_node_id := node_id
	var snapshot_player_slot := player_slot
	var snapshot_reward_index := reward_index
	var snapshot_seed := RunManager.seed_value
	var allowed_ids := _risk_allowed_ids(snapshot_pool)
	if not _is_live(snapshot_controller) or not _is_live(snapshot_runtime) or not _is_live(snapshot_player) or not _is_live(snapshot_pool):
		_release_activation(token)
		return
	if snapshot_runtime.reward_offer != null or snapshot_pool.id != &"risk" or allowed_ids.is_empty() or not snapshot_player.has_method(&"get_luck") or not snapshot_player.has_method(&"can_acquire_item") or not snapshot_player.has_method(&"try_spend_health"):
		_release_activation(token)
		return
	var eligibility := func(item: Variant) -> bool:
		return _is_live(self) and _is_current_activation(token) and _is_live(snapshot_player) and _is_live(item) and (item.rarity == ItemDef.Rarity.RARE or item.rarity == ItemDef.Rarity.LEGENDARY) and bool(snapshot_player.call(&"can_acquire_item", item))
	if not _risk_snapshot_is_current(snapshot_controller, snapshot_runtime, snapshot_player, snapshot_pool, snapshot_sector_index, snapshot_node_id, snapshot_player_slot, snapshot_reward_index, snapshot_seed, null):
		_release_activation(token)
		return
	var luck := float(snapshot_player.call(&"get_luck"))
	if not _risk_snapshot_is_current(snapshot_controller, snapshot_runtime, snapshot_player, snapshot_pool, snapshot_sector_index, snapshot_node_id, snapshot_player_slot, snapshot_reward_index, snapshot_seed, null):
		_release_activation(token)
		return
	var candidate := LootRoller.roll_offer(snapshot_pool, snapshot_seed, snapshot_sector_index, snapshot_node_id, snapshot_player_slot, snapshot_reward_index, luck, eligibility)
	if not _is_live(snapshot_controller) or not _is_live(snapshot_runtime) or not _is_live(snapshot_player) or not _is_live(snapshot_pool):
		_release_activation(token)
		return
	if not _is_valid_risk_offer(candidate, snapshot_seed, snapshot_sector_index, snapshot_node_id, snapshot_player_slot, snapshot_reward_index, snapshot_pool.id, allowed_ids):
		_release_activation(token)
		return
	if not _risk_snapshot_is_current(snapshot_controller, snapshot_runtime, snapshot_player, snapshot_pool, snapshot_sector_index, snapshot_node_id, snapshot_player_slot, snapshot_reward_index, snapshot_seed, null):
		_release_activation(token)
		return
	candidate.paid_with_temporal_echoes = false
	candidate.option_costs.clear()
	if not bool(snapshot_player.call(&"try_spend_health", 1.0, 1.0)):
		_release_activation(token)
		return
	if not _risk_snapshot_is_current(snapshot_controller, snapshot_runtime, snapshot_player, snapshot_pool, snapshot_sector_index, snapshot_node_id, snapshot_player_slot, snapshot_reward_index, snapshot_seed, null):
		_release_activation(token)
		return
	snapshot_runtime.reward_offer = candidate
	var deferred_allowed_ids := allowed_ids.duplicate()
	call_deferred("_continue_risk_activation", token, snapshot_controller, snapshot_runtime, snapshot_player, snapshot_pool, snapshot_sector_index, snapshot_node_id, snapshot_player_slot, snapshot_reward_index, snapshot_seed, deferred_allowed_ids, candidate)
	offer_created.emit(candidate)

func _continue_risk_activation(token: int, snapshot_controller: Variant, snapshot_runtime: Variant, snapshot_player: Variant, snapshot_pool: Variant, snapshot_sector_index: int, snapshot_node_id: int, snapshot_player_slot: int, snapshot_reward_index: int, snapshot_seed: int, allowed_ids: Dictionary, candidate: Variant) -> void:
	if not _is_live(self) or not _is_current_activation(token):
		return
	if not _risk_snapshot_is_current(snapshot_controller, snapshot_runtime, snapshot_player, snapshot_pool, snapshot_sector_index, snapshot_node_id, snapshot_player_slot, snapshot_reward_index, snapshot_seed, candidate) or not _is_live(candidate) or candidate.claimed or not _is_valid_risk_offer(candidate, snapshot_seed, snapshot_sector_index, snapshot_node_id, snapshot_player_slot, snapshot_reward_index, snapshot_pool.id, allowed_ids):
		_release_activation(token)
		return
	call_deferred("_release_activation", token)
	offer_requested.emit(candidate, snapshot_player)

func _risk_snapshot_is_current(snapshot_controller: Variant, snapshot_runtime: Variant, snapshot_player: Variant, snapshot_pool: Variant, snapshot_sector_index: int, snapshot_node_id: int, snapshot_player_slot: int, snapshot_reward_index: int, snapshot_seed: int, expected_offer: Variant) -> bool:
	return _is_live(self) and _is_live(snapshot_controller) and _is_live(snapshot_runtime) and _is_live(snapshot_player) and _is_live(snapshot_pool) and _room_controller == snapshot_controller and snapshot_controller.runtime == snapshot_runtime and _player == snapshot_player and pool == snapshot_pool and sector_index == snapshot_sector_index and node_id == snapshot_node_id and player_slot == snapshot_player_slot and reward_index == snapshot_reward_index and RunManager.seed_value == snapshot_seed and snapshot_runtime.reward_offer == expected_offer

func _risk_allowed_ids(snapshot_pool: Variant) -> Dictionary:
	var allowed_ids: Dictionary = {}
	if not _is_live(snapshot_pool) or snapshot_pool.id != &"risk":
		return allowed_ids
	for entry in snapshot_pool.entries:
		if not _is_live(entry) or entry.base_weight <= 0.0:
			continue
		var item: Variant = entry.item
		if not _is_live(item) or item.id.is_empty() or not item.validate_content().is_empty():
			continue
		if item.rarity == ItemDef.Rarity.RARE or item.rarity == ItemDef.Rarity.LEGENDARY:
			allowed_ids[item.id] = true
	return allowed_ids

func _is_valid_risk_offer(offer: Variant, expected_seed: int, expected_sector_index: int, expected_node_id: int, expected_player_slot: int, expected_reward_index: int, expected_pool_id: StringName, allowed_ids: Dictionary) -> bool:
	if not _is_live(offer) or expected_pool_id != &"risk" or offer.run_seed != expected_seed or offer.pool_id != expected_pool_id or offer.sector_index != expected_sector_index or offer.node_id != expected_node_id or offer.player_slot != expected_player_slot or offer.reward_index != expected_reward_index or offer.options.size() != 3:
		return false
	var item_ids: Dictionary = {}
	for item in offer.options:
		if not _is_live(item) or item.id.is_empty() or item_ids.has(item.id) or not allowed_ids.has(item.id):
			return false
		if item.rarity != ItemDef.Rarity.RARE and item.rarity != ItemDef.Rarity.LEGENDARY:
			return false
		item_ids[item.id] = true
	return true

func _begin_activation() -> int:
	_activation_serial += 1
	_active_activation_token = _activation_serial
	_activating = true
	return _active_activation_token

func _is_current_activation(token: int) -> bool:
	return _activating and token == _active_activation_token

func _release_activation(token: int) -> void:
	if token != _active_activation_token:
		return
	_active_activation_token = 0
	_activating = false

func _has_live_runtime() -> bool:
	return _is_live(_room_controller) and _is_live(_room_controller.runtime)

func _is_live(value: Variant) -> bool:
	if typeof(value) != TYPE_OBJECT or not is_instance_valid(value):
		return false
	if value is Node and value.is_queued_for_deletion():
		return false
	return true

func _draw() -> void:
	if not _available or _core_managed:
		return
	var claimed := _room_controller != null and _room_controller.runtime != null and _room_controller.runtime.reward_offer != null and _room_controller.runtime.reward_offer.claimed
	var color := Color(0.32, 0.72, 0.42) if not claimed else Color(0.28, 0.32, 0.38)
	draw_rect(Rect2(-14, -9, 28, 18), Color(0.03, 0.06, 0.1, 0.95), true)
	draw_rect(Rect2(-12, -7, 24, 14), color, true)
	draw_line(Vector2(-12, 0), Vector2(12, 0), Color(0.9, 0.95, 0.7), 1.0)
	draw_string(ThemeDB.fallback_font, Vector2(-25, 25), "BAU  [Enter]", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.85, 1, 0.8))
