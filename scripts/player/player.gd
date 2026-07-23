extends CharacterBody2D
## Nave do jogador.
## Movimento X,Y com aceleração/atrito, inclinação progressiva (5 poses),
## propulsor reativo, disparo primário (Espaço) e blink (Shift): investida curta
## com i-frames, recarga e rastro de pós-imagem.

@export var max_speed: float = 150.0
@export var acceleration: float = 1000.0
@export var friction: float = 1300.0
## Quão rápido a inclinação acompanha a entrada horizontal (poses por segundo).
@export var bank_rate: float = 6.0
## Cadência de tiro em disparos por segundo (segure Espaço para atirar).
@export var fire_rate: float = 6.0

@export_group("Blink")
@export var blink_speed: float = 700.0
@export var blink_duration: float = 0.13
@export var blink_cooldown: float = 0.9
## I-frames extras após o fim da investida.
@export var blink_invuln_extra: float = 0.1

const BULLET := preload("res://scenes/projectiles/bullet.tscn")

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var thruster: CPUParticles2D = $Thruster
@onready var muzzle: Marker2D = $Muzzle

var _bank: float = 0.0
var _fire_cooldown: float = 0.0
var _blink_timer: float = 0.0
var _blink_cd: float = 0.0
var _invuln_timer: float = 0.0
var _blink_dir: Vector2 = Vector2.UP
var _projectiles: Node = null
var _effects: Node = null
var _bounds: Vector2 = Vector2(
	float(ProjectSettings.get_setting("display/window/size/viewport_width", 480)),
	float(ProjectSettings.get_setting("display/window/size/viewport_height", 270))
)

func _ready() -> void:
	_projectiles = get_tree().get_first_node_in_group("projectiles")
	_effects = get_tree().get_first_node_in_group("effects")

func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	_handle_blink_input(dir)

	if _blink_timer > 0.0:
		velocity = _blink_dir * blink_speed
		_spawn_afterimage()
	elif dir != Vector2.ZERO:
		velocity = velocity.move_toward(dir * max_speed, acceleration * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)

	move_and_slide()
	_clamp_to_bounds()
	_update_bank(dir.x, delta)
	_update_thruster()
	_update_invuln_visual()
	_handle_fire(delta)

## Verdadeiro enquanto a nave está em i-frames (consumido pelo dano em T4).
func is_invulnerable() -> bool:
	return _invuln_timer > 0.0

func _tick_timers(delta: float) -> void:
	_fire_cooldown -= delta
	_blink_timer = maxf(0.0, _blink_timer - delta)
	_blink_cd = maxf(0.0, _blink_cd - delta)
	_invuln_timer = maxf(0.0, _invuln_timer - delta)

## Inicia a investida na direção da entrada (ou para frente/cima se parado).
func _handle_blink_input(dir: Vector2) -> void:
	if _blink_cd <= 0.0 and _blink_timer <= 0.0 and Input.is_action_just_pressed("blink"):
		_blink_dir = dir.normalized() if dir != Vector2.ZERO else Vector2.UP
		_blink_timer = blink_duration
		_blink_cd = blink_cooldown
		_invuln_timer = blink_duration + blink_invuln_extra

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

## Pisca a nave enquanto invulnerável (feedback dos i-frames).
func _update_invuln_visual() -> void:
	if _invuln_timer > 0.0:
		var t := Time.get_ticks_msec() * 0.001
		var k := 0.5 + 0.5 * sin(t * 40.0)
		sprite.modulate = Color(0.6, 0.85, 1.0).lerp(Color.WHITE, k)
	elif sprite.modulate != Color.WHITE:
		sprite.modulate = Color.WHITE

## Deixa uma cópia esmaecida da nave na posição atual durante a investida.
func _spawn_afterimage() -> void:
	if _effects == null or sprite.sprite_frames == null:
		return
	var ghost := Sprite2D.new()
	ghost.texture = sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	ghost.global_position = global_position
	ghost.z_index = -1
	ghost.modulate = Color(0.5, 0.85, 1.0, 0.55)
	_effects.add_child(ghost)
	var tw := ghost.create_tween()
	tw.tween_property(ghost, "modulate:a", 0.0, 0.28)
	tw.tween_callback(ghost.queue_free)

## Dispara enquanto Espaço estiver pressionado, respeitando a cadência.
func _handle_fire(delta: float) -> void:
	if _fire_cooldown <= 0.0 and Input.is_action_pressed("shoot"):
		_fire()
		_fire_cooldown = 1.0 / fire_rate

func _fire() -> void:
	if _projectiles == null:
		return
	var b := Pools.acquire(BULLET)
	if b.get_parent() == null:
		_projectiles.add_child(b)
	b.activate(muzzle.global_position, Vector2.UP)
