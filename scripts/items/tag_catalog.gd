class_name TagCatalog
extends RefCounted
## Reúne os nomes canônicos de tags usados pelos provedores.

const VALID_TAGS := {
	&"fire": true,
	&"ice": true,
	&"shock": true,
	&"void": true,
	&"projectile": true,
	&"contact": true,
	&"blink": true,
	&"drone": true,
	&"explosion": true,
	&"curse": true,
	&"time": true,
}

## Informa se uma tag pertence ao catálogo canônico de tags.
static func is_valid(tag: StringName) -> bool:
	return VALID_TAGS.has(tag)
