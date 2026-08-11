class_name AtiradorDeFresta
extends Enemy

enum AttackState { DRIFT, TELEGRAPH, FIRE, VULNERABLE, IDLE }
const ENEMY_PROJECTILE := preload("res://scenes/projectiles/enemy_projectile.tscn")

@export var attack_state: AttackState = AttackState.DRIFT
@export var telegraph_duration := 0.7
@export var vulnerable_duration := 0.7
@export var idle_duration := 1.0

var locked_direction := Vector2.DOWN
var _elapsed := 0.0
var _activation_distance := 100.0
var _entry_speed := 90.0
var _max_drift_time := 1.2
var _entry_start_position := Vector2.ZERO

@onready var telegraph: Line2D = $Telegraph
@onready var fire_fx: Sprite2D = $FireFx
@onready var aim_visual: Sprite2D = $Telegraph/AimVisual

func _ready() -> void:
	super()
	_activation_distance = RunManager.rng.randf_range(100.0, 200.0)
	_entry_speed = RunManager.rng.randf_range(90.0, 140.0)
	_max_drift_time = RunManager.rng.randf_range(1.2, 1.8)
	_entry_start_position = global_position
	_enter_state(attack_state)

func _physics_process(delta: float) -> void:
	if _should_cull():
		_resolve(ResolveReason.CULLED)
		queue_free()
		return
	delta = _consume_stun_delta(delta)
	if delta <= 0.0:
		return
	_elapsed += delta
	match attack_state:
		AttackState.DRIFT:
			_process_drift()
			_mark_room_entry()
			if _has_entered_room and (global_position.distance_to(_entry_start_position) >= _activation_distance or _elapsed >= _max_drift_time):
				_lock_target()
				_enter_state(AttackState.TELEGRAPH)
		AttackState.TELEGRAPH:
			velocity = Vector2.ZERO
			aim_visual.frame = mini(aim_visual.hframes - 1, int(_elapsed / telegraph_duration * aim_visual.hframes))
			if _elapsed >= telegraph_duration:
				_enter_state(AttackState.FIRE)
		AttackState.FIRE:
			_fire_projectile()
			_enter_state(AttackState.VULNERABLE)
		AttackState.VULNERABLE:
			velocity = Vector2.ZERO
			fire_fx.frame = mini(7, int(_elapsed / 0.18 * 8.0))
			if _elapsed >= vulnerable_duration:
				_enter_state(AttackState.IDLE)
		AttackState.IDLE:
			velocity = Vector2.ZERO
			if _elapsed >= idle_duration:
				_enter_state(AttackState.DRIFT)
	move_and_slide()
	if attack_state == AttackState.DRIFT:
		_mark_room_entry()

func take_damage(info: DamageInfo) -> float:
	# Mantem o mesmo limite de cadeias de Enemy antes de criar o dano derivado.
	if info == null or info.trigger_depth > 3:
		return 0.0
	if attack_state == AttackState.VULNERABLE:
		var actual_drop := health.apply_damage(info.create_chain_damage(info.amount * 3.0, [&"vulnerable"]))
		return actual_drop / 3.0
	return super(info)

func _process_drift() -> void:
	velocity = _entry_inward * _entry_speed

func _mark_room_entry() -> void:
	if not _has_entered_room and _room_bounds.has_point(global_position):
		_has_entered_room = true
		_entry_start_position = global_position
		_elapsed = 0.0

func _lock_target() -> void:
	if is_instance_valid(_player):
		locked_direction = global_position.direction_to(_player.global_position)
	if locked_direction == Vector2.ZERO:
		locked_direction = Vector2.DOWN

func _enter_state(next: AttackState) -> void:
	attack_state = next
	_elapsed = 0.0
	telegraph.visible = next == AttackState.TELEGRAPH
	fire_fx.visible = next == AttackState.VULNERABLE
	if next == AttackState.TELEGRAPH:
		velocity = Vector2.ZERO
		telegraph.points = PackedVector2Array([Vector2.ZERO, locked_direction * 340.0])
		aim_visual.rotation = locked_direction.angle()
		aim_visual.frame = 0
	if next == AttackState.VULNERABLE:
		fire_fx.frame = 0

func _fire_projectile() -> void:
	# O script do projetil pode ainda nao estar registrado no cache de classes
	# durante a primeira importacao; o contrato publico continua nos metodos.
	var projectile := ENEMY_PROJECTILE.instantiate() as Node
	projectile.call(&"set_room_bounds", _room_bounds)
	projectile.call(&"launch", global_position + locked_direction * 16.0, locked_direction, self, contact_damage)
	var projectiles := get_tree().get_first_node_in_group(&"projectiles")
	(projectiles if projectiles != null else get_parent()).add_child(projectile)
	var controller := get_tree().get_first_node_in_group(&"room_controller")
	if controller != null and controller.has_method(&"register_enemy_projectile"):
		controller.call(&"register_enemy_projectile", projectile)
