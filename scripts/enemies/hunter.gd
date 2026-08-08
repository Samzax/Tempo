class_name Hunter
extends Enemy
## Perseguidor de investida: captura a posicao do jogador antes do impulso.

enum AttackState { CHASE, TELEGRAPH, DASH, RECOVER }

@export var attack_state: AttackState = AttackState.CHASE
@export_range(0.05, 10.0, 0.05) var telegraph_duration: float = 0.45
@export_range(0.05, 10.0, 0.05) var dash_duration: float = 0.28
@export_range(0.05, 10.0, 0.05) var recover_duration: float = 0.5
@export_range(0.05, 20.0, 0.05) var attack_cooldown_duration: float = 1.25
@export_range(1.0, 1000.0, 1.0) var engagement_distance: float = 230.0
@export_range(1.0, 2000.0, 1.0) var dash_speed: float = 300.0
@export_range(0, 100, 1) var temporal_echo_reward: int = 1

var dash_direction := Vector2.DOWN
var _state_elapsed := 0.0
var _attack_cooldown := 0.0
var _telegraph_tween: Tween
var _dead := false
var _reward_granted := false

func _ready() -> void:
	super()
	_attack_cooldown = attack_cooldown_duration
	_enter_state(attack_state)

func _exit_tree() -> void:
	_cancel_attack_cycle()

func _physics_process(delta: float) -> void:
	if _dead:
		velocity = Vector2.ZERO
		return
	var dash_finished := false
	var state_elapsed_before := _state_elapsed
	_state_elapsed += delta
	match attack_state:
		AttackState.CHASE:
			_process_chase(delta)
		AttackState.TELEGRAPH:
			velocity = Vector2.ZERO
			if _state_elapsed >= telegraph_duration:
				_capture_dash_direction()
				_enter_state(AttackState.DASH)
		AttackState.DASH:
			velocity = dash_direction * dash_speed
			if delta > 0.0:
				velocity *= minf(1.0, maxf(0.0, dash_duration - state_elapsed_before) / delta)
			if _state_elapsed >= dash_duration:
				dash_finished = true
		AttackState.RECOVER:
			velocity = Vector2.ZERO
			if _state_elapsed >= recover_duration:
				_enter_state(AttackState.CHASE)
	move_and_slide()
	if dash_finished and not _dead:
		_enter_state(AttackState.RECOVER)
	if _room_cull_policy == RoomDef.CullPolicy.DESPAWN_BOTTOM and global_position.y > _room_bounds.end.y + 40.0:
		_resolve(ResolveReason.CULLED)
		queue_free()

func _process_chase(delta: float) -> void:
	if is_instance_valid(_player):
		velocity = global_position.direction_to(_player.global_position) * speed
	else:
		velocity = Vector2.DOWN * speed
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	if is_instance_valid(_player) and _attack_cooldown <= 0.0 and global_position.distance_to(_player.global_position) <= engagement_distance:
		_enter_state(AttackState.TELEGRAPH)

func enter_attack_state(next_state: AttackState) -> void:
	if not _dead:
		_enter_state(next_state)

func _enter_state(next_state: AttackState) -> void:
	if _dead:
		return
	attack_state = next_state
	_state_elapsed = 0.0
	if next_state != AttackState.TELEGRAPH:
		_stop_telegraph_pulse()
	match next_state:
		AttackState.CHASE:
			_attack_cooldown = attack_cooldown_duration
		AttackState.TELEGRAPH:
			_start_telegraph_pulse()
		AttackState.DASH:
			velocity = dash_direction * dash_speed
		AttackState.RECOVER:
			velocity = Vector2.ZERO

func _capture_dash_direction() -> void:
	if is_instance_valid(_player):
		dash_direction = global_position.direction_to(_player.global_position)
	if dash_direction == Vector2.ZERO:
		dash_direction = Vector2.DOWN

func _start_telegraph_pulse() -> void:
	_stop_telegraph_pulse()
	sprite.modulate = tint.lightened(0.35)
	_telegraph_tween = create_tween()
	_telegraph_tween.set_loops()
	_telegraph_tween.tween_property(sprite, "scale", Vector2(1.28, 1.28), 0.11)
	_telegraph_tween.tween_property(sprite, "scale", Vector2.ONE, 0.11)

func _stop_telegraph_pulse() -> void:
	if is_instance_valid(_telegraph_tween):
		_telegraph_tween.kill()
	_telegraph_tween = null
	if is_instance_valid(sprite):
		sprite.scale = Vector2.ONE
		sprite.modulate = tint

func _on_died(fatal_info: DamageInfo) -> void:
	if _dead:
		return
	_dead = true
	_cancel_attack_cycle()
	if not _reward_granted and temporal_echo_reward > 0:
		_reward_granted = true
		GameState.add_temporal_echoes(temporal_echo_reward)
	super(fatal_info)

func _cancel_attack_cycle() -> void:
	velocity = Vector2.ZERO
	_stop_telegraph_pulse()
