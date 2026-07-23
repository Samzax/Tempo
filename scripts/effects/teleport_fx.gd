extends Node2D
## Efeito de teleporte: um anel branco que começa nas bordas e colapsa no centro,
## com um brilho que se concentra no ponto conforme o anel fecha. Some ao terminar.

@export var start_radius: float = 26.0
@export var duration: float = 0.22

var _t: float = 0.0

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	if _t >= duration:
		queue_free()

func _draw() -> void:
	var p := clampf(_t / duration, 0.0, 1.0)
	var r := lerpf(start_radius, 0.0, p)      # colapsa das bordas para o centro
	var ring_a := 1.0 - p                       # o anel some ao fechar
	# anel externo
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(1.0, 1.0, 1.0, ring_a), 2.5, true)
	# anel interno, mais tênue e adiantado
	draw_arc(Vector2.ZERO, r * 0.62, 0.0, TAU, 40, Color(0.75, 0.9, 1.0, ring_a * 0.75), 1.5, true)
	# brilho que se concentra no centro conforme o anel fecha
	draw_circle(Vector2.ZERO, lerpf(0.0, 5.0, p), Color(1.0, 1.0, 1.0, p * 0.9))
