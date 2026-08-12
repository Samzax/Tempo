extends Node
## Barramento de sinais global — desacopla emissores de ouvintes.
## Novos sinais são adicionados conforme os sistemas surgem.

@warning_ignore("unused_signal")
signal player_hit(info: DamageInfo)
@warning_ignore("unused_signal")
signal enemy_died(enemy: Node, fatal_info: DamageInfo)
@warning_ignore("unused_signal")
signal ability_used(slot: StringName)
@warning_ignore("unused_signal")
signal temporal_echoes_credited(amount: int, total: int)
@warning_ignore("unused_signal")
signal temporal_echoes_spent(amount: int, total: int)
