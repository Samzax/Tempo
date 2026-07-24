class_name CharacterDef
extends ProviderDef
## Define os dados de autoria de um personagem jogável.

@export var display_name: String
@export var description: String
@export var portrait: Texture2D
@export var ability_e: StringName

## Devolve os erros de autoria encontrados neste personagem.
func validate_content() -> Array[String]:
	var errors := super()
	if not ability_e.is_empty() and not AbilityCatalog.is_valid(ability_e):
		errors.append("Habilidade do personagem desconhecida: %s." % ability_e)
	return errors
