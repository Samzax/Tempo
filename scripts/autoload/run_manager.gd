extends Node
## Guarda o RNG semeado da execucao; toda rolagem do jogo passa por RunManager.rng.

## Provisorio ate haver selecao de semente por execucao na fase de estrutura de execucao.
const DEFAULT_SEED := 1
const DEFAULT_CHARACTER_ID := &"hacker"

var rng: RunRng
var seed_value: int = DEFAULT_SEED
var selected_character_id: StringName = DEFAULT_CHARACTER_ID

func _ready() -> void:
	start_run(DEFAULT_SEED)

func start_run(seed_value: int) -> void:
	self.seed_value = seed_value
	rng = RunRng.new(seed_value)

func select_character(character_id: StringName) -> void:
	selected_character_id = CharacterDef.resolve_id(character_id).id
