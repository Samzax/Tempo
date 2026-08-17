class_name RoomDef
extends Resource

enum RoomType { OPENING, COMBAT, BOSS, TREASURE, RISK }
enum CameraPolicy { FIXED }
enum CullPolicy { DESPAWN_BOTTOM, NONE, DESPAWN_ALL_BORDERS }
enum ClearPolicy { ALL_SPAWNS_RESOLVED }

## Descricao imutavel de uma onda. A agenda concreta fica no SpawnDirector;
## isto mantem RoomDef como o contrato de conteudo da sala.
class WaveSpec extends RefCounted:
	var common_count: int
	var hunter_count: int
	var max_active: int
	var cadence: float
	var paired_commons: bool
	var threat_types: Array[StringName] = []

	func _init(common: int = 0, hunters: int = 0, active_limit: int = 1, interval: float = 1.1, paired: bool = false) -> void:
		common_count = common
		hunter_count = hunters
		max_active = active_limit
		cadence = interval
		paired_commons = paired

	func with_threat_types(types: Array[StringName]) -> WaveSpec:
		threat_types = types.duplicate()
		return self

func get_upper_waves() -> Array[WaveSpec]:
	return [WaveSpec.new(0, 0, 3, 1.1).with_threat_types([
		&"common", &"common", &"atirador", &"common", &"common", &"kamikaze", &"atirador", &"kamikaze",
	])]

func get_sector3_upper_waves() -> Array[WaveSpec]:
	return [
		WaveSpec.new(0, 0, 2, 1.1).with_threat_types([&"common", &"common"]),
		WaveSpec.new(0, 0, 1, 1.1).with_threat_types([&"atirador"]),
		WaveSpec.new(0, 0, 3, 1.1).with_threat_types([&"common", &"common", &"kamikaze"]),
		WaveSpec.new(0, 0, 2, 1.1).with_threat_types([&"atirador", &"kamikaze"]),
	]

func get_phase_one_waves() -> Array[WaveSpec]:
	return [
		WaveSpec.new(6, 0, 2, 2.4, true),
		WaveSpec.new(18, 0, 6, 1.5),
		WaveSpec.new(0, 2, 2, 0.25),
		WaveSpec.new(18, 4, 8, 1.1),
		WaveSpec.new(18, 12, 12, 0.75),
	]

@export var id: StringName
@export var room_type: RoomType = RoomType.OPENING
## Os perfis sao dados independentes. "default" preserva a sala legada.
@export var encounter_profile: StringName = &"default"
@export var environment_profile: StringName = &"default"
@export var transition_profile: StringName = &"default"
@export var scene: PackedScene
@export var size: Vector2 = Vector2(720, 405)
@export var camera_policy: CameraPolicy = CameraPolicy.FIXED
@export var cull_policy: CullPolicy = CullPolicy.DESPAWN_BOTTOM
@export var clear_policy: ClearPolicy = ClearPolicy.ALL_SPAWNS_RESOLVED
@export_range(0, 100000, 1) var finite_spawn_count: int = 5
## Nao e exportada: as cinco ondas sao construidas programaticamente para evitar
## recursos auxiliares e preservar as salas legadas baseadas em finite_spawn_count.
var wave_specs: Array[WaveSpec] = []
## Objetos de mundo pertencentes a sala. Cada entrada usa somente dados
## deterministas para que o perfil nao consuma o RNG da execucao.
var initial_debris: Array[Dictionary] = []

func get_bounds() -> Rect2:
	return Rect2(Vector2.ZERO, size)

func has_waves() -> bool:
	return not wave_specs.is_empty()

func configure_phase_one_waves() -> void:
	encounter_profile = &"phase_one"
	wave_specs = get_phase_one_waves()
	cull_policy = CullPolicy.DESPAWN_ALL_BORDERS

func configure_upper_waves() -> void:
	encounter_profile = &"upper"
	wave_specs = get_upper_waves()
	cull_policy = CullPolicy.DESPAWN_ALL_BORDERS
	initial_debris = [
		{"position": Vector2(180.0, 132.0), "size_class": 0, "drift_velocity": Vector2(12.0, 5.0)},
		{"position": Vector2(390.0, 246.0), "size_class": 1, "drift_velocity": Vector2(-10.0, 8.0)},
		{"position": Vector2(590.0, 154.0), "size_class": 0, "drift_velocity": Vector2(-7.0, -6.0)},
	]

func configure_sector3_upper_waves() -> void:
	encounter_profile = &"sector3_upper"
	wave_specs = get_sector3_upper_waves()
	cull_policy = CullPolicy.DESPAWN_ALL_BORDERS
	initial_debris.clear()

## O encontro da Regente e deliberadamente singular: nao ha agenda de waves
## nem fallback para o contador legado do SpawnDirector.
func configure_regente_dos_ecos_encounter() -> void:
	encounter_profile = &"regente_dos_ecos"
	wave_specs.clear()
	finite_spawn_count = 0
	cull_policy = CullPolicy.NONE
	initial_debris.clear()

func configure_encounter_profile(profile: StringName) -> void:
	match profile:
		&"phase_one":
			configure_phase_one_waves()
		&"upper":
			configure_upper_waves()
		&"sector3_upper":
			configure_sector3_upper_waves()
		&"regente_dos_ecos":
			configure_regente_dos_ecos_encounter()
