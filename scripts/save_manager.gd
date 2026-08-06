class_name SaveManager
extends RefCounted

const SAVE_PATH := "user://fortress_progress.cfg"
const TEMP_PATH := "user://fortress_progress.tmp"
const BACKUP_PATH := "user://fortress_progress.bak"
const RESTORE_PATH := "user://fortress_progress.restore"
const SECTION := "progress"
const MAX_SAVE_VERSION := SaveSchema.VERSION
const MAX_STAGE := SaveSchema.MAX_STAGE
const MAX_GOLD := SaveSchema.MAX_GOLD

enum SaveDataKind {
	INVALID,
	LEGACY,
	CURRENT,
	FUTURE
}

# Используется только из изолированного регрессионного теста: в игровом UI этот
# переключатель недоступен и в сохранения не попадает.
static var regression_force_final_validation_failure: bool = false
static var last_loaded_kind: SaveDataKind = SaveDataKind.INVALID

static func save_game(data: Dictionary, save_path := SAVE_PATH, temp_path := TEMP_PATH, backup_path := BACKUP_PATH, restore_path := RESTORE_PATH) -> Error:
	var temp_path_absolute := ProjectSettings.globalize_path(temp_path)
	if FileAccess.file_exists(temp_path):
		var cleanup_temp_error := DirAccess.remove_absolute(temp_path_absolute)
		if cleanup_temp_error != OK:
			push_warning("Не удалось удалить старый временный файл сохранения: %s" % cleanup_temp_error)
			return cleanup_temp_error
	var config := ConfigFile.new()
	for key in data:
		config.set_value(SECTION, key, data[key])
	var save_error := config.save(temp_path)
	if save_error != OK:
		push_warning("Не удалось записать временное сохранение: %s" % save_error)
		return save_error
	if load_data_from_path(temp_path, "новое временное").is_empty():
		DirAccess.remove_absolute(temp_path_absolute)
		push_warning("Новое временное сохранение не прошло проверку.")
		return ERR_FILE_CORRUPT
	var main_path := ProjectSettings.globalize_path(save_path)
	var backup_path_absolute := ProjectSettings.globalize_path(backup_path)
	var raw_main_data := read_data_from_path(save_path, "текущее основное")
	if detect_save_data_kind(raw_main_data) == SaveDataKind.FUTURE:
		DirAccess.remove_absolute(temp_path_absolute)
		push_warning("Основное сохранение создано более новой версией игры и не будет перезаписано.")
		return ERR_UNAVAILABLE
	var current_main_data := load_data_from_path(save_path, "текущее основное")
	if not current_main_data.is_empty():
		if FileAccess.file_exists(backup_path):
			var delete_backup_error := DirAccess.remove_absolute(backup_path_absolute)
			if delete_backup_error != OK:
				DirAccess.remove_absolute(temp_path_absolute)
				push_warning("Не удалось заменить резервную копию сохранения: %s" % delete_backup_error)
				return delete_backup_error
		var backup_error := DirAccess.copy_absolute(main_path, backup_path_absolute)
		if backup_error != OK:
			DirAccess.remove_absolute(temp_path_absolute)
			push_warning("Не удалось создать резервную копию сохранения: %s" % backup_error)
			return backup_error
		if load_data_from_path(backup_path, "новое резервное").is_empty():
			DirAccess.remove_absolute(temp_path_absolute)
			push_warning("Новая резервная копия не прошла проверку.")
			return ERR_FILE_CORRUPT
	if FileAccess.file_exists(save_path):
		var remove_error := DirAccess.remove_absolute(main_path)
		if remove_error != OK:
			DirAccess.remove_absolute(temp_path_absolute)
			push_warning("Не удалось заменить основное сохранение: %s" % remove_error)
			return remove_error
	var replace_error := DirAccess.rename_absolute(temp_path_absolute, main_path)
	if replace_error != OK:
		if FileAccess.file_exists(backup_path): DirAccess.copy_absolute(backup_path_absolute, main_path)
		push_warning("Не удалось завершить замену сохранения: %s" % replace_error)
		return replace_error
	var final_data: Dictionary = {}
	if not regression_force_final_validation_failure:
		final_data = load_data_from_path(save_path, "новое основное")
	if final_data.is_empty():
		push_warning("Новое основное сохранение не прошло проверку.")
		if FileAccess.file_exists(save_path):
			var remove_corrupt_error := DirAccess.remove_absolute(main_path)
			if remove_corrupt_error != OK:
				push_warning("Не удалось удалить не прошедшее проверку основное сохранение: %s" % remove_corrupt_error)
		if FileAccess.file_exists(backup_path):
			if not restore_main_from_backup(save_path, backup_path, restore_path):
				push_warning("Не удалось восстановить backup после неудачной финальной проверки сохранения.")
		else:
			push_warning("Backup отсутствует: прежний прогресс невозможно восстановить после неудачной финальной проверки.")
		return ERR_FILE_CORRUPT
	return OK

static func load_game(save_path := SAVE_PATH, backup_path := BACKUP_PATH, restore_path := RESTORE_PATH) -> Dictionary:
	last_loaded_kind = SaveDataKind.INVALID
	var main_data := read_data_from_path(save_path, "основное")
	var main_kind := detect_save_data_kind(main_data)
	if main_kind == SaveDataKind.CURRENT or main_kind == SaveDataKind.LEGACY:
		last_loaded_kind = main_kind
		return main_data
	if main_kind == SaveDataKind.FUTURE:
		push_warning("Основное сохранение создано более новой версией игры. Оно не будет перезаписано.")
		var future_backup_data := load_data_from_path(backup_path, "резервное")
		if future_backup_data.is_empty(): return {}
		# Keep FUTURE here so callers cannot migrate the backup over the newer main file.
		last_loaded_kind = SaveDataKind.FUTURE
		return future_backup_data
	var backup_data := load_data_from_path(backup_path, "резервное")
	if backup_data.is_empty(): return {}
	last_loaded_kind = detect_save_data_kind(backup_data)
	if not restore_main_from_backup(save_path, backup_path, restore_path):
		push_warning("Основное сохранение не удалось восстановить, используются данные резервной копии.")
	return backup_data

static func restore_main_from_backup(save_path: String, backup_path: String, restore_path: String) -> bool:
	var backup_absolute := ProjectSettings.globalize_path(backup_path)
	var restore_absolute := ProjectSettings.globalize_path(restore_path)
	var main_absolute := ProjectSettings.globalize_path(save_path)
	if FileAccess.file_exists(restore_path):
		var cleanup_error := DirAccess.remove_absolute(restore_absolute)
		if cleanup_error != OK:
			push_warning("Не удалось очистить временный файл восстановления: %s" % cleanup_error)
			return false
	var copy_error := DirAccess.copy_absolute(backup_absolute, restore_absolute)
	if copy_error != OK:
		push_warning("Не удалось скопировать резервную копию для восстановления: %s" % copy_error)
		return false
	if load_data_from_path(restore_path, "временное восстановление").is_empty():
		DirAccess.remove_absolute(restore_absolute)
		push_warning("Временный файл восстановления не прошёл проверку.")
		return false
	if FileAccess.file_exists(save_path):
		var remove_error := DirAccess.remove_absolute(main_absolute)
		if remove_error != OK:
			DirAccess.remove_absolute(restore_absolute)
			push_warning("Не удалось удалить повреждённое основное сохранение: %s" % remove_error)
			return false
	var rename_error := DirAccess.rename_absolute(restore_absolute, main_absolute)
	if rename_error != OK:
		push_warning("Не удалось завершить восстановление основного сохранения: %s" % rename_error)
		return false
	if load_data_from_path(save_path, "восстановленное основное").is_empty():
		push_warning("Восстановленное основное сохранение не прошло повторную проверку.")
		return false
	return true

static func is_numeric_value(value: Variant) -> bool:
	if not (value is int or value is float): return false
	return not (value is float and (is_nan(value) or is_inf(value)))

static func is_integer_in_range(value: Variant, minimum: int, maximum: int) -> bool:
	if not is_numeric_value(value): return false
	return value >= minimum and value <= maximum

static func has_valid_stage_and_gold(data: Dictionary) -> bool:
	return data.has("stage") and data.has("gold") \
		and is_integer_in_range(data["stage"], 1, MAX_STAGE) \
		and is_integer_in_range(data["gold"], 0, MAX_GOLD)

static func is_current_save_data(data: Dictionary) -> bool:
	if data.is_empty() or not data.has("version") or not has_valid_stage_and_gold(data): return false
	return is_integer_in_range(data["version"], 1, MAX_SAVE_VERSION)

static func is_legacy_save_data(data: Dictionary) -> bool:
	return not data.is_empty() and not data.has("version") and has_valid_stage_and_gold(data)

static func detect_save_data_kind(data: Dictionary) -> SaveDataKind:
	if is_legacy_save_data(data): return SaveDataKind.LEGACY
	if not data.has("version") or not is_numeric_value(data["version"]): return SaveDataKind.INVALID
	if data["version"] > MAX_SAVE_VERSION: return SaveDataKind.FUTURE
	if is_current_save_data(data): return SaveDataKind.CURRENT
	return SaveDataKind.INVALID

static func save_requires_migration(data: Dictionary) -> bool:
	if is_legacy_save_data(data): return true
	return data.has("version") and is_numeric_value(data["version"]) and int(data["version"]) < MAX_SAVE_VERSION

static func validate_save_data(data: Dictionary) -> bool:
	return is_current_save_data(data) or is_legacy_save_data(data)

static func read_data_from_path(path: String, source_name: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var config := ConfigFile.new()
	var load_error := config.load(path)
	if load_error != OK:
		push_warning("Не удалось загрузить %s сохранение: %s" % [source_name, load_error])
		return {}
	if not config.has_section(SECTION):
		push_warning("%s сохранение не содержит секцию прогресса." % source_name.capitalize())
		return {}
	var data: Dictionary = {}
	for key in config.get_section_keys(SECTION):
		data[key] = config.get_value(SECTION, key)
	return data

static func load_data_from_path(path: String, source_name: String) -> Dictionary:
	var data := read_data_from_path(path, source_name)
	if data.is_empty(): return {}
	if detect_save_data_kind(data) == SaveDataKind.FUTURE:
		push_warning("%s сохранение создано более новой версией игры и не будет перезаписано." % source_name.capitalize())
		return {}
	if not validate_save_data(data):
		push_warning("%s сохранение не прошло проверку структуры." % source_name.capitalize())
		return {}
	return data

static func save_exists(save_path := SAVE_PATH) -> bool:
	return FileAccess.file_exists(save_path)

static func delete_save(save_path := SAVE_PATH, temp_path := TEMP_PATH, backup_path := BACKUP_PATH, restore_path := RESTORE_PATH) -> Error:
	var first_error: Error = OK
	for path in [save_path, temp_path, backup_path, restore_path]:
		if not FileAccess.file_exists(path): continue
		var delete_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if delete_error != OK and first_error == OK: first_error = delete_error
	return first_error
