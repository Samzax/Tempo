extends Node
## Disponibiliza globalmente as definições de estatísticas do catálogo.

const STAT_CATALOG = preload("res://resources/stats/stat_catalog.tres")

var _stats_by_id: Dictionary = {}

func _init() -> void:
	for stat: StatDef in STAT_CATALOG.stats:
		_stats_by_id[stat.id] = stat

## Devolve a definição de uma estatística conhecida.
func get_stat(id: StringName) -> StatDef:
	if not _stats_by_id.has(id):
		push_error("Estatística desconhecida: %s" % id)
		return null
	return _stats_by_id[id]

## Informa se uma estatística pertence ao catálogo.
func has_stat(id: StringName) -> bool:
	return _stats_by_id.has(id)

## Devolve todas as definições de estatísticas do catálogo.
func get_all() -> Array[StatDef]:
	var stats: Array[StatDef] = []
	for stat: StatDef in STAT_CATALOG.stats:
		stats.append(stat)
	return stats
