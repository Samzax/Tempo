extends Node2D
## Linhas coloridas reutilizaveis sobre o casco. Puramente visuais e locais ao Player.

@onready var lines: Array[Line2D] = [$LeftLine, $CenterLine, $RightLine]

const BLINK_BOOST_DURATION := 0.42
const BLINK_WIDTH_MULTIPLIER := 1.16

var _thrust_color := Color.WHITE
var _pulse_frequency := 1.0
var _alpha_min := 0.35
var _alpha_max := 0.75
var _base_width := 1.0
var _elapsed := 0.0
var _blink_boost_elapsed := BLINK_BOOST_DURATION

## Configuracao publica para que a camada possa ser usada por qualquer ShipDef opt-in.
func configure(thrust_color: Color, pulse_frequency: float, alpha_min: float, alpha_max: float, line_width: float) -> void:
	_thrust_color = thrust_color
	_pulse_frequency = maxf(pulse_frequency, 0.001)
	_alpha_min = clampf(alpha_min, 0.0, 1.0)
	_alpha_max = clampf(maxf(alpha_max, _alpha_min), 0.0, 1.0)
	_base_width = maxf(line_width, 0.01)
	_apply_pulse()

## Inicia uma janela local de pre/durante/pos feedback visual para um blink valido.
func boost_for_blink() -> void:
	_blink_boost_elapsed = 0.0

func _process(delta: float) -> void:
	_elapsed += delta
	_blink_boost_elapsed = minf(_blink_boost_elapsed + delta, BLINK_BOOST_DURATION)
	_apply_pulse()

func _apply_pulse() -> void:
	var cycle := 0.5 + 0.5 * sin(_elapsed * TAU * _pulse_frequency)
	var blink_boost := _blink_boost_amount()
	var alpha := clampf(lerpf(_alpha_min, _alpha_max, cycle) + blink_boost * 0.2, 0.0, 1.0)
	var width := _base_width * (1.0 + blink_boost * (BLINK_WIDTH_MULTIPLIER - 1.0))
	for line in lines:
		line.width = width
		line.default_color = Color(_thrust_color.r, _thrust_color.g, _thrust_color.b, alpha)

func _blink_boost_amount() -> float:
	if _blink_boost_elapsed >= BLINK_BOOST_DURATION:
		return 0.0
	var progress := _blink_boost_elapsed / BLINK_BOOST_DURATION
	# Sobe antes do pico, permanece forte no blink e decai suavemente depois.
	return sin(progress * PI)
