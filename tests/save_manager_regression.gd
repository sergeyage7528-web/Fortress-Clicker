extends SceneTree

const TEST_SAVE := "user://fortress_regression_primary.cfg"
const TEST_TEMP := "user://fortress_regression_primary.tmp"
const TEST_BACKUP := "user://fortress_regression_primary.bak"
const TEST_RESTORE := "user://fortress_regression_primary.restore"
const TEST_LEGACY_SAVE := "user://fortress_regression_legacy.cfg"
const TEST_LEGACY_TEMP := "user://fortress_regression_legacy.tmp"
const TEST_LEGACY_BACKUP := "user://fortress_regression_legacy.bak"
const TEST_LEGACY_RESTORE := "user://fortress_regression_legacy.restore"
const TEST_FUTURE_SAVE := "user://fortress_regression_future.cfg"
const TEST_FUTURE_TEMP := "user://fortress_regression_future.tmp"
const TEST_FUTURE_BACKUP := "user://fortress_regression_future.bak"
const TEST_FUTURE_RESTORE := "user://fortress_regression_future.restore"
const TEST_ROLLBACK_SAVE := "user://fortress_regression_rollback.cfg"
const TEST_ROLLBACK_TEMP := "user://fortress_regression_rollback.tmp"
const TEST_ROLLBACK_BACKUP := "user://fortress_regression_rollback.bak"
const TEST_ROLLBACK_RESTORE := "user://fortress_regression_rollback.restore"
const GameScript = preload("res://main.gd")

var failures: int = 0

func _init() -> void:
	cleanup_test_files()
	SaveManager.set_regression_final_validation_failure(false)
	test_clamped_save_values()
	test_atomic_stage_completion()
	test_single_enemy_reward()
	test_old_projectile_generation()
	test_maximum_gold()
	test_prestige_combat_bonuses_and_save_data()
	test_fractional_required_values()
	test_legacy_save_migration()
	test_unsupported_future_version()
	test_final_validation_rollback()
	SaveManager.delete_save(TEST_SAVE, TEST_TEMP, TEST_BACKUP, TEST_RESTORE)
	check(SaveManager.save_game({"version":SaveSchema.VERSION, "stage":5, "gold":100}, TEST_SAVE, TEST_TEMP, TEST_BACKUP) == OK, "initial save")
	check(SaveManager.save_game({"version":SaveSchema.VERSION, "stage":6, "gold":200}, TEST_SAVE, TEST_TEMP, TEST_BACKUP) == OK, "backup-producing save")
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
	cleanup_test_files()
	SaveManager.set_regression_final_validation_failure(false)
	if failures == 0:
		print("SaveManager regression checks passed.")
		quit(0)
	else:
		quit(1)

func check(condition: bool, description: String) -> void:
	if condition: return
	failures += 1
	push_error("Regression check failed: %s" % description)

func cleanup_test_files() -> void:
	SaveManager.delete_save(TEST_SAVE, TEST_TEMP, TEST_BACKUP, TEST_RESTORE)
	SaveManager.delete_save(TEST_LEGACY_SAVE, TEST_LEGACY_TEMP, TEST_LEGACY_BACKUP, TEST_LEGACY_RESTORE)
	SaveManager.delete_save(TEST_FUTURE_SAVE, TEST_FUTURE_TEMP, TEST_FUTURE_BACKUP, TEST_FUTURE_RESTORE)
	SaveManager.delete_save(TEST_ROLLBACK_SAVE, TEST_ROLLBACK_TEMP, TEST_ROLLBACK_BACKUP, TEST_ROLLBACK_RESTORE)

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
	check(not game.projectile_matches_current_generation({"generation":"7"}), "non-integer projectile generation is rejected")
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

func test_prestige_combat_bonuses_and_save_data() -> void:
	var game := GameScript.new()
	game.tower_crit_level = 2
	game.prestige_critical_level = 5
	check(is_equal_approx(game.tower_crit_chance(), 0.13), "prestige critical bonus is applied once")
	game.prestige_monster_damage_level = 3
	game.current_enemy_type = "elite"
	check(is_equal_approx(game.enemy_type_damage_multiplier(), 1.45), "prestige monster bonus applies to elites")
	game.current_enemy_type = "normal"
	check(is_equal_approx(game.enemy_type_damage_multiplier(), 1.0), "prestige monster bonus skips normal enemies")
	check(game.format_number(1250.0) == "1.25K" and game.format_number(1_500_000.0) == "1.50M", "large number formatting is compact")
	var saved := game.build_save_data()
	check(int(saved.get("prestige_critical_level", -1)) == 5 and int(saved.get("prestige_monster_damage_level", -1)) == 3, "new prestige levels are saved")
	var restored := GameScript.new()
	restored.apply_save_data(saved)
	check(restored.prestige_critical_level == 5 and restored.prestige_monster_damage_level == 3, "new prestige levels are restored")
	restored.free()
	game.free()

func test_fractional_required_values() -> void:
	for data in [
		{"version":SaveSchema.VERSION, "stage":5.5, "gold":100},
		{"version":3.5, "stage":5, "gold":100},
		{"version":SaveSchema.VERSION, "stage":5, "gold":100.25}
	]:
		check(SaveManager.detect_save_data_kind(data) == SaveManager.SaveDataKind.INVALID, "fractional required value is invalid")
	var integral_floats := {"version":float(SaveSchema.VERSION), "stage":5.0, "gold":100.0}
	check(SaveManager.detect_save_data_kind(integral_floats) == SaveManager.SaveDataKind.CURRENT, "mathematically integral floats are accepted")

func test_legacy_save_migration() -> void:
	SaveManager.delete_save(TEST_LEGACY_SAVE, TEST_LEGACY_TEMP, TEST_LEGACY_BACKUP, TEST_LEGACY_RESTORE)
	var config := ConfigFile.new()
	config.set_value("progress", "stage", 6)
	config.set_value("progress", "gold", 350)
	config.set_value("progress", "fortress", 4)
	config.set_value("progress", "forge", 5)
	config.set_value("progress", "barracks", 3)
	check(config.save(TEST_LEGACY_SAVE) == OK, "legacy save is written")
	var legacy_data := SaveManager.load_game(TEST_LEGACY_SAVE, TEST_LEGACY_BACKUP, TEST_LEGACY_RESTORE)
	check(not legacy_data.is_empty() and int(legacy_data.get("stage", 0)) == 6 and int(legacy_data.get("gold", -1)) == 350, "legacy save is accepted")
	check(SaveManager.detect_save_data_kind(legacy_data) == SaveManager.SaveDataKind.LEGACY, "legacy save kind is detected")
	check(SaveManager.last_loaded_kind == SaveManager.SaveDataKind.LEGACY, "legacy load kind is retained")
	var game := GameScript.new()
	game.load_progress_from_paths(TEST_LEGACY_SAVE, TEST_LEGACY_BACKUP, TEST_LEGACY_RESTORE, TEST_LEGACY_TEMP)
	check(game.fortress_level == 4 and game.tower_level == 5 and game.barracks_level == 3 and game.barracks_open, "legacy fields are applied")
	var migrated_data := SaveManager.load_game(TEST_LEGACY_SAVE, TEST_LEGACY_BACKUP, TEST_LEGACY_RESTORE)
	check(int(migrated_data.get("version", 0)) == SaveSchema.VERSION, "migrated save has current version")
	check(int(migrated_data.get("fortress_level", 0)) == 4 and int(migrated_data.get("tower_level", 0)) == 5 and int(migrated_data.get("barracks_level", 0)) == 3, "migrated save has current field names")
	check(SaveManager.detect_save_data_kind(migrated_data) == SaveManager.SaveDataKind.CURRENT, "migrated save is current")
	var legacy_backup := SaveManager.read_data_from_path(TEST_LEGACY_BACKUP, "legacy backup")
	check(SaveManager.detect_save_data_kind(legacy_backup) == SaveManager.SaveDataKind.LEGACY, "backup preserves the original legacy save")
	game.free()

func test_unsupported_future_version() -> void:
	SaveManager.delete_save(TEST_FUTURE_SAVE, TEST_FUTURE_TEMP, TEST_FUTURE_BACKUP, TEST_FUTURE_RESTORE)
	var config := ConfigFile.new()
	config.set_value("progress", "version", SaveSchema.VERSION + 1)
	config.set_value("progress", "stage", 10)
	config.set_value("progress", "gold", 500)
	check(config.save(TEST_FUTURE_SAVE) == OK, "future-version save is written")
	var original_future_contents := FileAccess.get_file_as_string(TEST_FUTURE_SAVE)
	var raw_future := SaveManager.read_data_from_path(TEST_FUTURE_SAVE, "future test")
	check(SaveManager.detect_save_data_kind(raw_future) == SaveManager.SaveDataKind.FUTURE, "future-version save kind is detected")
	var future_data := SaveManager.load_game(TEST_FUTURE_SAVE, TEST_FUTURE_BACKUP, TEST_FUTURE_RESTORE)
	check(future_data.is_empty(), "future-version save is rejected")
	check(SaveManager.last_loaded_kind == SaveManager.SaveDataKind.INVALID, "future save without backup has no loadable kind")
	check(FileAccess.file_exists(TEST_FUTURE_SAVE), "future-version save is not overwritten")
	check(FileAccess.get_file_as_string(TEST_FUTURE_SAVE) == original_future_contents, "future-version save is unchanged")
	check(SaveManager.save_game({"version":SaveSchema.VERSION, "stage":11, "gold":600}, TEST_FUTURE_SAVE, TEST_FUTURE_TEMP, TEST_FUTURE_BACKUP, TEST_FUTURE_RESTORE) == ERR_UNAVAILABLE, "future-version save cannot be overwritten")
	check(FileAccess.get_file_as_string(TEST_FUTURE_SAVE) == original_future_contents, "blocked write keeps future-version save unchanged")
	check(SaveManager.save_game({"version":SaveSchema.VERSION, "stage":9, "gold":450}, TEST_FUTURE_BACKUP, TEST_FUTURE_TEMP, TEST_FUTURE_RESTORE, TEST_FUTURE_SAVE) == OK, "compatible future backup is written")
	var backup_data := SaveManager.load_game(TEST_FUTURE_SAVE, TEST_FUTURE_BACKUP, TEST_FUTURE_RESTORE)
	check(int(backup_data.get("stage", 0)) == 9 and SaveManager.last_loaded_kind == SaveManager.SaveDataKind.FUTURE, "compatible backup loads without replacing future main")
	check(FileAccess.get_file_as_string(TEST_FUTURE_SAVE) == original_future_contents, "future main remains after backup fallback")

func test_final_validation_rollback() -> void:
	SaveManager.delete_save(TEST_ROLLBACK_SAVE, TEST_ROLLBACK_TEMP, TEST_ROLLBACK_BACKUP, TEST_ROLLBACK_RESTORE)
	check(SaveManager.save_game({"version":SaveSchema.VERSION, "stage":9, "gold":900}, TEST_ROLLBACK_SAVE, TEST_ROLLBACK_TEMP, TEST_ROLLBACK_BACKUP) == OK, "rollback initial save")
	check(SaveManager.save_game({"version":SaveSchema.VERSION, "stage":10, "gold":1000}, TEST_ROLLBACK_SAVE, TEST_ROLLBACK_TEMP, TEST_ROLLBACK_BACKUP) == OK, "rollback backup-producing save")
	SaveManager.set_regression_final_validation_failure(true)
	var failed_save := SaveManager.save_game({"version":SaveSchema.VERSION, "stage":11, "gold":1100}, TEST_ROLLBACK_SAVE, TEST_ROLLBACK_TEMP, TEST_ROLLBACK_BACKUP, TEST_ROLLBACK_RESTORE)
	SaveManager.set_regression_final_validation_failure(false)
	check(failed_save == ERR_FILE_CORRUPT, "simulated final validation failure returns ERR_FILE_CORRUPT")
	var rolled_back_data := SaveManager.load_game(TEST_ROLLBACK_SAVE, TEST_ROLLBACK_BACKUP, TEST_ROLLBACK_RESTORE)
	check(int(rolled_back_data.get("stage", 0)) == 10 and int(rolled_back_data.get("gold", -1)) == 1000, "rollback restores the previous main save")
	check(not FileAccess.file_exists(TEST_ROLLBACK_TEMP) and not FileAccess.file_exists(TEST_ROLLBACK_RESTORE), "rollback leaves no temporary files")

func test_structurally_invalid_save() -> void:
	check(SaveManager.save_game({"version":SaveSchema.VERSION, "stage":7, "gold":700}, TEST_SAVE, TEST_TEMP, TEST_BACKUP) == OK, "structural test initial save")
	check(SaveManager.save_game({"version":SaveSchema.VERSION, "stage":8, "gold":800}, TEST_SAVE, TEST_TEMP, TEST_BACKUP) == OK, "structural test backup save")
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
