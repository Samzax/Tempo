extends CharacterBody2D
## Nave do jogador.
## Movimento X,Y com aceleração/atrito, inclinação progressiva (5 poses),
## propulsor reativo, disparo primário (Espaço) e blink (Shift): teleporte
## instantâneo com i-frames. Recebe dano por contato com inimigos (respeitando
## os i-frames) e renasce no centro ao morrer.

@export var max_speed: float = 150.0
@export var acceleration: float = 1000.0
@export var friction: float = 1300.0
## Quão rápido a inclinação acompanha a entrada horizontal (poses por segundo).
@export var bank_rate: float = 6.0
## Cadência de tiro em disparos por segundo (segure Espaço para atirar).
@export var fire_rate: float = 6.0

@export_group("Blink")
## Distância do teleporte instantâneo.
@export var blink_distance: float = 100.0
@export var blink_cooldown: float = 0.9
## Duração dos i-frames concedidos pelo blink.
@export var blink_invuln: float = 0.25

@export_group("Vida")
## I-frames concedidos ao levar dano por contato.
@export var hit_invuln: float = 0.8
## I-frames concedidos ao renascer.
@export var respawn_invuln: float = 1.5

const BULLET := preload("res://scenes/projectiles/bullet.tscn")
const TELEPORT_FX := preload("res://scenes/effects/teleport_fx.tscn")

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var thruster: CPUParticles2D = $Thruster
@onready var muzzle: Marker2D = $Muzzle
@onready var health: HealthComponent = $HealthComponent
@onready var hurtbox: Area2D = $Hurtbox

var _bank: float = 0.0
var _fire_cooldown: float = 0.0
var _blink_cd: float = 0.0
var _invuln_timer: float = 0.0
var _spawn_point: Vector2 = Vector2.ZERO
var _projectiles: Node = null
var _effects: Node = null
var _bounds: Vector2 = Vector2(
	float(ProjectSettings.get_setting("display/window/size/viewport_width", 480)),
	float(ProjectSettings.get_setting("display/window/size/viewport_height", 270))
)

func _ready() -> void:
	_projectiles = get_tree().get_first_node_in_group("projectiles")
	_effects = get_tree().get_first_node_in_group("effects")
	_spawn_point = global_position
	health.died.connect(_on_died)

func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	_handle_blink_input(dir)

	if dir != Vector2.ZERO:
		velocity = velocity.move_toward(dir * max_speed, acceleration * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)

	move_and_slide()
	_clamp_to_bounds()
	_check_contact()
	_update_bank(dir.x, delta)
	_update_thruster()
	_update_invuln_visual()
	_handle_fire(delta)

## Verdadeiro enquanto a nave está em i-frames (blink, dano ou renascimento).
func is_invulnerable() -> bool:
	return _invuln_timer > 0.0

## Fração de recarga do blink (0 = pronto, 1 = acabou de usar). Usado pelo HUD.
func blink_cooldown_ratio() -> float:
	if blink_cooldown <= 0.0:
		return 0.0
	return clampf(_blink_cd / blink_cooldown, 0.0, 1.0)

func _tick_timers(delta: float) -> void:
	_fire_cooldown -= delta
	_blink_cd = maxf(0.0, _blink_cd - delta)
	_invuln_timer = maxf(0.0, _invuln_timer - delta)

## Blink: teleporte instantâneo na direção do movimento (ou para cima se parado),
## com efeito de colapso na origem e no destino, i-frames e recarga.
func _handle_blink_input(dir: Vector2) -> void:
	if _blink_cd > 0.0 or not Input.is_action_just_pressed("blink"):
		return
	var bdir := dir.normalized() if dir != Vector2.ZERO else Vector2.UP
	var origin := global_position
	var m := 10.0
	var dest := origin + bdir * blink_distance
	dest.x = clampf(dest.x, m, _bounds.x - m)
	dest.y = clampf(dest.y, m, _bounds.y - m)

	global_position = dest      # teleporte instantâneo
	velocity = Vector2.ZERO     # é um blink, não um empurrão
	_blink_cd = blink_cooldown
	_invuln_timer = maxf(_invuln_timer, blink_invuln)
	_spawn_teleport_fx(origin)
	_spawn_teleport_fx(dest)

## Leva dano por contato enquanto um inimigo estiver sobreposto e não houver i-frames.
func _check_contact() -> void:
	if is_invulnerable():
		return
	for body in hurtbox.get_overlapping_bodies():
		if body.is_in_group("enemies"):
			health.apply_damage(body.contact_damage)
			_invuln_timer = hit_invuln
			return

func _on_died() -> void:
	GameState.player_lives = maxi(0, GameState.player_lives - 1)
	_spawn_teleport_fx(global_position)
	if GameState.player_lives <= 0:
		hide()
		set_physics_process(false)
		return  # sem renascer: o HUD assume o fim de jogo
	global_position = _spawn_point
	velocity = Vector2.ZERO
	health.reset()
	_invuln_timer = respawn_invuln
	_spawn_teleport_fx(_spawn_point)

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

func _spawn_teleport_fx(pos: Vector2) -> void:
	if _effects == null:
		return
	var fx := TELEPORT_FX.instantiate()
	_effects.add_child(fx)
	fx.global_position = pos

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
