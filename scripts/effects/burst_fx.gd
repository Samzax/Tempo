extends CPUParticles2D
## Explosão curta de partículas (morte de inimigo). Emite uma vez e se remove.

func _ready() -> void:
	emitting = true
	finished.connect(queue_free)
