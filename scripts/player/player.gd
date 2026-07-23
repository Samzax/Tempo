extends CharacterBody2D
## Nave do jogador.
## Movimento no plano X,Y com aceleração e atrito, inclinação progressiva usando
## as cinco poses do sprite (esquerda forte/leve, neutro, direita leve/forte) e um
## propulsor que reage à velocidade. Disparo (Espaço) e blink (Shift) chegam em T5/T6.

@export var max_speed: float = 150.0
@export var acceleration: float = 1000.0
@export var friction: float = 1300.0
## Quão rápido a inclinação acompanha a entrada horizontal (poses por segundo).
@export var bank_rate: float = 6.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var thruster: CPUParticles2D = $Thruster

var _bank: float = 0.0
var _bounds: Vector2 = Vector2(
	float(ProjectSettings.get_setting("display/window/size/viewport_width", 480)),
	float(ProjectSettings.get_setting("display/window/size/viewport_height", 270))
)

func _physics_process(delta: float) -> void:
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")

	if dir != Vector2.ZERO:
		velocity = velocity.move_toward(dir * max_speed, acceleration * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)

	move_and_slide()
	_clamp_to_bounds()
	_update_bank(dir.x, delta)
	_update_thruster()

## Mantém a nave dentro da área visível (arena de tela única).
func _clamp_to_bounds() -> void:
	var m := 10.0
	global_position.x = clampf(global_position.x, m, _bounds.x - m)
	global_position.y = clampf(global_position.y, m, _bounds.y - m)

## Faz a inclinação seguir a entrada suavemente e escolhe a pose correspondente.
func _update_bank(input_x: float, delta: float) -> void:
	_bank = move_toward(_bank, input_x, bank_rate * delta)
	var anim := &"neutral"
	if _bank <= -0.66:
		anim = &"hard_left"
	elif _bank <= -0.2:
		anim = &"soft_left"
	elif _bank < 0.2:
		anim = &"neutral"
	elif _bank < 0.66:
		anim = &"soft_right"
	else:
		anim = &"hard_right"
	if sprite.animation != anim:
		sprite.play(anim)

## O propulsor estica e intensifica conforme a velocidade atual.
func _update_thruster() -> void:
	var ratio := clampf(velocity.length() / max_speed, 0.0, 1.0)
	thruster.initial_velocity_min = 20.0 + ratio * 40.0
	thruster.initial_velocity_max = 50.0 + ratio * 70.0
	thruster.scale_amount_min = 0.8 + ratio * 0.4
	thruster.scale_amount_max = 1.4 + ratio * 0.8
