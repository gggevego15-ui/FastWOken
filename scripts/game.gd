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
	_setup_forest_audio()
	queue_redraw()


func _setup_forest_audio() -> void:
	# Generate loopable ambient audio in code so the project needs no downloaded assets.
	var wind_player := AudioStreamPlayer.new()
	wind_player.name = "ForestAmbience"
	wind_player.stream = _make_forest_audio(false)
	wind_player.volume_db = -17.0
	wind_player.bus = "Master"
	add_child(wind_player)
	wind_player.play()

	var birds_player := AudioStreamPlayer.new()
	birds_player.name = "ForestBirds"
	birds_player.stream = _make_forest_audio(true)
	birds_player.volume_db = -20.0
	birds_player.bus = "Master"
	add_child(birds_player)
	birds_player.play()

func _make_forest_audio(birds_only: bool) -> AudioStreamWAV:
	const SAMPLE_RATE := 22050
	const DURATION := 8.0
	var sample_count := int(SAMPLE_RATE * DURATION)
	var pcm := PackedByteArray()
	pcm.resize(sample_count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 44021 if birds_only else 91273
	var smooth_wind := 0.0
	var chirps := [
		{"start": 0.72, "length": 0.28, "frequency": 1850.0},
		{"start": 1.12, "length": 0.22, "frequency": 2230.0},
		{"start": 2.85, "length": 0.42, "frequency": 1650.0},
		{"start": 4.76, "length": 0.24, "frequency": 2450.0},
		{"start": 5.10, "length": 0.31, "frequency": 2050.0},
		{"start": 6.65, "length": 0.38, "frequency": 1780.0}
	]
	var phase := 0.0
	for i in range(sample_count):
		var t := float(i) / SAMPLE_RATE
		var sample := 0.0
		if birds_only:
			for chirp in chirps:
				var local_t: float = t - float(chirp["start"])
				var chirp_length: float = float(chirp["length"])
				if local_t >= 0.0 and local_t < chirp_length:
					var progress := local_t / chirp_length
					var envelope := sin(PI * progress)
					var frequency: float = float(chirp["frequency"]) + 480.0 * sin(progress * PI)
					phase += TAU * frequency / SAMPLE_RATE
					sample += sin(phase) * envelope * 0.17
					sample += sin(phase * 2.01) * envelope * 0.035
		else:
			# Filtered random noise resembles a distant breeze; brighter noise adds leaf rustle.
			smooth_wind = lerpf(smooth_wind, rng.randf_range(-1.0, 1.0), 0.018)
			var gust := 0.72 + 0.28 * sin(TAU * t / 5.7)
			var rustle := rng.randf_range(-1.0, 1.0)
			sample = (smooth_wind * 0.48 + rustle * 0.12) * gust
			sample += sin(TAU * 83.0 * t) * 0.018
		# Short fade at the loop boundary reduces clicks when playback repeats.
		var fade_samples := int(SAMPLE_RATE * 0.035)
		var fade := minf(1.0, minf(float(i) / fade_samples, float(sample_count - 1 - i) / fade_samples))
		sample *= maxf(0.0, fade)
		var signed_sample := int(clampf(sample, -0.95, 0.95) * 32767.0)
		if signed_sample < 0:
			signed_sample += 65536
		pcm[i * 2] = signed_sample & 0xff
		pcm[i * 2 + 1] = (signed_sample >> 8) & 0xff

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = sample_count
	stream.data = pcm
	return stream

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
	# A realistic-feeling forest painted from layered shapes and texture details.
	# The player remains pixel-art, creating the intended visual contrast.
	draw_rect(Rect2(0, 0, LEVEL_END, 540), Color("#a7bdc1"))
	# Overcast sky, with a warm break near the horizon.
	for band in range(18):
		var t := float(band) / 18.0
		var c := Color("#c5d0c8").lerp(Color("#6c8585"), t)
		draw_rect(Rect2(0, band * 18, LEVEL_END, 19), c)
	draw_rect(Rect2(0, 255, LEVEL_END, 145), Color(0.72, 0.77, 0.69, 0.32))

	# Far ridge and dense forest silhouettes.
	var far_rng := RandomNumberGenerator.new()
	far_rng.seed = 917
	for i in range(38):
		var x := float(i) * 64.0 - 20.0
		var h := far_rng.randf_range(48.0, 145.0)
		var w := far_rng.randf_range(62.0, 112.0)
		var trunk := Color("#536b61").lerp(Color("#78897a"), far_rng.randf())
		draw_colored_polygon(PackedVector2Array([
			Vector2(x - w * 0.5, 345), Vector2(x - w * 0.36, 345 - h * 0.48),
			Vector2(x - w * 0.12, 345 - h), Vector2(x + w * 0.08, 345 - h * 0.68),
			Vector2(x + w * 0.36, 345 - h * 0.91), Vector2(x + w * 0.5, 345)
		]), trunk)
		draw_rect(Rect2(x - 4, 345 - h * 0.38, 8, h * 0.38), Color("#625e4b"))

	# Soft shafts of light through the canopy.
	for i in range(9):
		var x := float((i * 251 + 95) % int(LEVEL_END))
		var beam := PackedVector2Array([
			Vector2(x, 0), Vector2(x + 28, 0),
			Vector2(x + 100, 385), Vector2(x + 46, 385)
		])
		draw_colored_polygon(beam, Color(0.96, 0.93, 0.72, 0.075))

	# Foreground trees: irregular trunks, roots, bark grooves and layered foliage.
	var tree_rng := RandomNumberGenerator.new()
	tree_rng.seed = 202610
	for i in range(24):
		var x := float(i) * 105.0 + tree_rng.randf_range(-28.0, 28.0)
		var base_y := tree_rng.randf_range(375.0, 430.0)
		var h := tree_rng.randf_range(155.0, 280.0)
		var trunk_w := tree_rng.randf_range(18.0, 38.0)
		var lean := tree_rng.randf_range(-20.0, 20.0)
		var bark := Color("#554d3c").lerp(Color("#766c51"), tree_rng.randf())
		draw_colored_polygon(PackedVector2Array([
			Vector2(x - trunk_w * 0.5, base_y), Vector2(x - trunk_w * 0.35, base_y - h * 0.55),
			Vector2(x + lean * 0.3 - trunk_w * 0.25, base_y - h),
			Vector2(x + lean * 0.3 + trunk_w * 0.2, base_y - h),
			Vector2(x + lean + trunk_w * 0.55, base_y)
		]), bark)
		for groove in range(4):
			var gx := x - trunk_w * 0.3 + groove * trunk_w * 0.19
			draw_line(Vector2(gx, base_y - 5), Vector2(gx + lean * 0.18, base_y - h * 0.72), Color(0.2, 0.19, 0.14, 0.34), 2.0)
		# Exposed roots spread into the forest floor.
		draw_line(Vector2(x, base_y - 4), Vector2(x - trunk_w * 1.1, base_y + 5), bark.lightened(0.12), 4.0)
		draw_line(Vector2(x + 2, base_y - 2), Vector2(x + trunk_w * 1.25, base_y + 4), bark.darkened(0.12), 4.0)
		for leaf in range(13):
			var lx := x + tree_rng.randf_range(-82.0, 82.0) + lean * 0.25
			var ly := base_y - h + tree_rng.randf_range(-18.0, 105.0)
			var r := tree_rng.randf_range(20.0, 48.0)
			var foliage := Color("#263f35").lerp(Color("#64734a"), tree_rng.randf())
			draw_circle(Vector2(lx, ly), r, foliage)
			draw_arc(Vector2(lx - r * 0.1, ly - r * 0.12), r * 0.72, 3.2, 5.3, 12, Color(0.77, 0.79, 0.54, 0.13), 2.0)

	# Thin mist sits between the trees and the playable path.
	for i in range(5):
		var mist_y := 305.0 + i * 24.0
		draw_rect(Rect2(0, mist_y, LEVEL_END, 13), Color(0.86, 0.91, 0.87, 0.055))
	for i in range(7):
		var my := 292.0 + i * 19.0
		draw_rect(Rect2(0, my, LEVEL_END, 8), Color(0.87, 0.91, 0.86, 0.045))

	# Dense canopy shade: uneven silhouettes darken the upper edge of the scene.
	var canopy_rng := RandomNumberGenerator.new()
	canopy_rng.seed = 681
	for i in range(42):
		var cx := float(i) * 58.0 + canopy_rng.randf_range(-18.0, 18.0)
		var cy := canopy_rng.randf_range(-24.0, 28.0)
		var radius := canopy_rng.randf_range(30.0, 72.0)
		draw_circle(Vector2(cx, cy), radius, Color(0.08, 0.13, 0.10, 0.28))

	# Soft contact shadows cast by the foreground trees onto the forest floor.
	var shadow_rng := RandomNumberGenerator.new()
	shadow_rng.seed = 202610
	for i in range(24):
		var sx := float(i) * 105.0 + shadow_rng.randf_range(-28.0, 28.0)
		var sy := shadow_rng.randf_range(395.0, 432.0)
		var sw := shadow_rng.randf_range(48.0, 104.0)
		for layer in range(4):
			var spread := float(layer) * 9.0
			var shadow_rect := Rect2(sx - sw * 0.5 - spread, sy - 4.0 - spread * 0.15, sw + spread * 2.0, 9.0 + spread * 0.5)
			var shadow_points := PackedVector2Array([Vector2(shadow_rect.position.x, shadow_rect.position.y + shadow_rect.size.y * 0.5), Vector2(shadow_rect.position.x + shadow_rect.size.x * 0.18, shadow_rect.position.y), Vector2(shadow_rect.end.x - shadow_rect.size.x * 0.18, shadow_rect.position.y), Vector2(shadow_rect.end.x, shadow_rect.position.y + shadow_rect.size.y * 0.5), Vector2(shadow_rect.end.x - shadow_rect.size.x * 0.18, shadow_rect.end.y), Vector2(shadow_rect.position.x + shadow_rect.size.x * 0.18, shadow_rect.end.y)])
			draw_colored_polygon(shadow_points, Color(0.04, 0.06, 0.04, 0.11 - layer * 0.02))

	# Broad, faint light pools break up the cool forest shade.
	for i in range(12):
		var lx := float((i * 193 + 75) % int(LEVEL_END))
		var ly := 335.0 + float((i * 47) % 80)
		for layer in range(5):
			var r := 22.0 + layer * 13.0
			draw_circle(Vector2(lx, ly), r, Color(0.91, 0.91, 0.68, 0.018))

	# Ground and platforms: soil strata, grass, pebbles and small roots.
	for platform in get_tree().get_nodes_in_group("platforms"):
		if not is_instance_valid(platform):
			continue
		var size: Vector2 = platform.get_child(0).shape.size
		var rect := Rect2(platform.position - size / 2.0, size)
		draw_rect(rect, Color("#51483a"))
		draw_rect(Rect2(rect.position.x, rect.position.y + 8, size.x, size.y - 8), Color("#3d382f"))
		draw_rect(Rect2(rect.position.x, rect.position.y, size.x, 10), Color("#4f6843"))
		draw_rect(Rect2(rect.position.x, rect.position.y + 7, size.x, 4), Color("#7b8051"))
		var detail_rng := RandomNumberGenerator.new()
		detail_rng.seed = int(platform.position.x * 17.0 + size.x)
		for d in range(int(size.x / 8.0)):
			var dx := rect.position.x + detail_rng.randf_range(2.0, size.x - 2.0)
			var dy := rect.position.y + detail_rng.randf_range(13.0, size.y - 8.0)
			var pebble_size := detail_rng.randf_range(1.0, 3.6)
			draw_circle(Vector2(dx, dy), pebble_size, Color("#756b56") if d % 3 == 0 else Color("#2d3029"))
		for g in range(int(size.x / 7.0)):
			var gx := rect.position.x + detail_rng.randf_range(0.0, size.x)
			var gy := rect.position.y + 2.0
			draw_line(Vector2(gx, gy + 3), Vector2(gx + detail_rng.randf_range(-3.0, 3.0), gy - detail_rng.randf_range(1.0, 7.0)), Color("#87915a"), 1.4)

	# Brambles and small plants along the forest floor.
	var plant_rng := RandomNumberGenerator.new()
	plant_rng.seed = 844
	for i in range(160):
		var px := plant_rng.randf_range(0.0, LEVEL_END)
		var py := plant_rng.randf_range(385.0, 455.0)
		var leaf_color := Color("#3c5940").lerp(Color("#8b925c"), plant_rng.randf())
		draw_line(Vector2(px, py + 8), Vector2(px + plant_rng.randf_range(-7.0, 7.0), py - plant_rng.randf_range(2.0, 12.0)), leaf_color, 2.0)
		if i % 4 == 0:
			draw_circle(Vector2(px + 2, py + 1), plant_rng.randf_range(2.0, 4.0), Color("#a1a16c"))

	# Spikes, crystals and the portal retain a clean game-readable silhouette.
	for child in get_children():
		if not child is Area2D:
			continue
		var kind: String = child.get_meta("kind", "")
		if kind == "spike":
			var count: int = child.get_meta("count", 3)
			for i in range(count):
				var px := child.position.x - count * 9.0 + i * 18.0
				var points := PackedVector2Array([Vector2(px - 8, child.position.y + 6), Vector2(px, child.position.y - 12), Vector2(px + 8, child.position.y + 6)])
				draw_colored_polygon(points, Color("#51443e"))
				draw_colored_polygon(PackedVector2Array([points[0], points[1], Vector2(px - 1, child.position.y + 4)]), Color("#a3a18a"))
				draw_line(points[0], points[1], Color("#d4cbb1"), 1.5)
		elif kind == "crystal":
			var p: Vector2 = child.position
			draw_circle(p, 17, Color(0.42, 0.91, 0.88, 0.16))
			var points := PackedVector2Array([p + Vector2(0, -12), p + Vector2(9, 0), p + Vector2(0, 12), p + Vector2(-9, 0)])
			draw_colored_polygon(points, Color("#74ded0"))
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -12), p + Vector2(0, 12), p + Vector2(-9, 0)]), Color("#b4fff0"))
			draw_line(p + Vector2(0, -8), p + Vector2(0, 7), Color.WHITE, 2)
		elif kind == "goal":
			var p: Vector2 = child.position
			draw_circle(p, 54, Color(0.42, 0.22, 0.72, 0.13))
			draw_rect(Rect2(p.x - 18, p.y - 42, 36, 84), Color("#594c68"), false, 6)
			draw_rect(Rect2(p.x - 13, p.y - 36, 26, 72), Color("#8b7ed0", 0.72))
			draw_rect(Rect2(p.x - 7, p.y - 30, 14, 60), Color("#c4fff2", 0.82))
