class_name RunRng extends RefCounted
## Fonte unica de aleatoriedade por execucao, deterministica pela semente.

var _rng: RandomNumberGenerator

func _init(seed_value: int) -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value

func randf() -> float:
	return _rng.randf()

func randf_range(from: float, to: float) -> float:
	return _rng.randf_range(from, to)

func randi_range(from: int, to: int) -> int:
	return _rng.randi_range(from, to)

func chance(p: float) -> bool:
	if p <= 0.0:
		return false
	if p >= 1.0:
		return true
	return randf() < p

func pick(arr: Array) -> Variant:
	if arr.is_empty():
		return null
	return arr[randi_range(0, arr.size() - 1)]

func get_state() -> int:
	return _rng.state

func set_state(s: int) -> void:
	_rng.state = s
