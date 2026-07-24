extends Node2D
## Ponto de entrada da cena principal.
## A montagem de mundo, jogador e diretores acontece nas tarefas seguintes.

func _ready() -> void:
	RunManager.start_run(RunManager.DEFAULT_SEED)
