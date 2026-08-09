extends Node2D
## Faixa visual de uso unico para o blink da Interceptadora. Nao participa da fisica.

@onready var outer_line: Line2D = $OuterLine
@onready var core_line: Line2D = $CoreLine

var _duration := 0.18
var _elapsed := 0.0

func configure(origin: Vector2, dest: Vector2, thrust_color: Color, width: float, duration: float) -> void:
	global_position = origin
	_duration = maxf(duration, 0.01)
	var points := _make_irregular_points(dest - origin, width)
	outer_line.points = points
	outer_line.width = width
	outer_line.default_color = thrust_color
	core_line.points = points
	core_line.width = maxf(1.0, width * 0.32)
	core_line.default_color = Color.WHITE.lerp(thrust_color, 0.22)

func _process(delta: float) -> void:
	_elapsed += delta
	var alpha := 1.0 - clampf(_elapsed / _duration, 0.0, 1.0)
	outer_line.modulate.a = alpha * 0.8
	core_line.modulate.a = alpha
	if _elapsed >= _duration:
		queue_free()

func _make_irregular_points(delta: Vector2, width: float) -> PackedVector2Array:
	var points := PackedVector2Array([Vector2.ZERO])
	var perpendicular := delta.normalized().rotated(PI * 0.5)
	var random := RandomNumberGenerator.new()
	random.seed = hash(Vector2i(roundi(global_position.x), roundi(global_position.y))) ^ hash(Vector2i(roundi(delta.x), roundi(delta.y)))
	for index in range(1, 6):
		var progress := float(index) / 6.0
		var offset := perpendicular * random.randf_range(-width * 0.42, width * 0.42)
		points.append(delta * progress + offset)
	points.append(delta)
	return points
