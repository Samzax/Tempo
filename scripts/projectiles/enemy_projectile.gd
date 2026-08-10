class_name EnemyProjectile
extends Area2D

@export var speed := 260.0
@export var damage := 1.0
@export var lifetime := 2.5

var _velocity := Vector2.ZERO
var _life := 0.0
var _source: Node
var _room_bounds := Rect2(Vector2.ZERO, Vector2(720, 405))

func _ready() -> void:
	add_to_group(&"enemy_projectiles")
	body_entered.connect(_on_body_entered)

func set_room_bounds(bounds: Rect2) -> void:
	_room_bounds = bounds

func launch(origin: Vector2, direction: Vector2, source: Node, amount: float = 1.0) -> void:
	global_position = origin
	_source = source
	damage = amount
	_velocity = direction.normalized() * speed
	rotation = _velocity.angle() + PI * 0.5
	_life = lifetime

func _physics_process(delta: float) -> void:
	global_position += _velocity * delta
	_life -= delta
	if _life <= 0.0 or not _room_bounds.grow(24.0).has_point(global_position):
		queue_free()

func _on_body_entered(body: Node) -> void:
	if body.has_method(&"take_damage"):
		var info := DamageInfo.new()
		info.amount = damage
		info.source = _source
		info.tags = [&"enemy_projectile"]
		info.position = global_position
		body.call(&"take_damage", info)
	queue_free()
