class_name ShipDef
extends ProviderDef
## Define os dados de autoria de uma nave jogável.

@export var display_name: String
@export var hull_texture: Texture2D
@export var base_stats: Array[BaseStatValue] = []
@export var ability_q: StringName

## Devolve os erros de autoria encontrados nesta nave.
func validate_content() -> Array[String]:
	var errors := super()
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
	return errors
