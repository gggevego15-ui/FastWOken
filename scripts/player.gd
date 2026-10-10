extends CharacterBody2D

const RUN_SPEED := 245.0
const ACCELERATION := 1700.0
const FRICTION := 1900.0
const JUMP_VELOCITY := -445.0
const GRAVITY := 1200.0
const LANDING_DURATION := 0.16
const DEATH_DURATION := 0.42

var facing := 1
var spawn_position := Vector2(80, 350)
var controls_locked := false

var animation_time := 0.0
var run_phase := 0.0
var landing_time := 0.0
var was_on_floor := false
var is_dying := false
var death_time := 0.0

func _ready() -> void:
	add_to_group("player")
	position = spawn_position
	was_on_floor = is_on_floor()
	queue_redraw()

func _physics_process(delta: float) -> void:
	animation_time += delta

	if is_dying:
		death_time += delta
		queue_redraw()
		return

	if controls_locked:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
		if not is_on_floor():
			velocity.y += GRAVITY * delta
			move_and_slide()
		queue_redraw()
		return

	var on_floor_before_move := is_on_floor()
	var direction := Input.get_axis("move_left", "move_right")
	if direction != 0.0:
		facing = 1 if direction > 0.0 else -1
		velocity.x = move_toward(velocity.x, direction * RUN_SPEED, ACCELERATION * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)

	if not on_floor_before_move:
		velocity.y += GRAVITY * delta
	elif velocity.y > 0.0:
		velocity.y = 0.0

	if Input.is_action_just_pressed("jump") and on_floor_before_move:
		velocity.y = JUMP_VELOCITY

	move_and_slide()
	var on_floor_after_move := is_on_floor()
	if not on_floor_before_move and on_floor_after_move and velocity.y >= 0.0:
		landing_time = LANDING_DURATION
	if landing_time > 0.0:
		landing_time = maxf(0.0, landing_time - delta)

	if on_floor_after_move and absf(velocity.x) > 18.0:
		run_phase += delta * (8.0 + 8.0 * absf(velocity.x) / RUN_SPEED)
	else:
		run_phase = move_toward(run_phase, roundf(run_phase / TAU) * TAU, delta * 5.0)

	was_on_floor = on_floor_after_move
	queue_redraw()

func play_death_animation() -> void:
	if is_dying:
		return
	is_dying = true
	controls_locked = true
	death_time = 0.0
	velocity = Vector2.ZERO
	queue_redraw()

func reset_to_spawn() -> void:
	global_position = spawn_position
	velocity = Vector2.ZERO
	rotation = 0.0
	modulate = Color.WHITE
	is_dying = false
	death_time = 0.0
	landing_time = 0.0
	controls_locked = false
	queue_redraw()

func _draw() -> void:
	var skin := Color("#ffd1a3")
	var hair := Color("#1b1735")
	var coat := Color("#40e0d0")
	var coat_shadow := Color("#176e83")
	var boot := Color("#f7f3ff")
	var outline := Color("#20283b")

	var body_offset := 0.0
	var body_scale := Vector2.ONE
	var head_tilt := 0.0
	var arm_swing := 0.0
	var leg_swing := 0.0

	if is_dying:
		var death_progress := clampf(death_time / DEATH_DURATION, 0.0, 1.0)
		body_offset = 4.0 * sin(death_progress * PI)
		body_scale = Vector2(1.0 + 0.2 * death_progress, maxf(0.2, 1.0 - 0.72 * death_progress))
		head_tilt = facing * death_progress * 0.45
	elif landing_time > 0.0:
		var land_progress := landing_time / LANDING_DURATION
		body_scale = Vector2(1.0 + 0.22 * sin(land_progress * PI), 1.0 - 0.28 * sin(land_progress * PI))
		body_offset = 2.0 * sin(land_progress * PI)
	elif not is_on_floor():
		if velocity.y < -60.0:
			body_scale = Vector2(0.88, 1.14)
			arm_swing = -0.8
			leg_swing = -0.38
		else:
			body_scale = Vector2(1.08, 0.88)
			arm_swing = 0.95
			leg_swing = 0.3
	else:
		var movement := clampf(absf(velocity.x) / RUN_SPEED, 0.0, 1.0)
		body_offset = absf(sin(run_phase * 2.0)) * 2.2 * movement
		arm_swing = sin(run_phase) * 0.72 * movement
		leg_swing = sin(run_phase) * 0.88 * movement
		if movement < 0.05:
			body_offset = sin(animation_time * 2.3) * 0.45

	# Draw in the same compact pixel-art style, but animate the silhouette and limbs.
	draw_set_transform(Vector2(0, body_offset), head_tilt, body_scale)

	# Rear arm and legs are drawn first so the torso overlaps their joints.
	var rear_arm_end := Vector2(-facing * 10.0 + arm_swing * 6.0, -7.0 + arm_swing * 5.0)
	var front_arm_end := Vector2(facing * 11.0 - arm_swing * 6.0, -8.0 - arm_swing * 5.0)
	draw_line(Vector2(-6, -12), rear_arm_end, outline, 5.0, false)
	draw_line(Vector2(-6, -12), rear_arm_end, skin, 3.0, false)
	draw_line(Vector2(6, -12), front_arm_end, outline, 5.0, false)
	draw_line(Vector2(6, -12), front_arm_end, skin, 3.0, false)

	var left_knee := Vector2(-4.0 + leg_swing * 5.0, -1.0)
	var right_knee := Vector2(4.0 - leg_swing * 5.0, -1.0)
	var left_foot := Vector2(-5.0 + leg_swing * 9.0, 2.0)
	var right_foot := Vector2(5.0 - leg_swing * 9.0, 2.0)
	draw_line(Vector2(-4, -5), left_knee, outline, 6.0, false)
	draw_line(Vector2(4, -5), right_knee, outline, 6.0, false)
	draw_line(Vector2(-4, -5), left_knee, coat_shadow, 4.0, false)
	draw_line(Vector2(4, -5), right_knee, coat_shadow, 4.0, false)
	draw_line(left_knee, left_foot, outline, 5.0, false)
	draw_line(right_knee, right_foot, outline, 5.0, false)
	draw_line(left_knee, left_foot, boot, 3.0, false)
	draw_line(right_knee, right_foot, boot, 3.0, false)

	# Jacket, collar and tiny folds.
	draw_rect(Rect2(-9, -16, 18, 13), outline)
	draw_rect(Rect2(-7, -15, 14, 10), coat)
	draw_rect(Rect2(-2, -14, 3, 8), coat_shadow)
	draw_line(Vector2(-6, -7), Vector2(-2, -5), Color("#8cf4e7"), 1.0, false)
	draw_rect(Rect2(-3, -14, 2, 2), Color("#f7f3ff"))

	# Head and hair.
	draw_rect(Rect2(-8, -29, 16, 14), outline)
	draw_rect(Rect2(-7, -28, 14, 12), skin)
	draw_rect(Rect2(-9, -30, 18, 5), hair)
	draw_rect(Rect2(-9, -27, 4, 8), hair)
	draw_rect(Rect2(2, -24, 4, 3), hair)
	var eye_x := 2.0 if facing == 1 else -5.0
	draw_rect(Rect2(eye_x, -23, 3, 3), Color("#12152d"))
	draw_rect(Rect2(eye_x + (1.0 if facing == 1 else 0.0), -23, 1, 1), Color.WHITE)
	draw_rect(Rect2(5 if facing == 1 else -8, -19, 3, 2), Color("#e7a28b"))

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
