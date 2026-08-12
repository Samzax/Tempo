class_name KamikazeFraturado
extends Enemy

enum AttackState { APPROACH, TELEGRAPH, DASH, RECOVER }
@export var attack_state: AttackState = AttackState.APPROACH
@export var telegraph_duration := 0.45
@export var dash_duration := 0.55
@export var recover_duration := 0.5
@export var engagement_distance := 210.0
@export var dash_speed := 310.0

var dash_direction := Vector2.DOWN
var _elapsed := 0.0

const DETONATE_FX := preload("res://scenes/effects/kamikaze_detonate_fx.tscn")

@onready var animation_sprite: AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	super()
	_enter_state(attack_state)

func _physics_process(delta: float) -> void:
	if _should_cull():
		_resolve(ResolveReason.CULLED)
		queue_free()
		return
	var frame_delta := delta
	delta = _consume_stun_delta(delta)
	var dash_finished := false
	var state_elapsed_before := _elapsed
	_elapsed += delta
	if delta > 0.0:
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
				var active_fraction := clampf((dash_duration - state_elapsed_before) / delta, 0.0, 1.0)
				velocity *= active_fraction
				if _elapsed >= dash_duration:
					dash_finished = true
			AttackState.RECOVER:
				velocity = Vector2.ZERO
				if _elapsed >= recover_duration: _enter_state(AttackState.APPROACH)
	_integrate_physics_motion(delta, frame_delta)
	if dash_finished:
		_enter_state(AttackState.RECOVER)
		_elapsed = maxf(0.0, delta - maxf(0.0, dash_duration - state_elapsed_before))
		if _elapsed >= recover_duration:
			_enter_state(AttackState.APPROACH)
	if _room_bounds.grow(16.0).has_point(global_position): _has_entered_room = true

func _enter_state(next: AttackState) -> void:
	attack_state = next
	_elapsed = 0.0
	match next:
		AttackState.APPROACH, AttackState.RECOVER:
			animation_sprite.rotation = 0.0
			animation_sprite.play(&"approach")
		AttackState.TELEGRAPH:
			animation_sprite.rotation = 0.0
			animation_sprite.play(&"warning")
		AttackState.DASH:
			animation_sprite.rotation = dash_direction.angle() + PI
			animation_sprite.play(&"dash")

func _on_died(fatal_info: DamageInfo) -> void:
	_spawn_detonation_fx()
	_spawn_fragment_feedback()
	super(fatal_info)

func _spawn_detonation_fx() -> void:
	var host: Node = _effects.get_parent() if is_instance_valid(_effects) else get_parent()
	if host == null:
		return
	var detonate_fx := DETONATE_FX.instantiate() as AnimatedSprite2D
	if detonate_fx == null:
		return
	host.add_child(detonate_fx)
	detonate_fx.global_position = global_position
	detonate_fx.play(&"detonate")

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
