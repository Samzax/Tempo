class_name HealthComponent
extends Node
## Componente reutilizável de vida. Usado pelo jogador e pelos inimigos.

signal died(fatal_info: DamageInfo)
signal damaged(info: DamageInfo, actual_drop: float)

@export var max_health: float = 3.0

var health: float

func _ready() -> void:
	health = max_health

func apply_damage(info: DamageInfo) -> void:
	## Ignora dano nulo ou negativo para preservar os limites de vida.
	if info.amount <= 0.0:
		return
	if health <= 0.0:
		return
	var previous_health := health
	health = clampf(health - info.amount, 0.0, max_health)
	var actual_drop := previous_health - health
	if actual_drop > 0.0:
		damaged.emit(info, actual_drop)
	if health <= 0.0:
		died.emit(info)

## Recupera vida ate o maximo. Ignora valores nao-positivos.
func heal(amount: float) -> void:
	if amount <= 0.0:
		return
	health = clampf(health + amount, 0.0, max_health)

func reset() -> void:
	health = max_health
