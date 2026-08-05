class_name HackerOverdriveAbility
extends AbilityDef
## Aumenta temporariamente a cadencia do Hacker sem compartilhar origem com a nave.

const SOURCE_ID := &"hacker_overdrive_runtime"

func _init() -> void:
	id = &"hacker_overdrive"
	display_name = "Overdrive de Precisao"
	cooldown = 8.0

func activate(player: Node2D) -> void:
	player.apply_temporary_modifier(SOURCE_ID, &"fire_rate", StatDef.Op.ADD_PCT, 0.5, 3.0)
