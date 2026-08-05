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

## Variante que informa se a ativacao teve efeito. A implementacao padrao
## preserva habilidades legadas que implementam apenas `activate`.
func try_activate(player: Node2D) -> bool:
	activate(player)
	return true

## Devolve a recarga aplicavel ao slot para este jogador.
func get_cooldown(_player: Node2D) -> float:
	return cooldown
