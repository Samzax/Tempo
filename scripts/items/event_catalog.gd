class_name EventCatalog
extends RefCounted
## Reúne os nomes canônicos de eventos usados pelos efeitos.

const VALID_EVENTS := {
	&"on_run_start": true,
	&"on_floor_enter": true,
	&"on_room_enter": true,
	&"on_room_clear": true,
	&"on_fire": true,
	&"on_hit": true,
	&"on_kill": true,
	&"on_damaged": true,
	&"on_blink": true,
	&"on_ability": true,
	&"on_pickup": true,
	&"on_tick": true,
	&"on_death": true,
}

## Informa se um nome pertence ao catálogo canônico de eventos.
static func is_valid(event: StringName) -> bool:
	return VALID_EVENTS.has(event)
