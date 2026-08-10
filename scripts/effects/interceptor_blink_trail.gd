extends Node2D
## Faixa visual de uso unico para o blink da Interceptadora. Nao participa da fisica.

@onready var outer_line: Line2D = $OuterLine
@onready var violet_line: Line2D = $VioletLine
@onready var core_line: Line2D = $CoreLine

const FIXED_DURATION := 0.4
const OUTER_VISUAL_WIDTH := 12.0
const VIOLET_VISUAL_WIDTH := 7.0
const CORE_VISUAL_WIDTH := 3.6
const JAGGED_OFFSET_AMPLITUDE := 22.0

var _duration := FIXED_DURATION
var _elapsed := 0.0

func configure(origin: Vector2, dest: Vector2, thrust_color: Color, width: float, _duration_arg: float) -> void:
	global_position = origin
	# A trilha aprovada tem quatro décimos de segundo em todas as ativações.
	# O argumento continua aceito para preservar o contrato público do endpoint.
	_duration = FIXED_DURATION
	_elapsed = 0.0
	# A largura de gameplay continua no contrato, mas não determina a escala gráfica.
	var points := _make_irregular_points(dest - origin)
	outer_line.points = points
	outer_line.width = OUTER_VISUAL_WIDTH
	outer_line.default_color = Color(0.12, 0.9, 1.0, 0.9)
	violet_line.points = points
	violet_line.width = VIOLET_VISUAL_WIDTH
	violet_line.default_color = Color(0.58, 0.22, 1.0, 0.95)
	core_line.points = points
	core_line.width = CORE_VISUAL_WIDTH
	core_line.default_color = Color.WHITE
	# O matiz do propulsor só tinge sutilmente o halo, sem substituir a leitura ciano/violeta.
	outer_line.default_color = outer_line.default_color.lerp(thrust_color, 0.12)
	queue_redraw()

func _process(delta: float) -> void:
	_elapsed += delta
	var alpha := 1.0 - clampf(_elapsed / _duration, 0.0, 1.0)
	outer_line.modulate.a = alpha * 0.82
	violet_line.modulate.a = alpha * 0.7
	core_line.modulate.a = alpha
	queue_redraw()
	if _elapsed >= _duration:
		queue_free()

func _draw() -> void:
	if outer_line == null or outer_line.points.size() < 2:
		return
	var alpha := 1.0 - clampf(_elapsed / _duration, 0.0, 1.0)
	var points := outer_line.points
	var direction := points[points.size() - 1].normalized()
	var normal := direction.rotated(PI * 0.5)
	var impact_radius := maxf(2.0, outer_line.width * 0.36)
	# Dois espinhos compactos evitam a leitura de árvore de relâmpagos.
	for fraction in [0.31, 0.69]:
		var index := clampi(roundi(fraction * float(points.size() - 1)), 1, points.size() - 2)
		var anchor: Vector2 = points[index]
		var sign := -1.0 if fraction < 0.5 else 1.0
		draw_line(anchor, anchor + normal * outer_line.width * 0.62 * sign + direction * outer_line.width * 0.20, Color(0.48, 0.2, 1.0, alpha * 0.7), maxf(1.0, outer_line.width * 0.16), false)
	draw_circle(Vector2.ZERO, impact_radius, Color(0.55, 0.25, 1.0, alpha * 0.55))
	draw_circle(points[points.size() - 1], impact_radius, Color(0.1, 0.9, 1.0, alpha * 0.6))

func _make_irregular_points(delta: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array([Vector2.ZERO])
	if delta.length_squared() <= 0.001:
		return points
	var perpendicular := delta.normalized().rotated(PI * 0.5)
	# Perfil fixo: um único corte angular dominante, com poucos espinhos curtos.
	# Não há RNG: origem/destino iguais sempre geram a mesma geometria.
	var profile := [Vector2(0.15, -0.42), Vector2(0.34, 1.0), Vector2(0.52, -0.76), Vector2(0.71, 0.86), Vector2(0.87, -0.36)]
	for knot in profile:
		points.append(delta * knot.x + perpendicular * (knot.y * JAGGED_OFFSET_AMPLITUDE))
	points.append(delta)
	return points
