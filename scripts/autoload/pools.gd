extends Node
## Pool de nós reutilizáveis por PackedScene (object pooling), evitando
## instanciar e liberar nós a cada quadro. Usado pelos projéteis (T5).
##
## Nós recolhidos ficam estacionados sob este autoload (fora de cena e inertes),
## de modo que permanecem na árvore e são liberados normalmente ao sair — sem
## nós órfãos.

var _free: Dictionary = {}  # PackedScene -> Array[Node]

## Devolve um nó pronto para uso (reaproveitado se houver, senão instanciado).
## O chamador deve adicioná-lo à árvore e reinicializá-lo (ex.: activate()).
func acquire(scene: PackedScene) -> Node:
	var list: Array = _free.get(scene, [])
	var node: Node
	if list.is_empty():
		node = scene.instantiate()
		node.set_meta("pool_scene", scene)
	else:
		node = list.pop_back()
		remove_child(node)
	return node

## Recolhe um nó: tira do pai atual e o estaciona sob o pool para reuso.
func release(node: Node) -> void:
	if not is_instance_valid(node):
		return
	var parent := node.get_parent()
	if parent != null:
		parent.remove_child(node)
	var scene: PackedScene = node.get_meta("pool_scene", null)
	if scene == null:
		node.queue_free()
		return
	add_child(node)
	var list: Array = _free.get(scene, [])
	list.append(node)
	_free[scene] = list
