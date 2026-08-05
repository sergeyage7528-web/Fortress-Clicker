class_name SaveManager
extends RefCounted

const SAVE_PATH := "user://fortress_progress.cfg"
const TEMP_PATH := "user://fortress_progress.tmp"
const BACKUP_PATH := "user://fortress_progress.bak"
const RESTORE_PATH := "user://fortress_progress.restore"
const SECTION := "progress"
const MAX_SAVE_VERSION := 4
const MAX_STAGE := 1000
const MAX_GOLD := 9000000000000000000

static func save_game(data: Dictionary, save_path := SAVE_PATH, temp_path := TEMP_PATH, backup_path := BACKUP_PATH) -> Error:
	var config := ConfigFile.new()
	for key in data:
		config.set_value(SECTION, key, data[key])
	var save_error := config.save(temp_path)
	if save_error != OK:
		push_warning("Не удалось записать временное сохранение: %s" % save_error)
		return save_error
	var main_path := ProjectSettings.globalize_path(save_path)
	var temp_path_absolute := ProjectSettings.globalize_path(temp_path)
	var backup_path_absolute := ProjectSettings.globalize_path(backup_path)
	if FileAccess.file_exists(save_path):
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
	if load_data_from_path(save_path, "новое основное").is_empty():
		push_warning("Новое основное сохранение не прошло проверку.")
		return ERR_FILE_CORRUPT
	return OK

static func load_game(save_path := SAVE_PATH, backup_path := BACKUP_PATH, restore_path := RESTORE_PATH) -> Dictionary:
	var main_data := load_data_from_path(save_path, "основное")
	if not main_data.is_empty(): return main_data
	var backup_data := load_data_from_path(backup_path, "резервное")
	if backup_data.is_empty(): return {}
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

static func validate_save_data(data: Dictionary) -> bool:
	if data.is_empty(): return false
	for key in ["version", "stage", "gold"]:
		if not data.has(key) or not is_numeric_value(data[key]): return false
	var version := int(data["version"])
	var stage := int(data["stage"])
	var gold := int(data["gold"])
	return version >= 0 and version <= MAX_SAVE_VERSION and stage >= 1 and stage <= MAX_STAGE and gold >= 0 and gold <= MAX_GOLD

static func load_data_from_path(path: String, source_name: String) -> Dictionary:
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
