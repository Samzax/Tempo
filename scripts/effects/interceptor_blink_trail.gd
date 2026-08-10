extends Node2D
## Faixa visual de uso unico para o blink da Interceptadora. Nao participa da fisica.

const FIXED_DURATION := 0.4
const NATIVE_TEXTURE_WIDTH := 1823.0
const FIXED_VERTICAL_SCALE := 0.10

@onready var trail_sprite: Sprite2D = $TrailSprite

var _duration := FIXED_DURATION
var _elapsed := 0.0
var _base_scale := Vector2.ONE

func configure(origin: Vector2, dest: Vector2, thrust_color: Color, _width: float, _duration_arg: float) -> void:
	var delta := dest - origin
	global_position = origin.lerp(dest, 0.5)
	rotation = delta.angle() if delta.length_squared() > 0.0 else 0.0
	_base_scale = Vector2(delta.length() / NATIVE_TEXTURE_WIDTH, FIXED_VERTICAL_SCALE)
	trail_sprite.material.set_shader_parameter(&"tint_color", thrust_color)
	trail_sprite.modulate = Color.WHITE
	_duration = FIXED_DURATION
	_elapsed = 0.0
	_apply_visual_state()

func _process(delta: float) -> void:
	_elapsed += delta
	_apply_visual_state()
	if _elapsed >= FIXED_DURATION:
		queue_free()

func _apply_visual_state() -> void:
	var longitudinal_scale := 1.0
	var vertical_scale := FIXED_VERTICAL_SCALE
	var alpha := 1.0

	if _elapsed < 0.05:
		var entrance_progress := ease(clampf(_elapsed / 0.05, 0.0, 1.0), -2.0)
		longitudinal_scale = entrance_progress
		vertical_scale = lerpf(0.0, 0.15, entrance_progress)
		alpha = entrance_progress
	elif _elapsed < 0.15:
		var peak_progress := (_elapsed - 0.05) / 0.10
		vertical_scale = lerpf(0.15, FIXED_VERTICAL_SCALE, peak_progress)
	else:
		var dissolve_progress := ease(clampf((_elapsed - 0.15) / 0.25, 0.0, 1.0), 2.0)
		vertical_scale = lerpf(FIXED_VERTICAL_SCALE, 0.0, dissolve_progress)
		alpha = 1.0 - dissolve_progress

	trail_sprite.scale = Vector2(_base_scale.x * longitudinal_scale, vertical_scale)
	trail_sprite.modulate.a = alpha
