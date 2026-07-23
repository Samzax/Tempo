extends Node
## Reuso de projéteis e efeitos (object pooling) para evitar instanciar
## e liberar nós a cada quadro. Implementado na tarefa de disparo (T5).

func acquire(_key: StringName) -> Node:
	return null

func release(_node: Node) -> void:
	pass
