class_name RewardChest
extends Node2D
## Baú local da sala: só fica disponível após o clear e não refaz sua oferta.

signal offer_requested(offer: RewardOffer, player: Node)
signal offer_created(offer: RewardOffer)

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
	_room_controller.room_cleared.connect(_unlock)
	# Uma sala sem spawns pode ser limpa durante o _ready do controlador.
	if _room_controller.runtime != null and _room_controller.runtime.is_cleared():
		_unlock.call_deferred()
	queue_redraw()

func _unlock() -> void:
	_ensure_offer()
	_available = true
	queue_redraw()

func _input(event: InputEvent) -> void:
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
	if not _available or _room_controller == null or _room_controller.runtime == null or _player == null:
		return
	var offer := _room_controller.runtime.reward_offer
	if offer == null or offer.claimed:
		return
	if offer.options.is_empty():
		offer.claimed = true
		offer.claimed_item_id = &""
		queue_redraw()
		return
	offer_requested.emit(offer, _player)

func configure(player: Node, new_sector_index: int, new_node_id: int, new_player_slot: int, new_reward_index: int, new_pool: ItemPoolDef, existing_offer: RewardOffer) -> void:
	_player = player
	sector_index = new_sector_index
	node_id = new_node_id
	player_slot = new_player_slot
	reward_index = new_reward_index
	pool = new_pool
	if existing_offer != null:
		_pending_offer = existing_offer
	_restore_pending_offer_if_possible()

func _restore_pending_offer_if_possible() -> void:
	if _pending_offer == null or _room_controller == null or _room_controller.runtime == null or _room_controller.runtime.reward_offer != null:
		return
	_room_controller.runtime.reward_offer = _pending_offer

func _ensure_offer() -> void:
	if _room_controller == null or _room_controller.runtime == null or _room_controller.runtime.reward_offer != null or _player == null:
		return
	_room_controller.runtime.reward_offer = LootRoller.roll_offer(pool, RunManager.seed_value, sector_index, node_id, player_slot, reward_index, _player.get_luck(), Callable(_player, &"can_acquire_item"))
	offer_created.emit(_room_controller.runtime.reward_offer)

func _draw() -> void:
	if not _available:
		return
	var claimed := _room_controller != null and _room_controller.runtime != null and _room_controller.runtime.reward_offer != null and _room_controller.runtime.reward_offer.claimed
	var color := Color(0.32, 0.72, 0.42) if not claimed else Color(0.28, 0.32, 0.38)
	draw_rect(Rect2(-14, -9, 28, 18), Color(0.03, 0.06, 0.1, 0.95), true)
	draw_rect(Rect2(-12, -7, 24, 14), color, true)
	draw_line(Vector2(-12, 0), Vector2(12, 0), Color(0.9, 0.95, 0.7), 1.0)
	draw_string(ThemeDB.fallback_font, Vector2(-25, 25), "BAU  [Enter]", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.85, 1, 0.8))
