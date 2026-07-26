class_name RoomDef
extends Resource

enum RoomType { OPENING, COMBAT, BOSS }
enum CameraPolicy { FIXED }
enum CullPolicy { DESPAWN_BOTTOM, NONE }
enum ClearPolicy { ALL_SPAWNS_RESOLVED }

@export var id: StringName
@export var room_type: RoomType = RoomType.OPENING
@export var scene: PackedScene
@export var camera_policy: CameraPolicy = CameraPolicy.FIXED
@export var cull_policy: CullPolicy = CullPolicy.DESPAWN_BOTTOM
@export var clear_policy: ClearPolicy = ClearPolicy.ALL_SPAWNS_RESOLVED
@export_range(0, 100000, 1) var finite_spawn_count: int = 5
