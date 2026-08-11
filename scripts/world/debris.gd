class_name Debris
extends RigidBody2D

enum SizeClass { LARGE, MEDIUM, SMALL }

const DEBRIS_SCENE := preload("res://scenes/world/debris.tscn")

@export var size_class: SizeClass = SizeClass.LARGE
@export var contact_damage := 1.0
@export var drift_velocity := Vector2.ZERO
@export_range(0.1, 120.0, 0.1) var lifetime := 18.0
@export_range(0.0, 512.0, 1.0) var cull_margin := 96.0

@onready var health: HealthComponent = $HealthComponent

var _room_bounds := Rect2(Vector2.ZERO, Vector2(720.0, 405.0))
var _age := 0.0
var _has_entered_room := false
var _destroyed := false

func _ready() -> void:
	add_to_group(&"debris")
	health.died.connect(_on_died)
	_configure_size()
	linear_velocity = drift_velocity
	body_entered.connect(_on_body_entered)
	_has_entered_room = _room_bounds.has_point(global_position)

func set_room_bounds(bounds: Rect2) -> void:
	if bounds.size.x > 0.0 and bounds.size.y > 0.0:
		_room_bounds = bounds

func _physics_process(delta: float) -> void:
	_age += delta
	if _room_bounds.has_point(global_position):
		_has_entered_room = true
	if _age >= lifetime or (_has_entered_room and not _room_bounds.grow(cull_margin).has_point(global_position)):
		queue_free()

func take_damage(info: DamageInfo) -> float:
	if info == null or info.trigger_depth > 3:
		return 0.0
	return health.apply_damage(info)

func _configure_size() -> void:
	match size_class:
		SizeClass.LARGE:
			health.max_health = 6.0
			$CollisionShape2D.shape.radius = 18.0
			$Sprite2D.scale = Vector2.ONE * 1.5
		SizeClass.MEDIUM:
			health.max_health = 3.0
			$CollisionShape2D.shape.radius = 11.0
			$Sprite2D.scale = Vector2.ONE
		SizeClass.SMALL:
			health.max_health = 1.0
			$CollisionShape2D.shape.radius = 6.0
			$Sprite2D.scale = Vector2.ONE * 0.65
	health.reset()

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group(&"player") or not body.has_method(&"take_damage"):
		return
	var info := DamageInfo.new()
	info.amount = contact_damage
	info.source = self
	info.tags = [&"contact", &"debris"]
	info.position = global_position
	body.call(&"take_damage", info)

func _on_died(_fatal_info: DamageInfo) -> void:
	if _destroyed:
		return
	_destroyed = true
	if size_class != SizeClass.SMALL:
		for index in 2:
			var fragment := DEBRIS_SCENE.instantiate() as Debris
			fragment.size_class = size_class + 1
			fragment.global_position = global_position + Vector2(8.0, 0.0).rotated(index * PI)
			fragment.drift_velocity = linear_velocity + Vector2(45.0, 0.0).rotated(index * PI)
			fragment.set_room_bounds(_room_bounds)
			fragment.lifetime = maxf(0.1, lifetime - _age)
			get_parent().add_child.call_deferred(fragment)
	queue_free()
