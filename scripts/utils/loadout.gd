class_name Loadout
extends RefCounted
## Aplica os dados de nave e personagem a um bloco de estatísticas.

static func apply(stats: StatBlock, ship: ShipDef, character: CharacterDef) -> void:
	if ship != null:
		for base_stat in ship.base_stats:
			if base_stat == null:
				continue
			stats.set_base(base_stat.stat, base_stat.value)

		for modifier in ship.get_runtime_modifiers():
			stats.add_modifier(modifier)

	if character != null:
		for modifier in character.get_runtime_modifiers():
			stats.add_modifier(modifier)
