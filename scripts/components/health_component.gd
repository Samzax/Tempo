class_name HealthComponent
extends Node
## Componente reutilizável de vida. Usado pelo jogador e pelos inimigos.

const HEALTH_UNITS := preload("res://scripts/components/health_units.gd")

signal died(fatal_info: DamageInfo)
signal damaged(info: DamageInfo, actual_drop: int)

var _max_health: int = 300
var _health: int = 0

## Authoring boundaries assign quantized HealthUnits to this field.
@export var max_health: int:
	get:
		return _max_health
	set(value):
		_max_health = maxi(value, 0)
		_health = mini(_health, _max_health)

## Authoritative health state, in HealthUnits. Invalid negative state is rejected.
var health: int:
	get:
		return _health
	set(value):
		_health = clampi(value, 0, _max_health)

func _ready() -> void:
	health = max_health

func apply_damage(info: DamageInfo) -> int:
	if info == null:
		return 0
	## Ignora dano nulo ou negativo para preservar os limites de vida.
	if info.amount <= 0:
		return 0
	if health <= 0:
		return 0
	var previous_health := health
	health = maxi(health - mini(info.amount, health), 0)
	var actual_drop := previous_health - health
	if actual_drop > 0:
		damaged.emit(info, actual_drop)
	if health <= 0:
		died.emit(info)
	return actual_drop

func try_spend_health(amount: int, minimum_remaining: int = HEALTH_UNITS.HP_SCALE) -> bool:
	if amount <= 0 or minimum_remaining < 0 or health < 0:
		return false
	var remaining := health - amount
	if remaining < minimum_remaining:
		return false
	health = remaining
	return true

## Recupera vida ate o maximo. Ignora valores nao-positivos.
func heal(amount: int) -> void:
	if amount <= 0:
		return
	health = mini(HEALTH_UNITS.saturating_add(health, amount), max_health)

func reset() -> void:
	health = max_health
