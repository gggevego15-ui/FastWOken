extends Node2D

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const LEVEL_END := 2240.0
const FLOOR_Y := 468.0

var player: CharacterBody2D
var camera: Camera2D
var hud: CanvasLayer
var score := 0
var deaths := 0
var won := false
var message_label: Label
var score_label: Label
var touch_left := false
var touch_right := false
var touch_jump := false
var applied_touch_left := false
var applied_touch_right := false
var applied_touch_jump := false

func _ready() -> void:
	_setup_input()
	_build_level()
	_spawn_player()
	_build_ui()
	queue_redraw()

func _setup_input() -> void:
	_add_key_action("move_left", [KEY_A, KEY_LEFT])
	_add_key_action("move_right", [KEY_D, KEY_RIGHT])
	_add_key_action("jump", [KEY_SPACE, KEY_W, KEY_UP])
	_add_key_action("restart", [KEY_R])

func _add_key_action(action_name: String, keys: Array) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	for keycode in keys:
		var event := InputEventKey.new()
		event.physical_keycode = keycode
		if not InputMap.action_has_event(action_name, event):
			InputMap.action_add_event(action_name, event)

func _build_level() -> void:
	# Continuous ground is broken into chunks so the pits matter.
	_add_platform(Vector2(240, FLOOR_Y), Vector2(480, 144))
	_add_platform(Vector2(760, FLOOR_Y), Vector2(260, 144))
	_add_platform(Vector2(1130, FLOOR_Y), Vector2(300, 144))
	_add_platform(Vector2(1560, FLOOR_Y), Vector2(300, 144))
	_add_platform(Vector2(2040, FLOOR_Y), Vector2(400, 144))

	_add_platform(Vector2(520, 365), Vector2(112, 18))
	_add_platform(Vector2(900, 315), Vector2(112, 18))
	_add_platform(Vector2(1280, 365), Vector2(112, 18))
	_add_platform(Vector2(1690, 300), Vector2(120, 18))
	_add_platform(Vector2(1900, 355), Vector2(100, 18))

	_add_spikes(Vector2(340, 396), 4)
	_add_spikes(Vector2(760, 396), 3)
	_add_spikes(Vector2(1130, 396), 4)
	_add_spikes(Vector2(1560, 396), 4)
	_add_spikes(Vector2(2010, 396), 3)

	for p in [Vector2(190, 410), Vector2(520, 320), Vector2(760, 410), Vector2(900, 270), Vector2(1280, 320), Vector2(1690, 255), Vector2(1900, 310), Vector2(2160, 410)]:
		_add_crystal(p)

	_add_goal(Vector2(2200, 405))

func _add_platform(center: Vector2, size: Vector2) -> void:
	var body := StaticBody2D.new()
	body.position = center
	body.collision_layer = 1
	body.collision_mask = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	body.add_child(shape)
	add_child(body)
	body.add_to_group("platforms")

func _add_spikes(center: Vector2, count: int) -> void:
	var hazard := Area2D.new()
	hazard.position = center
	hazard.collision_layer = 0
	hazard.collision_mask = 1
	hazard.set_meta("kind", "spike")
	var collision := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(count * 18.0, 20)
	collision.shape = rect
	collision.position.y = -5
	hazard.add_child(collision)
	hazard.body_entered.connect(_on_hazard_entered)
	add_child(hazard)
	hazard.set_meta("count", count)

func _add_crystal(at: Vector2) -> void:
	var crystal := Area2D.new()
	crystal.position = at
	crystal.collision_layer = 0
	crystal.collision_mask = 1
	crystal.set_meta("kind", "crystal")
	var collision := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 12
	collision.shape = circle
	crystal.add_child(collision)
	crystal.body_entered.connect(_on_crystal_collected.bind(crystal))
	add_child(crystal)

func _add_goal(at: Vector2) -> void:
	var goal := Area2D.new()
	goal.position = at
	goal.collision_layer = 0
	goal.collision_mask = 1
	goal.set_meta("kind", "goal")
	var collision := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(30, 72)
	collision.shape = rect
	goal.add_child(collision)
	goal.body_entered.connect(_on_goal_reached)
	add_child(goal)

func _spawn_player() -> void:
	player = PLAYER_SCENE.instantiate()
	player.position = Vector2(80, 350)
	player.spawn_position = player.position
	add_child(player)
	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 7.0
	camera.limit_left = 0
	camera.limit_right = int(LEVEL_END)
	camera.limit_top = 0
	camera.limit_bottom = 540
	player.add_child(camera)
	camera.make_current()

func _build_ui() -> void:
	hud = CanvasLayer.new()
	add_child(hud)
	var top := PanelContainer.new()
	top.position = Vector2(18, 16)
	top.add_theme_stylebox_override("panel", _panel_style(Color(0.04, 0.06, 0.16, 0.86)))
	hud.add_child(top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	top.add_child(row)
	score_label = Label.new()
	score_label.add_theme_color_override("font_color", Color("#5fffea"))
	score_label.add_theme_font_size_override("font_size", 20)
	row.add_child(score_label)
	var deaths_label := Label.new()
	deaths_label.name = "Deaths"
	deaths_label.text = "  ☠ 0"
	deaths_label.add_theme_color_override("font_color", Color("#ff6588"))
	deaths_label.add_theme_font_size_override("font_size", 20)
	row.add_child(deaths_label)

	message_label = Label.new()
	message_label.position = Vector2(0, 66)
	message_label.size = Vector2(960, 40)
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.add_theme_color_override("font_color", Color("#ffffff"))
	message_label.add_theme_font_size_override("font_size", 24)
	hud.add_child(message_label)
	_update_hud()

	if OS.has_feature("mobile") or DisplayServer.is_touchscreen_available():
		_add_touch_button("◀", Vector2(28, 420), "left")
		_add_touch_button("▶", Vector2(112, 420), "right")
		_add_touch_button("JUMP", Vector2(820, 410), "jump")

func _panel_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style

func _add_touch_button(caption: String, at: Vector2, action: String) -> void:
	var button := Button.new()
	button.text = caption
	button.position = at
	button.size = Vector2(76, 64) if action != "jump" else Vector2(108, 72)
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _panel_style(Color(0.12, 0.22, 0.36, 0.86)))
	button.add_theme_stylebox_override("pressed", _panel_style(Color(0.08, 0.7, 0.68, 0.95)))
	hud.add_child(button)
	if action == "left":
		button.button_down.connect(func(): touch_left = true)
		button.button_up.connect(func(): touch_left = false)
	elif action == "right":
		button.button_down.connect(func(): touch_right = true)
		button.button_up.connect(func(): touch_right = false)
	else:
		button.button_down.connect(func(): touch_jump = true)
		button.button_up.connect(func(): touch_jump = false)

func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		return
	if touch_left != applied_touch_left:
		if touch_left:
			Input.action_press("move_left")
		else:
			Input.action_release("move_left")
		applied_touch_left = touch_left
	if touch_right != applied_touch_right:
		if touch_right:
			Input.action_press("move_right")
		else:
			Input.action_release("move_right")
		applied_touch_right = touch_right
	if touch_jump != applied_touch_jump:
		if touch_jump:
			Input.action_press("jump")
		else:
			Input.action_release("jump")
		applied_touch_jump = touch_jump

	if player.global_position.y > 620:
		_respawn()
	if Input.is_action_just_pressed("restart"):
		_respawn()
	queue_redraw()

func _on_hazard_entered(body: Node2D) -> void:
	if body == player:
		_respawn()

func _on_crystal_collected(body: Node2D, crystal: Area2D) -> void:
	if body != player or not is_instance_valid(crystal):
		return
	score += 1
	crystal.queue_free()
	_update_hud()

func _on_goal_reached(body: Node2D) -> void:
	if body != player or won:
		return
	won = true
	player.controls_locked = true
	message_label.text = "LEVEL CLEAR!  Crystals: %d  —  Press R to replay" % score

func _respawn() -> void:
	if won:
		won = false
		score = 0
		for node in get_children():
			if node is Area2D and node.get_meta("kind", "") == "crystal":
				node.queue_free()
		# Restart the complete level for a clean run.
		get_tree().reload_current_scene()
		return
	deaths += 1
	player.reset_to_spawn()
	var deaths_label: Label = hud.find_child("Deaths", true, false)
	if deaths_label:
		deaths_label.text = "  ☠ %d" % deaths
	_update_hud()

func _update_hud() -> void:
	if is_instance_valid(score_label):
		score_label.text = "◆ %d / 8" % score

func _draw() -> void:
	# Procedural parallax-like pixel skyline and platform tops.
	draw_rect(Rect2(0, 0, LEVEL_END, 540), Color("#090d25"))
	for i in range(90):
		var x := float((i * 137 + 31) % int(LEVEL_END))
		var y := float((i * 71 + 17) % 320)
		draw_rect(Rect2(x, y, 3, 3), Color(0.45, 0.75, 1.0, 0.45))
	for i in range(22):
		var x := float(i * 112)
		var h := float(70 + (i * 37) % 100)
		draw_rect(Rect2(x, 400 - h, 72, h), Color("#111936"))
		draw_rect(Rect2(x + 12, 410 - h, 6, 6), Color("#20365b"))
	for platform in get_tree().get_nodes_in_group("platforms"):
		if is_instance_valid(platform):
			var size: Vector2 = platform.get_child(0).shape.size
			draw_rect(Rect2(platform.position - size / 2.0, size), Color("#252b51"))
			draw_rect(Rect2(platform.position.x - size.x / 2.0, platform.position.y - size.y / 2.0, size.x, 7), Color("#41d9cc"))
	for hazard in get_tree().get_nodes_in_group("hazards"):
		pass
	for child in get_children():
		if child is Area2D:
			var kind: String = child.get_meta("kind", "")
			if kind == "spike":
				var count: int = child.get_meta("count", 3)
				for i in range(count):
					var px := child.position.x - count * 9.0 + i * 18.0
					var points := PackedVector2Array([Vector2(px - 8, child.position.y + 6), Vector2(px, child.position.y - 12), Vector2(px + 8, child.position.y + 6)])
					draw_colored_polygon(points, Color("#ff527c"))
					draw_line(points[0], points[1], Color("#ffd2e0"), 2)
			elif kind == "crystal":
				var p: Vector2 = child.position
				var points := PackedVector2Array([p + Vector2(0, -12), p + Vector2(9, 0), p + Vector2(0, 12), p + Vector2(-9, 0)])
				draw_colored_polygon(points, Color("#5fffea"))
				draw_line(p + Vector2(0, -8), p + Vector2(0, 7), Color.WHITE, 2)
			elif kind == "goal":
				var p: Vector2 = child.position
				draw_rect(Rect2(p.x - 18, p.y - 42, 36, 84), Color("#a55cff"), false, 4)
				draw_rect(Rect2(p.x - 10, p.y - 34, 20, 68), Color("#5fffea", 0.7))
