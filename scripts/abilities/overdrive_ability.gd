class_name OverdriveAbility
extends AbilityDef
## Dobra temporariamente a cadencia de tiro do jogador.

func _init() -> void:
	id = &"sobrecarga"
	display_name = "Sobrecarga"
	cooldown = 8.0

## Cria o modificador temporario aplicado pela sobrecarga.
func make_modifier() -> StatModifierDef:
	var modifier := StatModifierDef.new()
	modifier.stat = &"fire_rate"
	modifier.op = StatDef.Op.ADD_PCT
	modifier.value = 1.0
	modifier.duration = 3.0
	modifier.source_id = id
	return modifier

func activate(player: Node2D) -> void:
	player._stats.add_modifier(make_modifier())
