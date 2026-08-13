class_name MeteoriteOneShotFx
extends AnimatedSprite2D

func configure(texture: Texture2D, frame_count: int, frame_size: Vector2, frame_duration: float, visual_scale: float) -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	scale = Vector2.ONE * visual_scale
	z_index = 1
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	frames.add_animation(&"play")
	frames.set_animation_loop(&"play", false)
	frames.set_animation_speed(&"play", 1.0 / frame_duration)
	for frame_index in frame_count:
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(Vector2(frame_size.x * frame_index, 0.0), frame_size)
		frames.add_frame(&"play", atlas)
	sprite_frames = frames
	animation = &"play"

func _ready() -> void:
	animation_finished.connect(queue_free)
	play(&"play")
