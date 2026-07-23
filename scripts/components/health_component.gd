class_name HealthComponent
extends Node
## Componente reutilizável de vida. Usado pelo jogador e pelos inimigos.

signal died
signal damaged(amount: int, current: int)

@export var max_health: int = 3

var health: int

func _ready() -> void:
	health = max_health

func apply_damage(amount: int) -> void:
	if health <= 0:
		return
	health = maxi(0, health - amount)
	damaged.emit(amount, health)
	if health <= 0:
		died.emit()

func reset() -> void:
	health = max_health
