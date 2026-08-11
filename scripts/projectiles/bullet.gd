extends Area2D
## Projétil do jogador. Viaja em linha reta, some por tempo de vida ou ao sair
## da tela, e retorna ao pool. O dano será aplicado ao componente de vida do
## alvo quando os inimigos existirem (T4/T8).

@export var speed: float = 320.0
@export var damage: float = 1.0
@export var lifetime: float = 2.0

const DEFAULT_SPEED: float = 320.0
const DEFAULT_LIFETIME: float = 2.0
const DEFAULT_SCALE := Vector2.ONE

var _velocity: Vector2 = Vector2.UP * speed
var _life: float = 0.0
var _active: bool = false
var _shooter: Node = null
var _room_bounds := Rect2(Vector2.ZERO, Vector2(720, 405))
var _remaining_damage: float = 0.0
var _hit_targets: Dictionary = {}
var _activation_epoch: int = 0
var _range_remaining: float = 0.0
var _despawn_on_valid_hit: bool = false

func _ready() -> void:
	body_entered.connect(_on_hit)
	area_entered.connect(_on_hit)

## Recebe a geometria da sala antes de o projétil ser ativado pelo pool.
func set_room_bounds(bounds: Rect2) -> void:
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		push_error("Bullet requires positive room bounds.")
		return
	_room_bounds = bounds

## (Re)inicializa o projétil ao ser tirado do pool.
func activate(
	pos: Vector2,
	dir: Vector2,
	shooter: Node,
	damage_amount: float = 1.0,
	projectile_speed: float = 320.0,
	projectile_lifetime: float = 2.0,
	projectile_scale: float = 1.0,
	despawn_on_valid_hit: bool = false,
) -> void:
	_activation_epoch += 1
	var safe_speed := projectile_speed
	if not is_finite(safe_speed) or safe_speed <= 0.0:
		safe_speed = DEFAULT_SPEED
	var safe_lifetime := projectile_lifetime
	if not is_finite(safe_lifetime) or safe_lifetime <= 0.0:
		safe_lifetime = DEFAULT_LIFETIME
	var valid_damage := is_finite(damage_amount) and damage_amount > 0.0
	var safe_scale := projectile_scale if is_finite(projectile_scale) and projectile_scale > 0.0 else 1.0
	global_position = pos
	_shooter = shooter
	damage = damage_amount if valid_damage else 0.0
	speed = safe_speed
	lifetime = safe_lifetime
	_remaining_damage = damage
	_hit_targets.clear()
	scale = DEFAULT_SCALE * safe_scale
	_velocity = dir.normalized() * speed
	rotation = dir.angle() + PI / 2.0
	_life = lifetime
	_range_remaining = speed * lifetime
	_despawn_on_valid_hit = despawn_on_valid_hit
	_active = true
	show()
	monitoring = true
	monitorable = true
	set_physics_process(true)
	if not valid_damage:
		_despawn()

func _physics_process(delta: float) -> void:
	var travel_time := minf(delta, minf(_life, _range_remaining / speed))
	global_position += _velocity * travel_time
	_life -= travel_time
	_range_remaining = maxf(0.0, _range_remaining - speed * travel_time)
	var m := 16.0
	if travel_time < delta or _life <= 0.0 or _range_remaining <= 0.0 \
			or global_position.y < _room_bounds.position.y - m or global_position.y > _room_bounds.end.y + m \
			or global_position.x < _room_bounds.position.x - m or global_position.x > _room_bounds.end.x + m:
		_despawn()

func _on_hit(other: Node) -> void:
	if not _active:
		return
	if not other.has_method("take_damage"):
		_despawn()
		return

	var target_id := other.get_instance_id()
	if _hit_targets.has(target_id):
		return
	_hit_targets[target_id] = true

	var info := DamageInfo.new()
	info.amount = _remaining_damage
	info.source = _shooter
	info.tags = [&"projectile"]
	info.position = global_position
	var reported_consumption: Variant = other.take_damage(info)
	if _despawn_on_valid_hit:
		_despawn()
		return
	var consumed := _remaining_damage
	if typeof(reported_consumption) == TYPE_FLOAT or typeof(reported_consumption) == TYPE_INT:
		var numeric_consumption := float(reported_consumption)
		if not is_nan(numeric_consumption) and not is_inf(numeric_consumption):
			consumed = clampf(numeric_consumption, 0.0, _remaining_damage)

	_remaining_damage -= consumed
	if _remaining_damage <= 0.0:
		_despawn()

func _despawn() -> void:
	if not _active:
		return
	var despawn_epoch := _activation_epoch
	_active = false
	_remaining_damage = 0.0
	_hit_targets.clear()
	_range_remaining = 0.0
	_despawn_on_valid_hit = false
	_shooter = null
	hide()
	set_physics_process(false)
	call_deferred("_disable_collision_after_despawn", despawn_epoch)
	call_deferred("_release_if_still_despawned", despawn_epoch)

func _disable_collision_after_despawn(despawn_epoch: int) -> void:
	if _active or _activation_epoch != despawn_epoch:
		return
	monitoring = false
	monitorable = false

func _release_if_still_despawned(despawn_epoch: int) -> void:
	if _active or _activation_epoch != despawn_epoch:
		return
	Pools.release(self)
