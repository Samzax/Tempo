class_name N0N1V27Progress
extends RefCounted

const COMBAT_CAP := 92.9
var presentation_progress := 0.0
var authoritative_cap := 0.0

func update_from_snapshot(snapshot: Dictionary, delta: float) -> float:
	var expected := maxi(1, int(snapshot.get("expected_spawn_count", 0)))
	var resolved := mini(expected, int(snapshot.get("resolved_count", 0)))
	authoritative_cap = COMBAT_CAP * float(resolved) / float(expected)
	if bool(snapshot.get("combat_cleared", false)):
		authoritative_cap = COMBAT_CAP
	presentation_progress = move_toward(presentation_progress, authoritative_cap, maxf(0.0, delta) * 12.0)
	return presentation_progress
