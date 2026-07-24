class_name ShieldAbility
extends AbilityDef
## Concede invulnerabilidade temporaria ao jogador.

func _init() -> void:
	id = &"escudo"
	display_name = "Escudo"
	cooldown = 10.0

func activate(player: Node2D) -> void:
	player.grant_invuln(2.0)
