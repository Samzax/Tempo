class_name HasTagCondition
extends ConditionDef
## Verifica se o dano associado ao evento possui uma tag.

@export var tag: StringName

func check(context: EffectContext) -> bool:
	return context.payload is DamageInfo and (context.payload as DamageInfo).tags.has(tag)
