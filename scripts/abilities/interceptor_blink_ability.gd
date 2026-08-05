class_name InterceptorBlinkAbility
extends AbilityDef
## Habilidade Q da Interceptadora. ID estavel: &"interceptadora_blink".

func _init() -> void:
	id = &"interceptadora_blink"
	display_name = "Blink da Interceptadora"
	cooldown = 0.9

func try_activate(player: Node2D) -> bool:
	if player == null or not player.has_method(&"try_blink"):
		return false
	# try_blink tambem controla a recarga fisica compartilhada com o Shift.
	return bool(player.call(&"try_blink"))

func get_cooldown(player: Node2D) -> float:
	if player == null or not player.has_method(&"blink_cooldown_duration"):
		return cooldown
	return float(player.call(&"blink_cooldown_duration"))
