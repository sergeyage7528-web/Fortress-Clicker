extends SceneTree

const TEST_SAVE := "user://fortress_regression_primary.cfg"
const TEST_TEMP := "user://fortress_regression_primary.tmp"
const TEST_BACKUP := "user://fortress_regression_primary.bak"
const GameScript = preload("res://main.gd")

var failures: int = 0

func _init() -> void:
	test_clamped_save_values()
	test_atomic_stage_completion()
	test_single_enemy_reward()
	test_old_projectile_generation()
	SaveManager.delete_save(TEST_SAVE, TEST_TEMP, TEST_BACKUP)
	check(SaveManager.save_game({"version":4, "stage":5, "gold":100}, TEST_SAVE, TEST_TEMP, TEST_BACKUP) == OK, "initial save")
	check(SaveManager.save_game({"version":4, "stage":6, "gold":200}, TEST_SAVE, TEST_TEMP, TEST_BACKUP) == OK, "backup-producing save")
	var corrupt_file := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	if corrupt_file != null:
		corrupt_file.store_string("[broken\n")
		corrupt_file.close()
	else:
		failures += 1
		push_error("Не удалось создать повреждённое тестовое сохранение.")
	var restored_data := SaveManager.load_game(TEST_SAVE, TEST_BACKUP)
	check(int(restored_data.get("stage", 0)) == 5, "backup recovery returns the prior save")
	check(FileAccess.file_exists(TEST_SAVE), "backup recovery restores the main file")
	SaveManager.delete_save(TEST_SAVE, TEST_TEMP, TEST_BACKUP)
	if failures == 0:
		print("SaveManager regression checks passed.")
		quit(0)
	else:
		quit(1)

func check(condition: bool, description: String) -> void:
	if condition: return
	failures += 1
	push_error("Regression check failed: %s" % description)

func test_clamped_save_values() -> void:
	var game := GameScript.new()
	game.apply_save_data({"stage":-50, "gold":-1000, "tower_level":-10, "fortress_level":"broken", "heart_shards":-500})
	check(game.stage == 1, "negative stage is normalized")
	check(game.gold == 0, "negative gold is normalized")
	check(game.tower_level == 1 and game.fortress_level == 1, "invalid upgrade levels are normalized")
	check(game.heart_shards == 0, "negative prestige currency is normalized")
	game.free()

func test_atomic_stage_completion() -> void:
	var game := GameScript.new()
	game.stage = 5
	game.wave = 10
	game.highest_stage_this_run = 5
	game.highest_stage_ever = 5
	check(game.process_stage_completion(400), "first stage completion is processed")
	check(game.stage == 6 and game.wave == 1 and game.gold == 400, "completion advances and rewards atomically")
	check(not game.process_stage_completion(400) and game.gold == 400, "repeat completion does not duplicate reward")
	game.free()

func test_single_enemy_reward() -> void:
	var game := GameScript.new()
	var enemy: Dictionary = {"gold":21, "x":430.0, "y":535.0, "death_processed":false}
	game.enemies.append(enemy)
	game.kill_enemy(enemy)
	game.kill_enemy(enemy)
	check(game.gold == 21 and game.enemies_killed == 1, "enemy reward is granted once")
	game.free()

func test_old_projectile_generation() -> void:
	var game := GameScript.new()
	game.battle_generation = 7
	check(not game.projectile_matches_current_generation({"generation":6}), "old projectile generation is rejected")
	check(game.projectile_matches_current_generation({"generation":7}), "current projectile generation is accepted")
	game.free()
