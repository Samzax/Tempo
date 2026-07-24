class_name AbilityDef
extends Resource
## Define a interface base para habilidades ativas do jogador.

var id: StringName
var display_name: String
var cooldown: float = 0.0
var icon: Texture2D

## Ativa a habilidade para o jogador informado.
func activate(_player: Node2D) -> void:
	pass
