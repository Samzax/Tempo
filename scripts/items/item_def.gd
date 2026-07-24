class_name ItemDef
extends ProviderDef
## Define os dados de autoria de um item coletável.

enum Rarity {
	COMMON,
	RARE,
	LEGENDARY,
}

@export var display_name: String
@export_multiline var description: String
@export var icon: Texture2D
@export var rarity: Rarity = Rarity.COMMON
@export var pools: Array[StringName] = []
@export var max_stacks: int = 1

## Devolve os erros de autoria encontrados neste item.
func validate_content() -> Array[String]:
	var errors := super()
	if max_stacks < 1:
		errors.append("O item precisa permitir ao menos um acúmulo.")
	return errors
