class_name RegenteDosEcos
extends Enemy
## Infraestrutura de movimento do chefe. Ataques, fases, drones e efeitos
## pertencem a camadas futuras; esta classe so movimenta raiz, pivôs e cadeias.

@export_range(0.0, 1000.0, 1.0) var root_max_speed: float = 72.0
@export_range(0.0, 1000.0, 1.0) var root_stop_distance: float = 20.0
@export_range(0.01, 100.0, 0.01) var root_acceleration: float = 5.0
@export_range(0.01, 100.0, 0.01) var root_deceleration: float = 7.0
@export_range(0.0, 200.0, 0.1) var mask_axial_offset: float = 8.0
@export_range(0.0, 200.0, 0.1) var crown_axial_offset: float = -10.0
@export_range(0.01, 100.0, 0.01) var mask_follow_rate: float = 8.0
@export_range(0.01, 100.0, 0.01) var crown_follow_rate: float = 5.0
@export_range(0.01, 100.0, 0.01) var mask_turn_rate: float = 8.0
@export_range(0.01, 100.0, 0.01) var crown_turn_rate: float = 5.0
@export_group("Visual Culling")
## Margem extra alem da margem de sala da classe base, em pixels de mundo.
## Cobre o footprint aproximado do Sprite2D da Regente em torno da raiz.
@export_range(64.0, 500.0, 1.0) var visual_cull_margin_x: float = 64.0
@export_range(169.0, 500.0, 1.0) var visual_cull_margin_y: float = 169.0

@onready var mask_pivot: Node2D = get_node_or_null("MaskPivot")
@onready var crown_pivot: Node2D = get_node_or_null("CrownPivot")
@onready var arm_chains: Array[Node] = _nodes_in_group(&"regente_arm_chain")
@onready var conduit_chains: Array[Node] = _nodes_in_group(&"regente_conduit_chain")

var _facing := Vector2.DOWN

func _ready() -> void:
	super()
	_initialize_pivots()
	_reset_chains()

func _physics_process(delta: float) -> void:
	if _should_cull():
		_resolve(ResolveReason.CULLED)
		queue_free()
		return
	var target_velocity := _target_velocity()
	var response := root_acceleration if target_velocity.length_squared() > 0.000001 else root_deceleration
	velocity = velocity.lerp(target_velocity, _exp_weight(response, delta))
	if velocity.length_squared() > 0.000001:
		_facing = velocity.normalized()
	move_and_slide()
	if _room_bounds.grow(16.0).has_point(global_position):
		_has_entered_room = true
	_update_pivots(delta)
	_step_chains(delta)
	if _should_cull():
		_resolve(ResolveReason.CULLED)
		queue_free()

func _target_velocity() -> Vector2:
	if is_instance_valid(_player):
		if global_position.distance_to(_player.global_position) <= root_stop_distance:
			return Vector2.ZERO
		var to_player := global_position.direction_to(_player.global_position)
		if to_player != Vector2.ZERO:
			return to_player * root_max_speed
	return _entry_inward * root_max_speed

func _should_cull() -> bool:
	if _room_cull_policy == RoomDef.CullPolicy.NONE:
		return false
	var visual_margin := Vector2(40.0 + visual_cull_margin_x, 40.0 + visual_cull_margin_y)
	if _room_cull_policy == RoomDef.CullPolicy.DESPAWN_BOTTOM:
		return global_position.y > _room_bounds.end.y + visual_margin.y
	return _has_entered_room and not _room_bounds.grow_individual(
		visual_margin.x,
		visual_margin.y,
		visual_margin.x,
		visual_margin.y
	).has_point(global_position)

func _update_pivots(delta: float) -> void:
	if is_instance_valid(mask_pivot):
		mask_pivot.global_position = mask_pivot.global_position.lerp(global_position + _facing * mask_axial_offset, _exp_weight(mask_follow_rate, delta))
		mask_pivot.global_rotation = lerp_angle(mask_pivot.global_rotation, _facing.angle(), _exp_weight(mask_turn_rate, delta))
	if is_instance_valid(crown_pivot):
		crown_pivot.global_position = crown_pivot.global_position.lerp(global_position + _facing * crown_axial_offset, _exp_weight(crown_follow_rate, delta))
		crown_pivot.global_rotation = lerp_angle(crown_pivot.global_rotation, _facing.angle(), _exp_weight(crown_turn_rate, delta))

func _initialize_pivots() -> void:
	if is_instance_valid(mask_pivot):
		mask_pivot.global_position = global_position + _facing * mask_axial_offset
		mask_pivot.global_rotation = _facing.angle()
	if is_instance_valid(crown_pivot):
		crown_pivot.global_position = global_position + _facing * crown_axial_offset
		crown_pivot.global_rotation = _facing.angle()

func _step_chains(delta: float) -> void:
	for chain in arm_chains + conduit_chains:
		if chain is ProceduralChain2D:
			chain.step(chain.global_position, delta)

func _reset_chains() -> void:
	for chain in arm_chains + conduit_chains:
		if chain is ProceduralChain2D:
			chain.reset_chain(chain.global_position, _facing)

func _nodes_in_group(group_name: StringName) -> Array[Node]:
	var found: Array[Node] = []
	for node in get_tree().get_nodes_in_group(group_name):
		if is_ancestor_of(node):
			found.append(node)
	return found

func _exp_weight(rate: float, delta: float) -> float:
	return 1.0 - exp(-maxf(0.0, rate) * maxf(0.0, delta))
