extends SceneTree

const MAIN_SCENE := preload("res://scenes/main.tscn")
const JUMP_SPEED := 445.0
const GRAVITY := 1200.0
const RUN_SPEED := 245.0
const RUNWAY_MARGIN := 22.0

func _initialize() -> void:
	call_deferred("_run_validation")


func _run_validation() -> void:
	var game: Node = MAIN_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	var failures: Array[String] = []
	for level_index in range(10):
		game.call("_load_level", level_index)
		await process_frame
		var platforms: Array[Dictionary] = []
		for node in get_nodes_in_group("platforms"):
			if not is_instance_valid(node) or node.get_child_count() == 0:
				continue
			var shape_node := node.get_child(0) as CollisionShape2D
			var shape: Shape2D = shape_node.shape
			if not shape is RectangleShape2D:
				continue
			var size: Vector2 = shape.size
			platforms.append({
				"x": node.position.x,
				"left": node.position.x - size.x * 0.5,
				"right": node.position.x + size.x * 0.5,
				"top": node.position.y - size.y * 0.5,
				"width": size.x,
				"ground": size.y > 40.0
			})
		platforms.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["x"]) < float(b["x"]))
		if platforms.is_empty():
			failures.append("Level %02d has no platforms" % (level_index + 1))
			continue
		var reachable := PackedByteArray()
		reachable.resize(platforms.size())
		for i in range(platforms.size()):
			var p: Dictionary = platforms[i]
			if bool(p["ground"]) and float(p["left"]) <= 80.0 and float(p["right"]) >= 80.0:
				reachable[i] = 1
		for _pass_index in range(platforms.size()):
			var changed := false
			for i in range(platforms.size()):
				if reachable[i] == 0:
					continue
				var source: Dictionary = platforms[i]
				for j in range(i + 1, platforms.size()):
					if reachable[j] != 0:
						continue
					var target: Dictionary = platforms[j]
					var vertical_delta := float(target["top"]) - float(source["top"])
					var discriminant := JUMP_SPEED * JUMP_SPEED + 2.0 * GRAVITY * vertical_delta
					if discriminant < 0.0:
						continue
					var descending_time := (JUMP_SPEED + sqrt(discriminant)) / GRAVITY
					var max_horizontal := RUN_SPEED * descending_time - RUNWAY_MARGIN
					var gap := maxf(0.0, float(target["left"]) - float(source["right"]))
					if gap <= max_horizontal:
						reachable[j] = 1
						changed = true
			if not changed:
				break
		var unreachable: Array[String] = []
		for i in range(platforms.size()):
			if reachable[i] == 0:
				unreachable.append("x=%.0f top=%.0f" % [platforms[i]["x"], platforms[i]["top"]])
		if not unreachable.is_empty():
			failures.append("Level %02d has unreachable platforms: %s" % [level_index + 1, ", ".join(unreachable)])
		var crystals: Array[Area2D] = []
		for node in get_nodes_in_group("level_objects"):
			if node is Area2D and node.get_meta("kind", "") == "crystal":
				crystals.append(node as Area2D)
		if crystals.size() != int(game.get("crystal_total")):
			failures.append("Level %02d crystal count mismatch: nodes=%d expected=%d" % [level_index + 1, crystals.size(), int(game.get("crystal_total"))])
		for crystal in crystals:
			var can_collect := false
			for platform in platforms:
				var horizontal_overlap := absf(crystal.position.x - float(platform["x"])) <= float(platform["width"]) * 0.5 + 10.0 + 19.0
				var vertical_distance := absf(crystal.position.y - float(platform["top"]))
				if horizontal_overlap and vertical_distance <= 48.0:
					can_collect = true
					break
			if not can_collect:
				failures.append("Level %02d crystal at (%.0f, %.0f) has no nearby standing surface" % [level_index + 1, crystal.position.x, crystal.position.y])
		print("LEVEL %02d: %d platforms, %d crystals, reachability=%s" % [level_index + 1, platforms.size(), crystals.size(), "PASS" if unreachable.is_empty() else "FAIL"])
	if failures.is_empty():
		print("FASTWOKEN LEVEL VALIDATION: PASS (10 levels checked; analytical collision/jump model, not manual playtesting)")
		game.queue_free()
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FASTWOKEN LEVEL VALIDATION: FAIL (%d issues)" % failures.size())
		game.queue_free()
		quit(1)
