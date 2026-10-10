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

func _ready() -> void:
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
	# Each level has a hand-authored platform route and hazard rhythm.
	var layouts := [
		{"name":"Forest Entry", "ground":[[240,480],[760,260],[1130,300],[1560,300],[2040,400],[2440,280]], "platforms":[[520,365,112],[900,315,112],[1280,365,112],[1690,300,120],[1900,355,100],[2290,315,120]], "spikes":[[340,4],[760,3],[1130,4],[1560,4],[2010,3]], "crystals":[[190,410],[520,320],[760,410],[900,270],[1280,320],[1690,255],[1900,310],[2160,410]]},
		{"name":"Broken Canopy", "ground":[[220,440],[690,180],[1050,180],[1440,210],[1850,200],[2280,360]], "platforms":[[450,380,90],[590,330,86],[850,370,88],[1000,300,82],[1250,350,90],[1390,285,80],[1640,340,90],[1790,285,84],[2100,350,100]], "spikes":[[310,4],[690,3],[1050,3],[1440,3],[1850,3]], "crystals":[[170,410],[450,335],[590,285],[850,325],[1000,255],[1250,305],[1390,240],[1640,295],[1790,240],[2100,305]]},
		{"name":"Root Maze", "ground":[[210,420],[650,170],[1010,180],[1420,180],[1810,180],[2220,300]], "platforms":[[420,370,88],[520,310,80],[800,350,82],[900,285,82],[1170,355,84],[1280,300,82],[1580,350,86],[1690,285,82],[1980,350,90],[2090,295,82]], "spikes":[[290,4],[650,3],[1010,3],[1420,3],[1810,3]], "crystals":[[160,410],[420,325],[520,265],[800,305],[900,240],[1170,310],[1280,255],[1580,305],[1690,240],[1980,305]]},
		{"name":"Mossy Cliffs", "ground":[[220,440],[690,160],[1070,160],[1450,160],[1830,160],[2250,340]], "platforms":[[440,390,100],[570,335,90],[820,390,90],[950,325,90],[1200,370,90],[1330,300,86],[1580,365,90],[1710,295,90],[1980,360,90],[2110,300,86]], "spikes":[[300,4],[690,3],[1070,3],[1450,3],[1830,3]], "crystals":[[180,410],[440,345],[570,290],[820,345],[950,280],[1200,325],[1330,255],[1580,320],[1710,250],[1980,315]]},
		{"name":"Flooded Hollow", "ground":[[220,420],[650,180],[1030,180],[1410,180],[1790,180],[2200,320]], "platforms":[[440,360,100],[560,300,86],[820,345,88],[940,280,82],[1200,350,88],[1320,285,84],[1580,340,90],[1700,275,84],[1970,340,90],[2090,285,84]], "spikes":[[300,3],[650,3],[1030,3],[1410,3],[1790,3]], "crystals":[[160,410],[440,315],[560,260],[820,300],[940,240],[1200,305],[1320,245],[1580,295],[1700,235],[1970,295]]},
		{"name":"Thorn Run", "ground":[[230,450],[700,170],[1080,160],[1460,170],[1840,170],[2290,380]], "platforms":[[480,365,90],[590,305,82],[860,355,82],[970,290,80],[1240,350,82],[1350,285,80],[1620,345,84],[1730,280,82],[2050,350,90],[2170,290,82]], "spikes":[[310,5],[700,4],[1080,4],[1460,4],[1840,4]], "crystals":[[170,410],[480,320],[590,265],[860,310],[970,245],[1240,305],[1350,240],[1620,300],[1730,235],[2050,305]]},
		{"name":"Ravine Steps", "ground":[[220,420],[660,160],[1050,160],[1440,160],[1830,160],[2250,340]], "platforms":[[420,390,90],[530,340,80],[640,290,78],[820,370,82],[930,320,78],[1040,270,78],[1210,365,82],[1320,315,78],[1430,265,78],[1600,365,82],[1710,315,78],[1820,265,78],[2010,355,84],[2120,300,80]], "spikes":[[300,4],[660,3],[1050,3],[1440,3],[1830,3]], "crystals":[[160,410],[420,345],[640,245],[820,325],[1040,225],[1210,320],[1430,220],[1600,320],[1820,220],[2010,310]]},
		{"name":"Nightwood", "ground":[[220,420],[660,170],[1030,170],[1410,170],[1790,170],[2210,320]], "platforms":[[430,370,90],[550,310,82],[800,360,84],[920,295,80],[1180,355,84],[1300,290,80],[1560,350,84],[1680,285,80],[1940,350,86],[2060,290,82]], "spikes":[[300,4],[660,3],[1030,3],[1410,3],[1790,3]], "crystals":[[160,410],[430,325],[550,265],[800,315],[920,250],[1180,310],[1300,245],[1560,305],[1680,240],[1940,305]]},
		{"name":"Shattered Bridge", "ground":[[220,400],[600,130],[910,130],[1220,130],[1530,130],[1840,130],[2200,280]], "platforms":[[410,375,80],[500,320,72],[710,370,72],[810,315,72],[1020,370,72],[1120,310,72],[1330,365,72],[1430,305,72],[1640,360,72],[1740,300,72],[1950,355,80],[2050,295,76]], "spikes":[[300,4],[600,3],[910,3],[1220,3],[1530,3],[1840,3]], "crystals":[[150,410],[410,330],[500,275],[710,325],[810,270],[1020,325],[1120,265],[1330,320],[1430,260],[1640,315],[1740,255],[1950,310]]},
		{"name":"The Last Canopy", "ground":[[220,390],[590,130],[900,130],[1210,130],[1520,130],[1830,130],[2180,260],[2580,300]], "platforms":[[400,380,76],[490,325,70],[690,370,70],[780,310,70],[1000,360,70],[1090,300,70],[1310,355,70],[1400,295,70],[1620,350,70],[1710,290,70],[1930,350,76],[2020,285,70],[2320,345,90],[2440,290,80]], "spikes":[[300,4],[590,3],[900,3],[1210,3],[1520,3],[1830,3],[2180,3]], "crystals":[[150,410],[400,335],[490,280],[690,325],[780,265],[1000,315],[1090,255],[1310,310],[1400,250],[1620,305],[1710,245],[1930,305],[2020,240],[2320,300]]}
	]
	var data: Dictionary = layouts[selected_level]
	var ground: Array = data["ground"]
	var elevated: Array = data["platforms"]
	var spike_data: Array = data["spikes"]
	var crystal_data: Array = data["crystals"]
	level_end = float(ground[-1][0]) + float(ground[-1][1]) * 0.5 + 100.0
	crystal_total = crystal_data.size()
	for piece in ground:
		_add_platform(Vector2(piece[0], FLOOR_Y), Vector2(piece[1], 144))
	for piece in elevated:
		_add_platform(Vector2(piece[0], piece[1]), Vector2(piece[2], 18))
	for spike in spike_data:
		_add_spikes(Vector2(spike[0], 396), int(spike[1]))
	for p in crystal_data:
		_add_crystal(Vector2(p[0], p[1]))
	_add_goal(Vector2(float(ground[-1][0]) + float(ground[-1][1]) * 0.5 - 45.0, 405))

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

func _process(_delta: float) -> void:
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
	if won:
		_load_level(selected_level)
		return
	deaths += 1
	player.reset_to_spawn()
	var deaths_label: Label = hud.find_child("Deaths", true, false)
	if deaths_label:
		deaths_label.text = "  ☠ %d" % deaths
	_update_hud()

func _update_hud() -> void:
	if is_instance_valid(score_label):
		score_label.text = "LEVEL %02d/10   ◆ %d/%d" % [selected_level + 1, score, crystal_total]

func _draw() -> void:
	# The forest photograph is rendered by a parallax TextureRect behind the world.
	# Platforms use a real CC0 forest-floor texture on their walkable surfaces.
	# Ground and platforms: soil strata, grass, pebbles and small roots.
	for platform in get_tree().get_nodes_in_group("platforms"):
		if not is_instance_valid(platform):
			continue
		var size: Vector2 = platform.get_child(0).shape.size
		var rect := Rect2(platform.position - size / 2.0, size)
		draw_rect(rect, Color("#4b4034"))
		draw_rect(Rect2(rect.position.x, rect.position.y + 8, size.x, size.y - 8), Color("#302c26"))
		var tile_width := 128.0
		var tile_count := int(ceil(size.x / tile_width))
		for tile_index in range(tile_count):
			var tile_x := rect.position.x + tile_index * tile_width
			var draw_width := minf(tile_width, rect.end.x - tile_x)
			var source_width := 512.0 * draw_width / tile_width
			draw_texture_rect_region(GROUND_TEXTURE, Rect2(tile_x, rect.position.y, draw_width, 18.0), Rect2(0, 128, source_width, 72.0))
		# A narrow dark seam separates the photo surface from the soil cutaway.
		draw_rect(Rect2(rect.position.x, rect.position.y + 18, size.x, 3), Color(0.16, 0.14, 0.11, 0.78))

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
