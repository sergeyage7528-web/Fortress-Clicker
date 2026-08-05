extends SceneTree

const TEST_SAVE := "user://fortress_regression_primary.cfg"
const TEST_TEMP := "user://fortress_regression_primary.tmp"
const TEST_BACKUP := "user://fortress_regression_primary.bak"
const TEST_RESTORE := "user://fortress_regression_primary.restore"
const GameScript = preload("res://main.gd")

var failures: int = 0

func _init() -> void:
	test_clamped_save_values()
	test_atomic_stage_completion()
	test_single_enemy_reward()
	test_old_projectile_generation()
	test_maximum_gold()
	SaveManager.delete_save(TEST_SAVE, TEST_TEMP, TEST_BACKUP, TEST_RESTORE)
	check(SaveManager.save_game({"version":4, "stage":5, "gold":100}, TEST_SAVE, TEST_TEMP, TEST_BACKUP) == OK, "initial save")
	check(SaveManager.save_game({"version":4, "stage":6, "gold":200}, TEST_SAVE, TEST_TEMP, TEST_BACKUP) == OK, "backup-producing save")
	var corrupt_file := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	if corrupt_file != null:
		corrupt_file.store_string("[broken\n")
		corrupt_file.close()
	else:
		failures += 1
		push_error("Не удалось создать повреждённое тестовое сохранение.")
	var restored_data := SaveManager.load_game(TEST_SAVE, TEST_BACKUP, TEST_RESTORE)
	check(int(restored_data.get("stage", 0)) == 5, "backup recovery returns the prior save")
	check(int(restored_data.get("gold", -1)) == 100, "backup recovery returns prior gold")
	var restored_main := SaveManager.load_data_from_path(TEST_SAVE, "восстановленное тестовое основное")
	check(int(restored_main.get("stage", 0)) == 5 and int(restored_main.get("gold", -1)) == 100, "main file is restored from backup")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_BACKUP))
	var reloaded_without_backup := SaveManager.load_game(TEST_SAVE, TEST_BACKUP, TEST_RESTORE)
	check(int(reloaded_without_backup.get("stage", 0)) == 5, "restored main loads without backup")
	test_structurally_invalid_save()
	SaveManager.delete_save(TEST_SAVE, TEST_TEMP, TEST_BACKUP, TEST_RESTORE)
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
	var saved_after_completion := game.build_save_data()
	check(int(saved_after_completion.get("stage", 0)) == 6 and int(saved_after_completion.get("gold", -1)) == 400, "next stage and reward are prepared for saving")
	check(not saved_after_completion.has("wave"), "unfinished wave is not saved")
	check(not game.process_stage_completion(400) and game.gold == 400 and game.stage == 6, "repeat completion does not duplicate reward")
	var saved_after_repeat := game.build_save_data()
	check(saved_after_repeat == saved_after_completion, "repeat completion does not change save data")
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

func test_maximum_gold() -> void:
	var game := GameScript.new()
	game.gold = GameScript.MAX_GOLD - 5
	game.add_gold(100)
	check(game.gold == GameScript.MAX_GOLD, "gold is capped at MAX_GOLD")
	game.add_gold(-100)
	check(game.gold == GameScript.MAX_GOLD, "negative gold amount is ignored")
	var enemy: Dictionary = {"gold":100, "x":430.0, "y":535.0, "death_processed":false}
	game.enemies.append(enemy)
	game.kill_enemy(enemy)
	check(game.gold == GameScript.MAX_GOLD, "enemy reward respects MAX_GOLD")
	game.free()

func test_structurally_invalid_save() -> void:
	check(SaveManager.save_game({"version":4, "stage":7, "gold":700}, TEST_SAVE, TEST_TEMP, TEST_BACKUP) == OK, "structural test initial save")
	check(SaveManager.save_game({"version":4, "stage":8, "gold":800}, TEST_SAVE, TEST_TEMP, TEST_BACKUP) == OK, "structural test backup save")
	var config := ConfigFile.new()
	config.set_value("progress", "version", "broken")
	config.set_value("progress", "stage", "not_a_number")
	config.set_value("progress", "gold", {"invalid":true})
	check(config.save(TEST_SAVE) == OK, "structurally invalid main save is written")
	var recovered_data := SaveManager.load_game(TEST_SAVE, TEST_BACKUP, TEST_RESTORE)
	check(int(recovered_data.get("stage", 0)) == 7 and int(recovered_data.get("gold", -1)) == 700, "structurally invalid main uses backup")
	var recovered_main := SaveManager.load_data_from_path(TEST_SAVE, "восстановленное структурное основное")
	check(int(recovered_main.get("stage", 0)) == 7 and int(recovered_main.get("gold", -1)) == 700, "structural recovery replaces main file")
	check(config.save(TEST_SAVE) == OK and config.save(TEST_BACKUP) == OK, "invalid main and backup are written")
	check(SaveManager.load_game(TEST_SAVE, TEST_BACKUP, TEST_RESTORE).is_empty(), "two invalid save files return safe empty data")
