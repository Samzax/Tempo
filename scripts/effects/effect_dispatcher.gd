class_name EffectDispatcher
extends RefCounted
## Dispara os efeitos associados aos eventos de um unico dono.

var _owner: Node
var _effects: Array[EffectDef] = []
var _cooldowns: Dictionary = {}

func _init(owner: Node, effects: Array[EffectDef]) -> void:
	_owner = owner
	for effect in effects:
		if effect != null:
			_effects.append(effect)

## Adiciona efeitos em tempo de execucao ao dispatcher.
func add_effects(effects: Array[EffectDef]) -> void:
	for effect in effects:
		if effect != null:
			_effects.append(effect)

## Remove efeitos em tempo de execucao e suas recargas associadas.
func remove_effects(effects: Array[EffectDef]) -> void:
	for effect in effects:
		_effects.erase(effect)
		_cooldowns.erase(effect)

func dispatch(event: StringName, payload: Variant, depth: int) -> void:
	if depth > 3:
		return
	for effect in _effects.duplicate():
		if effect.event != event:
			continue
		if _cooldowns.get(effect, 0.0) > 0.0:
			continue
		var context := EffectContext.new()
		context.owner = _owner
		context.event = event
		context.payload = payload
		context.rng = RunManager.rng
		context.trigger_depth = depth
		if effect.condition != null and not effect.condition.check(context):
			continue
		if not RunManager.rng.chance(effect.chance):
			continue
		if effect.action != null:
			effect.action.execute(context)
		if effect in _effects and effect.cooldown > 0.0:
			_cooldowns[effect] = effect.cooldown

func tick(delta: float) -> void:
	for effect in _cooldowns:
		_cooldowns[effect] = maxf(0.0, _cooldowns[effect] - delta)
