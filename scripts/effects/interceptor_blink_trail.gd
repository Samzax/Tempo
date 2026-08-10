extends Node2D
## Faixa visual de uso unico para o blink da Interceptadora. Nao participa da fisica.

const FIXED_DURATION := 0.4
const NATIVE_TEXTURE_WIDTH := 1823.0
const FIXED_VERTICAL_SCALE := 0.34

@onready var trail_sprite: Sprite2D = $TrailSprite

var _duration := FIXED_DURATION
var _elapsed := 0.0

func configure(origin: Vector2, dest: Vector2, thrust_color: Color, _width: float, _duration_arg: float) -> void:
	var delta := dest - origin
	global_position = origin.lerp(dest, 0.5)
	rotation = delta.angle() if delta.length_squared() > 0.0 else 0.0
	trail_sprite.scale = Vector2(delta.length() / NATIVE_TEXTURE_WIDTH, FIXED_VERTICAL_SCALE)
	trail_sprite.material.set_shader_parameter(&"tint_color", thrust_color)
	trail_sprite.modulate = Color.WHITE
	_duration = FIXED_DURATION
	_elapsed = 0.0

func _process(delta: float) -> void:
	_elapsed += delta
	trail_sprite.modulate.a = 1.0 - clampf(_elapsed / FIXED_DURATION, 0.0, 1.0)
	if _elapsed >= FIXED_DURATION:
		queue_free()
