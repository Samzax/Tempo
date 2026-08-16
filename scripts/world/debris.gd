class_name Debris
extends RigidBody2D
const HEALTH_UNITS := preload("res://scripts/components/health_units.gd")

enum SizeClass { LARGE, MEDIUM, SMALL }

const DEBRIS_SCENE := preload("res://scenes/world/debris.tscn")
const METEOR_TEXTURES := [
	preload("res://assets/sprites/world/meteorites/upper_meteorite_large.png"),
	preload("res://assets/sprites/world/meteorites/upper_meteorite_medium.png"),
	preload("res://assets/sprites/world/meteorites/upper_meteorite_small.png"),
]
const HIT_TEXTURE := preload("res://assets/sprites/world/meteorites/upper_meteorite_hit_strip.png")
const BREAK_TEXTURE := preload("res://assets/sprites/world/meteorites/upper_meteorite_break_strip.png")
const ONE_SHOT_FX := preload("res://scripts/effects/meteorite_one_shot_fx.gd")
const HIT_SCALES := [1.25, 0.75, 0.50]
const BREAK_SCALES := [1.0, 0.625, 0.375]

@export var size_class: SizeClass = SizeClass.LARGE
@export var contact_damage := 1.0
@export var drift_velocity := Vector2.ZERO
@export_range(0.1, 120.0, 0.1) var lifetime := 18.0
@export_range(0.0, 512.0, 1.0) var cull_margin := 96.0

@onready var health: HealthComponent = $HealthComponent
@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var _room_bounds := Rect2(Vector2.ZERO, Vector2(720.0, 405.0))
var _age := 0.0
var _has_entered_room := false
var _destroyed := false
var _contact_damage_units: int = 0

func _ready() -> void:
	add_to_group(&"debris")
	health.died.connect(_on_died)
	health.damaged.connect(_on_damaged)
	_configure_size()
	_contact_damage_units = HEALTH_UNITS.from_hp(contact_damage)
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

func take_damage(info: DamageInfo) -> int:
	if info == null or info.trigger_depth > 3:
		return 0
	return health.apply_damage(info)

func _configure_size() -> void:
	health.max_health = HEALTH_UNITS.from_hp([6.0, 3.0, 1.0][size_class])
	sprite.texture = METEOR_TEXTURES[size_class]
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2.ONE
	sprite.z_index = 2
	var shape := ConvexPolygonShape2D.new()
	shape.points = _hull_for(size_class)
	collision_shape.shape = shape
	health.reset()

func _hull_for(kind: SizeClass) -> PackedVector2Array:
	match kind:
		SizeClass.LARGE:
			return PackedVector2Array([Vector2(-17, -4), Vector2(-12, -10), Vector2(-3, -14), Vector2(9, -16), Vector2(11, -13), Vector2(16, 0), Vector2(9, 11), Vector2(1, 15), Vector2(-5, 14), Vector2(-12, 8)])
		SizeClass.MEDIUM:
			return PackedVector2Array([Vector2(-10, 1), Vector2(-7, -4), Vector2(-3, -9), Vector2(2, -9), Vector2(10, -1), Vector2(10, 6), Vector2(5, 9), Vector2(-3, 9), Vector2(-7, 6)])
		_:
			return PackedVector2Array([Vector2(-6, -4), Vector2(-1, -5), Vector2(4, -3), Vector2(6, 1), Vector2(4, 4), Vector2(-3, 4), Vector2(-6, 1)])

func _on_damaged(_info: DamageInfo, _actual_drop: int) -> void:
	if not _destroyed and health.health > 0:
		_emit_fx(HIT_TEXTURE, 2, Vector2(32, 32), 0.05, HIT_SCALES[size_class])

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group(&"player") or not body.has_method(&"take_damage"):
		return
	var info := DamageInfo.new()
	info.amount = _contact_damage_units
	info.source = self
	info.tags = [&"contact", &"debris"]
	info.position = global_position
	body.call(&"take_damage", info)

func _on_died(_fatal_info: DamageInfo) -> void:
	if _destroyed:
		return
	_destroyed = true
	_emit_fx(BREAK_TEXTURE, 5, Vector2(48, 48), 0.04, BREAK_SCALES[size_class])
	if size_class != SizeClass.SMALL:
		var offset := 12.0 if size_class == SizeClass.LARGE else 8.0
		for index in 2:
			var fragment := DEBRIS_SCENE.instantiate() as Debris
			fragment.size_class = size_class + 1
			fragment.global_position = global_position + Vector2(offset, 0.0).rotated(index * PI)
			fragment.rotation = rotation
			fragment.drift_velocity = linear_velocity + Vector2(45.0, 0.0).rotated(index * PI)
			fragment.set_room_bounds(_room_bounds)
			fragment.lifetime = maxf(0.1, lifetime - _age)
			get_parent().add_child.call_deferred(fragment)
	queue_free()

func _emit_fx(texture: Texture2D, frames: int, frame_size: Vector2, frame_duration: float, visual_scale: float) -> void:
	if texture == null or not is_inside_tree() or get_parent() == null:
		return
	var fx := ONE_SHOT_FX.new()
	fx.configure(texture, frames, frame_size, frame_duration, visual_scale)
	# O break precisa sobreviver ao debris que o disparou, mas ainda pertence a
	# esta sala para ser limpo junto dela. Hit segue o mesmo ownership local.
	get_parent().add_child(fx)
	fx.global_position = global_position
