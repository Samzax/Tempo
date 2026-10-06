class_name ContactRicochet
extends RefCounted

## Contato fisico entre corpos. A restituicao roteirizada substitui a resposta
## nativa do deslizamento apenas quando existe outro corpo participante na
## mesma colisao; fora disso a resposta nativa (paredes, por exemplo) segue
## intacta. O impulso e aplicado uma unica vez por par por frame fisico.

## Restituicao aprovada no staging de game feel entre corpos.
const RESTITUTION := 0.85
## Massa minima para evitar divisao por zero no reparto de impulso.
const MIN_MASS := 0.01
## O impulso adiado ao jogador sobrevive a no maximo este intervalo de frames.
const DEFERRED_LIFETIME_FRAMES := 1

## Velocidade de controle congelada imediatamente antes do deslizamento.
static var _pre_velocity: Dictionary = {}
## Par de corpos ja impulsionados no frame fisico corrente.
static var _pairs: Dictionary = {}
## Delta adiado ao jogador ate a leitura de contatos do proprio frame.
static var _deferred: Dictionary = {}

## Guarda a velocidade de controle antes do slide para separar a resposta
## nativa do corpo da correcao roteirizada.
static func prepare(body: CharacterBody2D) -> void:
	if body == null or not is_instance_valid(body):
		return
	_purge_stale()
	_pre_velocity[body.get_instance_id()] = {
		&"frame": Engine.get_physics_frames(),
		&"v": body.velocity,
		&"post": body.velocity,
	}

## Devolve a velocidade de controle apos o slide e arquiva a resposta nativa.
## Sem esta restauracao o deslizamento zera a componente normal de contato e
## o leitor de sobreposicoes deixaria de ver a velocidade de aproximacao.
static func restore_after_slide(body: CharacterBody2D) -> void:
	if body == null or not is_instance_valid(body):
		return
	var entry: Variant = _pre_velocity.get(body.get_instance_id())
	if not entry is Dictionary:
		return
	entry[&"post"] = body.velocity
	body.velocity = entry[&"v"]

## Aplica o impulso roteirizado uma vez por par e decide a velocidade final do
## corpo: resposta nativa quando nao ha participante, correcao quando ha.
static func resolve(body: CharacterBody2D) -> void:
	if body == null or not is_instance_valid(body):
		return
	var id := body.get_instance_id()
	var entry: Variant = _pre_velocity.get(id)
	if not entry is Dictionary:
		return
	var frame := Engine.get_physics_frames()
	if int(entry.get(&"frame", -1)) != frame:
		return
	if int(entry.get(&"resolved", -1)) == frame:
		return
	entry[&"resolved"] = frame
	var v0: Vector2 = entry.get(&"v", body.velocity)
	var post: Vector2 = entry.get(&"post", v0)
	_purge_stale()
	# O flush do delta adiado ja somou a velocidade; preserva esse valor.
	var already := body.velocity - v0
	var total := Vector2.ZERO
	var applied := false
	for index in body.get_slide_collision_count():
		var collision := body.get_slide_collision(index)
		if collision == null:
			continue
		var other := collision.get_collider()
		# Um inimigo morto neste quadro nao participa: o par nao e registrado e
		# nenhum impulso e escrito em corpo ja na fila de liberacao. O deslize
		# nativo responde ao contato e o caminho nao quebra.
		if not is_participant(other):
			continue
		var other_body := other as CharacterBody2D
		if other_body == null:
			continue
		var other_id := other_body.get_instance_id()
		if other_id == id:
			continue
		var pair := _pair_key(id, other_id)
		if int(_pairs.get(pair, -1)) == frame:
			continue
		_pairs[pair] = frame
		var normal := collision.get_normal()
		if not _finite_vector(normal) or normal.length_squared() <= 0.0:
			continue
		normal = normal.normalized()
		# Normal canonica do par: min_id -> max_id. A normal do Godot aponta da
		# superficie para o movel, entao a orientacao depende de quem sou.
		var self_is_min := id < other_id
		var n_ab: Vector2 = -normal if self_is_min else normal
		var v0_other: Vector2 = other_body.velocity
		var other_entry: Variant = _pre_velocity.get(other_id)
		if other_entry is Dictionary and int(other_entry.get(&"frame", -1)) == frame:
			v0_other = other_entry.get(&"v", other_body.velocity)
		var mass_self := mass_of(body)
		var mass_other := mass_of(other_body)
		var v0_a: Vector2 = v0 if self_is_min else v0_other
		var v0_b: Vector2 = v0_other if self_is_min else v0
		var mass_a: float = mass_self if self_is_min else mass_other
		var mass_b: float = mass_other if self_is_min else mass_self
		var impulse := compute_impulse(v0_a, v0_b, n_ab, mass_a, mass_b)
		if not impulse[&"applied"]:
			continue
		var delta_self: Vector2 = impulse[&"da"] if self_is_min else impulse[&"db"]
		var delta_other: Vector2 = impulse[&"db"] if self_is_min else impulse[&"da"]
		if is_player_body(other_body):
			# O jogador so le o delta na leitura de contatos do frame, para nao
			# sobrescrever o knockback que o resolver de impactos ja somou.
			defer(other_body, delta_other)
		elif other_body.has_method(&"apply_collision_knockback"):
			other_body.call(&"apply_collision_knockback", delta_other)
		total += delta_self
		applied = true
	if applied:
		body.velocity = v0 + already + total
		if body.has_method(&"apply_collision_knockback"):
			body.call(&"apply_collision_knockback", total)
	else:
		# Sem participante a resposta nativa do slide vale por inteiro.
		body.velocity = post + already

## Registra um delta adiado ao jogador ate o flush do proprio frame.
static func defer(body: Variant, delta: Vector2) -> void:
	if body == null or not is_instance_valid(body):
		return
	if not _finite_vector(delta) or delta == Vector2.ZERO:
		return
	var frame := Engine.get_physics_frames()
	var id: int = body.get_instance_id()
	var entry: Variant = _deferred.get(id)
	if entry is Dictionary and int(entry.get(&"frame", -1)) >= frame - DEFERRED_LIFETIME_FRAMES:
		entry[&"delta"] = entry.get(&"delta", Vector2.ZERO) + delta
		entry[&"frame"] = frame
		return
	_deferred[id] = {&"delta": delta, &"frame": frame}

## Consome o delta adiado: soma a velocidade e ao canal de knockback para que a
## extracao da base controlada (velocity - knockback) continue limpa.
static func flush_deferred(body: CharacterBody2D) -> void:
	if body == null or not is_instance_valid(body):
		return
	var id := body.get_instance_id()
	var entry: Variant = _deferred.get(id)
	if not entry is Dictionary:
		return
	_deferred.erase(id)
	if int(entry.get(&"frame", -1)) < Engine.get_physics_frames() - DEFERRED_LIFETIME_FRAMES:
		return
	var delta: Vector2 = entry.get(&"delta", Vector2.ZERO)
	if not _finite_vector(delta) or delta == Vector2.ZERO:
		return
	body.velocity += delta
	if body.has_method(&"apply_collision_knockback"):
		body.call(&"apply_collision_knockback", delta)

## Descarta o delta adiado sem somar. Usado quando a leitura de contatos
## derrubou o jogador no meio do quadro: o reset de morte ja zerou o canal de
## knockback e a velocidade, e somar agora reacenderia estado morto.
static func discard_deferred(body: Variant) -> void:
	if body == null or not is_instance_valid(body):
		return
	_deferred.erase(body.get_instance_id())

## Impulso puro de reparto de momento. Devolve o delta de cada lado do par.
static func compute_impulse(v0a: Vector2, v0b: Vector2, n_ab: Vector2, mass_a: float, mass_b: float) -> Dictionary:
	var no_impulse := {&"applied": false, &"j": 0.0, &"da": Vector2.ZERO, &"db": Vector2.ZERO}
	if not _finite_vector(n_ab) or n_ab.length_squared() <= 0.0:
		return no_impulse
	if not _finite_vector(v0a) or not _finite_vector(v0b):
		return no_impulse
	var normal := n_ab.normalized()
	var ma := _finite_mass(mass_a)
	var mb := _finite_mass(mass_b)
	var closing := (v0a - v0b).dot(normal)
	if not is_finite(closing) or closing <= 0.0:
		return no_impulse
	var j := (1.0 + RESTITUTION) * closing / (1.0 / ma + 1.0 / mb)
	if not is_finite(j):
		return no_impulse
	return {
		&"applied": true,
		&"j": j,
		&"da": normal * (-j / ma),
		&"db": normal * (j / mb),
	}

## Ator de contato: classe e capacidades exigidas pela condicao D2, sem olhar o
## estado de fila. O cadaver de um inimigo continua sendo ator ate o fim do
## quadro, entao ele nao vira "mundo" no caminho da investida.
static func is_contact_actor(body: Variant) -> bool:
	if body == null or not is_instance_valid(body):
		return false
	if not body is CharacterBody2D:
		return false
	return body.has_method(&"get_collision_mass") and body.has_method(&"apply_collision_knockback")

## Participante do calculo de impulso: ator de contato que nao esta na fila de
## liberacao. A escolha para o ricochete de tick e deixar o cadaver de fora dos
## dois lados do par (nada e escrito em corpo destruido), mantendo a resposta
## nativa do deslizamento e sem quebrar o loop de contatos.
static func is_participant(body: Variant) -> bool:
	if not is_contact_actor(body):
		return false
	var node := body as Node
	return node != null and not node.is_queued_for_deletion()

## O jogador e identificado so pelo contrato de impacto, nunca por grupo.
static func is_player_body(body: Variant) -> bool:
	if body == null or not is_instance_valid(body):
		return false
	return body.has_method(&"get_collision_impact_generation")

static func mass_of(body: Variant) -> float:
	if body != null and is_instance_valid(body) and body.has_method(&"get_collision_mass"):
		return _finite_mass(float(body.call(&"get_collision_mass")))
	return MIN_MASS

## Descarta entradas que ja pertencem a frames anteriores.
static func clear_all_state() -> void:
	_pre_velocity.clear()
	_pairs.clear()
	_deferred.clear()

static func _purge_stale() -> void:
	var current := Engine.get_physics_frames()
	for id in _pre_velocity.keys():
		var entry: Variant = _pre_velocity[id]
		if not entry is Dictionary or int(entry.get(&"frame", -1)) < current:
			_pre_velocity.erase(id)
	for id in _pairs.keys():
		if int(_pairs.get(id, -1)) < current:
			_pairs.erase(id)
	for id in _deferred.keys():
		var entry: Variant = _deferred[id]
		if not entry is Dictionary or int(entry.get(&"frame", -1)) < current - DEFERRED_LIFETIME_FRAMES:
			_deferred.erase(id)

static func _pair_key(id_a: int, id_b: int) -> String:
	var low := mini(id_a, id_b)
	var high := maxi(id_a, id_b)
	return "%d:%d" % [low, high]

static func _finite_mass(value: float) -> float:
	if not is_finite(value) or value <= 0.0:
		return MIN_MASS
	return maxf(value, MIN_MASS)

static func _finite_vector(value: Vector2) -> bool:
	return is_finite(value.x) and is_finite(value.y)
