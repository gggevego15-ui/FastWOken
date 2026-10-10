extends Node2D

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const GROUND_TEXTURE := preload("res://assets/forest_leaves_02.jpg")
var level_end := 2240.0
var selected_level := 0
var unlocked_level := 0
var best_crystals: Dictionary = {}
var tutorial_completed := false
const PROGRESS_PATH := "user://fastwoken_progress.cfg"
var crystal_total := 8
const FLOOR_Y := 468.0

var player: CharacterBody2D
var camera: Camera2D
var hud: CanvasLayer
var score := 0
var deaths := 0
var won := false
var menu_open := true
var main_menu_layer: CanvasLayer
var game_hud: CanvasLayer
var transition_active := false
var transition_overlay: ColorRect
var message_label: Label
var score_label: Label
var touch_left := false
var touch_right := false
var touch_jump := false
var forest_background: TextureRect
var applied_touch_left := false
var applied_touch_right := false
var applied_touch_jump := false
var fx_particles: Array[Dictionary] = []
var fx_rng := RandomNumberGenerator.new()

func _ready() -> void:
	fx_rng.randomize()
	_setup_input()
	_setup_forest_background()
	_load_progress()
	_load_level(0)
	_spawn_player()
	_build_ui()
	_setup_forest_audio()
	_show_main_menu()
	if not tutorial_completed:
		_show_tutorial()
	if is_instance_valid(player):
		player.controls_locked = true
	queue_redraw()


func _setup_forest_background() -> void:
	var background_layer := CanvasLayer.new()
	background_layer.name = "PhotographicForestBackground"
	background_layer.layer = -1
	add_child(background_layer)
	forest_background = TextureRect.new()
	forest_background.name = "ForestPhoto"
	forest_background.texture = load("res://assets/forest_slope.jpg") as Texture2D
	forest_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	forest_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	forest_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	forest_background.position = Vector2.ZERO
	forest_background.size = Vector2(1800, 540)
	forest_background.modulate = Color(0.9, 0.94, 0.91, 1.0)
	background_layer.add_child(forest_background)


func _load_progress() -> void:
	var config := ConfigFile.new()
	if config.load(PROGRESS_PATH) != OK:
		unlocked_level = 0
		best_crystals = {}
		return
	unlocked_level = clampi(int(config.get_value("progress", "unlocked_level", 0)), 0, 9)
	var stored_scores = config.get_value("progress", "best_crystals", {})
	best_crystals = stored_scores if stored_scores is Dictionary else {}
	tutorial_completed = bool(config.get_value("progress", "tutorial_completed", false))


func _save_progress() -> void:
	var config := ConfigFile.new()
	config.set_value("progress", "unlocked_level", unlocked_level)
	config.set_value("progress", "best_crystals", best_crystals)
	config.set_value("progress", "tutorial_completed", tutorial_completed)
	var error := config.save(PROGRESS_PATH)
	if error != OK:
		push_warning("FastWOken could not save progress (error %d)." % error)


func _play_sfx(kind: String) -> void:
	# Short effects are synthesized in code; no external audio assets are required.
	const SAMPLE_RATE := 22050
	var duration := 0.24 if kind == "jump" else (0.34 if kind == "crystal" else 0.72)
	var sample_count := int(SAMPLE_RATE * duration)
	var pcm := PackedByteArray()
	pcm.resize(sample_count * 2)
	var phase := 0.0
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in range(sample_count):
		var t := float(i) / SAMPLE_RATE
		var progress := t / duration
		var envelope := 1.0 - progress
		var sample := 0.0
		if kind == "jump":
			var frequency := lerpf(240.0, 620.0, progress)
			phase += TAU * frequency / SAMPLE_RATE
			sample = (sin(phase) * 0.72 + sin(phase * 2.0) * 0.18) * envelope * 0.42
		elif kind == "crystal":
			var frequency := 880.0 if progress < 0.45 else 1320.0
			phase += TAU * frequency / SAMPLE_RATE
			sample = (sin(phase) * 0.7 + sin(phase * 2.5) * 0.22) * envelope * 0.38
		else:
			var frequency := lerpf(180.0, 920.0, progress)
			phase += TAU * frequency / SAMPLE_RATE
			var shimmer := sin(phase * 2.03) * 0.22 + sin(phase * 3.01) * 0.12
			var airy_noise := rng.randf_range(-1.0, 1.0) * (1.0 - progress) * 0.08
			sample = (sin(phase) * 0.48 + shimmer + airy_noise) * envelope * 0.5
		var signed_sample := int(clampf(sample, -0.95, 0.95) * 32767.0)
		if signed_sample < 0:
			signed_sample += 65536
		pcm[i * 2] = signed_sample & 0xff
		pcm[i * 2 + 1] = (signed_sample >> 8) & 0xff
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = pcm
	var audio_player := AudioStreamPlayer.new()
	audio_player.name = "SFX_" + kind
	audio_player.stream = stream
	audio_player.volume_db = -7.0 if kind == "portal" else -4.0
	add_child(audio_player)
	audio_player.finished.connect(audio_player.queue_free)
	audio_player.play()


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
	_add_key_action("level_next", [KEY_BRACKETRIGHT, KEY_PAGEUP])
	_add_key_action("level_previous", [KEY_BRACKETLEFT, KEY_PAGEDOWN])

func _add_key_action(action_name: String, keys: Array) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	for keycode in keys:
		var event := InputEventKey.new()
		event.physical_keycode = keycode
		if not InputMap.action_has_event(action_name, event):
			InputMap.action_add_event(action_name, event)

func _load_level(index: int) -> void:
	selected_level = posmod(index, 10)
	for node in get_tree().get_nodes_in_group("level_objects"):
		node.queue_free()
	for node in get_tree().get_nodes_in_group("platforms"):
		node.remove_from_group("platforms")
	level_end = 2400.0 + selected_level * 120.0
	score = 0
	won = false
	crystal_total = 8
	_build_level()
	if is_instance_valid(player):
		player.global_position = Vector2(80, 350)
		player.velocity = Vector2.ZERO
		player.spawn_position = player.global_position
		player.controls_locked = false
	if is_instance_valid(camera):
		camera.limit_right = int(level_end)
	if is_instance_valid(message_label):
		message_label.text = "LEVEL %02d / 10   —   [ ] to change level" % (selected_level + 1)
	_update_hud()
	queue_redraw()

func _build_level() -> void:
	# Hardcore routes are generated from a reachability budget, not arbitrary gaps.
	# Player physics: jump speed 445 px/s, gravity 1200 px/s^2, run speed 245 px/s.
	var ground: Array = [[220, 440]]
	var target_end := 2400.0 + float(selected_level) * 120.0
	var ground_x := 820.0
	while ground_x < target_end - 600.0:
		ground.append([ground_x, 220.0])
		ground_x += 600.0
	var final_ground_x := target_end - 230.0
	ground.append([final_ground_x, 300.0])

	# Difficulty rises through narrower ledges, slightly longer gaps, and more
	# dangerous ground recovery zones. Vertical changes stay inside the jump envelope.
	var route_width := maxf(60.0, 84.0 - float(selected_level) * 2.5)
	var route_spacing := 148.0 + float(selected_level) * 1.6
	var elevated: Array = []
	var crystal_data: Array = []
	var route_x := 500.0
	var route_index := 0
	while route_x < final_ground_x - 105.0:
		var pattern := [374.0, 336.0, 380.0, 342.0, 378.0, 340.0, 382.0, 346.0]
		var y: float = pattern[route_index % pattern.size()]
		# Later stages vary the rhythm without introducing unreachable height spikes.
		if selected_level >= 5 and route_index % 4 == 2:
			y -= 5.0
		if selected_level >= 8 and route_index % 5 == 4:
			y += 4.0
		elevated.append([route_x, y, route_width])
		crystal_data.append([route_x, y - 42.0])
		route_x += route_spacing
		route_index += 1

	var spike_data: Array = []
	for ground_index in range(1, ground.size() - 1):
		var ground_piece: Array = ground[ground_index]
		var spike_count := mini(5, 3 + int(selected_level / 3))
		spike_data.append([ground_piece[0], spike_count])
	# First crystal gives a safe target; optional crystals above narrow ledges reward precision.
	crystal_data.push_front([170.0, 410.0])
	var data := {"ground": ground, "platforms": elevated, "spikes": spike_data, "crystals": crystal_data}
	var spike_count_total := spike_data.size()
	crystal_total = crystal_data.size()
	level_end = final_ground_x + 250.0
	_validate_jump_route(elevated, ground)
	for piece in ground:
		_add_platform(Vector2(piece[0], FLOOR_Y), Vector2(piece[1], 144))
	for piece in elevated:
		_add_platform(Vector2(piece[0], piece[1]), Vector2(piece[2], 18))
	for spike in spike_data:
		_add_spikes(Vector2(spike[0], 396), int(spike[1]))
	for p in crystal_data:
		_add_crystal(Vector2(p[0], p[1]))
	_add_goal(Vector2(float(ground[-1][0]) + float(ground[-1][1]) * 0.5 - 45.0, 405))


func _max_jump_horizontal_distance(source_top: float, target_top: float) -> float:
	# Solve dy = -445*t + 0.5*1200*t^2 for the descending crossing.
	var vertical_delta := target_top - source_top
	var discriminant := 445.0 * 445.0 + 2.0 * 1200.0 * vertical_delta
	if discriminant < 0.0:
		return 0.0
	var landing_time := (445.0 + sqrt(discriminant)) / 1200.0
	return 245.0 * landing_time


func _validate_jump_route(elevated: Array, ground: Array) -> void:
	# Conservative 24 px reserve accounts for imperfect takeoff/landing timing.
	var source_left := float(ground[0][0]) - float(ground[0][1]) * 0.5
	var source_right := float(ground[0][0]) + float(ground[0][1]) * 0.5
	var source_top := FLOOR_Y - 72.0
	var route_gaps: Array[Dictionary] = []
	for ledge in elevated:
		var ledge_x: float = ledge[0]
		var ledge_top: float = ledge[1] - 9.0
		var ledge_width: float = ledge[2]
		var gap := maxf(0.0, ledge_x - ledge_width * 0.5 - source_right)
		var available := _max_jump_horizontal_distance(source_top, ledge_top) - 24.0
		route_gaps.append({"gap": gap, "available": available, "from": source_right, "to": ledge_x - ledge_width * 0.5})
		if gap > available:
			push_warning("FastWOken level %02d: jump to ledge at x=%.0f needs %.1f px but conservative reach is %.1f px." % [selected_level + 1, ledge_x, gap, available])
		source_left = ledge_x - ledge_width * 0.5
		source_right = ledge_x + ledge_width * 0.5
		source_top = ledge_top
	var final_piece: Array = ground[ground.size() - 1]
	var final_left := float(final_piece[0]) - float(final_piece[1]) * 0.5
	var final_gap := maxf(0.0, final_left - source_right)
	var final_available := _max_jump_horizontal_distance(source_top, FLOOR_Y - 72.0) - 24.0
	if final_gap > final_available:
		push_warning("FastWOken level %02d: final jump needs %.1f px but conservative reach is %.1f px." % [selected_level + 1, final_gap, final_available])

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
	body.add_to_group("level_objects")

func _add_spikes(center: Vector2, count: int) -> void:
	var hazard := Area2D.new()
	hazard.position = center
	hazard.collision_layer = 0
	hazard.collision_mask = 1
	hazard.set_meta("kind", "spike")
	hazard.add_to_group("level_objects")
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
	crystal.add_to_group("level_objects")
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
	goal.add_to_group("level_objects")
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
	player.fx_requested.connect(_on_player_fx_requested)
	add_child(player)
	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 7.0
	camera.limit_left = 0
	camera.limit_right = int(level_end)
	camera.limit_top = 0
	camera.limit_bottom = 540
	player.add_child(camera)
	camera.make_current()

func _build_ui() -> void:
	hud = CanvasLayer.new()
	game_hud = hud
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
		_add_level_touch_button("LEVEL −", Vector2(360, 448), -1)
		_add_level_touch_button("LEVEL +", Vector2(500, 448), 1)

	var menu_button := Button.new()
	menu_button.text = "LEVEL SELECT"
	menu_button.position = Vector2(790, 16)
	menu_button.size = Vector2(152, 42)
	menu_button.add_theme_font_size_override("font_size", 15)
	menu_button.add_theme_color_override("font_color", Color.WHITE)
	menu_button.add_theme_stylebox_override("normal", _panel_style(Color(0.12, 0.22, 0.36, 0.92)))
	hud.add_child(menu_button)
	menu_button.pressed.connect(_show_main_menu)



func _show_tutorial() -> void:
	if not is_instance_valid(main_menu_layer):
		return
	# Put the tutorial above the menu without leaving an opaque, misplaced
	# ColorRect covering the whole screen when the game first launches.
	var tutorial_layer := CanvasLayer.new()
	tutorial_layer.name = "TutorialLayer"
	tutorial_layer.layer = 20
	add_child(tutorial_layer)

	var shade := ColorRect.new()
	shade.name = "TutorialOverlay"
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.015, 0.025, 0.035, 0.82)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	tutorial_layer.add_child(shade)

	var panel := PanelContainer.new()
	panel.position = Vector2(200, 50)
	panel.size = Vector2(560, 440)
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.055, 0.105, 0.12, 0.99)))
	shade.add_child(panel)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 13)
	panel.add_child(content)

	var title := Label.new()
	title.text = "FIRST TIME IN THE FOREST?"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 27)
	title.add_theme_color_override("font_color", Color("#8fffe3"))
	content.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "QUICK TUTORIAL"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 15)
	subtitle.add_theme_color_override("font_color", Color("#c0d6c9"))
	content.add_child(subtitle)

	var instructions := Label.new()
	instructions.text = "MOVE     A / D or LEFT / RIGHT\nJUMP     SPACE, W or UP\nRESTART  R after a fall\n\nCollect crystals for points. Avoid spikes\nand reach the glowing portal to finish.\nEach cleared level unlocks the next one.\n\nPHONE / TABLET: use the on-screen buttons."
	instructions.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	instructions.add_theme_font_size_override("font_size", 18)
	instructions.add_theme_color_override("font_color", Color("#f1f7ee"))
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(instructions)

	var start_button := Button.new()
	start_button.text = "LET'S GO!"
	start_button.custom_minimum_size = Vector2(0, 48)
	start_button.add_theme_font_size_override("font_size", 19)
	start_button.add_theme_color_override("font_color", Color.WHITE)
	start_button.add_theme_stylebox_override("normal", _panel_style(Color("#267d6a")))
	content.add_child(start_button)
	start_button.pressed.connect(func():
		tutorial_completed = true
		_save_progress()
		tutorial_layer.queue_free()
	)


func _show_main_menu() -> void:
	menu_open = true
	if is_instance_valid(player):
		player.controls_locked = true
	if is_instance_valid(game_hud):
		game_hud.visible = false
	if is_instance_valid(main_menu_layer):
		main_menu_layer.queue_free()
	main_menu_layer = CanvasLayer.new()
	main_menu_layer.layer = 10
	add_child(main_menu_layer)

	var shade := ColorRect.new()
	shade.position = Vector2.ZERO
	shade.size = Vector2(960, 540)
	shade.color = Color(0.025, 0.055, 0.065, 0.94)
	shade.modulate.a = 0.0
	main_menu_layer.add_child(shade)
	var shade_tween := create_tween()
	shade_tween.tween_property(shade, "modulate:a", 1.0, 0.35)

	var panel := PanelContainer.new()
	panel.position = Vector2(150, 34)
	panel.size = Vector2(660, 492)
	panel.modulate.a = 0.0
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.07, 0.12, 0.13, 0.97)))
	main_menu_layer.add_child(panel)
	var panel_tween := create_tween()
	panel_tween.set_parallel(true)
	panel_tween.tween_property(panel, "position:y", 24.0, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	panel_tween.tween_property(panel, "modulate:a", 1.0, 0.32)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	panel.add_child(content)

	var title := Label.new()
	title.text = "FastWOken"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color("#8fffe3"))
	content.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "FOREST TRIALS  •  SELECT YOUR LEVEL"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 15)
	subtitle.add_theme_color_override("font_color", Color("#c0d6c9"))
	content.add_child(subtitle)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	content.add_child(grid)

	var names := [
		"01  Forest Entry", "02  Broken Canopy",
		"03  Root Maze", "04  Mossy Cliffs",
		"05  Flooded Hollow", "06  Thorn Run",
		"07  Ravine Steps", "08  Nightwood",
		"09  Shattered Bridge", "10  The Last Canopy"
	]
	for i in range(names.size()):
		var level_button := Button.new()
		level_button.text = names[i]
		if i > unlocked_level:
			level_button.text += "  [LOCKED]"
			level_button.disabled = true
		elif best_crystals.has(str(i)):
			level_button.text += "  [CLEAR]"
		level_button.modulate.a = 0.0
		level_button.custom_minimum_size = Vector2(275, 48)
		level_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		level_button.add_theme_font_size_override("font_size", 17)
		level_button.add_theme_color_override("font_color", Color("#f1f7ee"))
		level_button.add_theme_stylebox_override("normal", _panel_style(Color("#25413b")))
		level_button.add_theme_stylebox_override("hover", _panel_style(Color("#387263")))
		level_button.add_theme_stylebox_override("pressed", _panel_style(Color("#5a9a80")))
		grid.add_child(level_button)
		level_button.pressed.connect(_transition_to_level.bind(i))
		var button_tween := create_tween()
		button_tween.tween_interval(0.08 + float(i) * 0.035)
		button_tween.tween_property(level_button, "modulate:a", 1.0, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	var footer := Label.new()
	footer.text = "PC: A/D or ←/→ to move • Space to jump • R to restart"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size", 13)
	footer.add_theme_color_override("font_color", Color("#a7bcb2"))
	content.add_child(footer)



func _transition_to_level(index: int) -> void:
	var target_level := posmod(index, 10)
	if target_level > unlocked_level:
		return
	if transition_active:
		return
	transition_active = true
	if is_instance_valid(player):
		player.controls_locked = true
	if is_instance_valid(transition_overlay):
		transition_overlay.queue_free()
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	transition_overlay = ColorRect.new()
	transition_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	transition_overlay.color = Color(0.015, 0.035, 0.04, 0.0)
	transition_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(transition_overlay)
	var tween := create_tween()
	tween.tween_property(transition_overlay, "color:a", 1.0, 0.28).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_callback(_finish_level_transition.bind(index))


func _finish_level_transition(index: int) -> void:
	_start_selected_level(index)
	if not is_instance_valid(transition_overlay):
		transition_active = false
		return
	var tween := create_tween()
	tween.tween_property(transition_overlay, "color:a", 0.0, 0.38).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_callback(_clear_transition_overlay)


func _clear_transition_overlay() -> void:
	if is_instance_valid(transition_overlay):
		var layer := transition_overlay.get_parent()
		if is_instance_valid(layer):
			layer.queue_free()
	transition_overlay = null
	transition_active = false



func _start_selected_level(index: int) -> void:
	_load_level(index)
	menu_open = false
	if is_instance_valid(main_menu_layer):
		main_menu_layer.queue_free()
		main_menu_layer = null
	if is_instance_valid(game_hud):
		game_hud.visible = true
	if is_instance_valid(player):
		player.controls_locked = false
		player.global_position = Vector2(80, 350)
		player.velocity = Vector2.ZERO
		player.spawn_position = player.global_position
	queue_redraw()


func _add_level_touch_button(caption: String, at: Vector2, direction: int) -> void:
	var button := Button.new()
	button.text = caption
	button.position = at
	button.size = Vector2(112, 42)
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _panel_style(Color(0.12, 0.22, 0.36, 0.86)))
	hud.add_child(button)
	button.pressed.connect(func(): _transition_to_level(selected_level + direction))

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

func _process(delta: float) -> void:
	_update_fx_particles(delta)
	if menu_open or not is_instance_valid(player):
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

	if Input.is_action_just_pressed("jump") and player.is_on_floor():
		_play_sfx("jump")
	if player.global_position.y > 620:
		_respawn()
	if Input.is_action_just_pressed("restart"):
		_respawn()
	if Input.is_action_just_pressed("level_next"):
		_transition_to_level(selected_level + 1)
	if Input.is_action_just_pressed("level_previous"):
		_transition_to_level(selected_level - 1)
	if is_instance_valid(forest_background) and is_instance_valid(camera):
		forest_background.position.x = -camera.global_position.x * 0.15
	queue_redraw()


func _on_player_fx_requested(kind: String, at: Vector2, direction: int) -> void:
	var count := 4 if kind == "run" else (13 if kind == "land" else 7)
	for i in range(count):
		var angle := fx_rng.randf_range(-PI * 0.92, -PI * 0.08)
		if kind == "run":
			angle = fx_rng.randf_range(-PI * 0.82, -PI * 0.18)
		var speed := fx_rng.randf_range(22.0, 85.0) if kind == "land" else fx_rng.randf_range(14.0, 48.0)
		var horizontal := cos(angle) * speed
		if kind == "run":
			horizontal = -direction * fx_rng.randf_range(18.0, 62.0)
		var vertical := sin(angle) * speed
		if kind == "jump":
			vertical = -fx_rng.randf_range(18.0, 58.0)
		var tint := Color("#b5a58a") if i % 3 != 0 else Color("#d7c9a7")
		var size := fx_rng.randf_range(2.0, 4.5) if kind == "land" else fx_rng.randf_range(1.5, 3.0)
		if kind == "run" and i == count - 1:
			tint = Color("#76e9d7")
			size = 2.0
		fx_particles.append({
			"position": at + Vector2(fx_rng.randf_range(-5.0, 5.0), fx_rng.randf_range(-2.0, 2.0)),
			"velocity": Vector2(horizontal, vertical),
			"life": fx_rng.randf_range(0.22, 0.42) if kind == "run" else fx_rng.randf_range(0.32, 0.58),
			"max_life": 0.42 if kind == "run" else 0.58,
			"size": size,
			"color": tint
		})
	if fx_particles.size() > 160:
		fx_particles = fx_particles.slice(fx_particles.size() - 160)


func _update_fx_particles(delta: float) -> void:
	for i in range(fx_particles.size() - 1, -1, -1):
		var particle: Dictionary = fx_particles[i]
		particle["life"] = float(particle["life"]) - delta
		if float(particle["life"]) <= 0.0:
			fx_particles.remove_at(i)
			continue
		var particle_velocity: Vector2 = particle["velocity"]
		particle_velocity.y += 190.0 * delta
		particle["velocity"] = particle_velocity
		particle["position"] = particle["position"] + particle_velocity * delta
		fx_particles[i] = particle
	if not fx_particles.is_empty():
		queue_redraw()


func _on_hazard_entered(body: Node2D) -> void:
	if body == player:
		_respawn()

func _on_crystal_collected(body: Node2D, crystal: Area2D) -> void:
	if body != player or not is_instance_valid(crystal):
		return
	_play_sfx("crystal")
	score += 1
	crystal.queue_free()
	_update_hud()

func _on_goal_reached(body: Node2D) -> void:
	if body != player or won:
		return
	_play_sfx("portal")
	won = true
	player.controls_locked = true
	var level_key := str(selected_level)
	best_crystals[level_key] = maxi(int(best_crystals.get(level_key, 0)), score)
	if selected_level < 9:
		unlocked_level = maxi(unlocked_level, selected_level + 1)
	_save_progress()
	message_label.text = "LEVEL %02d CLEAR!  Crystals: %d/%d  —  Press ] for next" % [selected_level + 1, score, crystal_total]

func _respawn() -> void:
	if won or not is_instance_valid(player) or player.is_dying:
		return
	deaths += 1
	player.play_death_animation()
	var deaths_label: Label = hud.find_child("Deaths", true, false)
	if deaths_label:
		deaths_label.text = "  ☠ %d" % deaths
	_update_hud()
	await get_tree().create_timer(0.42).timeout
	if is_instance_valid(player):
		player.reset_to_spawn()

func _update_hud() -> void:
	if is_instance_valid(score_label):
		score_label.text = "LEVEL %02d/10   ◆ %d/%d" % [selected_level + 1, score, crystal_total]

func _draw() -> void:
	# Forest photo stays in the far background; soil is drawn as layered, uneven earth.
	# Keep detail deterministic so it does not shimmer as _draw() runs every frame.
	for platform in get_tree().get_nodes_in_group("platforms"):
		if not is_instance_valid(platform) or platform.get_child_count() == 0:
			continue
		var size: Vector2 = platform.get_child(0).shape.size
		var rect := Rect2(platform.position - size / 2.0, size)
		var is_ground := size.y > 40.0

		# Dark damp soil base and two subtly different strata.
		draw_rect(rect, Color("#40362c"))
		if is_ground:
			var middle_y := rect.position.y + 28.0
			var lower_y := rect.position.y + 66.0
			var soil_mid := PackedVector2Array([
				Vector2(rect.position.x, middle_y),
				Vector2(rect.position.x + size.x * 0.18, middle_y + 5.0),
				Vector2(rect.position.x + size.x * 0.39, middle_y - 2.0),
				Vector2(rect.position.x + size.x * 0.63, middle_y + 4.0),
				Vector2(rect.end.x, middle_y - 1.0),
				Vector2(rect.end.x, lower_y),
				Vector2(rect.position.x, lower_y + 3.0)
			])
			draw_colored_polygon(soil_mid, Color("#514336"))
			var soil_lower := PackedVector2Array([
				Vector2(rect.position.x, lower_y),
				Vector2(rect.position.x + size.x * 0.22, lower_y + 4.0),
				Vector2(rect.position.x + size.x * 0.48, lower_y - 3.0),
				Vector2(rect.position.x + size.x * 0.77, lower_y + 2.0),
				Vector2(rect.end.x, lower_y - 2.0),
				Vector2(rect.end.x, rect.end.y),
				Vector2(rect.position.x, rect.end.y)
			])
			draw_colored_polygon(soil_lower, Color("#302b25"))
			# Small earthy clods, stones and thin roots break up the flat cutaway.
			var detail_step := 37.0
			var detail_count := int(size.x / detail_step)
			for detail_i in range(detail_count):
				var detail_x := rect.position.x + 9.0 + float(detail_i) * detail_step
				var seed_value := sin((platform.position.x + float(detail_i) * 19.7) * 0.137)
				var detail_y := rect.position.y + 38.0 + absf(seed_value) * 53.0
				var pebble_color := Color("#77624a") if detail_i % 3 == 0 else Color("#3b342b")
				draw_rect(Rect2(detail_x, detail_y, 3.0 + absf(seed_value) * 4.0, 2.0), pebble_color)
				if detail_i % 4 == 1:
					draw_line(Vector2(detail_x + 2.0, detail_y + 9.0), Vector2(detail_x + 7.0, detail_y + 13.0), Color("#29271f"), 1.5)
					draw_line(Vector2(detail_x + 7.0, detail_y + 13.0), Vector2(detail_x + 12.0, detail_y + 12.0), Color("#29271f"), 1.0)
		else:
			# Floating ledges have a compact dark rock/soil underside.
			draw_rect(Rect2(rect.position.x, rect.position.y + 8.0, size.x, maxf(0.0, size.y - 8.0)), Color("#332d27"))

		# A thin photo-textured moss/leaf layer forms the walkable surface.
		var tile_width := 128.0
		var tile_count := int(ceil(size.x / tile_width))
		for tile_index in range(tile_count):
			var tile_x := rect.position.x + float(tile_index) * tile_width
			var draw_width := minf(tile_width, rect.end.x - tile_x)
			var source_width := 512.0 * draw_width / tile_width
			draw_texture_rect_region(GROUND_TEXTURE, Rect2(tile_x, rect.position.y, draw_width, minf(18.0, size.y)), Rect2(0, 128, source_width, 72.0))
		# Mossy edge, damp seam, tiny grass blades and leaf litter.
		draw_line(Vector2(rect.position.x, rect.position.y + 17.0), Vector2(rect.end.x, rect.position.y + 17.0), Color("#302d22", 0.85), 2.0)
		var edge_count := int(size.x / 13.0)
		for edge_i in range(edge_count):
			var edge_x := rect.position.x + 5.0 + float(edge_i) * 13.0
			var edge_noise := sin((platform.position.x + float(edge_i) * 23.0) * 0.19)
			if edge_i % 3 != 1:
				var blade_height := 2.0 + absf(edge_noise) * 5.0
				var grass_color := Color("#526744") if edge_i % 2 == 0 else Color("#748052")
				draw_line(Vector2(edge_x, rect.position.y + 3.0), Vector2(edge_x - 2.0, rect.position.y - blade_height), grass_color, 1.5)
			if edge_i % 4 == 0:
				draw_rect(Rect2(edge_x + 3.0, rect.position.y + 8.0 + absf(edge_noise) * 4.0, 2.0, 1.5), Color("#b0a17b", 0.8))

	# Spikes, crystals and the portal retain a clean game-readable silhouette.
	for child in get_children():
		if not child is Area2D:
			continue
		var kind: String = child.get_meta("kind", "")
		if kind == "spike":
			var count: int = child.get_meta("count", 3)
			for i in range(count):
				var spike_x: float = child.position.x - count * 9.0 + i * 18.0
				var points := PackedVector2Array([Vector2(spike_x - 8, child.position.y + 6), Vector2(spike_x, child.position.y - 12), Vector2(spike_x + 8, child.position.y + 6)])
				draw_colored_polygon(points, Color("#51443e"))
				draw_colored_polygon(PackedVector2Array([points[0], points[1], Vector2(spike_x - 1, child.position.y + 4)]), Color("#a3a18a"))
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

	# Lightweight pixel particles: earthy dust plus a mint glint in the running trail.
	for particle in fx_particles:
		var life_ratio := clampf(float(particle["life"]) / float(particle["max_life"]), 0.0, 1.0)
		var particle_color: Color = particle["color"]
		particle_color.a = life_ratio * 0.78
		var particle_position: Vector2 = particle["position"]
		var particle_size: float = float(particle["size"]) * (0.45 + life_ratio * 0.55)
		draw_rect(Rect2(particle_position, Vector2(particle_size, particle_size)), particle_color)
