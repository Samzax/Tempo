class_name ShipDef
extends ProviderDef
## Define os dados de autoria de uma nave jogável.

@export var display_name: String
@export var hull_texture: Texture2D
@export var base_stats: Array[BaseStatValue] = []
@export var ability_q: StringName
## Um Q sem habilidade ativa pode ser apresentado como passivo, sem sugerir input.
@export var q_slot_passive: bool = false
## Habilidade exclusiva do Shift. Vazia preserva blink ou o fallback legado.
@export var ability_shift: StringName
## Acao sem habilidade do Shift (por exemplo, reposicionar um drone ja implantado).
@export var shift_command_id: StringName
## Glifo aprovado para a acao de comando; pode reutilizar a arte de outra acao da mesma familia.
@export var shift_command_icon_id: StringName
## Desliga o blink sem acoplar o controle a uma identidade de nave especifica.
@export var can_blink: bool = true
## Defaults preserve the original aim-driven 16x24 ship presentation.
@export_enum("aim_forward", "omni") var movement_style: String = "aim_forward"
@export var frame_size: Vector2i = Vector2i(16, 24)
## Grade do atlas da nave. Os defaults preservam as cinco poses e dois frames do casco legado.
@export var atlas_grid_size: Vector2i = Vector2i(5, 2)
## Regiões de atlas opcionais, em ordem de animação e frame. Permite frames não uniformes.
@export var custom_frame_regions: Array[Rect2] = []
## Rotacao aplicada somente ao sprite; nao afeta a mira, a fisica nem o Muzzle.
@export_range(-360.0, 360.0, 1.0, "radians_as_degrees") var visual_rotation_offset: float = 0.0
@export_range(0.01, 4.0, 0.01) var visual_scale: float = 1.0
@export_range(1.0, 32.0, 0.5) var hurtbox_radius: float = 8.0
@export_enum("capsule", "circle") var collision_shape_type: String = "capsule"
@export var has_muzzle: bool = true
## Deslocamento local adicional a partir do Marker2D de disparo da cena.
@export var muzzle_offset: Vector2 = Vector2.ZERO
@export var thrusters_enabled: bool = true
## Contrato opt-in para o rastro ofensivo do blink. Os defaults permanecem inertes.
@export var blink_trail_enabled: bool = false
@export_range(0.0, 100.0, 0.1) var blink_trail_damage: float = 0.0
@export_range(0.0, 128.0, 0.5) var blink_trail_width: float = 0.0
@export_range(0.01, 2.0, 0.01) var blink_trail_duration: float = 0.18
## Contrato opt-in para um rastro ofensivo emitido pelo movimento. Defaults inertes.
@export var engine_trail_enabled: bool = false
@export_range(0.0, 100.0, 0.1) var engine_trail_damage: float = 0.0
@export_range(0.0, 128.0, 0.5) var engine_trail_width: float = 0.0
@export_range(0.01, 5.0, 0.01) var engine_trail_duration: float = 0.8
@export_range(0.0, 1.0, 0.01) var engine_trail_min_speed_ratio: float = 0.5
@export_range(0.01, 5.0, 0.01) var engine_trail_damage_cooldown: float = 0.5
## Distancia minima entre pares de segmentos; evita emissao dependente do frame rate.
@export_range(1.0, 128.0, 1.0) var engine_trail_segment_spacing: float = 32.0
## Devolve os erros de autoria encontrados nesta nave.
func validate_content() -> Array[String]:
	var errors := super()
	if movement_style not in ["aim_forward", "omni"]:
		errors.append("Estilo de movimento desconhecido: %s." % movement_style)
	if movement_style == "omni" and muzzle_offset != Vector2.ZERO:
		errors.append("muzzle_offset diferente de zero so e suportado com movement_style aim_forward.")
	if frame_size.x <= 0 or frame_size.y <= 0:
		errors.append("Tamanho de frame invalido: %s." % frame_size)
	if atlas_grid_size.x <= 0 or atlas_grid_size.y <= 0:
		errors.append("Grade de atlas invalida: %s." % atlas_grid_size)
	if not custom_frame_regions.is_empty():
		if custom_frame_regions.size() != 10:
			errors.append("Atlas com regioes customizadas precisa de exatamente 10 regioes.")
		else:
			var atlas_size := hull_texture.get_size() if hull_texture != null else Vector2.ZERO
			var covered_area := 0.0
			for region_index in custom_frame_regions.size():
				var region := custom_frame_regions[region_index]
				if region.size.x <= 0.0 or region.size.y <= 0.0:
					errors.append("Regiao customizada %d precisa ter tamanho positivo." % region_index)
					continue
				if hull_texture != null and (region.position.x < 0.0 or region.position.y < 0.0 or region.end.x > atlas_size.x or region.end.y > atlas_size.y):
					errors.append("Regiao customizada %d esta fora do atlas configurado." % region_index)
				covered_area += region.get_area()
			for left_index in custom_frame_regions.size():
				for right_index in range(left_index + 1, custom_frame_regions.size()):
					if custom_frame_regions[left_index].intersects(custom_frame_regions[right_index]):
						errors.append("Regioes customizadas %d e %d se sobrepoem." % [left_index, right_index])
			if hull_texture != null and not is_equal_approx(covered_area, atlas_size.x * atlas_size.y):
				errors.append("Regioes customizadas devem cobrir integralmente o atlas configurado.")
	if visual_scale <= 0.0:
		errors.append("Escala visual deve ser positiva.")
	if hurtbox_radius <= 0.0:
		errors.append("Raio da hurtbox deve ser positivo.")
	if collision_shape_type not in ["capsule", "circle"]:
		errors.append("Formato de colisao desconhecido: %s." % collision_shape_type)
	if blink_trail_enabled:
		if blink_trail_damage <= 0.0:
			errors.append("Rastro do blink habilitado precisa de dano positivo.")
		if blink_trail_width <= 0.0:
			errors.append("Rastro do blink habilitado precisa de largura positiva.")
		if blink_trail_duration <= 0.0:
			errors.append("Rastro do blink habilitado precisa de duracao positiva.")
	if engine_trail_enabled:
		if engine_trail_damage <= 0.0:
			errors.append("Rastro do propulsor habilitado precisa de dano positivo.")
		if engine_trail_width <= 0.0:
			errors.append("Rastro do propulsor habilitado precisa de largura positiva.")
		if engine_trail_duration <= 0.0:
			errors.append("Rastro do propulsor habilitado precisa de duracao positiva.")
		if engine_trail_min_speed_ratio <= 0.0 or engine_trail_min_speed_ratio > 1.0:
			errors.append("Rastro do propulsor precisa de uma razao minima de velocidade entre 0 e 1.")
		if engine_trail_damage_cooldown <= 0.0:
			errors.append("Rastro do propulsor habilitado precisa de cooldown de dano positivo.")
		if engine_trail_segment_spacing <= 0.0:
			errors.append("Rastro do propulsor habilitado precisa de espacamento positivo.")
	var seen_stats: Dictionary = {}
	for base_stat_index in base_stats.size():
		var base_stat := base_stats[base_stat_index]
		if base_stat == null:
			errors.append("Estatística base nula no indice %d." % base_stat_index)
			continue
		if not StatCatalog.has_stat(base_stat.stat):
			errors.append("Valor base usa estatística desconhecida: %s." % base_stat.stat)
		if seen_stats.has(base_stat.stat):
			errors.append("Estatística base repetida: %s." % base_stat.stat)
		else:
			seen_stats[base_stat.stat] = true
	if not ability_q.is_empty() and not AbilityCatalog.is_valid(ability_q):
		errors.append("Habilidade da nave desconhecida: %s." % ability_q)
	if not ability_shift.is_empty() and not AbilityCatalog.is_valid(ability_shift):
		errors.append("Habilidade de Shift da nave desconhecida: %s." % ability_shift)
	if shift_command_id.is_empty() != shift_command_icon_id.is_empty():
		errors.append("Comando de Shift precisa de ID funcional e ID de glifo.")
	return errors
