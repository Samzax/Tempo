class_name Player
extends CharacterBody2D
## Nave do jogador.
## Movimento X,Y com aceleração/atrito, inclinação progressiva (5 poses),
## propulsor reativo, disparo primário (Espaço) e blink (Shift): teleporte
## instantâneo com i-frames. Recebe dano por contato com inimigos (respeitando
## os i-frames) e renasce no centro ao morrer.

signal health_capacity_changed(max_health: float)
	
@export var ship: ShipDef
@export var character: CharacterDef

const BULLET := preload("res://scenes/projectiles/bullet.tscn")
const TELEPORT_FX := preload("res://scenes/effects/teleport_fx.tscn")
const INTERCEPTOR_BLINK_TRAIL := preload("res://scenes/effects/interceptor_blink_trail.tscn")
const INTERCEPTOR_DETAIL_LINES := preload("res://scenes/effects/interceptor_detail_lines.tscn")
const BLINK_BASE_COOLDOWN := 0.9
## Índices correspondem aos degraus de aim_tier; dentro do cone, a trava é total.
const AIM_CONE_ANGLES := [0.0, PI / 36.0, PI / 12.0, PI / 6.0]

@onready var visual_root: Node2D = $VisualRoot
@onready var sprite: AnimatedSprite2D = $VisualRoot/AnimatedSprite2D
@onready var thruster: CPUParticles2D = $VisualRoot/Thruster
@onready var thrusters: Array[CPUParticles2D] = [$VisualRoot/Thruster, $VisualRoot/ThrusterTop, $VisualRoot/ThrusterLeft, $VisualRoot/ThrusterRight]
@onready var muzzle: Marker2D = $Muzzle
@onready var health: HealthComponent = $HealthComponent
@onready var hurtbox: Area2D = $Hurtbox
@onready var body_collision: CollisionShape2D = $CollisionShape2D
@onready var hurtbox_collision: CollisionShape2D = $Hurtbox/CollisionShape2D

enum AimSource { NONE, MOUSE, JOYPAD }
enum SpinState { IDLE, MOVING, SPINNING }

## Velocidade que dispara a pirueta durante a desaceleracao final.
const SPIN_TRIGGER_SPEED := 30.0
const OMNI_MOVING_SPEED := 50.0
const OMNI_STOP_SPIN_DURATION := 0.35
const OMNI_STOP_SPIN_ANTICIPATION := 0.15
const OMNI_STOP_SPIN_SETTLE := 0.12
const OMNI_STOP_SPIN_ANTICIPATION_ANGLE := PI / 18.0

var _fire_cooldown: float = 0.0
var _blink_cd: float = 0.0
var _blink_cd_duration: float = 0.0
var _ability_q: AbilityDef
var _ability_e: AbilityDef
var _ability_q_cd: float = 0.0
var _ability_q_cd_duration: float = 0.0
var _ability_e_cd: float = 0.0
var _ability_e_cd_duration: float = 0.0
var _invuln_timer: float = 0.0
var is_sandbox_invulnerable: bool = false
var _aim_vector: Vector2 = Vector2.UP
var _last_aim_source: AimSource = AimSource.NONE
var _joypad_aim_was_active: bool = false
var _spawn_point: Vector2 = Vector2.ZERO
var _projectiles: Node = null
var _effects: Node = null
var _stats: StatBlock
var _dispatcher: EffectDispatcher
var _inventory: Inventory
var _base_sprite_frames: SpriteFrames = null
var _base_body_shape: Shape2D = null
var _detail_lines: Node2D = null
var _room_bounds := Rect2(Vector2.ZERO, Vector2(720, 405))
var _omni_stop_spin_state: SpinState = SpinState.IDLE
var _omni_stop_spin_elapsed := 0.0
var _omni_stop_spin_direction := 1.0
var _omni_stop_spin_next_direction := 1.0

func _ready() -> void:
	if ship == null:
		ship = preload("res://resources/ships/base.tres")
	if character == null:
		character = preload("res://resources/characters/base.tres")

	_configure_loadout()
	EventBus.enemy_died.connect(_on_enemy_died)
	health.damaged.connect(_on_health_damaged)
	health.max_health = _stats.get_stat(&"max_health")
	health.health = health.max_health
	_projectiles = get_tree().get_first_node_in_group("projectiles")
	_effects = get_tree().get_first_node_in_group("effects")
	_spawn_point = global_position
	health.died.connect(_on_died)

## Troca a nave antes da execucao e reaplica o loadout se o Player ja estiver pronto.
func configure_ship(next_ship: ShipDef) -> bool:
	if next_ship == null:
		return false
	ship = next_ship
	if is_node_ready():
		_configure_loadout()
	return true

## Aplica nave e personagem como uma unica transacao para evitar reconstrucoes intermediarias do loadout.
func configure_selection(next_ship: ShipDef, character_id: StringName) -> bool:
	if next_ship == null:
		return false
	ship = next_ship
	character = CharacterDef.resolve_id(character_id)
	if is_node_ready():
		_configure_loadout()
	return true

## Cria o deployable da Engenheira no dono da sala ativa, nunca no Player.
func deploy_engineer_gadget() -> bool:
	var session := get_tree().get_first_node_in_group(&"session")
	return session != null and session.has_method(&"deploy_engineer_deployable") and bool(session.call(&"deploy_engineer_deployable", self))

## Aplica a selecao antes do inicio da run. Reconstruir o loadout nao reconecta
## sinais do Player e por isso permanece seguro mesmo apos o _ready da cena.
func configure_character(character_id: StringName) -> void:
	character = CharacterDef.resolve_id(character_id)
	if is_node_ready():
		_configure_loadout()

## Configura os limites da arena atual e o ponto de renascimento no seu centro.
func set_room_bounds(bounds: Rect2) -> void:
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		push_error("Player requires positive room bounds.")
		return
	_room_bounds = bounds
	_spawn_point = bounds.get_center()

func _configure_loadout() -> void:
	if character == null:
		character = preload("res://resources/characters/base.tres")
	_stats = StatBlock.new(StatCatalog.get_all())
	Loadout.apply(_stats, ship, character)
	_ability_q = AbilityCatalog.get_ability(ship.ability_q) if ship != null and not ship.ability_q.is_empty() else null
	_ability_e = AbilityCatalog.get_ability(character.ability_e) if character != null and not character.ability_e.is_empty() else null
	thruster.color = character.thrust_color
	for omni_thruster in thrusters:
		omni_thruster.color = character.thrust_color
	_reset_ship_visual_state()
	_apply_hull_texture()
	_configure_ship_geometry()
	_configure_detail_lines()
	muzzle.visible = ship == null or ship.has_muzzle
	_dispatcher = EffectDispatcher.new(self, _gather_effects())
	_inventory = Inventory.new(_stats, _dispatcher)
	if is_instance_valid(health):
		var previous_max_health := health.max_health
		health.max_health = _stats.get_stat(&"max_health")
		health.health = health.max_health
		if health.max_health != previous_max_health:
			health_capacity_changed.emit(health.max_health)

## Restaura o estado que pode ter sido alterado por uma nave omni antes de
## aplicar o novo casco. Isso tambem mantem a troca para naves legadas segura.
func _reset_ship_visual_state() -> void:
	_reset_omni_stop_spin()
	visual_root.rotation = 0.0
	sprite.modulate = Color.WHITE
	sprite.animation = &"neutral"
	sprite.play(&"neutral")
	thruster.position = Vector2(0, 12) if _is_omni_ship() else Vector2(0, 10)
	for current_thruster in thrusters:
		current_thruster.emitting = false
	$VisualRoot/ThrusterTop.position = Vector2(0, -12)
	$VisualRoot/ThrusterLeft.position = Vector2(-12, 0)
	$VisualRoot/ThrusterRight.position = Vector2(12, 0)

## Restaura os frames base e, quando houver textura, troca somente o atlas de cada frame.
## Regioes, animacoes e o casco sem rotacao sao preservados.
func _apply_hull_texture() -> void:
	if sprite == null:
		return
	if _base_sprite_frames == null:
		_base_sprite_frames = sprite.sprite_frames
	if _base_sprite_frames == null:
		return
	# SpriteFrames pode ser compartilhado por instancias da cena. Duplica-lo evita
	# que a escolha de um jogador altere o casco de outro em co-op.
	var frames := _base_sprite_frames.duplicate(true) as SpriteFrames
	if frames == null:
		return
	if ship != null and ship.hull_texture != null:
		if ship.movement_style == "omni":
			if ship.hull_texture.get_size() != Vector2(ship.frame_size):
				push_warning("A textura omni precisa ter exatamente o frame_size configurado.")
				sprite.sprite_frames = frames
				return
			frames.clear_all()
			frames.add_animation(&"neutral")
			frames.add_frame(&"neutral", ship.hull_texture)
			frames.set_animation_loop(&"neutral", true)
			frames.set_animation_speed(&"neutral", 1.0)
			sprite.sprite_frames = frames
			sprite.play(&"neutral")
			return
		for animation_name in frames.get_animation_names():
			for frame_index in frames.get_frame_count(animation_name):
				var old_texture := frames.get_frame_texture(animation_name, frame_index)
				var atlas_frame := old_texture as AtlasTexture
				if atlas_frame == null:
					continue
				var replacement := atlas_frame.duplicate() as AtlasTexture
				replacement.atlas = ship.hull_texture
				var frame_size := Vector2(ship.frame_size)
				if frame_size.x > 0.0 and frame_size.y > 0.0:
					var region := replacement.region
					region.position *= frame_size / Vector2(16, 24)
					region.size = frame_size
					replacement.region = region
				frames.set_frame(animation_name, frame_index, replacement)
	sprite.sprite_frames = frames

func _configure_ship_geometry() -> void:
	if _base_body_shape == null and body_collision.shape != null:
		_base_body_shape = body_collision.shape.duplicate()
	if ship == null:
		return
	var radius := ship.hurtbox_radius
	var hurt_shape := CircleShape2D.new()
	hurt_shape.radius = radius
	hurtbox_collision.shape = hurt_shape
	if ship.collision_shape_type == "circle":
		var body_shape := CircleShape2D.new()
		body_shape.radius = radius
		body_collision.shape = body_shape
	elif _base_body_shape != null:
		body_collision.shape = _base_body_shape.duplicate()

## Anexa somente a camada visual opt-in ao VisualRoot, sem participar da fisica.
func _configure_detail_lines() -> void:
	if is_instance_valid(_detail_lines):
		_detail_lines.queue_free()
		_detail_lines = null
	if ship == null or not ship.detail_lines_enabled:
		return
	_detail_lines = INTERCEPTOR_DETAIL_LINES.instantiate() as Node2D
	if _detail_lines == null:
		return
	visual_root.add_child(_detail_lines)
	_detail_lines.call(
		&"configure",
		character.thrust_color,
		ship.detail_lines_pulse_frequency,
		ship.detail_lines_alpha_min,
		ship.detail_lines_alpha_max,
		ship.detail_lines_width,
		Vector2(ship.frame_size) if ship != null else Vector2(16, 24),
		1.0,
	)

## Substitui o buff ativo da habilidade para evitar colisao de source_id e
## acúmulo acidental ao reativar uma habilidade ainda ativa.
func apply_temporary_modifier(source_id: StringName, stat_id: StringName, op: StatDef.Op, value: float, duration: float) -> void:
	if _stats == null:
		return
	_stats.remove_modifiers_by_source(source_id)
	var modifier := StatModifierDef.new()
	modifier.stat = stat_id
	modifier.op = op
	modifier.value = value
	modifier.duration = duration
	modifier.source_id = source_id
	_stats.add_modifier(modifier)

## Adquire um item e aplica seus efeitos e modificadores.
func acquire_item(item: ItemDef) -> bool:
	return _inventory.acquire(item)

func can_acquire_item(item: ItemDef) -> bool:
	return item != null and _inventory != null and _inventory.count(item.id) < item.max_stacks

## APIs usadas exclusivamente pelo overlay de sandbox.
func sandbox_set_stat_override(stat_id: StringName, value: float) -> bool:
	if _stats == null or not StatCatalog.has_stat(stat_id):
		return false
	var definition := StatCatalog.get_stat(stat_id)
	var normalized := clampf(value, definition.default_min, definition.default_max)
	if definition.is_integer:
		normalized = float(roundi(normalized))
	_stats.set_base(stat_id, normalized)
	if stat_id == &"max_health":
		var previous_max_health := health.max_health
		health.max_health = normalized
		health.health = minf(health.health, health.max_health)
		if health.max_health != previous_max_health:
			health_capacity_changed.emit(health.max_health)
	return true

func sandbox_grant_item(item_id: StringName, amount: int) -> int:
	if _inventory == null or not ItemCatalog.is_valid(item_id):
		return 0
	var granted := 0
	var item := ItemCatalog.get_item(item_id)
	for _index in maxi(0, amount):
		if not _inventory.acquire(item):
			break
		granted += 1
	return granted

func sandbox_remove_item(item_id: StringName, amount: int) -> int:
	if _inventory == null:
		return 0
	var removed := 0
	for _index in maxi(0, amount):
		if not _inventory.remove_one(item_id):
			break
		removed += 1
	return removed

func sandbox_heal_full() -> void:
	health.heal(health.max_health)

func sandbox_set_invulnerable(enabled: bool) -> void:
	is_sandbox_invulnerable = enabled

func get_luck() -> float:
	return _stats.get_stat(&"luck") if _stats != null else 0.0

func _physics_process(delta: float) -> void:
	_stats.tick(delta)
	_dispatcher.tick(delta)
	_tick_timers(delta)
	_update_aim()
	var omni := _is_omni_ship()
	if not omni:
		rotation = _aim_vector.angle() + PI / 2.0
	else:
		rotation = 0.0
	var movement_direction := _omni_movement_direction() if omni else _aim_vector
	var is_thrusting := movement_direction != Vector2.ZERO if omni else Input.is_action_pressed("move_up")
	var blink_consumed := _handle_blink_input()
	_handle_ability_input()

	if not blink_consumed:
		velocity = AsteroidsMotion.calculate_velocity(
			velocity,
			movement_direction,
			is_thrusting,
			_stats.get_stat(&"acceleration"),
			_stats.get_stat(&"friction"),
			_stats.get_stat(&"max_speed"),
			delta,
		)

		move_and_slide()
		_clamp_to_bounds()
	_refresh_mouse_aim()
	if not omni:
		rotation = _aim_vector.angle() + PI / 2.0
	_check_contact()
	_update_omni_stop_spin(delta, movement_direction if omni else Vector2.ZERO)
	_update_bank(movement_direction if omni else Vector2.ZERO)
	_update_thruster(movement_direction if omni else Vector2.DOWN)
	_update_invuln_visual()
	if ship == null or ship.has_muzzle:
		_handle_fire(delta)

func _is_omni_ship() -> bool:
	return ship != null and ship.movement_style == "omni"

## Usa a mesma convencao de eixos do blink: esquerda, direita, cima, baixo.
func _omni_movement_direction() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")

## Faz a Bruta girar na desaceleracao final apos movimento significativo.
## O giro vive apenas no VisualRoot para nunca afetar colisao ou orientacao fisica.
func _update_omni_stop_spin(delta: float, omni_direction: Vector2) -> void:
	if not _is_omni_ship():
		_reset_omni_stop_spin()
		return

	if _omni_stop_spin_state == SpinState.SPINNING:
		if omni_direction != Vector2.ZERO:
			_reset_omni_stop_spin()
			return
		_omni_stop_spin_elapsed += delta
		var progress := clampf(_omni_stop_spin_elapsed / OMNI_STOP_SPIN_DURATION, 0.0, 1.0)
		visual_root.rotation = _omni_stop_spin_rotation(progress)
		if progress >= 1.0:
			visual_root.rotation = 0.0
			_omni_stop_spin_state = SpinState.IDLE
			_omni_stop_spin_elapsed = 0.0
			_omni_stop_spin_next_direction *= -1.0
		return

	if velocity.length() >= OMNI_MOVING_SPEED:
		_omni_stop_spin_state = SpinState.MOVING
		return

	if _omni_stop_spin_state == SpinState.MOVING and velocity.length() <= SPIN_TRIGGER_SPEED and omni_direction == Vector2.ZERO:
		_omni_stop_spin_state = SpinState.SPINNING
		_omni_stop_spin_elapsed = 0.0
		_omni_stop_spin_direction = _omni_stop_spin_next_direction
		visual_root.rotation = 0.0

## A antecipacao vai contra o giro; em seguida, a rotacao numerica avanca sem
## cruzar a normalizacao angular ate o reset neutro no ultimo quadro.
func _omni_stop_spin_rotation(progress: float) -> float:
	var anticipation_end := OMNI_STOP_SPIN_ANTICIPATION
	var settle_start := 1.0 - OMNI_STOP_SPIN_SETTLE
	if progress < anticipation_end:
		var anticipation_t := _smoothstep(progress / anticipation_end)
		return -_omni_stop_spin_direction * OMNI_STOP_SPIN_ANTICIPATION_ANGLE * anticipation_t
	if progress < settle_start:
		var spin_t := _smoothstep((progress - anticipation_end) / (settle_start - anticipation_end))
		return lerpf(
			-_omni_stop_spin_direction * OMNI_STOP_SPIN_ANTICIPATION_ANGLE,
			_omni_stop_spin_direction * (TAU - OMNI_STOP_SPIN_ANTICIPATION_ANGLE),
			spin_t,
		)
	var settle_t := _smoothstep((progress - settle_start) / OMNI_STOP_SPIN_SETTLE)
	return lerpf(
		_omni_stop_spin_direction * (TAU - OMNI_STOP_SPIN_ANTICIPATION_ANGLE),
		_omni_stop_spin_direction * TAU,
		settle_t,
	)

func _smoothstep(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

## Cancela uma pirueta sem consumir a proxima direcao. Somente um giro concluido
## alterna o sentido, para que blink, respawn e novo input sejam neutros.
func _reset_omni_stop_spin() -> void:
	_omni_stop_spin_state = SpinState.IDLE
	_omni_stop_spin_elapsed = 0.0
	if is_instance_valid(visual_root):
		visual_root.rotation = 0.0

## Detecta o mouse antes da interface para preservar a troca de fonte da mira.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_last_aim_source = AimSource.MOUSE

## Atualiza a última direção válida de mira conforme a fonte de entrada ativa.
func _update_aim() -> void:
	var joypad_aim := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	var joypad_active := joypad_aim.length() > 0.2
	if joypad_active and not _joypad_aim_was_active:
		_last_aim_source = AimSource.JOYPAD
	if _last_aim_source == AimSource.JOYPAD and joypad_active:
		_aim_vector = joypad_aim.normalized()
	elif _last_aim_source != AimSource.JOYPAD or not joypad_active:
		_last_aim_source = AimSource.MOUSE
		_refresh_mouse_aim()
	_joypad_aim_was_active = joypad_active

## Recalcula a mira do mouse usando a posição final da nave no quadro.
func _refresh_mouse_aim() -> void:
	if _last_aim_source == AimSource.MOUSE:
		var mouse_aim := get_global_mouse_position() - global_position
		if mouse_aim.length() >= 0.001:
			_aim_vector = mouse_aim.normalized()

## Verdadeiro enquanto a nave está em i-frames (blink, dano ou renascimento).
func is_invulnerable() -> bool:
	return is_sandbox_invulnerable or _invuln_timer > 0.0

## Estende a invulnerabilidade atual pelo tempo informado.
func grant_invuln(duration: float) -> void:
	_invuln_timer = maxf(_invuln_timer, duration)

## Fração de recarga do blink (0 = pronto, 1 = acabou de usar). Usado pelo HUD.
func blink_cooldown_ratio() -> float:
	if _blink_cd <= 0.0 or _blink_cd_duration <= 0.0:
		return 0.0
	return clampf(_blink_cd / _blink_cd_duration, 0.0, 1.0)

func blink_cooldown_duration() -> float:
	if _stats == null:
		return BLINK_BASE_COOLDOWN
	return BLINK_BASE_COOLDOWN / maxf(_stats.get_stat(&"blink_haste"), 0.001)

## Fracao de recarga da habilidade da nave (0 = pronta, 1 = acabou de usar).
func ability_q_cooldown_ratio() -> float:
	if _ability_q is InterceptorBlinkAbility:
		return blink_cooldown_ratio()
	if _ability_q_cd <= 0.0 or _ability_q_cd_duration <= 0.0:
		return 0.0
	return clampf(_ability_q_cd / _ability_q_cd_duration, 0.0, 1.0)

## Fracao de recarga da habilidade do personagem (0 = pronta, 1 = acabou de usar).
func ability_e_cooldown_ratio() -> float:
	if _ability_e_cd <= 0.0 or _ability_e_cd_duration <= 0.0:
		return 0.0
	return clampf(_ability_e_cd / _ability_e_cd_duration, 0.0, 1.0)

func _tick_timers(delta: float) -> void:
	_fire_cooldown -= delta
	_blink_cd = maxf(0.0, _blink_cd - delta)
	_ability_q_cd = maxf(0.0, _ability_q_cd - delta)
	_ability_e_cd = maxf(0.0, _ability_e_cd - delta)
	_invuln_timer = maxf(0.0, _invuln_timer - delta)

## Blink: teleporte instantâneo na direção da mira,
## com efeito de colapso na origem e no destino, i-frames e recarga.
func try_blink(direction: Vector2 = Vector2.ZERO) -> bool:
	if _stats == null or _dispatcher == null or _blink_cd > 0.0:
		return false
	var requested_direction := direction
	if requested_direction == Vector2.ZERO:
		requested_direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var bdir := requested_direction.normalized() if requested_direction != Vector2.ZERO else _aim_vector
	var origin := global_position
	var m := 10.0
	var dest := origin + bdir * _stats.get_stat(&"blink_distance")
	dest.x = clampf(dest.x, _room_bounds.position.x + m, _room_bounds.end.x - m)
	dest.y = clampf(dest.y, _room_bounds.position.y + m, _room_bounds.end.y - m)

	_boost_detail_lines_for_blink()
	_resolve_blink_trail_damage(origin, dest)
	global_position = dest      # teleporte instantâneo
	velocity = Vector2.ZERO     # é um blink, não um empurrão
	_reset_omni_stop_spin()
	_dispatcher.dispatch(&"on_blink", null, 0)
	_invuln_timer = maxf(_invuln_timer, _stats.get_stat(&"blink_invuln"))
	_spawn_teleport_fx(origin)
	_spawn_teleport_fx(dest)
	_spawn_interceptor_blink_trail(origin, dest)
	var cooldown := blink_cooldown_duration()
	_blink_cd = cooldown
	_blink_cd_duration = cooldown
	return true

## Ativa as habilidades equipadas quando seus slots estao prontos.
func _handle_blink_input() -> bool:
	return Input.is_action_just_pressed("blink") and try_blink()

func _handle_ability_input() -> void:
	if Input.is_action_just_pressed("ability_q") and _ability_q != null and _ability_q_cd <= 0.0:
		if _ability_q.try_activate(self):
			var q_cooldown := _ability_q.get_cooldown(self)
			_ability_q_cd = q_cooldown
			_ability_q_cd_duration = q_cooldown
			EventBus.ability_used.emit(&"ability_q")
	if Input.is_action_just_pressed("ability_e") and _ability_e != null and _ability_e_cd <= 0.0:
		if _ability_e.try_activate(self):
			var e_cooldown := _ability_e.get_cooldown(self)
			_ability_e_cd = e_cooldown
			_ability_e_cd_duration = e_cooldown
			EventBus.ability_used.emit(&"ability_e")

## Notifica os efeitos do jogador apos a conclusao valida de uma sala.
func on_room_clear() -> void:
	if _dispatcher != null:
		_dispatcher.dispatch(&"on_room_clear", null, 0)

## Leva dano por contato enquanto um inimigo estiver sobreposto e não houver i-frames.
func _check_contact() -> void:
	if is_invulnerable():
		return
	for body in hurtbox.get_overlapping_bodies():
		if body.is_in_group("enemies"):
			var info := DamageInfo.new()
			info.amount = body.contact_damage
			info.source = body
			info.tags = [&"contact"]
			info.position = global_position
			take_damage(info)
			return

## Recebe dano respeitando a profundidade maxima de efeitos e os i-frames.
func take_damage(info: DamageInfo) -> void:
	if info.trigger_depth > 3:
		return
	if is_invulnerable():
		return
	_invuln_timer = _stats.get_stat(&"hit_invuln")
	health.apply_damage(info)

func _on_health_damaged(info: DamageInfo, _actual_drop: float) -> void:
	EventBus.player_hit.emit(info)
	_dispatcher.dispatch(&"on_damaged", info, 0)

func _on_enemy_died(_enemy: Node, fatal_info: DamageInfo) -> void:
	if fatal_info != null and fatal_info.source == self:
		_dispatcher.dispatch(&"on_kill", fatal_info, fatal_info.trigger_depth)

func _on_died(_fatal_info: DamageInfo) -> void:
	GameState.player_lives = maxi(0, GameState.player_lives - 1)
	_reset_omni_stop_spin()
	_spawn_teleport_fx(global_position)
	if GameState.player_lives <= 0:
		hide()
		set_physics_process(false)
		return  # sem renascer: o HUD assume o fim de jogo
	global_position = _spawn_point
	velocity = Vector2.ZERO
	_reset_omni_stop_spin()
	health.reset()
	_blink_cd = 0.0
	_blink_cd_duration = 0.0
	_ability_q_cd = 0.0
	_ability_q_cd_duration = 0.0
	_ability_e_cd = 0.0
	_ability_e_cd_duration = 0.0
	_stats.clear_temporary()
	_invuln_timer = _stats.get_stat(&"respawn_invuln")
	_spawn_teleport_fx(_spawn_point)

## Mantém a nave dentro da arena atual.
func _clamp_to_bounds() -> void:
	var m := 10.0
	global_position.x = clampf(global_position.x, _room_bounds.position.x + m, _room_bounds.end.x - m)
	global_position.y = clampf(global_position.y, _room_bounds.position.y + m, _room_bounds.end.y - m)

## Mantém a pose neutra: A/S/D não geram strafe nem inclinação.
func _update_bank(omni_direction: Vector2 = Vector2.ZERO) -> void:
	if _is_omni_ship():
		if _omni_stop_spin_state == SpinState.SPINNING:
			return
		var target := clampf(omni_direction.x * deg_to_rad(3.0), -deg_to_rad(3.0), deg_to_rad(3.0))
		visual_root.rotation = lerpf(visual_root.rotation, target, 0.2)
		return
	visual_root.rotation = 0.0
	if sprite.animation != &"neutral":
		sprite.play(&"neutral")

## O propulsor estica e intensifica conforme a velocidade atual.
func _update_thruster(omni_direction: Vector2 = Vector2.DOWN) -> void:
	if _is_omni_ship() and _omni_stop_spin_state == SpinState.SPINNING:
		for current_thruster in thrusters:
			current_thruster.emitting = true
			current_thruster.initial_velocity_min = 12.0
			current_thruster.initial_velocity_max = 24.0
			current_thruster.scale_amount_min = 0.45
			current_thruster.scale_amount_max = 0.7
		return
	var ratio := clampf(velocity.length() / _stats.get_stat(&"max_speed"), 0.0, 1.0)
	for current_thruster in thrusters:
		var active := current_thruster == thruster if not _is_omni_ship() else _is_thruster_active(current_thruster, omni_direction)
		current_thruster.emitting = active and (not _is_omni_ship() or omni_direction != Vector2.ZERO)
		current_thruster.initial_velocity_min = 20.0 + ratio * 40.0
		current_thruster.initial_velocity_max = 50.0 + ratio * 70.0
		current_thruster.scale_amount_min = 0.8 + ratio * 0.4
		current_thruster.scale_amount_max = 1.4 + ratio * 0.8

func _is_thruster_active(current_thruster: CPUParticles2D, direction: Vector2) -> bool:
	return (
		(current_thruster == thruster and direction.y < 0.0)
		or (current_thruster == $VisualRoot/ThrusterTop and direction.y > 0.0)
		or (current_thruster == $VisualRoot/ThrusterLeft and direction.x > 0.0)
		or (current_thruster == $VisualRoot/ThrusterRight and direction.x < 0.0)
	)

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

## Resolve o dano no quadro do blink; o FX posterior nunca participa da fisica.
func _resolve_blink_trail_damage(origin: Vector2, dest: Vector2) -> void:
	if ship == null or not ship.blink_trail_enabled or ship.blink_trail_damage <= 0.0 or ship.blink_trail_width <= 0.0 or ship.blink_trail_duration <= 0.0:
		return
	var segment := dest - origin
	var segment_length_squared := segment.length_squared()
	if segment_length_squared <= 0.001:
		return
	var hit_targets: Dictionary = {}
	var radius := ship.blink_trail_width * 0.5
	for node in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(node) or node.is_queued_for_deletion() or not node.has_method("take_damage"):
			continue
		var target := node as Node2D
		if target == null:
			continue
		var target_id := target.get_instance_id()
		if hit_targets.has(target_id):
			continue
		var projection := clampf((target.global_position - origin).dot(segment) / segment_length_squared, 0.0, 1.0)
		var closest_point := origin + segment * projection
		if target.global_position.distance_to(closest_point) > radius:
			continue
		hit_targets[target_id] = true
		var info := DamageInfo.new()
		info.amount = ship.blink_trail_damage
		info.source = self
		info.position = target.global_position
		info.tags = [&"blink", &"interceptor_blink_trail"]
		target.take_damage(info)

func _spawn_interceptor_blink_trail(origin: Vector2, dest: Vector2) -> void:
	if _effects == null or ship == null or not ship.blink_trail_enabled or ship.blink_trail_width <= 0.0 or ship.blink_trail_duration <= 0.0:
		return
	var fx := INTERCEPTOR_BLINK_TRAIL.instantiate()
	_effects.add_child(fx)
	fx.configure(origin, dest, character.thrust_color, ship.blink_trail_width, ship.blink_trail_duration)

## O boost pertence a camada visual local e nao afeta a resolucao instantanea do blink.
func _boost_detail_lines_for_blink() -> void:
	if is_instance_valid(_detail_lines) and _detail_lines.has_method(&"boost_for_blink"):
		_detail_lines.boost_for_blink()

## Dispara enquanto Espaço estiver pressionado, respeitando a cadência.
func _handle_fire(delta: float) -> void:
	if _fire_cooldown <= 0.0 and Input.is_action_pressed("shoot"):
		_fire()
		_fire_cooldown = 1.0 / _stats.get_stat(&"fire_rate")

func _fire() -> void:
	if _projectiles == null or (ship != null and not ship.has_muzzle):
		return
	var tier := clampi(_stats.get_stat_int(&"aim_tier"), 0, 3)
	var fire_dir := _aim_vector
	if tier > 0:
		var target_dir := _select_aim_target(tier)
		if target_dir != Vector2.ZERO:
			fire_dir = target_dir
	var b := Pools.acquire(BULLET)
	if b.get_parent() == null:
		_projectiles.add_child(b)
	b.set_room_bounds(_room_bounds)
	b.activate(muzzle.global_position, fire_dir, self, _stats.get_stat(&"damage"))
	_dispatcher.dispatch(&"on_fire", null, 0)

func _gather_effects() -> Array[EffectDef]:
	var effects: Array[EffectDef] = []
	if ship != null:
		effects.append_array(ship.effects)
	if character != null:
		effects.append_array(character.effects)
	return effects

## Escolhe o inimigo vivo mais alinhado à mira dentro do cone do tier atual.
func _select_aim_target(tier: int) -> Vector2:
	var max_angle: float = AIM_CONE_ANGLES[tier]
	var best_angle := INF
	var best_direction := Vector2.ZERO
	for node in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		var enemy := node as Node2D
		if enemy == null:
			continue
		var to_enemy := enemy.global_position - global_position
		if to_enemy.length() > 400.0 or to_enemy.length() < 0.001:
			continue
		var enemy_direction := to_enemy.normalized()
		var angle_difference := absf(_aim_vector.angle_to(enemy_direction))
		if angle_difference > max_angle or angle_difference >= best_angle:
			continue
		best_angle = angle_difference
		best_direction = enemy_direction
	return best_direction
