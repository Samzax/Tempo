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
