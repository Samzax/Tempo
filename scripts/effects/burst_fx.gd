class_name BurstFx
extends CPUParticles2D
## Explosão curta de partículas (morte de inimigo). Emite uma vez e se remove.
## A emissão é disparada por quem instancia, depois de posicionar o efeito,
## para que a rajada aconteça no lugar certo e não na origem do mundo.

func _ready() -> void:
	finished.connect(queue_free)

## Posiciona e dispara a rajada em um único passo, garantindo a ordem correta.
func burst_at(world_position: Vector2) -> void:
	global_position = world_position
	emitting = true
