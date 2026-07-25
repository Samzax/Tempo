extends GutTest

const BURST_FX_SCENE := preload("res://scenes/effects/burst_fx.tscn")


func test_burst_fx_starts_idle_and_bursts_at_position() -> void:
	var fx := add_child_autofree(BURST_FX_SCENE.instantiate() as BurstFx) as BurstFx

	assert_false(fx.emitting)

	fx.burst_at(Vector2(123, 45))

	assert_eq(fx.global_position, Vector2(123, 45))
	assert_true(fx.emitting)
