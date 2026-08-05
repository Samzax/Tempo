extends CharacterBody2D
## Nave do jogador.
## Movimento X,Y com aceleração/atrito, inclinação progressiva (5 poses),
## propulsor reativo, disparo primário (Espaço) e blink (Shift): teleporte
## instantâneo com i-frames. Recebe dano por contato com inimigos (respeitando
## os i-frames) e renasce no centro ao morrer.
	
## Quão rápido a inclinação acompanha a entrada horizontal (poses por segundo).
@export var bank_rate: float = 6.0
@export var ship: ShipDef
@export var character: CharacterDef

const BULLET := preload("res://scenes/projectiles/bullet.tscn")
const TELEPORT_FX := preload("res://scenes/effects/teleport_fx.tscn")
const BLINK_BASE_COOLDOWN := 0.9
## Índices correspondem aos degraus de aim_tier; dentro do cone, a trava é total.
const AIM_CONE_ANGLES := [0.0, PI / 36.0, PI / 12.0, PI / 6.0]

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var thruster: CPUParticles2D = $Thruster
@onready var muzzle: Marker2D = $Muzzle
@onready var health: HealthComponent = $HealthComponent
@onready var hurtbox: Area2D = $Hurtbox

enum AimSource { NONE, MOUSE, JOYPAD }

var _bank: float = 0.0
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
var _bounds: Vector2 = Vector2(
	float(ProjectSettings.get_setting("display/window/size/viewport_width", 480)),
	float(ProjectSettings.get_setting("display/window/size/viewport_height", 270))
)

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

## Aplica a selecao antes do inicio da run. Reconstruir o loadout nao reconecta
## sinais do Player e por isso permanece seguro mesmo apos o _ready da cena.
func configure_character(character_id: StringName) -> void:
	character = CharacterDef.resolve_id(character_id)
	if is_node_ready():
		_configure_loadout()

func _configure_loadout() -> void:
	if character == null:
		character = preload("res://resources/characters/base.tres")
	_stats = StatBlock.new(StatCatalog.get_all())
	Loadout.apply(_stats, ship, character)
	_ability_q = AbilityCatalog.get_ability(ship.ability_q) if ship != null and not ship.ability_q.is_empty() else null
	_ability_e = AbilityCatalog.get_ability(character.ability_e) if character != null and not character.ability_e.is_empty() else null
	_dispatcher = EffectDispatcher.new(self, _gather_effects())
	_inventory = Inventory.new(_stats, _dispatcher)
	if is_instance_valid(health):
		health.max_health = _stats.get_stat(&"max_health")
		health.health = health.max_health

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
		health.max_health = normalized
		health.health = minf(health.health, health.max_health)
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
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	_handle_blink_input(dir)
	_handle_ability_input()

	if dir != Vector2.ZERO:
		velocity = velocity.move_toward(dir * _stats.get_stat(&"max_speed"), _stats.get_stat(&"acceleration") * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, _stats.get_stat(&"friction") * delta)

	move_and_slide()
	_clamp_to_bounds()
	_refresh_mouse_aim()
	_check_contact()
	_update_bank(dir.x, delta)
	_update_thruster()
	_update_invuln_visual()
	muzzle.position = _aim_vector * 12.0
	muzzle.rotation = _aim_vector.angle() + PI / 2.0
	_handle_fire(delta)

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
	elif _last_aim_source == AimSource.MOUSE:
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

## Fracao de recarga da habilidade da nave (0 = pronta, 1 = acabou de usar).
func ability_q_cooldown_ratio() -> float:
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

## Blink: teleporte instantâneo na direção do movimento (ou da mira se parado),
## com efeito de colapso na origem e no destino, i-frames e recarga.
func _handle_blink_input(dir: Vector2) -> void:
	if _blink_cd > 0.0 or not Input.is_action_just_pressed("blink"):
		return
	var bdir := dir.normalized() if dir != Vector2.ZERO else _aim_vector
	var origin := global_position
	var m := 10.0
	var dest := origin + bdir * _stats.get_stat(&"blink_distance")
	dest.x = clampf(dest.x, m, _bounds.x - m)
	dest.y = clampf(dest.y, m, _bounds.y - m)

	global_position = dest      # teleporte instantâneo
	velocity = Vector2.ZERO     # é um blink, não um empurrão
	_dispatcher.dispatch(&"on_blink", null, 0)
	var cd := BLINK_BASE_COOLDOWN / _stats.get_stat(&"blink_haste")
	_blink_cd = cd
	_blink_cd_duration = cd
	_invuln_timer = maxf(_invuln_timer, _stats.get_stat(&"blink_invuln"))
	_spawn_teleport_fx(origin)
	_spawn_teleport_fx(dest)

## Ativa as habilidades equipadas quando seus slots estao prontos.
func _handle_ability_input() -> void:
	if Input.is_action_just_pressed("ability_q") and _ability_q != null and _ability_q_cd <= 0.0:
		_ability_q.activate(self)
		_ability_q_cd = _ability_q.cooldown
		_ability_q_cd_duration = _ability_q.cooldown
		EventBus.ability_used.emit(&"ability_q")
	if Input.is_action_just_pressed("ability_e") and _ability_e != null and _ability_e_cd <= 0.0:
		_ability_e.activate(self)
		_ability_e_cd = _ability_e.cooldown
		_ability_e_cd_duration = _ability_e.cooldown
		EventBus.ability_used.emit(&"ability_e")

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
	_spawn_teleport_fx(global_position)
	if GameState.player_lives <= 0:
		hide()
		set_physics_process(false)
		return  # sem renascer: o HUD assume o fim de jogo
	global_position = _spawn_point
	velocity = Vector2.ZERO
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
	var ratio := clampf(velocity.length() / _stats.get_stat(&"max_speed"), 0.0, 1.0)
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
		_fire_cooldown = 1.0 / _stats.get_stat(&"fire_rate")

func _fire() -> void:
	if _projectiles == null:
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
	b.activate(muzzle.global_position, fire_dir, self)
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
