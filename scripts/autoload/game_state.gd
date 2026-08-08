extends Node
## Estado global do jogo: pontuação, fase e vidas do jogador.
## Preenchido nas tarefas seguintes.

var score: int = 0
var stage: int = 1
var player_lives: int = 3
var temporal_echoes: int = 0

signal temporal_echoes_changed(amount: int, total: int)

func add_temporal_echoes(amount: int) -> void:
	if amount <= 0:
		return
	temporal_echoes += amount
	temporal_echoes_changed.emit(amount, temporal_echoes)
	EventBus.temporal_echoes_credited.emit(amount, temporal_echoes)

func reset_for_new_run() -> void:
	score = 0
	stage = 1
	player_lives = 3
	temporal_echoes = 0
	temporal_echoes_changed.emit(0, temporal_echoes)
