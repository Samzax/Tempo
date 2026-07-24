## Encapsula todos os dados de um evento de dano para o sistema de efeitos.
class_name DamageInfo extends RefCounted

## Quantidade de dano bruto antes de mitigacao do alvo.
var amount: float
## Entidade que causou o dano.
var source: Node
## Tags que classificam este dano.
var tags: Array[StringName]
## Indica se este dano foi um acerto critico.
var is_crit: bool
## Posicao do mundo onde o dano ocorreu.
var position: Vector2
## Profundidade da cadeia de efeitos para prevenir loops infinitos.
var trigger_depth: int = 0

## Gera dano derivado, incrementando a profundidade para evitar loops infinitos.
func create_chain_damage(new_amount: float, add_tags: Array[StringName]) -> DamageInfo:
	var chain := DamageInfo.new()
	chain.amount = new_amount
	chain.source = self.source
	chain.tags = self.tags.duplicate()
	chain.tags.append_array(add_tags)
	chain.is_crit = false
	chain.position = self.position
	chain.trigger_depth = self.trigger_depth + 1
	return chain
