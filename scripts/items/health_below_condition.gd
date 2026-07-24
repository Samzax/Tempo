class_name HealthBelowCondition
extends ConditionDef
## Verifica se a vida atual do dono esta abaixo da fracao configurada.

@export var fraction: float = 0.5

func check(context: EffectContext) -> bool:
	var health_component = context.owner.get("health")
	if health_component == null:
		return false
	return health_component.health < health_component.max_health * fraction
