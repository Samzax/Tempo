class_name SelectionShipEnergyFx
extends Control
## Camada procedural independente do casco: contorno e propulsao do piloto.

var thrust_color: Color = Color.WHITE
var ship_rotation := 0.0

func set_frame(color: Color, rotation_offset: float) -> void:
	thrust_color = color
	ship_rotation = rotation_offset
	queue_redraw()

func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.31
	# O aro fica fora do sprite e nao altera nenhum pixel do casco.
	draw_arc(center, radius, 0.0, TAU, 40, thrust_color, 1.5, true)
	# Chama procedural apontada para a traseira da nave, na mesma orientacao visual.
	var exhaust_direction := Vector2.DOWN.rotated(ship_rotation)
	var lateral := exhaust_direction.orthogonal() * radius * 0.22
	var origin := center + exhaust_direction * radius * 0.68
	var tip := origin + exhaust_direction * radius * 0.62
	draw_colored_polygon(PackedVector2Array([origin - lateral, origin + lateral, tip]), thrust_color)
