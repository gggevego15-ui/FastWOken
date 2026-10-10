extends CharacterBody2D

const RUN_SPEED := 245.0
const ACCELERATION := 1700.0
const FRICTION := 1900.0
const JUMP_VELOCITY := -445.0
const GRAVITY := 1200.0

var facing := 1
var spawn_position := Vector2(80, 350)
var controls_locked := false

func _ready() -> void:
	add_to_group("player")
	position = spawn_position
	queue_redraw()

func _physics_process(delta: float) -> void:
	if controls_locked:
		velocity = Vector2.ZERO
		return

	var direction := Input.get_axis("move_left", "move_right")
	if direction != 0.0:
		facing = 1 if direction > 0.0 else -1
		velocity.x = move_toward(velocity.x, direction * RUN_SPEED, ACCELERATION * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)

	if not is_on_floor():
		velocity.y += GRAVITY * delta
	elif velocity.y > 0.0:
		velocity.y = 0.0

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	move_and_slide()
	queue_redraw()

func reset_to_spawn() -> void:
	global_position = spawn_position
	velocity = Vector2.ZERO

func _draw() -> void:
	# Tiny, crisp pixel hero drawn from integer-aligned rectangles.
	var skin := Color("#ffd1a3")
	var hair := Color("#1b1735")
	var coat := Color("#40e0d0")
	var shade := Color("#176e83")
	var boot := Color("#f7f3ff")
	draw_rect(Rect2(-8, -27, 16, 12), skin)
	draw_rect(Rect2(-9, -29, 18, 5), hair)
	draw_rect(Rect2(-10, -25, 4, 8), hair)
	draw_rect(Rect2(2, -22, 3, 3), Color("#12152d") if facing == 1 else Color("#f7f3ff"))
	draw_rect(Rect2(-9, -14, 18, 10), coat)
	draw_rect(Rect2(-11, -12, 4, 8), skin)
	draw_rect(Rect2(7, -12, 4, 8), skin)
	draw_rect(Rect2(-8, -4, 7, 4), shade)
	draw_rect(Rect2(1, -4, 7, 4), shade)
	draw_rect(Rect2(-9, 0, 8, 4), boot)
	draw_rect(Rect2(1, 0, 9, 4), boot)
