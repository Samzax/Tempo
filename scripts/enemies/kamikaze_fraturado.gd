class_name KamikazeFraturado
extends Enemy

enum AttackState { APPROACH, TELEGRAPH, DASH, RECOVER }
@export var attack_state: AttackState = AttackState.APPROACH
@export var telegraph_duration := 0.45
@export var dash_duration := 0.32
@export var recover_duration := 0.5
@export var engagement_distance := 210.0
@export var dash_speed := 310.0

var dash_direction := Vector2.DOWN
var _elapsed := 0.0
var _pulse: Tween

func _ready() -> void:
	super()
	_enter_state(attack_state)

func _physics_process(delta: float) -> void:
	if _should_cull():
		_resolve(ResolveReason.CULLED)
		queue_free()
		return
	_elapsed += delta
	match attack_state:
		AttackState.APPROACH:
			velocity = global_position.direction_to(_player.global_position) * speed if is_instance_valid(_player) else _entry_inward * speed
			if is_instance_valid(_player) and global_position.distance_to(_player.global_position) <= engagement_distance:
				_enter_state(AttackState.TELEGRAPH)
		AttackState.TELEGRAPH:
			velocity = Vector2.ZERO
			if _elapsed >= telegraph_duration:
				if is_instance_valid(_player): dash_direction = global_position.direction_to(_player.global_position)
				if dash_direction == Vector2.ZERO: dash_direction = Vector2.DOWN
				_enter_state(AttackState.DASH)
		AttackState.DASH:
			velocity = dash_direction * dash_speed
			if _elapsed >= dash_duration: _enter_state(AttackState.RECOVER)
		AttackState.RECOVER:
			velocity = Vector2.ZERO
			if _elapsed >= recover_duration: _enter_state(AttackState.APPROACH)
	move_and_slide()
	if _room_bounds.grow(16.0).has_point(global_position): _has_entered_room = true

func _enter_state(next: AttackState) -> void:
	attack_state = next
	_elapsed = 0.0
	if is_instance_valid(_pulse): _pulse.kill()
	sprite.scale = Vector2.ONE
	sprite.modulate = tint
	if next == AttackState.TELEGRAPH:
		sprite.modulate = Color(1.0, 0.35, 0.35)
		_pulse = create_tween().set_loops()
		_pulse.tween_property(sprite, "scale", Vector2.ONE * 1.22, 0.1)
		_pulse.tween_property(sprite, "scale", Vector2.ONE, 0.1)

func _on_died(fatal_info: DamageInfo) -> void:
	if is_instance_valid(_pulse): _pulse.kill()
	_spawn_fragment_feedback()
	super(fatal_info)

## Reaproveita a rajada existente para sugerir estilhacos sem criar corpos
## persistentes, assets novos ou alterar o telegraph/investida.
func _spawn_fragment_feedback() -> void:
	if _effects == null:
		return
	for offset in [Vector2(-8.0, 3.0), Vector2(9.0, -4.0)]:
		var fragment_fx := BURST_FX.instantiate() as BurstFx
		if fragment_fx == null:
			continue
		_effects.add_child(fragment_fx)
		fragment_fx.burst_at(global_position + offset)
