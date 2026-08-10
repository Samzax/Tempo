class_name AtiradorDeFresta
extends Enemy

enum AttackState { DRIFT, TELEGRAPH, FIRE, VULNERABLE }
const ENEMY_PROJECTILE := preload("res://scenes/projectiles/enemy_projectile.tscn")

@export var attack_state: AttackState = AttackState.DRIFT
@export var telegraph_duration := 0.7
@export var vulnerable_duration := 0.7
@export var engagement_distance := 280.0
@export var drift_speed := 38.0

var locked_direction := Vector2.DOWN
var _elapsed := 0.0
var _anchor: Node2D

@onready var telegraph: Line2D = $Telegraph
@onready var fire_fx: Sprite2D = $FireFx

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
		AttackState.DRIFT:
			_process_drift()
			if _elapsed >= 1.1 or (is_instance_valid(_player) and global_position.distance_to(_player.global_position) <= engagement_distance):
				_lock_target()
				_enter_state(AttackState.TELEGRAPH)
		AttackState.TELEGRAPH:
			velocity = Vector2.ZERO
			if _elapsed >= telegraph_duration:
				_enter_state(AttackState.FIRE)
		AttackState.FIRE:
			_fire_projectile()
			_enter_state(AttackState.VULNERABLE)
		AttackState.VULNERABLE:
			velocity = Vector2.ZERO
			fire_fx.frame = mini(7, int(_elapsed / 0.18 * 8.0))
			if _elapsed >= vulnerable_duration:
				_enter_state(AttackState.DRIFT)
	move_and_slide()
	if _room_bounds.has_point(global_position):
		_has_entered_room = true

func take_damage(info: DamageInfo) -> void:
	# Mantem o mesmo limite de cadeias de Enemy antes de criar o dano derivado.
	if info == null or info.trigger_depth > 3:
		return
	if attack_state == AttackState.VULNERABLE:
		health.apply_damage(info.create_chain_damage(info.amount * 3.0, [&"vulnerable"]))
		return
	super(info)

func _process_drift() -> void:
	if not _has_entered_room:
		velocity = _entry_inward * drift_speed
		return
	_anchor = _find_anchor()
	if is_instance_valid(_anchor):
		velocity = global_position.direction_to(_anchor.global_position) * drift_speed
	elif is_instance_valid(_player):
		var lateral := global_position.direction_to(_player.global_position).rotated(PI * 0.5)
		velocity = lateral * drift_speed
	else:
		velocity = _entry_inward * drift_speed

func _find_anchor() -> Node2D:
	var best: Node2D
	var best_distance := INF
	for candidate in get_tree().get_nodes_in_group(&"debris"):
		var debris := candidate as Node2D
		if debris == null:
			continue
		var distance := global_position.distance_to(debris.global_position)
		if distance < best_distance and distance <= engagement_distance:
			best = debris
			best_distance = distance
	return best

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
		telegraph.points = PackedVector2Array([Vector2.ZERO, locked_direction * 340.0])
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
