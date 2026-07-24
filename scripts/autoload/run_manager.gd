extends Node
## Guarda o RNG semeado da execucao; toda rolagem do jogo passa por RunManager.rng.

## Provisorio ate haver selecao de semente por execucao na fase de estrutura de execucao.
const DEFAULT_SEED := 1

var rng: RunRng

func _ready() -> void:
	start_run(DEFAULT_SEED)

func start_run(seed_value: int) -> void:
	rng = RunRng.new(seed_value)
