class_name HealAction
extends ActionDef
## Recupera a vida do dono quando o efeito e ativado.

@export var amount: float = 1.0

func execute(context: EffectContext) -> void:
	if context == null or context.owner == null:
		return
	var h = context.owner.get("health")
	if h == null:
		return
	h.heal(amount)
