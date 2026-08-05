class_name TimeWarpAbility
extends AbilityDef
## Dobra a recuperacao do blink e amplia seus i-frames por um curto periodo.

const HASTE_SOURCE_ID := &"time_warp_haste_runtime"
const INVULN_SOURCE_ID := &"time_warp_invuln_runtime"

func _init() -> void:
	id = &"time_warp"
	display_name = "Distorcao Temporal"
	cooldown = 9.0

func activate(player: Node2D) -> void:
	player.apply_temporary_modifier(HASTE_SOURCE_ID, &"blink_haste", StatDef.Op.MULT, 1.0, 3.0)
	player.apply_temporary_modifier(INVULN_SOURCE_ID, &"blink_invuln", StatDef.Op.ADD_PCT, 1.0, 3.0)
