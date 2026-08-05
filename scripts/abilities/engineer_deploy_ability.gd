class_name EngineerDeployAbility
extends AbilityDef
## Habilidade Q da Engenheira. ID estavel: &"engenheira_deploy".

func _init() -> void:
	id = &"engenheira_deploy"
	display_name = "Deploy da Engenheira"
	cooldown = 2.0

func activate(player: Node2D) -> void:
	try_activate(player)

func try_activate(player: Node2D) -> bool:
	if player == null or not player.has_method(&"deploy_engineer_gadget"):
		return false
	return bool(player.call(&"deploy_engineer_gadget"))
