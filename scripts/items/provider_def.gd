class_name ProviderDef
extends Resource
## Define a base compartilhada por recursos que fornecem modificadores e efeitos.

@export var id: StringName
@export var tags: Array[StringName] = []
@export var modifiers: Array[StatModifierDef] = []
@export var effects: Array[EffectDef] = []

## Cria modificadores de execução com a origem deste provedor injetada.
func get_runtime_modifiers() -> Array[StatModifierDef]:
	var runtime_modifiers: Array[StatModifierDef] = []
	for modifier in modifiers:
		if modifier == null:
			continue
		var runtime_modifier := modifier.duplicate() as StatModifierDef
		runtime_modifier.source_id = id
		runtime_modifiers.append(runtime_modifier)
	return runtime_modifiers

## Devolve os erros de autoria encontrados neste recurso, sem alterá-lo.
func validate_content() -> Array[String]:
	var errors: Array[String] = []
	if id.is_empty():
		errors.append("O provedor precisa de um id não vazio.")

	for modifier_index in modifiers.size():
		var modifier := modifiers[modifier_index]
		if modifier == null:
			errors.append("Modificador nulo no indice %d." % modifier_index)
			continue
		if not StatCatalog.has_stat(modifier.stat):
			errors.append("Modificador usa estatística desconhecida: %s." % modifier.stat)
			continue
		var stat: StatDef = StatCatalog.get_stat(modifier.stat)
		if not stat.allowed_ops.has(modifier.op):
			errors.append("Operação não permitida para a estatística: %s." % modifier.stat)

	for effect_index in effects.size():
		var effect := effects[effect_index]
		if effect == null:
			errors.append("Efeito nulo no indice %d." % effect_index)
			continue
		if not EventCatalog.is_valid(effect.event):
			errors.append("Efeito usa evento desconhecido: %s." % effect.event)
		if effect.chance < 0.0 or effect.chance > 1.0:
			errors.append("Efeito tem chance fora do intervalo de 0.0 a 1.0.")

	for tag_index in tags.size():
		var tag := tags[tag_index]
		if tag == null or tag.is_empty():
			errors.append("Tag nula ou vazia no indice %d." % tag_index)
			continue
		if not TagCatalog.is_valid(tag):
			errors.append("Tag desconhecida: %s." % tag)

	return errors
