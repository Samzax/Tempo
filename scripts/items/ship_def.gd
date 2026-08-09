class_name ShipDef
extends ProviderDef
## Define os dados de autoria de uma nave jogável.

@export var display_name: String
@export var hull_texture: Texture2D
@export var base_stats: Array[BaseStatValue] = []
@export var ability_q: StringName
## Defaults preserve the original aim-driven 16x24 ship presentation.
@export_enum("aim_forward", "omni") var movement_style: String = "aim_forward"
@export var frame_size: Vector2i = Vector2i(16, 24)
@export_range(1.0, 32.0, 0.5) var hurtbox_radius: float = 8.0
@export_enum("capsule", "circle") var collision_shape_type: String = "capsule"
@export var has_muzzle: bool = true
@export var thrusters_enabled: bool = true
## Contrato opt-in para o rastro ofensivo do blink. Os defaults permanecem inertes.
@export var blink_trail_enabled: bool = false
@export_range(0.0, 100.0, 0.1) var blink_trail_damage: float = 0.0
@export_range(0.0, 128.0, 0.5) var blink_trail_width: float = 0.0
@export_range(0.01, 2.0, 0.01) var blink_trail_duration: float = 0.18
## Camada opt-in de linhas coloridas sobre o casco. Defaults neutros a mantem inativa.
@export var detail_lines_enabled: bool = false
@export_range(0.0, 30.0, 0.1) var detail_lines_pulse_frequency: float = 0.0
@export_range(0.0, 1.0, 0.01) var detail_lines_alpha_min: float = 0.0
@export_range(0.0, 1.0, 0.01) var detail_lines_alpha_max: float = 0.0
@export_range(0.0, 16.0, 0.1) var detail_lines_width: float = 0.0

## Devolve os erros de autoria encontrados nesta nave.
func validate_content() -> Array[String]:
	var errors := super()
	if movement_style not in ["aim_forward", "omni"]:
		errors.append("Estilo de movimento desconhecido: %s." % movement_style)
	if frame_size.x <= 0 or frame_size.y <= 0:
		errors.append("Tamanho de frame invalido: %s." % frame_size)
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
	if detail_lines_enabled:
		if detail_lines_pulse_frequency <= 0.0:
			errors.append("Linhas de detalhe habilitadas precisam de frequencia positiva.")
		if detail_lines_alpha_min <= 0.0:
			errors.append("Linhas de detalhe habilitadas precisam de alpha minimo positivo.")
		if detail_lines_alpha_max <= 0.0:
			errors.append("Linhas de detalhe habilitadas precisam de alpha maximo positivo.")
		if detail_lines_alpha_min > detail_lines_alpha_max:
			errors.append("Linhas de detalhe precisam ter alpha minimo menor ou igual ao maximo.")
		if detail_lines_width <= 0.0:
			errors.append("Linhas de detalhe habilitadas precisam de largura positiva.")
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
	return errors
