class_name BrutaChargeAbility
extends AbilityDef
## Investida continua da Bruta; o estado de movimento pertence ao Player.

func _init() -> void:
	id = &"bruta_investida"
	display_name = "Investida Brutal"
	cooldown = 7.5

func try_activate(player: Node2D) -> bool:
	if player == null or not player.has_method(&"start_bruta_charge"):
		return false
	return bool(player.call(&"start_bruta_charge"))
