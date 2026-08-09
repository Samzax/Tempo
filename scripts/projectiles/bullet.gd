extends Area2D
## Projétil do jogador. Viaja em linha reta, some por tempo de vida ou ao sair
## da tela, e retorna ao pool. O dano será aplicado ao componente de vida do
## alvo quando os inimigos existirem (T4/T8).

@export var speed: float = 320.0
@export var damage: float = 1.0
@export var lifetime: float = 2.0

var _velocity: Vector2 = Vector2.UP * speed
var _life: float = 0.0
var _active: bool = false
var _shooter: Node = null
var _room_bounds := Rect2(Vector2.ZERO, Vector2(720, 405))

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
func activate(pos: Vector2, dir: Vector2, shooter: Node, damage_amount: float = 1.0) -> void:
	global_position = pos
	_shooter = shooter
	damage = damage_amount
	_velocity = dir.normalized() * speed
	rotation = dir.angle() + PI / 2.0
	_life = lifetime
	_active = true
	show()
	monitoring = true
	monitorable = true
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	global_position += _velocity * delta
	_life -= delta
	var m := 16.0
	if _life <= 0.0 \
			or global_position.y < _room_bounds.position.y - m or global_position.y > _room_bounds.end.y + m \
			or global_position.x < _room_bounds.position.x - m or global_position.x > _room_bounds.end.x + m:
		_despawn()

func _on_hit(other: Node) -> void:
	if other.has_method("take_damage"):
		var info := DamageInfo.new()
		info.amount = damage
		info.source = _shooter
		info.tags = [&"projectile"]
		info.position = global_position
		other.take_damage(info)
	_despawn()

func _despawn() -> void:
	if not _active:
		return
	_active = false
	hide()
	set_physics_process(false)
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	Pools.release.call_deferred(self)
