extends Node
## Estado global do jogo: pontuação, fase e vidas do jogador.
## Preenchido nas tarefas seguintes.

var score: int = 0
var stage: int = 1
var player_lives: int = 3
var temporal_echoes: int = 0

const MAX_TEMPORAL_ECHOES: int = 9223372036854775807

signal temporal_echoes_changed(amount: int, total: int)

func add_temporal_echoes(amount: int) -> void:
	if amount <= 0:
		return
	if amount > MAX_TEMPORAL_ECHOES - temporal_echoes:
		push_error("Não foi possível adicionar Ecos Temporais: overflow do saldo.")
		return
	temporal_echoes += amount
	var total := temporal_echoes
	temporal_echoes_changed.emit(amount, total)
	EventBus.temporal_echoes_credited.emit(amount, total)

func has_temporal_echoes(amount: int) -> bool:
	return amount > 0 and temporal_echoes >= amount

func spend_temporal_echoes(amount: int) -> bool:
	if not has_temporal_echoes(amount):
		return false
	temporal_echoes -= amount
	var total := temporal_echoes
	temporal_echoes_changed.emit(-amount, total)
	EventBus.temporal_echoes_spent.emit(amount, total)
	return true

func reset_for_new_run() -> void:
	score = 0
	stage = 1
	player_lives = 3
	temporal_echoes = 0
	temporal_echoes_changed.emit(0, temporal_echoes)
